package models

// BannerSlide is one entry in the home carousel. Carries an optional
// article_id — the article that opens when the user taps the slide.
type BannerSlide struct {
	ID        string  `json:"id"`
	ImageURL  string  `json:"image_url"`
	Title     string  `json:"title"`
	Subtitle  string  `json:"subtitle"`
	Ord       int     `json:"ord"`
	ArticleID *string `json:"article_id,omitempty"`
}
