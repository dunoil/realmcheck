// Unit tests for auditrules. Every rule has a positive case it must
// catch and a clean case it must not flag. Fixtures are source text, not
// compiled realms, because the scanner reads text: a fixture only needs
// to look like Gno code, it does not need to type-check.
package auditrules

import "testing"

func findRule(findings []Finding, id string) (Finding, bool) {
	for _, f := range findings {
		if f.RuleID == id {
			return f, true
		}
	}
	return Finding{}, false
}

func expectHas(t *testing.T, findings []Finding, id string) {
	t.Helper()
	if _, ok := findRule(findings, id); !ok {
		t.Errorf("expected finding %s, got %v", id, findings)
	}
}

func expectNotHas(t *testing.T, findings []Finding, id string) {
	t.Helper()
	if f, ok := findRule(findings, id); ok {
		t.Errorf("expected no finding %s, got %+v", id, f)
	}
}

func TestRuleCatalog(t *testing.T) {
	rules := Rules()
	if len(rules) != 8 {
		t.Fatalf("expected 8 rules, got %d", len(rules))
	}
	seen := make(map[string]bool)
	for _, r := range rules {
		if r.ID == "" || r.Name == "" || r.Description == "" {
			t.Errorf("rule with empty field: %+v", r)
		}
		if seen[r.ID] {
			t.Errorf("duplicate rule id %s", r.ID)
		}
		seen[r.ID] = true
	}
	r, ok := RuleByID(RuleUnrestrictedMint)
	if !ok || r.Severity != SeverityCritical {
		t.Errorf("RuleByID(RC-02) should return the critical mint rule, got %+v %v", r, ok)
	}
	if _, ok := RuleByID("RC-99"); ok {
		t.Error("RuleByID should return false for an unknown id")
	}
}

func TestScore(t *testing.T) {
	if Score(nil) != 100 {
		t.Errorf("empty findings should score 100, got %d", Score(nil))
	}
	one := []Finding{{RuleID: RuleUnrestrictedMint, Severity: SeverityCritical}}
	if Score(one) != 75 {
		t.Errorf("one critical finding should score 75, got %d", Score(one))
	}
	many := []Finding{
		{Severity: SeverityCritical},
		{Severity: SeverityCritical},
		{Severity: SeverityCritical},
		{Severity: SeverityCritical},
		{Severity: SeverityCritical},
	}
	if Score(many) != 0 {
		t.Errorf("score should floor at 0, got %d", Score(many))
	}
	if SeverityWeight(SeverityHigh) != 15 || SeverityWeight(SeverityMedium) != 8 || SeverityWeight(SeverityLow) != 3 {
		t.Error("severity weights changed: expected critical 25, high 15, medium 8, low 3")
	}
}

func TestNoCallerGuardPositive(t *testing.T) {
	src := `package demo

func Withdraw(cur realm, to address, amount int64) {
	banker.SendCoins(cur, to, amount)
}
`
	findings := CheckNoCallerGuard(src)
	expectHas(t, findings, RuleNoCallerGuard)
	f, _ := findRule(findings, RuleNoCallerGuard)
	if f.Line != 4 {
		t.Errorf("expected finding on line 4, got %d", f.Line)
	}
	if f.SourceLine != "banker.SendCoins(cur, to, amount)" {
		t.Errorf("expected cited source line, got %q", f.SourceLine)
	}
}

func TestNoCallerGuardSingleLineFunction(t *testing.T) {
	src := "package demo\n\nfunc Withdraw(cur realm, to address, amount int64) { banker.SendCoins(cur, to, amount) }\n"
	findings := CheckNoCallerGuard(src)
	expectHas(t, findings, RuleNoCallerGuard)
	f, _ := findRule(findings, RuleNoCallerGuard)
	if f.Line != 3 {
		t.Errorf("expected finding on line 3, got %d", f.Line)
	}
}

func TestNoCallerGuardClean(t *testing.T) {
	src := `package demo

func Withdraw(cur realm, to address, amount int64) {
	if !cur.Previous().IsUserCall() {
		panic("only user call")
	}
	banker.SendCoins(cur, to, amount)
}
`
	expectNotHas(t, CheckNoCallerGuard(src), RuleNoCallerGuard)
}

