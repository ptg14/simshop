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

// ProductFilter holds optional filter criteria for listing products.
type ProductFilter struct {
	Category    string
	Search      string
	MinPrice    *float64
	MaxPrice    *float64
	MinRating   *float64
	StoreID     string
	SortBy      string // "price_asc", "price_desc", "rating", "name", "newest"
	Page        int
	PageSize    int
}

// ProductListResponse wraps paginated product results.
type ProductListResponse struct {
	Products   []Product `json:"products"`
	Total      int       `json:"total"`
	Page       int       `json:"page"`
	PageSize   int       `json:"page_size"`
	TotalPages int       `json:"total_pages"`
}
