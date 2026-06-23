package models

// Product represents a product in the store. Fields map to the Dart model.
type Product struct {
	ID            string   `json:"id"`
	Name          string   `json:"name"`
	Description   string   `json:"description"`
	Price         float64  `json:"price"`
	OriginalPrice *float64 `json:"original_price,omitempty"`
	// ImageURL is the primary image URL for backward compatibility.
	ImageURL string `json:"image_url,omitempty"`
	// Images contains all image URLs associated with the product (ordered).
	Images   []string `json:"images,omitempty"`
	Category string   `json:"category"`
	StoreID  *string  `json:"store_id,omitempty"`
	Rating   float64  `json:"rating"`
	Reviews  *int32   `json:"reviews,omitempty"`
	Stock    *int32   `json:"stock,omitempty"`
	Specs    []string `json:"specs"`
	// Categories holds multiple category names for the product.
	Categories []string `json:"categories,omitempty"`
	// Options represent product variants (e.g., size/color) with optional image association.
	Options []Option `json:"options,omitempty"`
}

// Option represents a product option/variant which may reference one of the product images.
type Option struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	// ImageURLs allows multiple images to be associated with this option.
	ImageURLs []string `json:"image_urls,omitempty"`
}

// ProductFilter holds optional filter criteria for listing products.
type ProductFilter struct {
	Category  string
	Search    string
	MinPrice  *float64
	MaxPrice  *float64
	MinRating *float64
	StoreID   string
	SortBy    string // "price_asc", "price_desc", "rating", "name", "newest"
	Page      int
	PageSize  int
}

// ProductListResponse wraps paginated product results.
type ProductListResponse struct {
	Products   []Product `json:"products"`
	Total      int       `json:"total"`
	Page       int       `json:"page"`
	PageSize   int       `json:"page_size"`
	TotalPages int       `json:"total_pages"`
}