func TestNoCallerGuardOwnerCheckCounts(t *testing.T) {
	src := `package demo

func SetOwner(cur realm, next address) {
	if unsafe.OriginCaller() != owner {
		panic("not owner")
	}
	owner = next
}
`
	expectNotHas(t, CheckNoCallerGuard(src), RuleNoCallerGuard)
}

func TestUnrestrictedMintPositive(t *testing.T) {
	src := `package demo

var totalSupply int64

func Mint(cur realm, to address, amount int64) {
	banker.IssueCoin(to, "demo", amount)
	totalSupply += amount
}
`
	findings := CheckUnrestrictedMint(src)
	expectHas(t, findings, RuleUnrestrictedMint)
	// Mint is covered by RC-02, not RC-01, so the same function must
	// not also produce a caller guard finding.
	expectNotHas(t, CheckNoCallerGuard(src), RuleNoCallerGuard)
}

func TestUnrestrictedMintClean(t *testing.T) {
	src := `package demo

var totalSupply int64

func Mint(cur realm, to address, amount int64) {
	if !cur.Previous().IsUserCall() {
		panic("only user call")
	}
	if unsafe.OriginCaller() != owner {
		panic("not owner")
	}
	banker.IssueCoin(to, "demo", amount)
	totalSupply += amount
}
`
	expectNotHas(t, CheckUnrestrictedMint(src), RuleUnrestrictedMint)
}

func TestAdminBackdoorPositive(t *testing.T) {
	src := `package demo

var admin address = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")

func Withdraw(cur realm, amount int64) {
	banker.SendCoins(cur, admin, amount)
}
`
	expectHas(t, CheckAdminBackdoor(src), RuleAdminBackdoor)
}

func TestAdminBackdoorCleanTimelock(t *testing.T) {
	src := `package demo

var admin address = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
var UnlockTime int64 = 9999999999

func Withdraw(cur realm, amount int64) {
	if runtime.ChainHeight() < UnlockTime {
		panic("timelock not expired")
	}
	banker.SendCoins(cur, admin, amount)
}
`
	expectNotHas(t, CheckAdminBackdoor(src), RuleAdminBackdoor)
}

func TestAdminBackdoorNoAdminVar(t *testing.T) {
	src := `package demo

func Withdraw(cur realm, to address, amount int64) {
	banker.SendCoins(cur, to, amount)
}
`
	expectNotHas(t, CheckAdminBackdoor(src), RuleAdminBackdoor)
}

func TestUnboundedStoragePositive(t *testing.T) {
	src := `package demo

var entries []string

func AddEntry(cur realm, e string) {
	entries = append(entries, e)
}
`
	findings := CheckUnboundedStorage(src)
	expectHas(t, findings, RuleUnboundedStorage)
	// The append line belongs to RC-04, not RC-08.
	expectNotHas(t, CheckPublicStateMutation(src), RulePublicMutation)
}

func TestUnboundedStorageClean(t *testing.T) {
	src := `package demo

var entries []string

func AddEntry(cur realm, e string) {
	if len(entries) >= 100 {
		panic("full")
	}
	entries = append(entries, e)
}
`
	expectNotHas(t, CheckUnboundedStorage(src), RuleUnboundedStorage)
}

func TestUnboundedStorageLocalAppendClean(t *testing.T) {
	src := `package demo

func Collect(cur realm, items []string) []string {
	out := []string{}
	for _, it := range items {
		out = append(out, it)
	}
	return out
}
`
	expectNotHas(t, CheckUnboundedStorage(src), RuleUnboundedStorage)
}

func TestFundsWithoutCheckPositive(t *testing.T) {
	src := `package demo

func Deposit(cur realm, amount int64) {
	sent := unsafe.OriginSend()
	credit(amount)
}
`
	findings := CheckFundsWithoutCheck(src)
	expectHas(t, findings, RuleFundsWithoutCheck)
	f, _ := findRule(findings, RuleFundsWithoutCheck)
	if f.Line != 4 {
		t.Errorf("expected finding on line 4, got %d", f.Line)
	}
}

