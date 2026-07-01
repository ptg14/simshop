package db

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"strings"

	"github.com/google/uuid"
	"github.com/ptg14/simshop/backend/models"
)

// ProductRepo provides CRUD operations for Product entities.
type ProductRepo struct {
	db *sql.DB
}

// NewProductRepo creates a new repository bound to the given DB.
func NewProductRepo(db *sql.DB) *ProductRepo {
	return &ProductRepo{db: db}
}

// GetCategories returns all category names persisted in the database.
func (r *ProductRepo) GetCategories() ([]string, error) {
	rows, err := r.db.Query(`SELECT name FROM categories ORDER BY name ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var cats []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		cats = append(cats, name)
	}
	if cats == nil {
		cats = []string{}
	}
	return cats, nil
}

// CategoryInfo represents a category and its optional large category.
type CategoryInfo struct {
	Name          string `json:"name"`
	LargeCategory string `json:"large_category,omitempty"`
}

// GetCategoriesWithParent returns all categories with their associated large category name (if any).
func (r *ProductRepo) GetCategoriesWithParent() ([]CategoryInfo, error) {
	rows, err := r.db.Query(`SELECT c.name, lc.name FROM categories c LEFT JOIN large_categories lc ON c.large_category_id = lc.id ORDER BY c.name ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []CategoryInfo
	for rows.Next() {
		var ci CategoryInfo
		var large sql.NullString
		if err := rows.Scan(&ci.Name, &large); err != nil {
			return nil, err
		}
		if large.Valid {
			ci.LargeCategory = large.String
		}
		result = append(result, ci)
	}
	if result == nil {
		result = []CategoryInfo{}
	}
	return result, nil
}

// GetLargeCategories returns all large category names.
func (r *ProductRepo) GetLargeCategories() ([]string, error) {
	rows, err := r.db.Query(`SELECT name FROM large_categories ORDER BY name ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var cats []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		cats = append(cats, name)
	}
	if cats == nil {
		cats = []string{}
	}
	return cats, nil
}

// AddLargeCategory inserts a new large category if it does not already exist.
func (r *ProductRepo) AddLargeCategory(name string) error {
	if name == "" {
		return nil
	}
	_, err := r.db.Exec(`INSERT OR IGNORE INTO large_categories (name) VALUES (?)`, name)
	return err
}

// DeleteLargeCategory removes a large category by name.
func (r *ProductRepo) DeleteLargeCategory(name string) error {
	if name == "" {
		return nil
	}
	_, err := r.db.Exec(`DELETE FROM large_categories WHERE name=?`, name)
	return err
}

// AddCategory inserts a new category if it does not already exist.
// AddCategory inserts a new category without a large category association.
func (r *ProductRepo) AddCategory(name string) error {
	if name == "" {
		return nil
	}
	_, err := r.db.Exec(`INSERT OR IGNORE INTO categories (name) VALUES (?)`, name)
	return err
}

// AddCategoryWithParent inserts a new category and optionally links it to a large category.
// If largeName is empty, the category will have no parent.
func (r *ProductRepo) AddCategoryWithParent(name, largeName string) error {
	if name == "" {
		return nil
	}
	// Resolve large category ID if provided.
	var largeID sql.NullInt64
	if largeName != "" {
		err := r.db.QueryRow(`SELECT id FROM large_categories WHERE name = ?`, largeName).Scan(&largeID)
		if err != nil {
			// If not found, create the large category first.
			if _, err2 := r.db.Exec(`INSERT OR IGNORE INTO large_categories (name) VALUES (?)`, largeName); err2 != nil {
				return err2
			}
			// Retrieve the newly inserted ID.
			err = r.db.QueryRow(`SELECT id FROM large_categories WHERE name = ?`, largeName).Scan(&largeID)
			if err != nil {
				return err
			}
		}
	}
	// Insert category with foreign key (may be NULL).
	if largeID.Valid {
		_, err := r.db.Exec(`INSERT OR IGNORE INTO categories (name, large_category_id) VALUES (?, ?)`, name, largeID.Int64)
		return err
	}
	// No parent.
	return r.AddCategory(name)
}

// DeleteCategory removes a category by name.
func (r *ProductRepo) DeleteCategory(name string) error {
	if name == "" {
		return nil
	}
	_, err := r.db.Exec(`DELETE FROM categories WHERE name=?`, name)
	return err
}

// GetAll returns all products.
func (r *ProductRepo) GetAll() ([]models.Product, error) {
	rows, err := r.db.Query(`SELECT id, name, description, price, original_price, image_url, category, store_id, rating, reviews, stock, specs, categories FROM products`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var products []models.Product
	for rows.Next() {
		var p models.Product
		var specsJSON string
		var categoriesJSON sql.NullString
		if err := rows.Scan(&p.ID, &p.Name, &p.Description, &p.Price, &p.OriginalPrice, &p.ImageURL, &p.Category, &p.StoreID, &p.Rating, &p.Reviews, &p.Stock, &specsJSON, &categoriesJSON); err != nil {
			return nil, err
		}
		if err := json.Unmarshal([]byte(specsJSON), &p.Specs); err != nil {
			return nil, err
		}
		// parse categories JSON if present
		p.Categories = []string{}
		if categoriesJSON.Valid && categoriesJSON.String != "" {
			_ = json.Unmarshal([]byte(categoriesJSON.String), &p.Categories)
		}
		// Load images for this product
		imgs, _ := r.getImagesForProduct(p.ID)
		p.Images = imgs
		if p.ImageURL == "" && len(imgs) > 0 {
			p.ImageURL = imgs[0]
		}
		// Load options
		opts, _ := r.getOptionsForProduct(p.ID)
		p.Options = opts
		products = append(products, p)
	}
	return products, nil
}

// GetByID returns a single product by its ID.
func (r *ProductRepo) GetByID(id string) (*models.Product, error) {
	var p models.Product
	var specsJSON string
	var categoriesJSON sql.NullString
	err := r.db.QueryRow(`SELECT id, name, description, price, original_price, image_url, category, store_id, rating, reviews, stock, specs, categories FROM products WHERE id=?`, id).
		Scan(&p.ID, &p.Name, &p.Description, &p.Price, &p.OriginalPrice, &p.ImageURL, &p.Category, &p.StoreID, &p.Rating, &p.Reviews, &p.Stock, &specsJSON, &categoriesJSON)
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal([]byte(specsJSON), &p.Specs); err != nil {
		return nil, err
	}
	// Load images
	imgs, _ := r.getImagesForProduct(p.ID)
	p.Images = imgs
	if p.ImageURL == "" && len(imgs) > 0 {
		p.ImageURL = imgs[0]
	}
	// Load options
	opts, _ := r.getOptionsForProduct(p.ID)
	p.Options = opts
	p.Categories = []string{}
	if categoriesJSON.Valid && categoriesJSON.String != "" {
		_ = json.Unmarshal([]byte(categoriesJSON.String), &p.Categories)
	}
	return &p, nil
}

// Create inserts a new product.
func (r *ProductRepo) Create(p *models.Product) error {
	specsJSON, _ := json.Marshal(p.Specs)
	categoriesJSON, _ := json.Marshal(p.Categories)
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer func() {
		if err != nil {
			tx.Rollback()
		} else {
			tx.Commit()
		}
	}()

	// Use primary image_url if provided; otherwise leave null and rely on product_images.
	if _, err = tx.Exec(`INSERT INTO products (id, name, description, price, original_price, image_url, category, store_id, rating, reviews, stock, specs, categories) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)`,
		p.ID, p.Name, p.Description, p.Price, p.OriginalPrice, p.ImageURL, p.Category, p.StoreID, p.Rating, p.Reviews, p.Stock, string(specsJSON), string(categoriesJSON)); err != nil {
		return err
	}

	// Insert images if any
	for i, url := range p.Images {
		if _, err = tx.Exec(`INSERT INTO product_images (product_id, image_url, ord) VALUES (?,?,?)`, p.ID, url, i); err != nil {
			return err
		}
	}
	// Insert options if any (store image_urls as JSON)
	for i, o := range p.Options {
		if o.ID == "" {
			o.ID = uuid.New().String()
		}
		imgJSON, _ := json.Marshal(o.ImageURLs)
		if _, err = tx.Exec(`INSERT INTO product_options (id, product_id, name, image_urls, ord) VALUES (?,?,?,?,?)`, o.ID, p.ID, o.Name, string(imgJSON), i); err != nil {
			return err
		}
	}
	return nil
}

// Update modifies an existing product.
//
// Every step logs with the product id prefix so an operator can
// correlate a 500 returned to the API client back to a specific
// SQL statement. Failures are wrapped with [fmt.Errorf] at the
// boundary so callers can inspect the underlying error with
// [errors.Is] / [errors.As] (mirrors the existing style in
// [ProductRepo.GetAllFiltered]).
func (r *ProductRepo) Update(id string, p *models.Product) error {
	specsJSON, _ := json.Marshal(p.Specs)
	categoriesJSON, _ := json.Marshal(p.Categories)
	tx, err := r.db.Begin()
	if err != nil {
		log.Printf("update product %s: begin tx: %v", id, err)
		return fmt.Errorf("begin tx for product %s: %w", id, err)
	}
	defer func() {
		if err != nil {
			log.Printf("update product %s: rolling back: %v", id, err)
			// Rollback itself can fail (disk full, broken
			// connection). Capture and log so the operator
			// sees the secondary failure alongside the cause.
			if rberr := tx.Rollback(); rberr != nil && !errors.Is(rberr, sql.ErrTxDone) {
				log.Printf("update product %s: rollback failed: %v", id, rberr)
			}
		} else {
			if cerr := tx.Commit(); cerr != nil {
				log.Printf("update product %s: commit failed: %v", id, cerr)
				err = fmt.Errorf("commit product %s: %w", id, cerr)
			}
		}
	}()

	if _, err = tx.Exec(`UPDATE products SET name=?, description=?, price=?, original_price=?, image_url=?, category=?, store_id=?, rating=?, reviews=?, stock=?, specs=?, categories=? WHERE id=?`,
		p.Name, p.Description, p.Price, p.OriginalPrice, p.ImageURL, p.Category, p.StoreID, p.Rating, p.Reviews, p.Stock, string(specsJSON), string(categoriesJSON), id); err != nil {
		log.Printf("update product %s: UPDATE products: %v", id, err)
		return fmt.Errorf("update product %s: %w", id, err)
	}

	// Replace images: delete existing and insert provided list
	if _, err = tx.Exec(`DELETE FROM product_images WHERE product_id=?`, id); err != nil {
		log.Printf("update product %s: DELETE product_images: %v", id, err)
		return fmt.Errorf("delete images for product %s: %w", id, err)
	}
	for i, url := range p.Images {
		if _, err = tx.Exec(`INSERT INTO product_images (product_id, image_url, ord) VALUES (?,?,?)`, id, url, i); err != nil {
			log.Printf("update product %s: INSERT product_images[%d]=%s: %v", id, i, url, err)
			return fmt.Errorf("insert image %d for product %s: %w", i, id, err)
		}
	}
	// Replace options: delete existing and insert provided list
	if _, err = tx.Exec(`DELETE FROM product_options WHERE product_id=?`, id); err != nil {
		log.Printf("update product %s: DELETE product_options: %v", id, err)
		return fmt.Errorf("delete options for product %s: %w", id, err)
	}
	// Track ids we've already used in this batch so a client that
	// accidentally submits the same id twice (e.g. copy/paste bug,
	// or two new options both carrying id="") doesn't violate the
	// PRIMARY KEY constraint and fail the whole transaction with a
	// 500. Treat the second occurrence as a new option by minting a
	// fresh UUID for it.
	seenIDs := make(map[string]struct{}, len(p.Options))
	for i, o := range p.Options {
		if o.ID == "" {
			o.ID = uuid.New().String()
		} else if _, dup := seenIDs[o.ID]; dup {
			log.Printf("update product %s: duplicate option id %s at index %d — reassigning", id, o.ID, i)
			o.ID = uuid.New().String()
		}
		seenIDs[o.ID] = struct{}{}
		imgJSON, _ := json.Marshal(o.ImageURLs)
		if _, err = tx.Exec(`INSERT INTO product_options (id, product_id, name, image_urls, ord) VALUES (?,?,?,?,?)`, o.ID, id, o.Name, string(imgJSON), i); err != nil {
			log.Printf("update product %s: INSERT product_options[%d] id=%s name=%s: %v", id, i, o.ID, o.Name, err)
			return fmt.Errorf("insert option %d for product %s: %w", i, id, err)
		}
	}
	return nil
}

// Delete removes a product.
func (r *ProductRepo) Delete(id string) error {
	// Delete product and its images (FK with ON DELETE CASCADE handles images,
	// but ensure deletion order).
	if _, err := r.db.Exec(`DELETE FROM product_images WHERE product_id=?`, id); err != nil {
		return err
	}
	_, err := r.db.Exec(`DELETE FROM products WHERE id=?`, id)
	return err
}

// GetAllFiltered returns products matching the given filter criteria with pagination.
func (r *ProductRepo) GetAllFiltered(f models.ProductFilter) (*models.ProductListResponse, error) {
	// Default pagination
	if f.Page < 1 {
		f.Page = 1
	}
	if f.PageSize < 1 || f.PageSize > 100 {
		f.PageSize = 20
	}

	var conditions []string
	var args []any

	if f.Category != "" {
		conditions = append(conditions, "category=?")
		args = append(args, f.Category)
	}
	if f.Search != "" {
		conditions = append(conditions, "name LIKE ?")
		args = append(args, "%"+f.Search+"%")
	}
	if f.MinPrice != nil {
		conditions = append(conditions, "price >= ?")
		args = append(args, *f.MinPrice)
	}
	if f.MaxPrice != nil {
		conditions = append(conditions, "price <= ?")
		args = append(args, *f.MaxPrice)
	}
	if f.MinRating != nil {
		conditions = append(conditions, "rating >= ?")
		args = append(args, *f.MinRating)
	}
	if f.StoreID != "" {
		conditions = append(conditions, "store_id=?")
		args = append(args, f.StoreID)
	}

	whereClause := ""
	if len(conditions) > 0 {
		whereClause = " WHERE " + strings.Join(conditions, " AND ")
	}

	// Count total matching rows
	var total int
	countQuery := "SELECT COUNT(*) FROM products" + whereClause
	if err := r.db.QueryRow(countQuery, args...).Scan(&total); err != nil {
		return nil, fmt.Errorf("count products: %w", err)
	}

	// Sort
	orderClause := " ORDER BY id"
	switch f.SortBy {
	case "price_asc":
		orderClause = " ORDER BY price ASC"
	case "price_desc":
		orderClause = " ORDER BY price DESC"
	case "rating":
		orderClause = " ORDER BY rating DESC"
	case "name":
		orderClause = " ORDER BY name ASC"
	case "newest":
		orderClause = " ORDER BY rowid DESC"
	}

	offset := (f.Page - 1) * f.PageSize
	// Include categories column to retrieve multi-category data.
	query := "SELECT id, name, description, price, original_price, image_url, category, store_id, rating, reviews, stock, specs, categories FROM products" +
		whereClause + orderClause + " LIMIT ? OFFSET ?"
	args = append(args, f.PageSize, offset)

	rows, err := r.db.Query(query, args...)
	if err != nil {
		return nil, fmt.Errorf("query products: %w", err)
	}
	defer rows.Close()

	var products []models.Product
	for rows.Next() {
		var p models.Product
		var specsJSON string
		var categoriesJSON sql.NullString
		if err := rows.Scan(&p.ID, &p.Name, &p.Description, &p.Price, &p.OriginalPrice, &p.ImageURL, &p.Category, &p.StoreID, &p.Rating, &p.Reviews, &p.Stock, &specsJSON, &categoriesJSON); err != nil {
			return nil, fmt.Errorf("scan product: %w", err)
		}
		if err := json.Unmarshal([]byte(specsJSON), &p.Specs); err != nil {
			return nil, fmt.Errorf("unmarshal specs: %w", err)
		}
		// Parse categories JSON if present.
		p.Categories = []string{}
		if categoriesJSON.Valid && categoriesJSON.String != "" {
			_ = json.Unmarshal([]byte(categoriesJSON.String), &p.Categories)
		}
		// Load images.
		imgs, _ := r.getImagesForProduct(p.ID)
		p.Images = imgs
		if p.ImageURL == "" && len(imgs) > 0 {
			p.ImageURL = imgs[0]
		}
		// Load options.
		opts, _ := r.getOptionsForProduct(p.ID)
		p.Options = opts
		products = append(products, p)
	}
	if products == nil {
		products = []models.Product{}
	}

	totalPages := int(math.Ceil(float64(total) / float64(f.PageSize)))

	return &models.ProductListResponse{
		Products:   products,
		Total:      total,
		Page:       f.Page,
		PageSize:   f.PageSize,
		TotalPages: totalPages,
	}, nil
}

// getImagesForProduct returns ordered image URLs for a product.
func (r *ProductRepo) getImagesForProduct(productID string) ([]string, error) {
	rows, err := r.db.Query(`SELECT image_url FROM product_images WHERE product_id=? ORDER BY ord ASC`, productID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var imgs []string
	for rows.Next() {
		var url string
		if err := rows.Scan(&url); err != nil {
			return nil, err
		}
		imgs = append(imgs, url)
	}
	if imgs == nil {
		imgs = []string{}
	}
	return imgs, nil
}

// getOptionsForProduct returns the ordered options for a product.
func (r *ProductRepo) getOptionsForProduct(productID string) ([]models.Option, error) {
	rows, err := r.db.Query(`SELECT id, name, image_urls FROM product_options WHERE product_id=? ORDER BY ord ASC`, productID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var opts []models.Option
	for rows.Next() {
		var o models.Option
		var imagesJSON sql.NullString
		if err := rows.Scan(&o.ID, &o.Name, &imagesJSON); err != nil {
			return nil, err
		}
		if imagesJSON.Valid && imagesJSON.String != "" {
			_ = json.Unmarshal([]byte(imagesJSON.String), &o.ImageURLs)
		} else {
			o.ImageURLs = []string{}
		}
		opts = append(opts, o)
	}
	if opts == nil {
		opts = []models.Option{}
	}
	return opts, nil
}
