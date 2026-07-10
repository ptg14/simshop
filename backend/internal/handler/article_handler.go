package handler

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"

	"github.com/gorilla/mux"
	"github.com/ptg14/simshop/backend/internal/db"
	"github.com/ptg14/simshop/backend/models"
)

// ArticleRepo re-exports the db.ArticleRepo type so the router can
// reference it.
type ArticleRepo = db.ArticleRepo

// Banner length caps. Mirrors validateStoreInfo in style.
const (
	maxArticleTitleLen    = 200
	maxArticleBodyLen     = 100 * 1024 // 100 KB
	maxArticleCoverURLLen = 1000
	maxArticleProductIDs  = 50
	maxBannerImageURLLen  = 1000
	maxBannerTitleLen     = 200
	maxBannerSubtitleLen  = 300
)

// ListBannersHandler returns every banner slide ordered by ord.
func ListBannersHandler(repo *ArticleRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		banners, err := repo.ListBanners()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to fetch banners")
			return
		}
		if banners == nil {
			banners = []models.BannerSlide{}
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"banners": banners})
	}
}

// GetArticleWithProductsHandler returns the article plus the products
// it mentions. The join collapses what would otherwise be an N+1 from
// the Flutter article screen.
func GetArticleWithProductsHandler(articleRepo *ArticleRepo, productRepo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := mux.Vars(r)["id"]
		if id == "" {
			writeError(w, http.StatusBadRequest, "id is required")
			return
		}

		article, err := articleRepo.GetArticle(id)
		if err == sql.ErrNoRows {
			writeError(w, http.StatusNotFound, "article not found")
			return
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to fetch article")
			return
		}

		products := fetchProductStubs(productRepo, article.ProductIDs)

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{
			"article":  article,
			"products": products,
		})
	}
}

// CreateArticleHandler persists a new article. The id in the body is
// trusted; the admin UI generates a UUID client-side.
//
// [removed_image_urls] is accepted on create for symmetry with the
// update path but is no-op in practice — there's no pre-existing
// image to delete on a brand-new article.
func CreateArticleHandler(repo *ArticleRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			models.Article
			RemovedImageURLs []string `json:"removed_image_urls"`
		}
		if err := readJSONBody(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		a := body.Article
		if err := validateArticle(&a, false); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		saved, err := repo.CreateArticle(a)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to create article")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(saved)
	}
}

// UpdateArticleHandler replaces an article. The id in the URL wins.
//
// The body may include a top-level [old_cover_url] field carrying
// the cover_image_url the row held before this update. When the
// admin swaps the cover, the previous file is best-effort deleted
// from disk after the UPDATE commits. Omitting the field is
// back-compat: the old file is simply left in place.
func UpdateArticleHandler(repo *ArticleRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := mux.Vars(r)["id"]
		if id == "" {
			writeError(w, http.StatusBadRequest, "id is required")
			return
		}
		var body struct {
			models.Article
			RemovedImageURLs []string `json:"removed_image_urls"`
			OldCoverURL      string   `json:"old_cover_url"`
		}
		if err := readJSONBody(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		a := body.Article
		if err := validateArticle(&a, true); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		saved, err := repo.UpdateArticle(id, a, body.OldCoverURL)
		if err == sql.ErrNoRows {
			writeError(w, http.StatusNotFound, "article not found")
			return
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to update article")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(saved)
	}
}

// DeleteArticleHandler removes an article. The FK on banner_slides
// sets article_id to NULL automatically.
func DeleteArticleHandler(repo *ArticleRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := mux.Vars(r)["id"]
		if id == "" {
			writeError(w, http.StatusBadRequest, "id is required")
			return
		}
		if err := repo.DeleteArticle(id); err == sql.ErrNoRows {
			writeError(w, http.StatusNotFound, "article not found")
			return
		} else if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to delete article")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// ListArticlesHandler returns every article (newest first). Used by
// the admin "Bài viết" tab.
func ListArticlesHandler(repo *ArticleRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		articles, err := repo.ListArticles()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to fetch articles")
			return
		}
		if articles == nil {
			articles = []models.Article{}
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"articles": articles})
	}
}

// CreateBannerHandler persists a new banner slide.
//
// [removed_image_urls] is accepted on create for symmetry with the
// update path but is no-op in practice — there's no pre-existing
// image to delete on a brand-new banner.
func CreateBannerHandler(repo *ArticleRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			models.BannerSlide
			RemovedImageURLs []string `json:"removed_image_urls"`
		}
		if err := readJSONBody(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		b := body.BannerSlide
		if err := validateBanner(&b); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		saved, err := repo.CreateBanner(b)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to create banner")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(saved)
	}
}

