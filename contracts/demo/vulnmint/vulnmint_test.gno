package vulnmint

import "testing"

// resetState clears all realm state so each test starts fresh. The Gno test
// runner keeps package state between tests in one run, so tests must reset.
func resetState() {
	balances = map[address]int64{}
	totalSupply = 0
}

func TestMintByAnyone(cur realm, t *testing.T) {
	resetState()
	alice := address("alice")
	bob := address("bob")

	// Alice is a stranger with no role at all, yet she can mint.
	testing.SetOriginCaller(alice)
	Mint(cross(cur), alice, 1000000)
	if got := BalanceOf(alice); got != 1000000 {
		t.Fatalf("BalanceOf(alice) = %d, want %d", got, 1000000)
	}
	if got := TotalSupply(); got != 1000000 {
		t.Fatalf("TotalSupply() = %d, want %d", got, 1000000)
	}

	// Bob, another stranger, can mint to himself too. Supply is unbounded.
	testing.SetOriginCaller(bob)
	Mint(cross(cur), bob, 500000)
	if got := BalanceOf(bob); got != 500000 {
		t.Fatalf("BalanceOf(bob) = %d, want %d", got, 500000)
	}
	if got := TotalSupply(); got != 1500000 {
		t.Fatalf("TotalSupply() = %d, want %d", got, 1500000)
	}
}

func TestMintToAnyAddress(cur realm, t *testing.T) {
	resetState()
	alice := address("alice")
	victim := address("victim")

	// Alice can mint tokens straight into someone else's balance.
	testing.SetOriginCaller(alice)
	Mint(cross(cur), victim, 42)
	if got := BalanceOf(victim); got != 42 {
		t.Fatalf("BalanceOf(victim) = %d, want %d", got, 42)
	}
}

func TestTransferMovesBalance(cur realm, t *testing.T) {
	resetState()
	alice := address("alice")
	bob := address("bob")

	testing.SetOriginCaller(alice)
	Mint(cross(cur), alice, 1000)

	if err := Transfer(cross(cur), bob, 300); err != nil {
		t.Fatalf("Transfer returned unexpected error: %v", err)
	}
	if got := BalanceOf(alice); got != 700 {
		t.Fatalf("BalanceOf(alice) = %d, want %d", got, 700)
	}
	if got := BalanceOf(bob); got != 300 {
		t.Fatalf("BalanceOf(bob) = %d, want %d", got, 300)
	}
	// Moving tokens does not change the total supply.
	if got := TotalSupply(); got != 1000 {
		t.Fatalf("TotalSupply() = %d, want %d", got, 1000)
	}
}

func TestTransferInsufficientBalanceErrors(cur realm, t *testing.T) {
	resetState()
	alice := address("alice")
	bob := address("bob")

	testing.SetOriginCaller(alice)
	Mint(cross(cur), alice, 10)
	if err := Transfer(cross(cur), bob, 11); err == nil {
		t.Fatalf("Transfer of more than the balance should return an error")
	}
	if got := BalanceOf(bob); got != 0 {
		t.Fatalf("BalanceOf(bob) = %d, want %d", got, 0)
	}
}

func TestRender(cur realm, t *testing.T) {
	resetState()
	testing.SetOriginCaller(address("alice"))
	Mint(cross(cur), address("alice"), 7)
	out := Render("")
	if out == "" {
		t.Fatalf("Render returned an empty string")
	}
	if got := TotalSupply(); got != 7 {
		t.Fatalf("TotalSupply() = %d, want %d", got, 7)
	}
}
