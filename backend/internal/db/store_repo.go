package db

import (
	"database/sql"
	"strings"

	"github.com/ptg14/simshop/backend/models"
)

// StoreRepo provides read/write access to the singleton site config row.
type StoreRepo struct {
	db *sql.DB
}

// NewStoreRepo wires the repo onto an already-open *sql.DB.
func NewStoreRepo(database *sql.DB) *StoreRepo {
	return &StoreRepo{db: database}
}

// Get returns the single site config row. The migration guarantees the row
// exists (with sensible defaults) so Get never returns sql.ErrNoRows.
//
// Fields are stored as NOT NULL with empty-string defaults; we convert
// NULL to "" defensively in case future migrations loosen the constraint.
func (r *StoreRepo) Get() (*models.StoreInfo, error) {
	row := r.db.QueryRow(`SELECT id, name, COALESCE(description,''), COALESCE(logo_url,''), COALESCE(phone,''), COALESCE(email,''), COALESCE(address,''), COALESCE(google_maps_url,'') FROM store_info WHERE id = 1`)
	info := &models.StoreInfo{}
	if err := row.Scan(&info.ID, &info.Name, &info.Description, &info.LogoURL, &info.Phone, &info.Email, &info.Address, &info.GoogleMapsURL); err != nil {
		return nil, err
	}
	return info, nil
}

// Update persists the editable fields. Name is required (handler validates
// this first); other fields are trimmed and stored as empty strings if blank.
// Returns the updated row so callers can confirm what was saved.
func (r *StoreRepo) Update(name, description, logoURL, phone, email, address, googleMapsURL string) (*models.StoreInfo, error) {
	_, err := r.db.Exec(`UPDATE store_info SET name = ?, description = ?, logo_url = ?, phone = ?, email = ?, address = ?, google_maps_url = ? WHERE id = 1`,
		strings.TrimSpace(name),
		strings.TrimSpace(description),
		strings.TrimSpace(logoURL),
		strings.TrimSpace(phone),
		strings.TrimSpace(email),
		strings.TrimSpace(address),
		strings.TrimSpace(googleMapsURL),
	)
	if err != nil {
		return nil, err
	}
	return r.Get()
}