func TestFundsWithoutCheckClean(t *testing.T) {
	src := `package demo

func Deposit(cur realm, amount int64) {
	sent := unsafe.OriginSend()
	if sent.AmountOf("ugnot") < amount {
		panic("insufficient payment")
	}
	credit(amount)
}
`
	expectNotHas(t, CheckFundsWithoutCheck(src), RuleFundsWithoutCheck)
}

func TestWeakRandomnessPositive(t *testing.T) {
	src := `package demo

func DrawWinner(cur realm, players []address) address {
	winner := players[int(runtime.ChainHeight()%int64(len(players)))]
	return winner
}
`
	expectHas(t, CheckWeakRandomness(src), RuleWeakRandomness)
}

func TestWeakRandomnessClean(t *testing.T) {
	src := `package demo

var deadline int64 = 1000

func Claim(cur realm) {
	if runtime.ChainHeight() > deadline {
		panic("ended")
	}
	claimed = true
}
`
	expectNotHas(t, CheckWeakRandomness(src), RuleWeakRandomness)
}

func TestWeakRandomnessTimeClean(t *testing.T) {
	src := `package demo

func DrawWinner(cur realm, players []address) address {
	seed := randomSeed
	return players[seed%len(players)]
}
`
	expectNotHas(t, CheckWeakRandomness(src), RuleWeakRandomness)
}

func TestUncheckedCallPositive(t *testing.T) {
	src := `package demo

func PingVault(cur realm, vault realm) {
	vault.Ping(cross(cur))
}
`
	expectHas(t, CheckUncheckedExternalCall(src), RuleUncheckedCall)
}

func TestUncheckedCallClean(t *testing.T) {
	src := `package demo

func ReadVault(cur realm, vault realm) int64 {
	bal, err := vault.Balance(cross(cur))
	if err != nil {
		panic("vault call failed")
	}
	return bal
}
`
	expectNotHas(t, CheckUncheckedExternalCall(src), RuleUncheckedCall)
}

func TestPublicMutationPositive(t *testing.T) {
	src := `package demo

var displayName string

func SetName(cur realm, name string) {
	displayName = name
}
`
	findings := CheckPublicStateMutation(src)
	expectHas(t, findings, RulePublicMutation)
	f, _ := findRule(findings, RulePublicMutation)
	if f.Line != 6 {
		t.Errorf("expected finding on line 6, got %d", f.Line)
	}
	if f.SourceLine != "displayName = name" {
		t.Errorf("expected cited source line, got %q", f.SourceLine)
	}
}

func TestPublicMutationClean(t *testing.T) {
	src := `package demo

var displayName string

func SetName(cur realm, name string) {
	if !cur.Previous().IsUserCall() {
		panic("only user call")
	}
	displayName = name
}
`
	expectNotHas(t, CheckPublicStateMutation(src), RulePublicMutation)
}

func TestPublicMutationRenderClean(t *testing.T) {
	src := `package demo

var displayName string

func Render(path string) string {
	displayName = path
	return displayName
}
`
	expectNotHas(t, CheckPublicStateMutation(src), RulePublicMutation)
}

func TestCommentsAndStringsNotFlagged(t *testing.T) {
	src := "package demo\n" +
		"\n" +
		"var displayName string\n" +
		"\n" +
		"func Note(cur realm) string {\n" +
		"	// SendCoins is called elsewhere, not here\n" +
		"	msg := \"{ not a brace, SendCoins inside a string\"\n" +
		"	return msg\n" +
		"}\n" +
		"\n" +
		"func SetName(cur realm, name string) {\n" +
		"	displayName = name\n" +
		"}\n"
	// The comment and the string must not trigger RC-01, and the brace
	// inside the string must not break function detection, so the real
	// mutation in SetName must still be found.
	expectNotHas(t, Audit(src), RuleNoCallerGuard)
	expectHas(t, Audit(src), RulePublicMutation)
	f, _ := findRule(Audit(src), RulePublicMutation)
	if f.Line != 12 {
		t.Errorf("expected RC-08 on line 12, got %d", f.Line)
	}
}

