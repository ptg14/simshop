package db

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"math"
	"strings"

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

// GetAll returns all products.
func (r *ProductRepo) GetAll() ([]models.Product, error) {
	rows, err := r.db.Query(`SELECT id, name, description, price, original_price, image_url, category, store_id, rating, reviews, stock, specs FROM products`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var products []models.Product
	for rows.Next() {
		var p models.Product
		var specsJSON string
		if err := rows.Scan(&p.ID, &p.Name, &p.Description, &p.Price, &p.OriginalPrice, &p.ImageURL, &p.Category, &p.StoreID, &p.Rating, &p.Reviews, &p.Stock, &specsJSON); err != nil {
			return nil, err
		}
		if err := json.Unmarshal([]byte(specsJSON), &p.Specs); err != nil {
			return nil, err
		}
		products = append(products, p)
	}
	return products, nil
}

// GetByID returns a single product by its ID.
func (r *ProductRepo) GetByID(id string) (*models.Product, error) {
	var p models.Product
	var specsJSON string
	err := r.db.QueryRow(`SELECT id, name, description, price, original_price, image_url, category, store_id, rating, reviews, stock, specs FROM products WHERE id=?`, id).
		Scan(&p.ID, &p.Name, &p.Description, &p.Price, &p.OriginalPrice, &p.ImageURL, &p.Category, &p.StoreID, &p.Rating, &p.Reviews, &p.Stock, &specsJSON)
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal([]byte(specsJSON), &p.Specs); err != nil {
		return nil, err
	}
	return &p, nil
}

// Create inserts a new product.
func (r *ProductRepo) Create(p *models.Product) error {
	specsJSON, _ := json.Marshal(p.Specs)
	_, err := r.db.Exec(`INSERT INTO products (id, name, description, price, original_price, image_url, category, store_id, rating, reviews, stock, specs) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`,
		p.ID, p.Name, p.Description, p.Price, p.OriginalPrice, p.ImageURL, p.Category, p.StoreID, p.Rating, p.Reviews, p.Stock, string(specsJSON))
	return err
}

// Update modifies an existing product.
func (r *ProductRepo) Update(id string, p *models.Product) error {
	specsJSON, _ := json.Marshal(p.Specs)
	_, err := r.db.Exec(`UPDATE products SET name=?, description=?, price=?, original_price=?, image_url=?, category=?, store_id=?, rating=?, reviews=?, stock=?, specs=? WHERE id=?`,
		p.Name, p.Description, p.Price, p.OriginalPrice, p.ImageURL, p.Category, p.StoreID, p.Rating, p.Reviews, p.Stock, string(specsJSON), id)
	return err
}

// Delete removes a product.
func (r *ProductRepo) Delete(id string) error {
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
	query := "SELECT id, name, description, price, original_price, image_url, category, store_id, rating, reviews, stock, specs FROM products" +
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
		if err := rows.Scan(&p.ID, &p.Name, &p.Description, &p.Price, &p.OriginalPrice, &p.ImageURL, &p.Category, &p.StoreID, &p.Rating, &p.Reviews, &p.Stock, &specsJSON); err != nil {
			return nil, fmt.Errorf("scan product: %w", err)
		}
		if err := json.Unmarshal([]byte(specsJSON), &p.Specs); err != nil {
			return nil, fmt.Errorf("unmarshal specs: %w", err)
		}
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
