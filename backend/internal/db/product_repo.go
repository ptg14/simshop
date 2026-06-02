package db

import (
	"database/sql"
	"encoding/json"

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
