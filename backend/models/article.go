package models

// Article is editorial content referenced by a banner slide. The body
// is stored as Markdown and rendered on the article screen.
type Article struct {
	ID            string   `json:"id"`
	Title         string   `json:"title"`
	BodyMarkdown  string   `json:"body_markdown"`
	CoverImageURL string   `json:"cover_image_url"`
	ProductIDs    []string `json:"product_ids"`
	CreatedAt     int64    `json:"created_at"`
}