func TestAuditCombined(t *testing.T) {
	src := `package demo

var entries []string

func DrawWinner(cur realm, players []address) address {
	winner := players[int(runtime.ChainHeight()%int64(len(players)))]
	return winner
}

func Withdraw(cur realm, to address, amount int64) {
	banker.SendCoins(cur, to, amount)
}

func AddEntry(cur realm, e string) {
	entries = append(entries, e)
}
`
	findings := Audit(src)
	expectHas(t, findings, RuleNoCallerGuard)
	expectHas(t, findings, RuleWeakRandomness)
	expectHas(t, findings, RuleUnboundedStorage)
	if len(findings) != 3 {
		t.Errorf("expected exactly 3 findings, got %d: %v", len(findings), findings)
	}
	// Findings come back in rule order, not file order: RC-01 first
	// even though the randomness issue appears first in the file.
	if findings[0].RuleID != RuleNoCallerGuard {
		t.Errorf("expected first finding to be %s, got %s", RuleNoCallerGuard, findings[0].RuleID)
	}
	if Score(findings) != 100-15-8-8 {
		t.Errorf("expected score %d, got %d", 100-15-8-8, Score(findings))
	}
}

func TestAuditCleanSource(t *testing.T) {
	src := `package demo

func Hello(cur realm) string {
	return "hello"
}
`
	findings := Audit(src)
	if len(findings) != 0 {
		t.Errorf("expected no findings, got %v", findings)
	}
	if Score(findings) != 100 {
		t.Errorf("expected score 100, got %d", Score(findings))
	}
}

func TestAuditEmptySource(t *testing.T) {
	if len(Audit("")) != 0 {
		t.Error("empty source should produce no findings")
	}
	if len(AuditFile("demo.gno", "")) != 0 {
		t.Error("empty source should produce no findings with a file name too")
	}
}

func TestAuditFileSetsFile(t *testing.T) {
	src := `package demo

func Withdraw(cur realm, to address, amount int64) {
	banker.SendCoins(cur, to, amount)
}
`
	findings := AuditFile("vault.gno", src)
	expectHas(t, findings, RuleNoCallerGuard)
	f, _ := findRule(findings, RuleNoCallerGuard)
	if f.File != "vault.gno" {
		t.Errorf("expected file vault.gno, got %q", f.File)
	}
	if len(Audit(src)) != len(findings) {
		t.Error("Audit and AuditFile should return the same findings apart from File")
	}
}

func TestInputCapConstant(t *testing.T) {
	if MaxSourceBytes != 262144 {
		t.Errorf("expected MaxSourceBytes 262144, got %d", MaxSourceBytes)
	}
	if MaxFindings != 256 {
		t.Errorf("expected MaxFindings 256, got %d", MaxFindings)
	}
}

func TestAdminBackdoorHardcodedPositive(t *testing.T) {
	src := `package demo

var Admin = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
var treasury int64

func Drain(cur realm, to address) (int64, error) {
	caller := cur.Previous().Address()
	if caller != Admin {
		return 0, errors.New("only the admin can drain the treasury")
	}
	amount := treasury
	treasury = 0
	return amount, nil
}
`
	// The admin is a hard-coded constant, not a stored variable the rule
	// used to require, and the drain is a ledger assignment, not a banker
	// call. The improved rule must still catch it, at the state rewrite.
	findings := CheckAdminBackdoor(src)
	expectHas(t, findings, RuleAdminBackdoor)
	f, _ := findRule(findings, RuleAdminBackdoor)
	if f.Line != 12 {
		t.Errorf("expected finding on line 12, got %d", f.Line)
	}
	if f.SourceLine != "treasury = 0" {
		t.Errorf("expected cited source line, got %q", f.SourceLine)
	}
	// The admin comparison is a guard for the other rules, so Drain must
	// not also produce RC-01 or RC-08 findings.
	expectNotHas(t, Audit(src), RuleNoCallerGuard)
	expectNotHas(t, Audit(src), RulePublicMutation)
	if len(Audit(src)) != 1 {
		t.Errorf("expected exactly 1 finding, got %v", Audit(src))
	}
}

