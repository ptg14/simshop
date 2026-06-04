package handler

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/google/uuid"
	"github.com/gorilla/mux"
	"github.com/ptg14/simshop/backend/internal/db"
	"github.com/ptg14/simshop/backend/models"
)

// UploadConfig holds configuration for file uploads.
type UploadConfig struct {
	UploadDir     string
	MaxUploadSize int64
}

// ProductRepo re-exports the db.ProductRepo type so the router can reference it.
type ProductRepo = db.ProductRepo

// HealthHandler responds with a simple health check.
func HealthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// GetProductsHandler returns products with optional filtering and pagination.
func GetProductsHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		filter := parseProductFilter(r)

		result, err := repo.GetAllFiltered(filter)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to fetch products")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(result)
	}
}

// GetProductHandler returns a single product by ID.
func GetProductHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := mux.Vars(r)["id"]
		product, err := repo.GetByID(id)
		if err != nil {
			writeError(w, http.StatusNotFound, "Product not found")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(product)
	}
}

// CreateProductHandler creates a new product.
func CreateProductHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var p models.Product
		if err := json.NewDecoder(r.Body).Decode(&p); err != nil {
			writeError(w, http.StatusBadRequest, "Invalid request body")
			return
		}

		if err := validateProduct(&p); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}

		// Auto-generate ID if not provided.
		if p.ID == "" {
			p.ID = uuid.New().String()
		}

		if err := repo.Create(&p); err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to create product")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(p)
	}
}

// UpdateProductHandler updates an existing product.
func UpdateProductHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := mux.Vars(r)["id"]
		var p models.Product
		if err := json.NewDecoder(r.Body).Decode(&p); err != nil {
			writeError(w, http.StatusBadRequest, "Invalid request body")
			return
		}

		if err := validateProduct(&p); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}

		if err := repo.Update(id, &p); err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to update product")
			return
		}

		// Fetch the updated product from the database to return it.
		updated, err := repo.GetByID(id)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Product updated but failed to fetch")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(updated)
	}
}

// DeleteProductHandler deletes a product.
func DeleteProductHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := mux.Vars(r)["id"]
		if err := repo.Delete(id); err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to delete product")
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// validateProduct checks required fields and trims whitespace.
func validateProduct(p *models.Product) error {
	var errs []string

	p.ID = strings.TrimSpace(p.ID)
	p.Name = strings.TrimSpace(p.Name)
	p.Description = strings.TrimSpace(p.Description)
	p.ImageURL = strings.TrimSpace(p.ImageURL)
	p.Category = strings.TrimSpace(p.Category)

	if p.Name == "" {
		errs = append(errs, "name is required")
	}
	if p.Description == "" {
		errs = append(errs, "description is required")
	}
	if p.ImageURL == "" {
		errs = append(errs, "image_url is required")
	}
	if p.Category == "" {
		errs = append(errs, "category is required")
	}
	if p.Price <= 0 {
		errs = append(errs, "price must be greater than 0")
	}
	if p.Rating < 0 || p.Rating > 5 {
		errs = append(errs, "rating must be between 0 and 5")
	}
	if p.Specs == nil {
		p.Specs = []string{}
	}

	if len(errs) > 0 {
		return errors.New(strings.Join(errs, "; "))
	}
	return nil
}

// parseProductFilter extracts filter parameters from the request query string.
func parseProductFilter(r *http.Request) models.ProductFilter {
	q := r.URL.Query()
	f := models.ProductFilter{
		Category: q.Get("category"),
		Search:   q.Get("search"),
		StoreID:  q.Get("store_id"),
		SortBy:   q.Get("sort_by"),
	}

	if v := q.Get("min_price"); v != "" {
		if val, err := strconv.ParseFloat(v, 64); err == nil {
			f.MinPrice = &val
		}
	}
	if v := q.Get("max_price"); v != "" {
		if val, err := strconv.ParseFloat(v, 64); err == nil {
			f.MaxPrice = &val
		}
	}
	if v := q.Get("min_rating"); v != "" {
		if val, err := strconv.ParseFloat(v, 64); err == nil {
			f.MinRating = &val
		}
	}
	if v := q.Get("page"); v != "" {
		if val, err := strconv.Atoi(v); err == nil {
			f.Page = val
		}
	}
	if v := q.Get("page_size"); v != "" {
		if val, err := strconv.Atoi(v); err == nil {
			f.PageSize = val
		}
	}

	return f
}

// UploadImageHandler handles multipart file upload for product images.
func UploadImageHandler(cfg *UploadConfig) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// Limit request body size.
		r.Body = http.MaxBytesReader(w, r.Body, cfg.MaxUploadSize)

		if err := r.ParseMultipartForm(cfg.MaxUploadSize); err != nil {
			writeError(w, http.StatusBadRequest, "File too large or invalid multipart form")
			return
		}

		file, header, err := r.FormFile("image")
		if err != nil {
			writeError(w, http.StatusBadRequest, "Missing 'image' field in form data")
			return
		}
		defer file.Close()

		// Validate file type by extension.
		ext := strings.ToLower(filepath.Ext(header.Filename))
		allowedExts := map[string]bool{
			".jpg": true, ".jpeg": true, ".png": true, ".gif": true, ".webp": true,
		}
		if !allowedExts[ext] {
			writeError(w, http.StatusBadRequest, "Unsupported file type. Allowed: jpg, jpeg, png, gif, webp")
			return
		}

		// Generate unique filename.
		filename := fmt.Sprintf("%s%s", uuid.New().String(), ext)

		// Ensure upload directory exists.
		if err := os.MkdirAll(cfg.UploadDir, 0755); err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to create upload directory")
			return
		}

		// Write file to disk.
		dst, err := os.Create(filepath.Join(cfg.UploadDir, filename))
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to save file")
			return
		}
		defer dst.Close()

		if _, err := io.Copy(dst, file); err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to write file")
			return
		}

		// Build the accessible URL for the uploaded image.
		// Use X-Forwarded-Proto / Host headers to build a proper URL when behind a proxy.
		scheme := r.Header.Get("X-Forwarded-Proto")
		if scheme == "" {
			if r.TLS != nil {
				scheme = "https"
			} else {
				scheme = "http"
			}
		}
		host := r.Header.Get("X-Forwarded-Host")
		if host == "" {
			host = r.Host
		}
		imageURL := fmt.Sprintf("%s://%s/uploads/%s", scheme, host, filename)

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{
			"image_url": imageURL,
			"filename":  filename,
		})
	}
}

// writeError sends a JSON error response.
func writeError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": message})
}
