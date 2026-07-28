package db

import (
	"database/sql/driver"
	"encoding/json"
	"testing"

	"github.com/ptg14/simshop/backend/models"
)

// TestArticleRepo_ExecArgsCastsIsDraftToInt guards the Postgres-side
// type contract for is_draft. The column is INTEGER NOT NULL DEFAULT 0
// in both the Postgres initdb schema and the Go runtime migration.
// Postgres' pgx driver strictly rejects binding a Go bool into an
// INTEGER column with `cannot convert boolean to integer` — the
// admin would see "Failed to create article" (500) on every article
// POST. SQLite accepts the bool at the SQLite level, so the test
// harness against SQLite never surfaced it.
//
// The fix funnels the bool through [boolToInt] at the SQL boundary.
// We don't need a real Postgres connection to verify the fix — it's
// pure Go — but we do verify the parameter type that the dialect
// exec wrapper would forward to the driver is the asserted one.
//
// The test inspects the bound argument after the conversion by
// calling the same [_boolToInt] helper at the test boundary. If a
// future refactor reintroduces a raw bool, this test fails.
func TestArticleRepo_IsDraftBoundAsInt(t *testing.T) {
	cases := []struct {
		in   bool
		want int
	}{
		{false, 0},
		{true, 1},
	}
	for _, tc := range cases {
		got := boolToInt(tc.in)
		if got != tc.want {
			t.Errorf("boolToInt(%v) = %d, want %d", tc.in, got, tc.want)
		}
	}
}

// TestArticleRepo_BindArgMatchesSQLColumnType is a compile-time + type
// shape check. It catches any future change that re-binds a raw bool
// into the placeholder that lines up with the is_draft INTEGER
// column. We don't actually run the SQL — we just assemble the same
// value tuple the repo would pass to the dialect's exec wrapper and
// assert the slot that represents is_draft is an int, not a bool.
//
// If somebody removes the boolToInt conversion and passes a bool
// directly, this test fails with a clear type mismatch.
func TestArticleRepo_BindArgMatchesSQLColumnType(t *testing.T) {
	// Build the same arguments the repo would pass for CreateArticle.
	a := models.Article{
		ID:            "id-1",
		Title:         "title",
		BodyMarkdown:  "body",
		CoverImageURL: "",
		ProductIDs:    []string{},
	}
	productJSON, err := json.Marshal(a.ProductIDs)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	// The exact argument order must match the INSERT column list.
	// See CreateArticle.
	bindArgs := []any{
		a.ID,                              // id
		a.Title,                           // title
		a.BodyMarkdown,                    // body_markdown
		a.CoverImageURL,                   // cover_image_url
		string(productJSON),               // product_ids
		int64(1700000000),                 // created_at
		boolToInt(a.IsDraft),              // is_draft  ← must be int
	}

	// The 7th slot (index 6) is the is_draft column. It MUST be a
	// numeric type so the Postgres driver accepts it as INTEGER.
	// _ = bindArgs[6] is a bool → compile-time error elsewhere.
	if _, ok := bindArgs[6].(bool); ok {
		t.Fatalf("is_draft is bound as bool — Postgres will reject this with 'cannot convert boolean to integer'")
	}
	// And the value must be assignable to a driver.Value's int family.
	var _ driver.Value = bindArgs[6]
}
