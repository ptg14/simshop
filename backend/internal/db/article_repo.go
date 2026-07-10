package db

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"github.com/ptg14/simshop/backend/internal/uploadfs"
	"github.com/ptg14/simshop/backend/models"
)

// ArticleRepo persists articles and banner slides. It is intentionally
// separate from ProductRepo to keep the surface narrow.
//
// [uploadCfg] enables post-commit best-effort image cleanup (banner
// images, article cover photos). nil disables filesystem deletes.
type ArticleRepo struct {
	db        *sql.DB
	dialect   Dialect
	uploadCfg *uploadfs.UploadConfig
}

// NewArticleRepo constructs a repo bound to the given DB.
// The dialect is used to rewrite ? placeholders to $N when running
// on Postgres; SQLite calls pass through unchanged.
//
// [uploadCfg] enables post-commit best-effort image cleanup. It
// may be nil to disable filesystem deletes.
func NewArticleRepo(db *sql.DB, dialect Dialect, uploadCfg *uploadfs.UploadConfig) *ArticleRepo {
	return &ArticleRepo{db: db, dialect: dialect, uploadCfg: uploadCfg}
}

// deleteUploadURLs is the per-repo thin wrapper that forwards each
// URL through the safe uploadfs helper. Centralizes the nil-cfg
// no-op so call sites stay terse.
func (r *ArticleRepo) deleteUploadURLs(urls []string) {
	for _, u := range urls {
		uploadfs.DeleteByURL(u, r.uploadCfg)
	}
}

// exec is the dialect-aware Exec wrapper used by every method below.
func (r *ArticleRepo) exec(query string, args ...any) (sql.Result, error) {
	return r.db.Exec(r.dialect.Rebind(query), args...)
}

// query is the dialect-aware Query wrapper.
func (r *ArticleRepo) query(query string, args ...any) (*sql.Rows, error) {
	return r.db.Query(r.dialect.Rebind(query), args...)
}

// queryRow is the dialect-aware QueryRow wrapper.
func (r *ArticleRepo) queryRow(query string, args ...any) *sql.Row {
	return r.db.QueryRow(r.dialect.Rebind(query), args...)
}

// ---------- Banner slides ----------

