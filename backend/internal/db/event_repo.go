package db

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/ptg14/simshop/backend/models"
)

// EventRepo persists promotion events. The repo deliberately stays
// narrow (one type) so the handlers can stay thin — only
// computeEffectivePrice in event_handler.go carries business logic.
type EventRepo struct {
	db *sql.DB
}

// NewEventRepo constructs a repo bound to the given DB.
func NewEventRepo(db *sql.DB) *EventRepo {
	return &EventRepo{db: db}
}

// Create inserts a new event. created_at is stamped server-side if
// the caller passed 0 so callers don't have to think about clock
// skew between admin devices.
func (r *EventRepo) Create(e models.Event) (models.Event, error) {
	if e.CreatedAt == 0 {
		e.CreatedAt = time.Now().Unix()
	}
	if e.ProductIDs == nil {
		e.ProductIDs = []string{}
	}
	productJSON, err := json.Marshal(e.ProductIDs)
	if err != nil {
		return e, err
	}
	var endTime interface{}
	if e.EndTime != nil {
		endTime = *e.EndTime
	}
	if _, err := r.db.Exec(
		`INSERT INTO events (id, name, end_time, discount_type, discount_value, product_ids, created_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		e.ID, e.Name, endTime, string(e.DiscountType), e.DiscountValue, string(productJSON), e.CreatedAt,
	); err != nil {
		log.Printf("create event %s: %v", e.ID, err)
		return e, err
	}
	return e, nil
}

// Update replaces every mutable field of the row with the given id.
// Returns sql.ErrNoRows if the event does not exist.
func (r *EventRepo) Update(id string, e models.Event) (models.Event, error) {
	if e.ProductIDs == nil {
		e.ProductIDs = []string{}
	}
	productJSON, err := json.Marshal(e.ProductIDs)
	if err != nil {
		return e, err
	}
	var endTime interface{}
	if e.EndTime != nil {
		endTime = *e.EndTime
	}
	res, err := r.db.Exec(
		`UPDATE events
		 SET name = ?, end_time = ?, discount_type = ?, discount_value = ?, product_ids = ?
		 WHERE id = ?`,
		e.Name, endTime, string(e.DiscountType), e.DiscountValue, string(productJSON), id,
	)
	if err != nil {
		log.Printf("update event %s: %v", id, err)
		return e, err
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return e, err
	}
	if rows == 0 {
		return e, sql.ErrNoRows
	}
	e.ID = id
	return e, nil
}

// Delete removes the row with the given id. Returns sql.ErrNoRows
// if the id does not exist (so the handler can return 404).
func (r *EventRepo) Delete(id string) error {
	res, err := r.db.Exec(`DELETE FROM events WHERE id = ?`, id)
	if err != nil {
		log.Printf("delete event %s: %v", id, err)
		return err
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if rows == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// Get fetches one event by id. Returns sql.ErrNoRows if missing.
// product_ids is decoded from the JSON column; an empty/blank
// column is normalized to an empty slice so callers never have to
// nil-check.
func (r *EventRepo) Get(id string) (models.Event, error) {
	var e models.Event
	var endTime sql.NullInt64
	var productJSON string
	var discountType string
	err := r.db.QueryRow(
		`SELECT id, name, end_time, discount_type, discount_value, product_ids, created_at
		 FROM events WHERE id = ?`, id,
	).Scan(&e.ID, &e.Name, &endTime, &discountType, &e.DiscountValue, &productJSON, &e.CreatedAt)
	if err != nil {
		return e, err
	}
	if endTime.Valid {
		v := endTime.Int64
		e.EndTime = &v
	}
	e.DiscountType = models.DiscountType(discountType)
	if productJSON == "" {
		productJSON = "[]"
	}
	if err := json.Unmarshal([]byte(productJSON), &e.ProductIDs); err != nil {
		return e, fmt.Errorf("decode product_ids: %w", err)
	}
	if e.ProductIDs == nil {
		e.ProductIDs = []string{}
	}
	return e, nil
}

// List returns every event, newest first. The list includes
// expired events — the admin UI wants to display them with a
// "Đã hết hạn" badge. Live filtering happens in
// ListActiveEventsForProduct.
func (r *EventRepo) List() ([]models.Event, error) {
	rows, err := r.db.Query(
		`SELECT id, name, end_time, discount_type, discount_value, product_ids, created_at
		 FROM events ORDER BY created_at DESC, id ASC`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Event
	for rows.Next() {
		var e models.Event
		var endTime sql.NullInt64
		var productJSON string
		var discountType string
		if err := rows.Scan(&e.ID, &e.Name, &endTime, &discountType, &e.DiscountValue, &productJSON, &e.CreatedAt); err != nil {
			return nil, err
		}
		if endTime.Valid {
			v := endTime.Int64
			e.EndTime = &v
		}
		e.DiscountType = models.DiscountType(discountType)
		if productJSON == "" {
			productJSON = "[]"
		}
		if err := json.Unmarshal([]byte(productJSON), &e.ProductIDs); err != nil {
			return nil, err
		}
		if e.ProductIDs == nil {
			e.ProductIDs = []string{}
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// ListActiveEventsForProduct returns every event that:
//   - applies to [productID] (product_id appears in product_ids JSON)
//   - has not expired by [now] (end_time NULL OR end_time > now)
//
// product_ids is stored as JSON like ["p1","p2","p3"], so the
// cheapest portable lookup is a LIKE match on the quoted form of
// the id — correct because product IDs are short alphanumeric
// strings the admin UI mints, never containing JSON metacharacters.
// We also enforce that the LIKE match sits between JSON brackets
// ("...") so that searching for "p1" doesn't accidentally match
// "p10" or "p11".
func (r *EventRepo) ListActiveEventsForProduct(productID string, now int64) ([]models.Event, error) {
	needle := fmt.Sprintf("%q", productID) // JSON-encoded string literal
	rows, err := r.db.Query(
		`SELECT id, name, end_time, discount_type, discount_value, product_ids, created_at
		 FROM events
		 WHERE (end_time IS NULL OR end_time > ?)
		   AND product_ids LIKE ?`,
		now, "%"+needle+"%",
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var matched []models.Event
	for rows.Next() {
		var e models.Event
		var endTime sql.NullInt64
		var productJSON string
		var discountType string
		if err := rows.Scan(&e.ID, &e.Name, &endTime, &discountType, &e.DiscountValue, &productJSON, &e.CreatedAt); err != nil {
			return nil, err
		}
		if endTime.Valid {
			v := endTime.Int64
			e.EndTime = &v
		}
		e.DiscountType = models.DiscountType(discountType)
		if productJSON == "" {
			productJSON = "[]"
		}
		if err := json.Unmarshal([]byte(productJSON), &e.ProductIDs); err != nil {
			return nil, err
		}
		// Defense-in-depth: even after the LIKE match, verify the
		// exact id is in the decoded slice. Catches the rare case
		// where a substring of a different id happens to contain
		// our quoted needle (vanishingly unlikely with short
		// generated IDs, but the cost is one slice scan).
		if !containsString(e.ProductIDs, productID) {
			continue
		}
		matched = append(matched, e)
	}
	return matched, rows.Err()
}

func containsString(s []string, v string) bool {
	for _, x := range s {
		if strings.EqualFold(x, v) {
			return true
		}
	}
	return false
}