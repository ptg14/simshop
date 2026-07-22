package db

import (
	"database/sql"
	"log"
	"strings"

	"github.com/ptg14/simshop/backend/internal/uploadfs"
	"github.com/ptg14/simshop/backend/models"
)

// StoreRepo provides read/write access to the singleton site config row.
//
// [uploadCfg] enables post-commit best-effort cleanup of the
// previous banner image when the admin replaces it. nil disables
// filesystem deletes (used in unit tests that don't touch uploads).
type StoreRepo struct {
	db        *sql.DB
	dialect   Dialect
	uploadCfg *uploadfs.UploadConfig
}

// NewStoreRepo wires the repo onto an already-open *sql.DB.
// Pass the dialect so any future parameterized queries get
// placeholders rewritten for Postgres. [uploadCfg] may be nil.
func NewStoreRepo(database *sql.DB, dialect Dialect, uploadCfg *uploadfs.UploadConfig) *StoreRepo {
	return &StoreRepo{db: database, dialect: dialect, uploadCfg: uploadCfg}
}

// exec is the dialect-aware Exec wrapper used by every method below.
func (r *StoreRepo) exec(query string, args ...any) (sql.Result, error) {
	return r.db.Exec(r.dialect.Rebind(query), args...)
}

// queryRow is the dialect-aware QueryRow wrapper.
func (r *StoreRepo) queryRow(query string, args ...any) *sql.Row {
	return r.db.QueryRow(r.dialect.Rebind(query), args...)
}

// Get returns the single site config row. The migration guarantees the row
// exists (with sensible defaults) so Get never returns sql.ErrNoRows.
//
// Fields are stored as NOT NULL with empty-string defaults; we convert
// NULL to "" defensively in case future migrations loosen the constraint.
func (r *StoreRepo) Get() (*models.StoreInfo, error) {
	row := r.queryRow(`SELECT id, name, COALESCE(description,''), COALESCE(banner_url,''), COALESCE(phone,''), COALESCE(email,''), COALESCE(address,''), COALESCE(google_maps_url,'') FROM store_info WHERE id = 1`)
	info := &models.StoreInfo{}
	if err := row.Scan(&info.ID, &info.Name, &info.Description, &info.BannerURL, &info.Phone, &info.Email, &info.Address, &info.GoogleMapsURL); err != nil {
		return nil, err
	}
	return info, nil
}

// Update persists the editable fields. Name is required (handler validates
// this first); other fields are trimmed and stored as empty strings if blank.
// Returns the updated row so callers can confirm what was saved.
//
// [oldBannerURL] is the banner_url the row held before this update.
// When it differs from the new [bannerURL], the old file is
// best-effort deleted from disk after the UPDATE commits. Pass ""
// for back-compat with older clients that don't track the prior URL.
func (r *StoreRepo) Update(name, description, bannerURL, phone, email, address, googleMapsURL, oldBannerURL string) (*models.StoreInfo, error) {
	_, err := r.exec(`UPDATE store_info SET name = ?, description = ?, banner_url = ?, phone = ?, email = ?, address = ?, google_maps_url = ? WHERE id = 1`,
		strings.TrimSpace(name),
		strings.TrimSpace(description),
		strings.TrimSpace(bannerURL),
		strings.TrimSpace(phone),
		strings.TrimSpace(email),
		strings.TrimSpace(address),
		strings.TrimSpace(googleMapsURL),
	)
	if err != nil {
		return nil, err
	}
	// Post-commit file cleanup. Only when the URL actually changed —
	// re-saving the same banner must not delete the live file.
	if oldBannerURL != "" && oldBannerURL != bannerURL {
		log.Printf("update store_info: deleting replaced banner %q", oldBannerURL)
		uploadfs.DeleteByURL(oldBannerURL, r.uploadCfg)
	}
	return r.Get()
}
