package models

// StoreInfo is the singleton site identity / branding row. It is edited
// from admin settings and displayed on the public-facing pages.
//
// The DB enforces a single row (id = 1) so callers never have to worry
// about list endpoints or missing rows. Handlers always return a fully
// populated object, defaulting to the migration's seed values.
type StoreInfo struct {
	ID          int64  `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
	LogoURL     string `json:"logo_url,omitempty"`
	Phone       string `json:"phone,omitempty"`
	Email       string `json:"email,omitempty"`
	Address     string `json:"address,omitempty"`
}