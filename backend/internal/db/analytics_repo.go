package db

import (
	"database/sql"
	"time"

	"github.com/ptg14/simshop/backend/models"
)

// AnalyticsRepo reads and writes pageview_events.
//
// Anonymous by design — there is no user_id on a pageview row. The
// intent is to track aggregate visitor flow, not to identify
// individuals.
type AnalyticsRepo struct {
	db *sql.DB
}

// NewAnalyticsRepo wires the repo onto an already-open *sql.DB.
func NewAnalyticsRepo(db *sql.DB) *AnalyticsRepo {
	return &AnalyticsRepo{db: db}
}

// RecordPageview inserts a single pageview_events row. created_at is
// set to the current unix-millisecond timestamp so the top-N query
// can ORDER BY cheaply. productID may be empty (for home_view).
func (r *AnalyticsRepo) RecordPageview(eventType, productID string) error {
	if productID == "" {
		_, err := r.db.Exec(
			`INSERT INTO pageview_events (event_type, product_id, created_at) VALUES (?, NULL, ?)`,
			eventType, time.Now().UnixMilli(),
		)
		return err
	}
	_, err := r.db.Exec(
		`INSERT INTO pageview_events (event_type, product_id, created_at) VALUES (?, ?, ?)`,
		eventType, productID, time.Now().UnixMilli(),
	)
	return err
}

// GetSummary returns total pageview count + the top-N most-viewed
// products. The top-N query joins pageview_events against products
// so the admin UI gets human-readable names + thumbnails without a
// second round trip.
//
// limit caps how many top-products to return (admin UI uses 5).
func (r *AnalyticsRepo) GetSummary(topN int) (*models.AnalyticsSummary, error) {
	summary := &models.AnalyticsSummary{TopProducts: []models.TopProduct{}}

	// Total visits — count all rows. Cheap with the (event_type, created_at)
	// index because SQLite uses the rowid for COUNT(*) on indexed tables.
	if err := r.db.QueryRow(`SELECT COUNT(*) FROM pageview_events`).Scan(&summary.TotalVisits); err != nil {
		return nil, err
	}

	// Top products — GROUP BY product_id, ORDER BY view_count DESC, JOIN
	// products for name + thumbnail. LEFT JOIN so a deleted product's
	// count still shows (the admin can still see which product IDs
	// were popular even after deletion).
	rows, err := r.db.Query(`
		SELECT p.id, COALESCE(p.name, ''), COALESCE(p.image_url, ''), COUNT(e.id) AS views
		FROM pageview_events e
		LEFT JOIN products p ON p.id = e.product_id
		WHERE e.event_type = 'product_view'
		GROUP BY p.id, p.name, p.image_url
		ORDER BY views DESC, p.id ASC
		LIMIT ?
	`, topN)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var tp models.TopProduct
		if err := rows.Scan(&tp.ProductID, &tp.Name, &tp.ImageURL, &tp.ViewCount); err != nil {
			return nil, err
		}
		summary.TopProducts = append(summary.TopProducts, tp)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return summary, nil
}