func TestAdminBackdoorHardcodedConstBlock(t *testing.T) {
	src := `package demo

const (
	Admin = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
)

var treasury int64

func Drain(cur realm, to address) (int64, error) {
	caller := cur.Previous().Address()
	if caller != Admin {
		return 0, errors.New("only the admin can drain the treasury")
	}
	treasury = 0
	return treasury, nil
}
`
	findings := CheckAdminBackdoor(src)
	expectHas(t, findings, RuleAdminBackdoor)
	f, _ := findRule(findings, RuleAdminBackdoor)
	if f.Line != 14 {
		t.Errorf("expected finding on line 14, got %d", f.Line)
	}
}

func TestAdminBackdoorHardcodedVarBlock(t *testing.T) {
	src := `package demo

var (
	admin address = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
)

func Withdraw(cur realm, amount int64) {
	banker.SendCoins(cur, admin, amount)
}
`
	// An admin declared inside a var block is a stored admin too. The
	// parser must read the name from the first field of a block line,
	// not the second.
	expectHas(t, CheckAdminBackdoor(src), RuleAdminBackdoor)
}

func TestAdminBackdoorCapitalMention(t *testing.T) {
	src := `package demo

var Admin address = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")

func Withdraw(cur realm, amount int64) {
	banker.SendCoins(cur, Admin, amount)
}
`
	// The drain mentions the admin as Admin, capital A. The mention
	// check must not miss it for being capitalized.
	expectHas(t, CheckAdminBackdoor(src), RuleAdminBackdoor)
}

func TestAdminBackdoorHardcodedReversedGuard(t *testing.T) {
	src := `package demo

var Admin = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
var treasury int64

func Drain(cur realm, to address) (int64, error) {
	caller := cur.Previous().Address()
	if Admin != caller {
		return 0, errors.New("only the admin can drain the treasury")
	}
	treasury = 0
	return treasury, nil
}
`
	findings := CheckAdminBackdoor(src)
	expectHas(t, findings, RuleAdminBackdoor)
	f, _ := findRule(findings, RuleAdminBackdoor)
	if f.Line != 11 {
		t.Errorf("expected finding on line 11, got %d", f.Line)
	}
	// The reversed comparison is still a guard for the other rules.
	expectNotHas(t, Audit(src), RuleNoCallerGuard)
	expectNotHas(t, Audit(src), RulePublicMutation)
}

func TestNoCallerGuardReversedAdminGuardClean(t *testing.T) {
	src := `package demo

var Admin = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
var owner address

func SetOwner(cur realm, next address) {
	if Admin != cur.Previous().Address() {
		panic("not admin")
	}
	owner = next
}
`
	expectNotHas(t, CheckNoCallerGuard(src), RuleNoCallerGuard)
}

func TestAdminBackdoorHardcodedCleanTimelock(t *testing.T) {
	src := `package demo

var Admin = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
var treasury int64
var UnlockTime int64 = 9999999999

func Drain(cur realm, to address) (int64, error) {
	caller := cur.Previous().Address()
	if caller != Admin {
		return 0, errors.New("only the admin can drain the treasury")
	}
	if runtime.ChainHeight() < UnlockTime {
		panic("timelock not expired")
	}
	treasury = 0
	return treasury, nil
}
`
	expectNotHas(t, CheckAdminBackdoor(src), RuleAdminBackdoor)
}

func TestAdminBackdoorHardcodedCleanReadOnly(t *testing.T) {
	src := `package demo

var Admin = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
var treasury int64

func Treasury() int64 {
	return treasury
}

func AdminAddress() address {
	return Admin
}
`
	// Mentioning the hard-coded admin without draining or rewriting
	// state is not a backdoor.
	expectNotHas(t, CheckAdminBackdoor(src), RuleAdminBackdoor)
}

