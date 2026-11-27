package adminbackdoor

import (
	"testing"

	vulnmint "gno.land/r/dunoil/vulnmint"
)

// resetState clears this realm's own state so each test starts fresh. The
// Gno test runner keeps package state between tests in one run, so tests
// must reset. The vulnmint pool is shared state, so tests below only assert
// relative changes to it, never an absolute zero.
func resetState() {
	treasury = 0
	drainedTo = map[address]int64{}
	paid = map[address]int64{}
}

func TestNonAdminCannotDrain(cur realm, t *testing.T) {
	resetState()
	alice := address("alice")
	bob := address("bob")

	testing.SetOriginCaller(alice)
	Fund(cross(cur), 1000)

	testing.SetOriginCaller(bob)
	if _, err := Drain(cross(cur), bob); err == nil {
		t.Fatalf("Drain by a non-admin should return an error")
	}
	if got := Treasury(); got != 1000 {
		t.Fatalf("Treasury() = %d, want %d after a rejected drain", got, 1000)
	}
}

func TestAdminDrainsEverythingImmediately(cur realm, t *testing.T) {
	resetState()
	alice := address("alice")
	payout := address("payout")

	testing.SetOriginCaller(alice)
	Fund(cross(cur), 1000)

	// The admin drains the whole treasury in one call, to any address it
	// chooses. There is no timelock to wait out, no cap, and no second
	// approver to stop it.
	testing.SetOriginCaller(Admin)
	amount, err := Drain(cross(cur), payout)
	if err != nil {
		t.Fatalf("Drain by the admin returned unexpected error: %v", err)
	}
	if amount != 1000 {
		t.Fatalf("Drain returned %d, want %d", amount, 1000)
	}
	if got := Treasury(); got != 0 {
		t.Fatalf("Treasury() = %d, want %d after the drain", got, 0)
	}
	if got := DrainedTo(payout); got != 1000 {
		t.Fatalf("DrainedTo(payout) = %d, want %d", got, 1000)
	}
}

func TestPayBonusIgnoresFailedTransfer(cur realm, t *testing.T) {
	resetState()
	bob := address("bob")

	// Pay more than the whole bonus pool, so the vulnmint transfer must
	// fail with insufficient balance. PayBonus ignores the error and still
	// records the bonus as paid, while the recipient receives nothing.
	testing.SetOriginCaller(address("alice"))
	before := vulnmint.BalanceOf(bob)
	amount := BonusPool() + 500
	PayBonus(cross(cur), bob, amount)
	if got := PaidBonus(bob); got != amount {
		t.Fatalf("PaidBonus(bob) = %d, want %d", got, amount)
	}
	if got := vulnmint.BalanceOf(bob); got != before {
		t.Fatalf("vulnmint balance of bob = %d, want %d: the transfer failed but was recorded as paid", got, before)
	}
}

func TestPayBonusWorksWhenFunded(cur realm, t *testing.T) {
	resetState()
	bob := address("bob")

	testing.SetOriginCaller(address("alice"))
	before := vulnmint.BalanceOf(bob)
	FundBonusPool(cross(cur), 1000)
	PayBonus(cross(cur), bob, 400)
	if got := PaidBonus(bob); got != 400 {
		t.Fatalf("PaidBonus(bob) = %d, want %d", got, 400)
	}
	if got := vulnmint.BalanceOf(bob); got != before+400 {
		t.Fatalf("vulnmint balance of bob = %d, want %d", got, before+400)
	}
}

func TestRender(cur realm, t *testing.T) {
	resetState()
	testing.SetOriginCaller(address("alice"))
	Fund(cross(cur), 5)
	out := Render("")
	if out == "" {
		t.Fatalf("Render returned an empty string")
	}
}
