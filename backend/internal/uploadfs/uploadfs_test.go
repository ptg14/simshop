package uploadfs

import (
	"os"
	"path/filepath"
	"testing"
)

// TestFilenameFromURL_NoBaseURLAcceptsAbsolute pins the dev-mode
// contract: when the BE is started without BASE_URL (dev sessions
// where flutter run -d chrome hits the BE directly), uploaded image
// URLs are emitted as absolute URLs derived from the request's Host
// header. The cleanup path must still extract the filename from
// those absolute URLs so image deletion works in dev. Without this,
// every `removedImageUrls` cleanup silently no-ops in dev mode and
// stale files pile up in /uploads/.
//
// Production operators who want strict host isolation MUST set
// cfg.BaseURL — that path is covered by TestFilenameFromURL_RejectsExternal.
func TestFilenameFromURL_NoBaseURLAcceptsAbsolute(t *testing.T) {
	cases := []struct {
		name string
		url  string
		want string
	}{
		{"relative path", "/uploads/20260101-foo-1.png", "20260101-foo-1.png"},
		{"absolute dev URL", "http://localhost:8080/uploads/20260101-foo-1.png", "20260101-foo-1.png"},
		{"absolute https URL", "https://api.example.com/uploads/20260101-bar-2.jpg", "20260101-bar-2.jpg"},
	}
	cfg := &UploadConfig{} // no BaseURL → dev mode
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := FilenameFromURL(tc.url, cfg)
			if got != tc.want {
				t.Fatalf("FilenameFromURL(%q) = %q, want %q", tc.url, got, tc.want)
			}
		})
	}
}

// TestFilenameFromURL_RejectsExternal asserts the production-mode
// contract: when BaseURL is configured, only URLs on that host are
// accepted. External URLs (CDN, attacker-supplied) must no-op so
// the BE never tries to delete a file it doesn't own.
func TestFilenameFromURL_RejectsExternal(t *testing.T) {
	cfg := &UploadConfig{BaseURL: "https://api.example.com"}

	cases := []struct {
		name string
		url  string
		want string
	}{
		{"matching host", "https://api.example.com/uploads/x.png", "x.png"},
		{"matching host http", "http://api.example.com/uploads/x.png", "x.png"},
		{"external host rejected", "https://cdn.example.com/uploads/x.png", ""},
		{"unrelated host rejected", "https://attacker.test/uploads/x.png", ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := FilenameFromURL(tc.url, cfg)
			if got != tc.want {
				t.Fatalf("FilenameFromURL(%q) = %q, want %q", tc.url, got, tc.want)
			}
		})
	}
}

// TestDeleteByURL_DevModeRemovesFile is the end-to-end contract
// for the dev workflow: upload emits absolute URL → admin removes
// image → product update posts that URL as removed_image_urls →
// cleanup deletes the actual file on disk. Without the dev-mode
// accept rule above, this test would fail with the file still on
// disk.
func TestDeleteByURL_DevModeRemovesFile(t *testing.T) {
	tmpDir := t.TempDir()
	filename := "20260101-devtest-1.png"
	if err := os.WriteFile(filepath.Join(tmpDir, filename), []byte("fake png bytes"), 0o644); err != nil {
		t.Fatalf("seed file: %v", err)
	}

	cfg := &UploadConfig{UploadDir: tmpDir} // dev: no BaseURL
	DeleteByURL("http://localhost:8080/uploads/"+filename, cfg)

	if _, err := os.Stat(filepath.Join(tmpDir, filename)); !os.IsNotExist(err) {
		t.Fatalf("file still exists after DeleteByURL: err=%v", err)
	}
}
