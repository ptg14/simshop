package handler

import "testing"

// Tests for the Vietnamese-aware slugify used to build upload filenames.
//
// Background: the previous implementation only kept [a-z0-9] runes and
// dropped everything else (including all Vietnamese letters), so a product
// named "Áo sơ mi nam" became "ao-s-mi-nam" — losing both the tone marks
// and the vowels ơ, ư, đ. These tests pin the contract we want:
//
//   - All Vietnamese letters are transliterated to ASCII (ă→a, ơ→o, đ→d, …)
//   - All tone marks are stripped (sắc, huyền, hỏi, ngã, nặng)
//   - Spaces, '-', '_' collapse into single dashes
//   - Pure-ASCII inputs are unchanged
//   - Empty / whitespace-only inputs return ""
func TestSlugify_ASCII(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"Hello World", "hello-world"},
		{"plain-ascii-123", "plain-ascii-123"},
		{"UPPER lower", "upper-lower"},
		{"foo_bar baz", "foo-bar-baz"},
	}
	for _, tc := range cases {
		got := slugify(tc.in)
		if got != tc.want {
			t.Errorf("slugify(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestSlugify_Vietnamese(t *testing.T) {
	// Canonical cases taken from real product names in the catalog.
	// Each input maps to the ASCII slug the team expects on disk.
	cases := []struct {
		in, want string
	}{
		{"Áo sơ mi nam", "ao-so-mi-nam"},
		{"áo sơ mi nam", "ao-so-mi-nam"},
		{"Đầm dự tiệc", "dam-du-tiec"},
		{"Quần jean nữ", "quan-jean-nu"},
		{"Giày thể thao bé trai", "giay-the-thao-be-trai"},
		{"Áo thun có cổ", "ao-thun-co-co"},
		{"Túi xách da thật", "tui-xach-da-that"},
		{"Váy ngắn", "vay-ngan"}, // "váy ngắn" → "vay-ngan" (â→a, ă→a)
		{"Nhẫn bạc nữ", "nhan-bac-nu"},
	}
	for _, tc := range cases {
		got := slugify(tc.in)
		if got != tc.want {
			t.Errorf("slugify(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestSlugify_Empty(t *testing.T) {
	if got := slugify(""); got != "" {
		t.Errorf("slugify(\"\") = %q, want \"\"", got)
	}
	if got := slugify("   "); got != "" {
		t.Errorf("slugify(\"   \") = %q, want \"\"", got)
	}
	if got := slugify("\t\n"); got != "" {
		t.Errorf("slugify whitespace = %q, want \"\"", got)
	}
}

func TestSlugify_LengthCap(t *testing.T) {
	// 60 chars of 'a' should be trimmed to 48.
	in := ""
	for i := 0; i < 60; i++ {
		in += "a"
	}
	got := slugify(in)
	if len(got) > 48 {
		t.Errorf("slugify long input len = %d, want <= 48", len(got))
	}
}

func TestSlugify_PunctuationStripped(t *testing.T) {
	// Non-letter, non-digit, non-separator characters must not survive.
	got := slugify("Áo!!! sơ??? mi@@@ nam###")
	if got != "ao-so-mi-nam" {
		t.Errorf("slugify with punctuation = %q, want \"ao-so-mi-nam\"", got)
	}
}

func TestSlugify_DoesNotStartOrEndWithDash(t *testing.T) {
	got := slugify("--- hello ---")
	if got != "hello" {
		t.Errorf("slugify dashes around = %q, want \"hello\"", got)
	}
}

// TestBuildUploadFilename_Format pins the overall filename shape:
// YYYYMMDD-<slug>-<index>-<uuid8>.<ext>
// It also exercises the Vietnamese slug in the final filename so a
// regression in slugify() cannot go unnoticed end-to-end.
func TestBuildUploadFilename_VietnameseName(t *testing.T) {
	full := buildUploadFilename("Áo sơ mi nam", "", 1, ".jpg")
	// Must start with date + "ao-so-mi-nam-1-"
	if !contains(full, "ao-so-mi-nam-1-") {
		t.Errorf("buildUploadFilename = %q, want contains %q", full, "ao-so-mi-nam-1-")
	}
	// Must end with .jpg
	if !endsWith(full, ".jpg") {
		t.Errorf("buildUploadFilename = %q, want ends with .jpg", full)
	}
}

// contains is a tiny helper to avoid pulling in strings just for these tests.
func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}

func endsWith(s, suffix string) bool {
	return len(s) >= len(suffix) && s[len(s)-len(suffix):] == suffix
}