// UpdateBannerHandler replaces a banner slide. The id in the URL wins.
//
// The body may include a top-level [old_image_url] field carrying
// the image_url the row held before this update. When the admin
// swaps the banner image, the previous file is best-effort deleted
// from disk after the UPDATE commits. Omitting the field is
// back-compat: the old file is simply left in place.
func UpdateBannerHandler(repo *ArticleRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := mux.Vars(r)["id"]
		if id == "" {
			writeError(w, http.StatusBadRequest, "id is required")
			return
		}
		var body struct {
			models.BannerSlide
			RemovedImageURLs []string `json:"removed_image_urls"`
			OldImageURL      string   `json:"old_image_url"`
		}
		if err := readJSONBody(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		b := body.BannerSlide
		if err := validateBanner(&b); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		saved, err := repo.UpdateBanner(id, b, body.OldImageURL)
		if err == sql.ErrNoRows {
			writeError(w, http.StatusNotFound, "banner not found")
			return
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to update banner")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(saved)
	}
}

// DeleteBannerHandler removes a banner slide.
func DeleteBannerHandler(repo *ArticleRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := mux.Vars(r)["id"]
		if id == "" {
			writeError(w, http.StatusBadRequest, "id is required")
			return
		}
		if err := repo.DeleteBanner(id); err == sql.ErrNoRows {
			writeError(w, http.StatusNotFound, "banner not found")
			return
		} else if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to delete banner")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// fetchProductStubs loads products by id and returns them in a minimal
// shape suitable for chip rendering. Skips missing ids.
func fetchProductStubs(productRepo *ProductRepo, ids []string) []map[string]any {
	if len(ids) == 0 {
		return []map[string]any{}
	}
	out := make([]map[string]any, 0, len(ids))
	for _, id := range ids {
		if id == "" {
			continue
		}
		p, err := productRepo.GetByID(id)
		if err != nil {
			// Silently skip deleted/missing products — the article body
			// referenced them but the row is gone.
			continue
		}
		out = append(out, map[string]any{
			"id":        p.ID,
			"name":      p.Name,
			"image_url": p.ImageURL,
		})
	}
	return out
}

// validateArticle trims strings, enforces length caps, and rejects
// empty titles. When [requireID] is true (update flow) the article id
// must also be present.
func validateArticle(a *models.Article, requireID bool) error {
	a.Title = strings.TrimSpace(a.Title)
	// BodyMarkdown is preserved verbatim — no normalization (no
	// trim/HTML-escape) so the author controls formatting.
	a.CoverImageURL = strings.TrimSpace(a.CoverImageURL)
	if requireID && a.ID == "" {
		return fmt.Errorf("id is required")
	}
	if a.Title == "" {
		return fmt.Errorf("title is required")
	}
	var errs []string
	if len(a.Title) > maxArticleTitleLen {
		errs = append(errs, fmt.Sprintf("title exceeds %d characters", maxArticleTitleLen))
	}
	if len(a.BodyMarkdown) > maxArticleBodyLen {
		errs = append(errs, fmt.Sprintf("body exceeds %d characters", maxArticleBodyLen))
	}
	if len(a.CoverImageURL) > maxArticleCoverURLLen {
		errs = append(errs, fmt.Sprintf("cover_image_url exceeds %d characters", maxArticleCoverURLLen))
	}
	if len(a.ProductIDs) > maxArticleProductIDs {
		errs = append(errs, fmt.Sprintf("product_ids exceeds %d entries", maxArticleProductIDs))
	}
	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "; "))
	}
	return nil
}

// validateBanner trims strings and enforces length caps. image_url is
// required; ord defaults to 0 when missing.
func validateBanner(b *models.BannerSlide) error {
	b.ImageURL = strings.TrimSpace(b.ImageURL)
	b.Title = strings.TrimSpace(b.Title)
	b.Subtitle = strings.TrimSpace(b.Subtitle)
	if b.ID == "" {
		return fmt.Errorf("id is required")
	}
	if b.ImageURL == "" {
		return fmt.Errorf("image_url is required")
	}
	var errs []string
	if len(b.ImageURL) > maxBannerImageURLLen {
		errs = append(errs, fmt.Sprintf("image_url exceeds %d characters", maxBannerImageURLLen))
	}
	if len(b.Title) > maxBannerTitleLen {
		errs = append(errs, fmt.Sprintf("title exceeds %d characters", maxBannerTitleLen))
	}
	if len(b.Subtitle) > maxBannerSubtitleLen {
		errs = append(errs, fmt.Sprintf("subtitle exceeds %d characters", maxBannerSubtitleLen))
	}
	if len(errs) > 0 {
		return fmt.Errorf("%s", strings.Join(errs, "; "))
	}
	return nil
}
