package models

// Article is editorial content referenced by a banner slide. The body
// is stored as Markdown and rendered on the article screen.
//
// IsDraft is the gate for public visibility: a non-admin caller reading
// /api/articles/:id only sees drafts=false rows. Admins always see
// drafts. Defaults to false so existing seeded content stays public.
type Article struct {
	ID            string   `json:"id"`
	Title         string   `json:"title"`
	BodyMarkdown  string   `json:"body_markdown"`
	CoverImageURL string   `json:"cover_image_url"`
	ProductIDs    []string `json:"product_ids"`
	CreatedAt     int64    `json:"created_at"`
	IsDraft       bool     `json:"is_draft"`
}
