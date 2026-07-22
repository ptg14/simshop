package handler

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/gorilla/mux"
	"github.com/ptg14/simshop/backend/internal/db"
	"github.com/ptg14/simshop/backend/models"
)

// EventRepo re-exports the db.EventRepo type so the router can
// reference it without importing the db package directly.
type EventRepo = db.EventRepo

// Event validation caps.
const (
	maxEventNameLen    = 200
	maxEventProductIDs = 200
)

// ListEventsHandler returns every event newest-first. Includes
// expired events — the admin UI wants to display them with a
// "Đã hết hạn" badge rather than dropping them silently.
func ListEventsHandler(repo *EventRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		events, err := repo.List()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to list events")
			return
		}
		if events == nil {
			events = []models.Event{}
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"events": events})
	}
}

// GetEventHandler fetches one event by id.
func GetEventHandler(repo *EventRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := mux.Vars(r)["id"]
		if id == "" {
			writeError(w, http.StatusBadRequest, "id is required")
			return
		}
		e, err := repo.Get(id)
		if err == sql.ErrNoRows {
			writeError(w, http.StatusNotFound, "event not found")
			return
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to fetch event")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(e)
	}
}

// CreateEventHandler persists a new event.
func CreateEventHandler(repo *EventRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var e models.Event
		if err := readJSONBody(r, &e); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		if err := validateEvent(&e); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		saved, err := repo.Create(e)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to create event")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(saved)
	}
}

// UpdateEventHandler replaces an event. The id in the URL wins.
func UpdateEventHandler(repo *EventRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := mux.Vars(r)["id"]
		if id == "" {
			writeError(w, http.StatusBadRequest, "id is required")
			return
		}
		var e models.Event
		if err := readJSONBody(r, &e); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		if err := validateEvent(&e); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		saved, err := repo.Update(id, e)
		if err == sql.ErrNoRows {
			writeError(w, http.StatusNotFound, "event not found")
			return
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to update event")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(saved)
	}
}

// DeleteEventHandler removes an event.
func DeleteEventHandler(repo *EventRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := mux.Vars(r)["id"]
		if id == "" {
			writeError(w, http.StatusBadRequest, "id is required")
			return
		}
		if err := repo.Delete(id); err == sql.ErrNoRows {
			writeError(w, http.StatusNotFound, "event not found")
			return
		} else if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to delete event")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// validateEvent enforces the rules from the admin form: id required,
// name optional (≤200 chars), end_time required and strictly in the
// future, discount_type ∈ {percent, fixed}, discount_value > 0
// (and ≤100 when percent), product_ids ≤200.
func validateEvent(e *models.Event) error {
	e.Name = strings.TrimSpace(e.Name)
	if e.ID == "" {
		return fmt.Errorf("id is required")
	}
	var errs []string
	if len(e.Name) > maxEventNameLen {
		errs = append(errs, fmt.Sprintf("name exceeds %d characters", maxEventNameLen))
	}
	if e.EndTime == nil {
		errs = append(errs, "end_time is required")
	} else if *e.EndTime <= time.Now().Unix() {
		errs = append(errs, "end_time must be in the future")
	}
	switch e.DiscountType {
	case models.DiscountPercent:
		if e.DiscountValue <= 0 {
			errs = append(errs, "discount_value must be > 0")
		}
		if e.DiscountValue > 100 {
			errs = append(errs, "percent discount_value cannot exceed 100")
		}
	case models.DiscountFixed:
		if e.DiscountValue <= 0 {
			errs = append(errs, "discount_value must be > 0")
		}
	default:
		errs = append(errs, fmt.Sprintf("discount_type must be %q or %q",
			models.DiscountPercent, models.DiscountFixed))
	}
	if len(e.ProductIDs) > maxEventProductIDs {
		errs = append(errs, fmt.Sprintf("product_ids exceeds %d entries", maxEventProductIDs))
	}
	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "; "))
	}
	return nil
}

// computeEffectivePrice picks the lowest post-discount price across
// [events] for a product priced at [basePrice]. Returns the
// basePrice unchanged when [events] is empty so callers don't have
// to nil-check. When two events would yield the same final price,
// the first one wins (stable for testing).
func computeEffectivePrice(basePrice float64, events []models.Event) (float64, *models.Event) {
	if len(events) == 0 {
		return basePrice, nil
	}
	bestPrice := basePrice
	var best *models.Event
	for i := range events {
		e := &events[i]
		p := e.ApplyTo(basePrice)
		if p < 0 {
			p = 0
		}
		if best == nil || p < bestPrice {
			bestPrice = p
			best = e
		}
	}
	return bestPrice, best
}

// productWithEvent wraps a Product with the runtime-computed
// effective_price + current_event fields. Defined here (and not in
// models) because Event metadata is read-side only — we never
// persist effective_price, only derive it on the fly. The embedded
// *models.Product keeps the existing JSON tags intact and adds two
// top-level keys.
type productWithEvent struct {
	*models.Product
	EffectivePrice float64       `json:"effective_price"`
	CurrentEvent   *models.Event `json:"current_event"`
}

// decorateProductsWithEvents attaches effective_price + current_event
// to every product in [products]. The lookup is O(events × products)
// but events are a small, capped table (admin UI discourages
// thousands), so a per-product query is fine. If [eventRepo] is nil
// (e.g. unit tests) the products are returned with their base price
// and no event metadata so the response shape stays consistent.
func decorateProductsWithEvents(products []models.Product, eventRepo *EventRepo) []productWithEvent {
	out := make([]productWithEvent, 0, len(products))
	now := time.Now().Unix()
	for i := range products {
		p := &products[i]
		wrapped := productWithEvent{
			Product:        p,
			EffectivePrice: p.Price,
			CurrentEvent:   nil,
		}
		if eventRepo != nil && p.ID != "" {
			events, err := eventRepo.ListActiveEventsForProduct(p.ID, now)
			if err != nil {
				// Don't fail the whole list read because of one
				// event-query error — log it and return the base
				// price so the customer still sees the product.
				log.Printf("decorate product %s: list active events: %v", p.ID, err)
			} else if len(events) > 0 {
				price, ev := computeEffectivePrice(p.Price, events)
				wrapped.EffectivePrice = price
				if ev != nil {
					wrapped.CurrentEvent = ev
				}
			}
		}
		out = append(out, wrapped)
	}
	return out
}