func TestAdminBackdoorHardcodedCleanNoGuard(t *testing.T) {
	src := `package demo

var Admin = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
var treasury int64

func Withdraw(cur realm, to address, amount int64) {
	banker.SendCoins(cur, to, amount)
}
`
	// Anyone can drain here, with no admin check at all. That is RC-01,
	// not a single-admin backdoor.
	expectNotHas(t, CheckAdminBackdoor(src), RuleAdminBackdoor)
	expectHas(t, CheckNoCallerGuard(src), RuleNoCallerGuard)
}

func TestWeakRandomnessTaintPositive(t *testing.T) {
	src := `package demo

func DrawNumberAt(height int64, unixTime int64) int {
	return int((height*31 + unixTime) % 6)
}

func DrawNumber() int {
	return DrawNumberAt(runtime.ChainHeight(), time.Now().Unix())
}
`
	// The sources and the modulo live in different functions. The taint
	// must follow the parameters into the helper and flag the modulo
	// line there, exactly once. The caller itself is not flagged.
	findings := CheckWeakRandomness(src)
	expectHas(t, findings, RuleWeakRandomness)
	if len(findings) != 1 {
		t.Fatalf("expected exactly 1 finding, got %v", findings)
	}
	if findings[0].Line != 4 {
		t.Errorf("expected finding on line 4, got %d", findings[0].Line)
	}
	if findings[0].SourceLine != "return int((height*31 + unixTime) % 6)" {
		t.Errorf("expected cited source line, got %q", findings[0].SourceLine)
	}
}

func TestWeakRandomnessTaintMultiHop(t *testing.T) {
	src := `package demo

func Pick(height int64, n int) int {
	return int(height % int64(n))
}

func Middle(h int64, n int) int {
	return Pick(h, n)
}

func Start() int {
	return Middle(runtime.ChainHeight(), 6)
}
`
	// Taint flows Start -> Middle -> Pick over two hops, so the fixed
	// point must propagate it before the modulo line is checked.
	findings := CheckWeakRandomness(src)
	expectHas(t, findings, RuleWeakRandomness)
	if len(findings) != 1 {
		t.Fatalf("expected exactly 1 finding, got %v", findings)
	}
	if findings[0].Line != 4 {
		t.Errorf("expected finding on line 4, got %d", findings[0].Line)
	}
}

func TestWeakRandomnessTaintCleanDeadline(t *testing.T) {
	src := `package demo

func Check(height int64, deadline int64) bool {
	if height > deadline {
		return true
	}
	return false
}

func Start() bool {
	return Check(runtime.ChainHeight(), 1000)
}
`
	// The helper receives the height but only compares it, never applies
	// modulo or a random call to it.
	expectNotHas(t, CheckWeakRandomness(src), RuleWeakRandomness)
}

func TestWeakRandomnessTaintCleanConstantArgs(t *testing.T) {
	src := `package demo

func Pick(height int64, n int) int {
	return int(height % int64(n))
}

func Start() int {
	return Pick(10, 6)
}
`
	// The helper does the modulo, but no call site ever passes a
	// randomness source into it, so its parameter is not tainted.
	expectNotHas(t, CheckWeakRandomness(src), RuleWeakRandomness)
}

func TestWeakRandomnessTaintCleanUnused(t *testing.T) {
	src := `package demo

func Helper(height int64) int64 {
	return height + 1
}

func Start() int64 {
	return Helper(runtime.ChainHeight())
}
`
	// The helper receives the height but never applies modulo or a random
	// call to it.
	expectNotHas(t, CheckWeakRandomness(src), RuleWeakRandomness)
}

func TestWeakRandomnessTaintVariableLimitation(t *testing.T) {
	src := `package demo

func DrawNumberAt(height int64, unixTime int64) int {
	return int((height*31 + unixTime) % 6)
}

func DrawNumber() int {
	h := runtime.ChainHeight()
	t := time.Now().Unix()
	return DrawNumberAt(h, t)
}
`
	// Known limit, pinned so it does not silently change: taint follows
	// parameters across calls, not local variables. When the caller
	// stores the sources in locals first, the helper is not flagged.
	expectNotHas(t, CheckWeakRandomness(src), RuleWeakRandomness)
}

