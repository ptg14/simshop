package models

// Pageview is one row in the pageview_events table.
//
// event_type is the kind of view ("home_view" or "product_view").
// product_id is empty for non-product events so all events fit one
// row shape. created_at is unix milliseconds so we can ORDER BY +
// do windowed aggregations cheaply.
type Pageview struct {
	ID        int64  `json:"id"`
	EventType string `json:"event_type"`
	ProductID string `json:"product_id,omitempty"`
	CreatedAt int64  `json:"created_at"`
}

// TopProduct is a row in the admin overview's "Sản phẩm xem nhiều
// nhất" table. ViewCount is the number of pageview_events rows
// with event_type='product_view' for this product_id in the lookback
// window (currently all-time — a TTL/retention job is a follow-up).
type TopProduct struct {
	ProductID string `json:"product_id"`
	Name      string `json:"name"`
	ImageURL  string `json:"image_url,omitempty"`
	ViewCount int    `json:"view_count"`
}

// AnalyticsSummary is the GET /api/admin/analytics/summary payload.
//
// TotalVisits is the count of all pageview_events rows. TopProducts
// is the top-N most-viewed products joined against the products
// table for the human-readable name + thumbnail.
type AnalyticsSummary struct {
	TotalVisits int          `json:"total_visits"`
	TopProducts []TopProduct `json:"top_products"`
}