package models

// DiscountType identifies how an Event reduces a product's price.
type DiscountType string

const (
	// DiscountPercent reduces the price by a percentage (0–100).
	DiscountPercent DiscountType = "percent"
	// DiscountFixed subtracts a flat amount from the price.
	DiscountFixed DiscountType = "fixed"
)

// Event represents a time-boxed promotion applied to one or more
// products. Customers see the discounted price via the
// `effective_price` field that product handlers compute on read —
// the underlying product row is never mutated, so when the event
// expires the discount simply disappears on the next request (no
// cron, no cleanup).
type Event struct {
	ID            string       `json:"id"`
	Name          string       `json:"name"`
	EndTime       *int64       `json:"end_time,omitempty"` // unix seconds; nil = never expires
	DiscountType  DiscountType `json:"discount_type"`
	DiscountValue float64      `json:"discount_value"`
	ProductIDs    []string     `json:"product_ids"`
	CreatedAt     int64        `json:"created_at"`
}

// IsActive reports whether the event is in force at [now]. An event
// with a nil EndTime never expires; otherwise EndTime must be
// strictly greater than now (so an event whose EndTime equals the
// current second is already considered expired — the same instant
// is the boundary).
func (e *Event) IsActive(now int64) bool {
	if e.EndTime == nil {
		return true
	}
	return *e.EndTime > now
}

// ApplyTo returns the price after applying this event's discount.
// Negative results are clamped to zero so the customer never sees a
// negative price tag (callers should validate DiscountValue up-front,
// but defense in depth is cheap here).
func (e *Event) ApplyTo(price float64) float64 {
	var p float64
	switch e.DiscountType {
	case DiscountPercent:
		p = price * (1 - e.DiscountValue/100.0)
	case DiscountFixed:
		p = price - e.DiscountValue
	default:
		return price
	}
	if p < 0 {
		p = 0
	}
	return p
}
