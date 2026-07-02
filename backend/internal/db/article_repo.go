package db

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"time"

	"github.com/ptg14/simshop/backend/models"
)

// ArticleRepo persists articles and banner slides. It is intentionally
// separate from ProductRepo to keep the surface narrow.
type ArticleRepo struct {
	db      *sql.DB
	dialect Dialect
}

// NewArticleRepo constructs a repo bound to the given DB.
// The dialect is used to rewrite ? placeholders to $N when running
// on Postgres; SQLite calls pass through unchanged.
func NewArticleRepo(db *sql.DB, dialect Dialect) *ArticleRepo {
	return &ArticleRepo{db: db, dialect: dialect}
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
func (r *ArticleRepo) UpdateBanner(id string, b models.BannerSlide) (models.BannerSlide, error) {
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
	return b, nil
}

// DeleteBanner removes the row with the given id. Returns
// sql.ErrNoRows if the id does not exist.
func (r *ArticleRepo) DeleteBanner(id string) error {
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
	return nil
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
func (r *ArticleRepo) UpdateArticle(id string, a models.Article) (models.Article, error) {
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
	return a, nil
}

// DeleteArticle removes the row. Any banner_slides referencing this
// article have their article_id set to NULL via the FK action.
func (r *ArticleRepo) DeleteArticle(id string) error {
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
	return nil
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