// ListBanners returns every banner slide ordered by ord, then by id
// for stability when two slides share the same ord.
func (r *ArticleRepo) ListBanners() ([]models.BannerSlide, error) {
	rows, err := r.query(
		`SELECT id, image_url, title, subtitle, ord, article_id
		 FROM banner_slides
		 ORDER BY ord ASC, id ASC`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.BannerSlide
	for rows.Next() {
		var b models.BannerSlide
		var articleID sql.NullString
		if err := rows.Scan(&b.ID, &b.ImageURL, &b.Title, &b.Subtitle, &b.Ord, &articleID); err != nil {
			return nil, err
		}
		if articleID.Valid {
			v := articleID.String
			b.ArticleID = &v
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

// CreateBanner inserts a new banner slide. The caller-supplied id is
// used directly (admin UI generates a UUID client-side for symmetry
// with the product CRUD).
func (r *ArticleRepo) CreateBanner(b models.BannerSlide) (models.BannerSlide, error) {
	var articleID interface{}
	if b.ArticleID != nil {
		articleID = *b.ArticleID
	}
	_, err := r.exec(
		`INSERT INTO banner_slides (id, image_url, title, subtitle, ord, article_id)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		b.ID, b.ImageURL, b.Title, b.Subtitle, b.Ord, articleID,
	)
	if err != nil {
		return b, err
	}
	return b, nil
}

// UpdateBanner replaces every mutable field of the row with the given
// id. Returns sql.ErrNoRows if the id does not exist.
//
// [oldImageURL] is the image URL the row held before this update; if
// it differs from the new [b.ImageURL], the old file is best-effort
// deleted from disk after the UPDATE succeeds. This is how banner
// image swaps get the previous file off the disk — without it the
// /uploads/ dir leaks one file per banner edit.
func (r *ArticleRepo) UpdateBanner(id string, b models.BannerSlide, oldImageURL string) (models.BannerSlide, error) {
	var articleID interface{}
	if b.ArticleID != nil {
		articleID = *b.ArticleID
	}
	res, err := r.exec(
		`UPDATE banner_slides
		 SET image_url = ?, title = ?, subtitle = ?, ord = ?, article_id = ?
		 WHERE id = ?`,
		b.ImageURL, b.Title, b.Subtitle, b.Ord, articleID, id,
	)
	if err != nil {
		return b, err
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return b, err
	}
	if rows == 0 {
		return b, sql.ErrNoRows
	}
	b.ID = id
	// Post-commit file cleanup. Only fires when the DB write
	// actually changed the row (rows > 0) and only when the URL
	// actually changed (admin didn't re-save the same image). Disk
	// failures are logged and swallowed — losing the orphan is the
	// exact bug we're fixing, never 500 over a delete hiccup.
	if oldImageURL != "" && oldImageURL != b.ImageURL {
		log.Printf("update banner %s: deleting replaced image %q", id, oldImageURL)
		uploadfs.DeleteByURL(oldImageURL, r.uploadCfg)
	}
	return b, nil
}

// DeleteBanner removes the row with the given id. The image file on
// disk is best-effort deleted post-commit. Returns sql.ErrNoRows if
// the id does not exist.
func (r *ArticleRepo) DeleteBanner(id string) error {
	// Snapshot the image URL before the row goes away so we can
	// clean the file. A failure here is non-fatal: the delete
	// can still proceed without losing the DB record.
	url, _ := r.getBannerImageURL(id)
	res, err := r.exec(`DELETE FROM banner_slides WHERE id = ?`, id)
	if err != nil {
		return err
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if rows == 0 {
		return sql.ErrNoRows
	}
	uploadfs.DeleteByURL(url, r.uploadCfg)
	return nil
}

// getBannerImageURL returns the image_url column for a banner row,
// or "" if the row is missing. sql.NullString guards against the
// (theoretically possible) NULL column; in practice the schema
// declares image_url NOT NULL.
func (r *ArticleRepo) getBannerImageURL(id string) (string, error) {
	var u sql.NullString
	err := r.queryRow(`SELECT image_url FROM banner_slides WHERE id = ?`, id).Scan(&u)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	if !u.Valid {
		return "", nil
	}
	return u.String, nil
}

// ---------- Articles ----------

// CreateArticle inserts a new article. created_at is set to now if the
// caller passed 0. The product_ids slice is stored as a JSON array.
func (r *ArticleRepo) CreateArticle(a models.Article) (models.Article, error) {
	if a.CreatedAt == 0 {
		a.CreatedAt = time.Now().Unix()
	}
	if a.ProductIDs == nil {
		a.ProductIDs = []string{}
	}
	productJSON, err := json.Marshal(a.ProductIDs)
	if err != nil {
		return a, err
	}
	_, err = r.exec(
		`INSERT INTO articles (id, title, body_markdown, cover_image_url, product_ids, created_at)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		a.ID, a.Title, a.BodyMarkdown, a.CoverImageURL, string(productJSON), a.CreatedAt,
	)
	if err != nil {
		return a, err
	}
	return a, nil
}

// UpdateArticle replaces the row with the given id. Returns
// sql.ErrNoRows if not found.
//
// [oldCoverURL] is the cover_image_url the row held before this
// update. When the admin replaces the cover image, the old file is
// best-effort deleted from disk after the UPDATE commits. Pass "" if
// the caller doesn't track the prior URL (back-compat with older
// clients); cleanup is silently skipped in that case.
func (r *ArticleRepo) UpdateArticle(id string, a models.Article, oldCoverURL string) (models.Article, error) {
	if a.ProductIDs == nil {
		a.ProductIDs = []string{}
	}
	productJSON, err := json.Marshal(a.ProductIDs)
	if err != nil {
		return a, err
	}
	res, err := r.exec(
		`UPDATE articles
		 SET title = ?, body_markdown = ?, cover_image_url = ?, product_ids = ?
		 WHERE id = ?`,
		a.Title, a.BodyMarkdown, a.CoverImageURL, string(productJSON), id,
	)
	if err != nil {
		return a, err
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return a, err
	}
	if rows == 0 {
		return a, sql.ErrNoRows
	}
	a.ID = id
	if oldCoverURL != "" && oldCoverURL != a.CoverImageURL {
		log.Printf("update article %s: deleting replaced cover %q", id, oldCoverURL)
		uploadfs.DeleteByURL(oldCoverURL, r.uploadCfg)
	}
	return a, nil
}

// DeleteArticle removes the row and best-effort deletes the cover
// image file from disk. Any banner_slides referencing this article
// have their article_id set to NULL via the FK action.
func (r *ArticleRepo) DeleteArticle(id string) error {
	url, _ := r.getArticleCoverURL(id)
	res, err := r.exec(`DELETE FROM articles WHERE id = ?`, id)
	if err != nil {
		return err
	}
	rows, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if rows == 0 {
		return sql.ErrNoRows
	}
	uploadfs.DeleteByURL(url, r.uploadCfg)
	return nil
}

// getArticleCoverURL returns the cover_image_url column for an
// article, or "" if the row is missing or the column is NULL.
// sql.NullString handles the schema's NULL-allowed column.
func (r *ArticleRepo) getArticleCoverURL(id string) (string, error) {
	var u sql.NullString
	err := r.queryRow(`SELECT cover_image_url FROM articles WHERE id = ?`, id).Scan(&u)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	if !u.Valid {
		return "", nil
	}
	return u.String, nil
}

// GetArticle fetches one article by id. Returns sql.ErrNoRows if
// missing. product_ids is decoded from the JSON column.
func (r *ArticleRepo) GetArticle(id string) (models.Article, error) {
	var a models.Article
	var productJSON string
	err := r.queryRow(
		`SELECT id, title, body_markdown, cover_image_url, product_ids, created_at
		 FROM articles WHERE id = ?`, id,
	).Scan(&a.ID, &a.Title, &a.BodyMarkdown, &a.CoverImageURL, &productJSON, &a.CreatedAt)
	if err != nil {
		return a, err
	}
	if productJSON == "" {
		productJSON = "[]"
	}
	if err := json.Unmarshal([]byte(productJSON), &a.ProductIDs); err != nil {
		return a, fmt.Errorf("decode product_ids: %w", err)
	}
	if a.ProductIDs == nil {
		a.ProductIDs = []string{}
	}
	return a, nil
}

// ListArticles returns every article, newest first.
func (r *ArticleRepo) ListArticles() ([]models.Article, error) {
	rows, err := r.query(
		`SELECT id, title, body_markdown, cover_image_url, product_ids, created_at
		 FROM articles ORDER BY created_at DESC, id ASC`,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Article
	for rows.Next() {
		var a models.Article
		var productJSON string
		if err := rows.Scan(&a.ID, &a.Title, &a.BodyMarkdown, &a.CoverImageURL, &productJSON, &a.CreatedAt); err != nil {
			return nil, err
		}
		if productJSON == "" {
			productJSON = "[]"
		}
		if err := json.Unmarshal([]byte(productJSON), &a.ProductIDs); err != nil {
			return nil, err
		}
		if a.ProductIDs == nil {
			a.ProductIDs = []string{}
		}
		out = append(out, a)
	}
	return out, rows.Err()
}