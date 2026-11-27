package realmcheck

import (
	"strings"
	"testing"

	"gno.land/p/dunoil/auditrules"
)

// resetState clears all realm state so each test starts fresh. The Gno test
// runner keeps package state between tests in one run, so tests must reset.
func resetState() {
	reports = map[int]auditrules.Report{}
	latestByRealm = map[string]int{}
	nextID = 1
}

func TestSubmitReportStoresReport(cur realm, t *testing.T) {
	resetState()
	testing.SetOriginCaller(address("alice"))
	findings := "RC-02|Critical|14|Unrestricted mint|Mint has no access control|func Mint(to string, amount int64) {\n" +
		"RC-01|High|22|Sensitive function without caller check|Withdraw moves funds with no guard|func Withdraw(amount int64) {"
	id := SubmitReport(cross(cur), "gno.land/r/dunoil/vulnmint", "abcdef1234567890", 60, findings)
	if id != 1 {
		t.Fatalf("SubmitReport returned id %d, want 1", id)
	}
	r, ok := GetReport(1)
	if !ok {
		t.Fatalf("GetReport(1) returned false, want a report")
	}
	if r.RealmPath != "gno.land/r/dunoil/vulnmint" {
		t.Fatalf("RealmPath = %q, want %q", r.RealmPath, "gno.land/r/dunoil/vulnmint")
	}
	if r.SourceHash != "abcdef1234567890" {
		t.Fatalf("SourceHash = %q, want %q", r.SourceHash, "abcdef1234567890")
	}
	if r.Score != 60 {
		t.Fatalf("Score = %d, want 60", r.Score)
	}
	if r.Auditor != "alice" {
		t.Fatalf("Auditor = %q, want %q", r.Auditor, "alice")
	}
	if len(r.Findings) != 2 {
		t.Fatalf("len(Findings) = %d, want 2", len(r.Findings))
	}
	if r.Findings[0].RuleID != "RC-02" {
		t.Fatalf("Findings[0].RuleID = %q, want RC-02", r.Findings[0].RuleID)
	}
	if r.Findings[0].Line != 14 {
		t.Fatalf("Findings[0].Line = %d, want 14", r.Findings[0].Line)
	}
	if r.Findings[0].SourceLine != "func Mint(to string, amount int64) {" {
		t.Fatalf("Findings[0].SourceLine = %q, unexpected", r.Findings[0].SourceLine)
	}
	if r.Findings[1].RuleID != "RC-01" {
		t.Fatalf("Findings[1].RuleID = %q, want RC-01", r.Findings[1].RuleID)
	}
	if got := ReportCount(); got != 1 {
		t.Fatalf("ReportCount() = %d, want 1", got)
	}
}

func TestLatestReportReturnsNewest(cur realm, t *testing.T) {
	resetState()
	testing.SetOriginCaller(address("alice"))
	SubmitReport(cross(cur), "gno.land/r/dunoil/vulnmint", "aaaa1111", 60, "RC-02|Critical|14|Unrestricted mint|Mint has no access control|func Mint() {")
	testing.SetOriginCaller(address("bob"))
	id2 := SubmitReport(cross(cur), "gno.land/r/dunoil/vulnmint", "bbbb2222", 85, "RC-04|Medium|30|Unbounded storage growth|List grows with no cap|items = append(items, e)")
	if id2 != 2 {
		t.Fatalf("second SubmitReport returned id %d, want 2", id2)
	}
	r, ok := LatestReport("gno.land/r/dunoil/vulnmint")
	if !ok {
		t.Fatalf("LatestReport returned false, want a report")
	}
	if r.ID != 2 {
		t.Fatalf("LatestReport ID = %d, want 2", r.ID)
	}
	if r.SourceHash != "bbbb2222" {
		t.Fatalf("LatestReport SourceHash = %q, want bbbb2222", r.SourceHash)
	}
	if r.Auditor != "bob" {
		t.Fatalf("LatestReport Auditor = %q, want bob", r.Auditor)
	}
	if got := ReportCount(); got != 2 {
		t.Fatalf("ReportCount() = %d, want 2", got)
	}
}

func TestGetReportMissing(cur realm, t *testing.T) {
	resetState()
	if _, ok := GetReport(999); ok {
		t.Fatalf("GetReport(999) returned true, want false")
	}
	if _, ok := LatestReport("gno.land/r/dunoil/nothing"); ok {
		t.Fatalf("LatestReport for an unknown realm returned true, want false")
	}
	if got := ReportCount(); got != 0 {
		t.Fatalf("ReportCount() = %d, want 0", got)
	}
}

func TestSubmitReportEmptyFindings(cur realm, t *testing.T) {
	resetState()
	testing.SetOriginCaller(address("alice"))
	id := SubmitReport(cross(cur), "gno.land/r/dunoil/clean", "00ff11aa", 100, "")
	if id != 1 {
		t.Fatalf("SubmitReport returned id %d, want 1", id)
	}
	r, ok := GetReport(1)
	if !ok {
		t.Fatalf("GetReport(1) returned false, want a report")
	}
	if r.Score != 100 {
		t.Fatalf("Score = %d, want 100", r.Score)
	}
	if len(r.Findings) != 0 {
		t.Fatalf("len(Findings) = %d, want 0", len(r.Findings))
	}
}

