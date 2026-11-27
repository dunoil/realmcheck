package unguardedvault

import (
	"chain"
	"testing"
)

// resetState clears all realm state so each test starts fresh. The Gno test
// runner keeps package state between tests in one run, so tests must reset.
func resetState() {
	deposits = map[address]int64{}
	paidOut = map[address]int64{}
	vaultBalance = 0
}

func TestDepositWithoutSendingCoins(cur realm, t *testing.T) {
	resetState()
	alice := address("alice")

	// Alice claims a deposit of 1000 without sending any coins at all.
	// There is no payment to verify in this call, yet the credit lands.
	testing.SetOriginCaller(alice)
	Deposit(cross(cur), 1000)
	if got := BalanceOf(alice); got != 1000 {
		t.Fatalf("BalanceOf(alice) = %d, want %d", got, 1000)
	}
	if got := VaultBalance(); got != 1000 {
		t.Fatalf("VaultBalance() = %d, want %d", got, 1000)
	}
}

func TestDepositIgnoresSentAmount(cur realm, t *testing.T) {
	resetState()
	alice := address("alice")

	// Banker setup: Alice really holds 10 ugnot and really sends 10 ugnot
	// with the call. The test proves the setup first, so the assertion
	// below cannot pass by accident: Deposit must credit the claimed
	// 1000, not the 10 actually sent.
	testing.SetOriginCaller(alice)
	testing.IssueCoins(alice, chain.Coins{{"ugnot", 10}})
	testing.SetOriginSend(chain.Coins{{"ugnot", 10}})
	if got := testing.GetContext().OriginSend.AmountOf("ugnot"); got != 10 {
		t.Fatalf("OriginSend = %d ugnot, want %d: the test setup did not send what it claims", got, 10)
	}
	Deposit(cross(cur), 1000)
	if got := BalanceOf(alice); got != 1000 {
		t.Fatalf("BalanceOf(alice) = %d, want %d: the deposit credited the claimed amount, not the 10 ugnot actually sent", got, 1000)
	}
	if got := VaultBalance(); got != 1000 {
		t.Fatalf("VaultBalance() = %d, want %d", got, 1000)
	}
}

func TestAnyoneCanWithdraw(cur realm, t *testing.T) {
	resetState()
	alice := address("alice")
	attacker := address("attacker")

	// Alice deposits 1000.
	testing.SetOriginCaller(alice)
	Deposit(cross(cur), 1000)

	// The attacker never deposited anything, but Withdraw has no caller
	// check, so the attacker can send Alice's deposit to itself.
	testing.SetOriginCaller(attacker)
	if err := Withdraw(cross(cur), attacker, 1000); err != nil {
		t.Fatalf("Withdraw returned unexpected error: %v", err)
	}
	if got := VaultBalance(); got != 0 {
		t.Fatalf("VaultBalance() = %d, want %d", got, 0)
	}
	if got := PaidOut(attacker); got != 1000 {
		t.Fatalf("PaidOut(attacker) = %d, want %d", got, 1000)
	}
	// Alice's recorded deposit is still 1000: the vault paid out funds it
	// still claims to owe her. The books no longer add up.
	if got := BalanceOf(alice); got != 1000 {
		t.Fatalf("BalanceOf(alice) = %d, want %d", got, 1000)
	}
}

func TestWithdrawMoreThanBalanceErrors(cur realm, t *testing.T) {
	resetState()
	alice := address("alice")

	testing.SetOriginCaller(alice)
	Deposit(cross(cur), 50)
	if err := Withdraw(cross(cur), alice, 51); err == nil {
		t.Fatalf("Withdraw of more than the vault balance should return an error")
	}
	if got := VaultBalance(); got != 50 {
		t.Fatalf("VaultBalance() = %d, want %d", got, 50)
	}
}

func TestRender(cur realm, t *testing.T) {
	resetState()
	testing.SetOriginCaller(address("alice"))
	Deposit(cross(cur), 5)
	out := Render("")
	if out == "" {
		t.Fatalf("Render returned an empty string")
	}
}
