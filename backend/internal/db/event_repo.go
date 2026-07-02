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
	db      *sql.DB
	dialect Dialect
}

// NewEventRepo constructs a repo bound to the given DB.
// The dialect is used to rewrite ? placeholders and to select
// the JSONB-containment vs LIKE match for product_ids.
func NewEventRepo(db *sql.DB, dialect Dialect) *EventRepo {
	return &EventRepo{db: db, dialect: dialect}
}

// exec is the dialect-aware Exec wrapper used by every method below.
func (r *EventRepo) exec(query string, args ...any) (sql.Result, error) {
	return r.db.Exec(r.dialect.Rebind(query), args...)
}

// query is the dialect-aware Query wrapper.
func (r *EventRepo) query(query string, args ...any) (*sql.Rows, error) {
	return r.db.Query(r.dialect.Rebind(query), args...)
}

// queryRow is the dialect-aware QueryRow wrapper.
func (r *EventRepo) queryRow(query string, args ...any) *sql.Row {
	return r.db.QueryRow(r.dialect.Rebind(query), args...)
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
	if _, err := r.exec(
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
	res, err := r.exec(
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
	res, err := r.exec(`DELETE FROM events WHERE id = ?`, id)
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
	err := r.queryRow(
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
	rows, err := r.query(
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
// Dialect split:
//   - Postgres: the column is JSONB, so we use the @> containment
//     operator with a jsonb_build_array(?::text) sentinel. Fast
//     (GIN-indexed) and unambiguous.
//   - SQLite: the column is TEXT, so LIKE on the JSON-quoted form
//     is the cheapest portable lookup. Correct because product IDs
//     are short alphanumeric strings the admin UI mints, never
//     containing JSON metacharacters.
//
// Either path leaves defense-in-depth: every match also has to
// verify that the decoded ProductIDs slice actually contains
// productID (catches the rare case where a LIKE substring match
// happens to land inside a JSON-stringified different id).
func (r *EventRepo) ListActiveEventsForProduct(productID string, now int64) ([]models.Event, error) {
	// The placeholder for the product id appears in both the
	// Postgres JSONB fragment and the SQLite LIKE pattern. The
	// dialect helper returns the fragment with our `?` placeholder
	// (which Rebind will rewrite to $N on Postgres), and
	// ProductIDsJSONArrayLiteral returns the value to bind.
	productLiteral := r.dialect.ProductIDsJSONArrayLiteral(productID)
	containsFrag := r.dialect.ProductIDsContains("?")
	rows, err := r.query(
		`SELECT id, name, end_time, discount_type, discount_value, product_ids, created_at
		 FROM events
		 WHERE (end_time IS NULL OR end_time > ?)
		   AND `+containsFrag,
		now, productLiteral,
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
		// Defense-in-depth: even after the LIKE/@> match, verify
		// the exact id is in the decoded slice.
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