func TestSubmitReportSkipsMalformedLines(cur realm, t *testing.T) {
	resetState()
	testing.SetOriginCaller(address("alice"))
	findings := "RC-02|Critical|14|Unrestricted mint|Mint has no access control|func Mint() {\n" +
		"this line has no separators\n" +
		"RC-99|Critical|20|Unknown rule|No such rule|func X() {\n" +
		"RC-01|High|notanumber|Bad line number|Line is not a number|func Y() {\n" +
		"RC-01|High|22|Sensitive function without caller check|Withdraw moves funds with no guard|func Withdraw() {"
	id := SubmitReport(cross(cur), "gno.land/r/dunoil/vulnmint", "aabb99", 60, findings)
	if id != 1 {
		t.Fatalf("SubmitReport returned id %d, want 1", id)
	}
	r, _ := GetReport(1)
	if len(r.Findings) != 2 {
		t.Fatalf("len(Findings) = %d, want 2 (only the well formed lines)", len(r.Findings))
	}
	if r.Findings[0].RuleID != "RC-02" || r.Findings[1].RuleID != "RC-01" {
		t.Fatalf("kept findings are %q and %q, want RC-02 and RC-01", r.Findings[0].RuleID, r.Findings[1].RuleID)
	}
}

func TestSubmitReportUnknownSeverityFallsBackToCatalog(cur realm, t *testing.T) {
	resetState()
	testing.SetOriginCaller(address("alice"))
	SubmitReport(cross(cur), "gno.land/r/dunoil/vulnmint", "aabb77", 60, "RC-02|Bogus|14|Unrestricted mint|Mint has no access control|func Mint() {")
	r, _ := GetReport(1)
	if len(r.Findings) != 1 {
		t.Fatalf("len(Findings) = %d, want 1", len(r.Findings))
	}
	if r.Findings[0].Severity != auditrules.SeverityCritical {
		t.Fatalf("Severity = %q, want the catalog severity Critical", r.Findings[0].Severity)
	}
}

func TestRenderListsReports(cur realm, t *testing.T) {
	resetState()
	testing.SetOriginCaller(address("alice"))
	SubmitReport(cross(cur), "gno.land/r/dunoil/vulnmint", "aaaa1111", 60, "RC-02|Critical|14|Unrestricted mint|Mint has no access control|func Mint() {")
	SubmitReport(cross(cur), "gno.land/r/dunoil/luckydice", "bbbb2222", 92, "RC-06|Medium|77|Weak randomness|Height used with modulo|return DrawNumberAt(runtime.ChainHeight(), time.Now().Unix())")
	out := Render("")
	if out == "" {
		t.Fatalf("Render returned an empty string")
	}
	if !strings.Contains(out, "gno.land/r/dunoil/vulnmint") {
		t.Fatalf("Render does not mention vulnmint")
	}
	if !strings.Contains(out, "gno.land/r/dunoil/luckydice") {
		t.Fatalf("Render does not mention luckydice")
	}
	if !strings.Contains(out, "score 60") || !strings.Contains(out, "score 92") {
		t.Fatalf("Render does not show both scores")
	}
}

func TestReportFindingsRoundTrip(cur realm, t *testing.T) {
	resetState()
	testing.SetOriginCaller(address("alice"))
	encoded := "RC-02|Critical|14|Unrestricted mint|Mint has no access control|func Mint() {\n" +
		"RC-01|High|22|Sensitive function without caller check|Withdraw moves funds with no guard|func Withdraw() {"
	id := SubmitReport(cross(cur), "gno.land/r/dunoil/vulnmint", "abcdef1234567890", 60, encoded)
	got := ReportFindings(id)
	// Severities are canonicalized to the catalog values (lowercase) on store.
	want := "RC-02|critical|14|Unrestricted mint|Mint has no access control|func Mint() {\n" +
		"RC-01|high|22|Sensitive function without caller check|Withdraw moves funds with no guard|func Withdraw() {"
	if got != want {
		t.Fatalf("ReportFindings returned %q, want %q", got, want)
	}
	if got := ReportFindings(999); got != "" {
		t.Fatalf("ReportFindings(999) returned %q, want empty", got)
	}
}

func TestRenderEmpty(cur realm, t *testing.T) {
	resetState()
	out := Render("")
	if !strings.Contains(out, "No reports stored yet") {
		t.Fatalf("Render on an empty store should say no reports are stored yet")
	}
}

func TestIsSafeRealmPath(t *testing.T) {
	good := []string{
		"gno.land/r/dunoil/vulnmint",
		"gno.land/p/dunoil/auditrules",
		"gno.land/r/gnoland/boards",
		"gno.land/r/a.b-c_d/e",
	}
	for _, p := range good {
		if !isSafeRealmPath(p) {
			t.Fatalf("isSafeRealmPath(%q) = false, want true", p)
		}
	}
	bad := []string{
		"",
		"gno.land/r/evil\n- injected line",
		"gno.land/r/evil|pipe",
		"gno.land/r/evil [link](https://example.com)",
		"example.com/r/dunoil/vulnmint",
		"gno.land/r/evil realm",
		"gno.land/r/evil?x=1",
	}
	for _, p := range bad {
		if isSafeRealmPath(p) {
			t.Fatalf("isSafeRealmPath(%q) = true, want false", p)
		}
	}
}

func TestIsHexHash(t *testing.T) {
	if !isHexHash("f8616d8b7c69e820e2b20aa49f970c8a7fe64e6e390367ae464f93db627f5b7e") {
		t.Fatalf("isHexHash of a SHA-256 hex string should be true")
	}
	if !isHexHash("ABCDEF0123456789") {
		t.Fatalf("isHexHash of uppercase hex should be true")
	}
	bad := []string{"", "xyz", "f8616d8b7c69e820e2b20aa49f970c8a7fe64e6e390367ae464f93db627f5b7e!", "hash with spaces"}
	for _, s := range bad {
		if isHexHash(s) {
			t.Fatalf("isHexHash(%q) = true, want false", s)
		}
	}
	long := ""
	for i := 0; i < 129; i++ {
		long += "a"
	}
	if isHexHash(long) {
		t.Fatalf("isHexHash of a 129 character string should be false")
	}
}
