package models

// Product represents a product in the store. Fields map to the Dart model.
type Product struct {
	ID            string   `json:"id"`
	Name          string   `json:"name"`
	Description   string   `json:"description"`
	Price         float64  `json:"price"`
	OriginalPrice *float64 `json:"original_price,omitempty"`
	ImageURL      string   `json:"image_url"`
	Category      string   `json:"category"`
	StoreID       *string  `json:"store_id,omitempty"`
	Rating        float64  `json:"rating"`
	Reviews       *int32   `json:"reviews,omitempty"`
	Stock         *int32   `json:"stock,omitempty"`
	Specs         []string `json:"specs"`
}
