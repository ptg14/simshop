// Package uploadfs handles filesystem side-effects for uploaded
// images: deletion (with strong safety against path traversal),
// and URL → filename extraction.
//
// Lives in its own package so both `handler` and `db` can import it
// without creating an import cycle (handler.go already imports db,
// so db cannot import handler directly).
package uploadfs

import (
	"errors"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"strings"
)

// UploadConfig holds configuration for file uploads.
//
// Mirrors the previously-inlined struct in handler.UploadConfig; the
// handler-side type is now an alias pointing here so existing call
// sites keep compiling.
type UploadConfig struct {
	// UploadDir is the absolute or relative directory under which
	// uploaded files live. Filenames are written flat (no nested
	// subdirectories) by the upload pipeline, so cleanup only ever
	// touches the top level.
	UploadDir string
	// MaxUploadSize caps the multipart body. Currently unused by
	// the cleanup helpers; preserved so the upload handler and the
	// store share one config object.
	MaxUploadSize int64
	// BaseURL is the public base URL (e.g. "https://example.com")
	// used to construct absolute image URLs. When set, it lets the
	// URL→filename extractor reject external hosts so we never try
	// to delete a CDN asset.
	BaseURL string
}

// errPathRejected is returned when a filename fails the safety
// checks in SafeDelete. Wraps the rejection reason so callers can
// log structured details.
type errPathRejected struct {
	filename string
	reason   string
}

func (e *errPathRejected) Error() string {
	return "uploadfs: rejected " + e.reason + " in " + e.filename
}

// SafeDelete removes [filename] from cfg.UploadDir after validating
// the path. The filename is treated as a base name only — any path
// separators or ".." segments are rejected so a malicious client
// can never coerce the server into removing an arbitrary file
// (e.g. /etc/passwd).
//
// Returns nil if:
//   - filename is empty (nothing to do)
//   - the file does not exist (idempotent)
//   - the file is successfully removed
//
// Returns an error for: path-traversal attempts, absolute paths,
// paths that resolve outside UploadDir, permission errors, etc.
// Callers are expected to log this as a warning and proceed —
// losing a stale upload must never roll back a successful DB write.
//
// Known limitation (documented): a file referenced by more than one
// product/banner/article can still be deleted when only one of them
// drops the reference. A reference-counted delete would be safer but
// requires extra DB work; we accept the trade-off here.
func SafeDelete(filename string, cfg *UploadConfig) error {
	if filename == "" {
		return nil
	}
	// Reject any path separator. The upload handler only ever builds
	// filenames from a slug + uuid hex + ext (see buildUploadFilename
	// in handler.go), so a legitimate value never contains "/".
	if strings.ContainsAny(filename, "/\\") {
		return &errPathRejected{filename: filename, reason: "path separator"}
	}
	if strings.Contains(filename, "..") {
		return &errPathRejected{filename: filename, reason: ".. segment"}
	}
	if filepath.IsAbs(filename) || strings.HasPrefix(filename, "~") {
		return &errPathRejected{filename: filename, reason: "absolute path"}
	}

	// Belt-and-braces: resolve the target and confirm it sits inside
	// UploadDir even after the separator/.. checks above.
	absUpload, err := filepath.Abs(cfg.UploadDir)
	if err != nil {
		return err
	}
	target := filepath.Join(absUpload, filepath.Base(filename))
	rel, err := filepath.Rel(absUpload, target)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return &errPathRejected{filename: filename, reason: "escapes UploadDir"}
	}

	if err := os.Remove(target); err != nil {
		if os.IsNotExist(err) {
			return nil // idempotent: already gone
		}
		return err
	}
	return nil
}

// FilenameFromURL extracts the upload filename from a public URL
// produced by the upload pipeline (which builds "<base>/uploads/<file>").
//
// Rules:
//   - If [imageURL] is empty or fails to parse → "" (no-op for caller).
//   - If [imageURL] has a host that differs from [cfg.BaseURL]'s host → ""
//     (external URL — not our file, leave it alone).
//   - Otherwise strip the "/uploads/" prefix and return the basename.
//   - Empty tail (just "/uploads/") or nested paths after /uploads/ → ""
//     because uploads live flat on disk.
//
// Returning "" tells callers to no-op, which is the safe default for
// unknown / external URLs.
func FilenameFromURL(imageURL string, cfg *UploadConfig) string {
	if imageURL == "" || cfg == nil {
		return ""
	}
	u, err := url.Parse(imageURL)
	if err != nil {
		return ""
	}

	// External (different host) URL: reject unless cfg.BaseURL matches.
	if u.Host != "" {
		if cfg.BaseURL == "" {
			return ""
		}
		base, err := url.Parse(cfg.BaseURL)
		if err != nil || base.Host != u.Host {
			return ""
		}
	}

	p := u.Path
	const marker = "/uploads/"
	if i := strings.Index(p, marker); i >= 0 {
		tail := p[i+len(marker):]
		// Empty tail ("/uploads/") or nested paths: no real filename
		// to extract. Reject so callers don't try to remove "." or
		// some path under uploads/.
		if tail == "" || strings.ContainsAny(tail, "/\\") {
			return ""
		}
		return tail
	}
	if strings.HasPrefix(p, "/uploads/") {
		// Belt-and-braces — should have been caught above, but keeps
		// the helper robust if the marker lookup ever misses it.
		tail := strings.TrimPrefix(p, "/uploads/")
		if tail == "" || strings.ContainsAny(tail, "/\\") {
			return ""
		}
		return tail
	}
	return ""
}

// DeleteByURL is the fire-and-forget convenience: extract the
// filename from [imageURL] and best-effort delete the file.
// Errors are logged and swallowed — by contract this is called
// after a successful DB write, and we never want a missing file
// to fail an otherwise successful admin action.
//
// Safe to call with a nil cfg (no-op), or with an external URL
// (no-op), or with an empty URL (no-op).
func DeleteByURL(imageURL string, cfg *UploadConfig) {
	if imageURL == "" || cfg == nil {
		return
	}
	name := FilenameFromURL(imageURL, cfg)
	if name == "" {
		return // external URL or no /uploads/ prefix; nothing to do
	}
	if err := SafeDelete(name, cfg); err != nil {
		log.Printf("upload delete: best-effort delete of %q failed: %v", name, err)
	}
}

// IsPathRejected reports whether [err] was produced by the
// path-traversal guard in [SafeDelete]. Exposed for tests that want
// to assert the rejection reason, not for production callers.
func IsPathRejected(err error) bool {
	var pe *errPathRejected
	return errors.As(err, &pe)
}