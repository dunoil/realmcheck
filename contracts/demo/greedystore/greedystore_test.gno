package greedystore

import (
	"strings"
	"testing"
)

// resetState clears all realm state so each test starts fresh. The Gno test
// runner keeps package state between tests in one run, so tests must reset.
func resetState() {
	entries = nil
	nextID = 0
}

func TestRegisterByAnyone(cur realm, t *testing.T) {
	resetState()

	// Two strangers with no role can both register. There is no guard.
	testing.SetOriginCaller(address("alice"))
	id1 := Register(cross(cur), "first", "hello")
	testing.SetOriginCaller(address("bob"))
	id2 := Register(cross(cur), "second", "world")
	if id1 != 0 || id2 != 1 {
		t.Fatalf("entry IDs = %d, %d, want 0, 1", id1, id2)
	}
	if got := EntryCount(); got != 2 {
		t.Fatalf("EntryCount() = %d, want %d", got, 2)
	}
	entry, ok := GetEntry(1)
	if !ok {
		t.Fatalf("GetEntry(1) not found")
	}
	if entry.Author != address("bob") {
		t.Fatalf("entry author = %q, want %q", entry.Author, "bob")
	}
	if entry.Title != "second" {
		t.Fatalf("entry title = %q, want %q", entry.Title, "second")
	}
}

func TestStorageGrowsWithoutBound(cur realm, t *testing.T) {
	resetState()
	testing.SetOriginCaller(address("alice"))

	// 300 registrations in a row, and nothing stops any of them. No cap
	// is ever hit, because there is no cap. The count is kept modest so
	// the suite stays fast; the code contains no limit at any size.
	for i := 0; i < 300; i++ {
		Register(cross(cur), "entry", "data")
	}
	if got := EntryCount(); got != 300 {
		t.Fatalf("EntryCount() = %d, want %d", got, 300)
	}
}

func TestOversizedEntryAccepted(cur realm, t *testing.T) {
	resetState()
	testing.SetOriginCaller(address("alice"))

	// A single 100,000 character entry is stored without complaint. There
	// is no per-entry size limit either.
	big := strings.Repeat("x", 100000)
	id := Register(cross(cur), "big", big)
	entry, ok := GetEntry(id)
	if !ok {
		t.Fatalf("GetEntry(%d) not found", id)
	}
	if len(entry.Data) != 100000 {
		t.Fatalf("stored entry size = %d, want %d", len(entry.Data), 100000)
	}
}

func TestRender(cur realm, t *testing.T) {
	resetState()
	testing.SetOriginCaller(address("alice"))
	Register(cross(cur), "one", "data")
	out := Render("")
	if out == "" {
		t.Fatalf("Render returned an empty string")
	}
}