func TestAssertGuardCountsForCallerGuard(t *testing.T) {
	src := `package demo

func assertDelegate(level int, rlm realm, want string) {
	if want == "" {
		panic("no delegate")
	}
}

func Withdraw(cur realm, to address, amount int64) {
	assertDelegate(0, cur, "manager")
	banker.SendCoins(cur, to, amount)
}
`
	// An assert* helper call is a guard: it panics when its check fails.
	expectNotHas(t, CheckNoCallerGuard(src), RuleNoCallerGuard)
}

func TestAssertGuardCountsForPublicMutation(t *testing.T) {
	src := `package demo

func assertDelegate(level int, rlm realm, want string) {
	if want == "" {
		panic("no delegate")
	}
}

var store *Store

func SetSetting(cur realm, key string, value string) {
	assertDelegate(0, cur, "manager")
	store.Set(key, value)
}
`
	expectNotHas(t, CheckPublicStateMutation(src), RulePublicMutation)
}

func TestPublicMutationUnexportedReceiverClean(t *testing.T) {
	src := `package demo

type Proposals struct {
	seq int64
}

func (ps *Proposals) SetProposal(p *Proposal) int64 {
	updated := ps.Set("1", p)
	if updated {
		panic("override not allowed")
	}
	ps.seq++
	return ps.seq
}
`
	// The gov/dao shape: SetProposal mutates only its own receiver
	// (ps.Set, ps.seq), never shared realm state, so it is not a public
	// state mutation. Note the type name is capitalized, so it is
	// exported by name; what clears it is the receiver-target rule, not
	// the unexported-type rule. A method that assigned a package-level
	// variable would still be flagged; see the next test.
	expectNotHas(t, CheckPublicStateMutation(src), RulePublicMutation)
}

func TestPublicMutationLowercaseReceiverClean(t *testing.T) {
	src := `package demo

type proposals struct {
	seq int64
}

var store *Store

func (ps *proposals) Save(key string, value string) {
	store.Set(key, value)
}
`
	// A method on a genuinely unexported type is not part of the public
	// API at all, so even a Set on shared state inside it is not
	// flagged. Only the realm's own functions can reach it, and they are
	// audited separately.
	expectNotHas(t, CheckPublicStateMutation(src), RulePublicMutation)
}

func TestPublicMutationMethodPackageVarPositive(t *testing.T) {
	src := `package demo

type Registry struct {
	seq int64
}

var treasury int64

func (r *Registry) Reset(amount int64) int64 {
	treasury = 0
	return amount
}
`
	// The receiver-target rule has a boundary: a method that assigns a
	// package-level variable rewrites shared realm state, so it is still
	// flagged even though it is a method.
	findings := CheckPublicStateMutation(src)
	expectHas(t, findings, RulePublicMutation)
	f, _ := findRule(findings, RulePublicMutation)
	if f.Line != 10 {
		t.Errorf("expected finding on line 10, got %d", f.Line)
	}
}

func TestPublicMutationExportedReceiverPositive(t *testing.T) {
	src := `package demo

type Registry struct {
	seq int64
}

func (r *Registry) Put(key string, value string) {
	r.store.Set(key, value)
}
`
	// The same shape on an exported receiver type is still a public
	// mutation when it has no guard.
	findings := CheckPublicStateMutation(src)
	expectHas(t, findings, RulePublicMutation)
	f, _ := findRule(findings, RulePublicMutation)
	if f.Line != 8 {
		t.Errorf("expected finding on line 8, got %d", f.Line)
	}
}

func TestUnrestrictedMintUnexportedReceiverClean(t *testing.T) {
	src := `package demo

type minter struct {
	total int64
}

func (m *minter) Mint(to address, amount int64) {
	banker.IssueCoin(to, "demo", amount)
	m.total += amount
}
`
	// A Mint method on an unexported type is only reachable from the
	// realm's own code, so it is not an unrestricted public mint.
	expectNotHas(t, CheckUnrestrictedMint(src), RuleUnrestrictedMint)
}
