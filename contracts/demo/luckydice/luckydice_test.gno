package luckydice

import (
	"chain"
	"testing"

	"chain/runtime"
	"time"
)

// resetState clears all realm state so each test starts fresh. The Gno test
// runner keeps package state between tests in one run, so tests must reset.
func resetState() {
	chips = map[address]int64{}
	gamesPlayed = 0
	totalWagered = 0
	totalPaid = 0
}

func TestDrawNumberAtKnownValues(t *testing.T) {
	// Hand computed: (10*31 + 1700000000) % 6 = 0, and
	// (11*31 + 1700000000) % 6 = 1. The formula is exact and public, so
	// anyone can reproduce the draw off chain.
	if got := DrawNumberAt(10, 1700000000); got != 0 {
		t.Fatalf("DrawNumberAt(10, 1700000000) = %d, want %d", got, 0)
	}
	if got := DrawNumberAt(11, 1700000000); got != 1 {
		t.Fatalf("DrawNumberAt(11, 1700000000) = %d, want %d", got, 1)
	}
	if got := DrawNumberAt(10, 1700000000); got != DrawNumberAt(10, 1700000000) {
		t.Fatalf("DrawNumberAt is not deterministic")
	}
}

func TestDrawNumberMatchesFormula(t *testing.T) {
	// The live draw is exactly the public formula applied to the public
	// height and time. Read both inputs at once and compare.
	height := runtime.ChainHeight()
	now := time.Now().Unix()
	if got := DrawNumber(); got != DrawNumberAt(height, now) {
		t.Fatalf("DrawNumber() = %d, want DrawNumberAt(%d, %d) = %d", got, height, now, DrawNumberAt(height, now))
	}
}

func TestPredictedGuessWins(cur realm, t *testing.T) {
	resetState()
	alice := address("alice")
	testing.SetOriginCaller(alice)
	BuyChips(cross(cur), 1000)

	// An attacker reads the public winning number, then bets on it. The
	// block height does not change during the test and the time is read
	// fresh on each attempt, so retry a few times in case a second ticks
	// over between reading the number and placing the bet.
	won := false
	for attempt := 0; attempt < 10 && !won; attempt++ {
		n := DrawNumber()
		w, err := PlaceBet(cross(cur), n)
		if err != nil {
			t.Fatalf("PlaceBet returned unexpected error: %v", err)
		}
		won = w
	}
	if !won {
		t.Fatalf("betting the publicly readable winning number never won in 10 attempts")
	}
	// Alice staked 100 at least once and won 500 at least once, so she is
	// ahead. A predictable game pays the player who reads the draw.
	if got := ChipsOf(alice); got <= 1000 {
		t.Fatalf("ChipsOf(alice) = %d, want more than %d after a predicted win", got, 1000)
	}
}

func TestBuyChipsIgnoresSentAmount(cur realm, t *testing.T) {
	resetState()
	alice := address("alice")

	// Banker setup: Alice really holds 10 ugnot and really sends 10 ugnot
	// with the call. The test proves the setup first, so the assertion
	// below cannot pass by accident: BuyChips must credit the claimed
	// 1000 chips, not the 10 ugnot actually sent.
	testing.SetOriginCaller(alice)
	testing.IssueCoins(alice, chain.Coins{{"ugnot", 10}})
	testing.SetOriginSend(chain.Coins{{"ugnot", 10}})
	if got := testing.GetContext().OriginSend.AmountOf("ugnot"); got != 10 {
		t.Fatalf("OriginSend = %d ugnot, want %d: the test setup did not send what it claims", got, 10)
	}
	BuyChips(cross(cur), 1000)
	if got := ChipsOf(alice); got != 1000 {
		t.Fatalf("ChipsOf(alice) = %d, want %d: BuyChips credited the claimed amount, not the 10 ugnot actually sent", got, 1000)
	}
}

func TestPlaceBetInsufficientChips(cur realm, t *testing.T) {
	resetState()
	alice := address("alice")
	testing.SetOriginCaller(alice)
	if _, err := PlaceBet(cross(cur), 0); err == nil {
		t.Fatalf("PlaceBet with no chips should return an error")
	}
}

func TestPlaceBetBadGuess(cur realm, t *testing.T) {
	resetState()
	alice := address("alice")
	testing.SetOriginCaller(alice)
	BuyChips(cross(cur), 1000)
	if _, err := PlaceBet(cross(cur), 6); err == nil {
		t.Fatalf("PlaceBet with guess 6 should return an error")
	}
}

func TestRender(cur realm, t *testing.T) {
	resetState()
	testing.SetOriginCaller(address("alice"))
	BuyChips(cross(cur), 100)
	out := Render("")
	if out == "" {
		t.Fatalf("Render returned an empty string")
	}
}
