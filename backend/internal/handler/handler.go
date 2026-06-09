package handler

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"mime/multipart"
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

// GetCategoriesHandler returns persisted categories.
func GetCategoriesHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		cats, err := repo.GetCategories()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to fetch categories")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"categories": cats})
	}
}

// CreateCategoryHandler persists a new category.
func CreateCategoryHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Name string `json:"name"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			writeError(w, http.StatusBadRequest, "Invalid request body")
			return
		}
		name := strings.TrimSpace(body.Name)
		if name == "" {
			writeError(w, http.StatusBadRequest, "name is required")
			return
		}
		if err := repo.AddCategory(name); err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to add category")
			return
		}
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]string{"name": name})
	}
}

// DeleteCategoryHandler deletes a persisted category.
func DeleteCategoryHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		name := mux.Vars(r)["name"]
		if name == "" {
			writeError(w, http.StatusBadRequest, "name required")
			return
		}
		if err := repo.DeleteCategory(name); err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to delete category")
			return
		}
		w.WriteHeader(http.StatusNoContent)
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

		// Ensure primary image_url is set from images if missing
		if p.ImageURL == "" && len(p.Images) > 0 {
			p.ImageURL = p.Images[0]
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

		// Ensure primary image_url is set from images if missing
		if p.ImageURL == "" && len(p.Images) > 0 {
			p.ImageURL = p.Images[0]
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
	// Trim image URLs in Images slice
	for i := range p.Images {
		p.Images[i] = strings.TrimSpace(p.Images[i])
	}
	p.Category = strings.TrimSpace(p.Category)

	if p.Name == "" {
		errs = append(errs, "name is required")
	}
	// Description is optional now; do not require it.
	// Require at least one image either in ImageURL or Images.
	if p.ImageURL == "" && len(p.Images) == 0 {
		errs = append(errs, "at least one image is required (image_url or images)")
	}
	// Require at least one category in the categories list.
	if len(p.Categories) == 0 {
		// fallback to single category field for older clients
		if p.Category == "" {
			errs = append(errs, "category is required")
		} else {
			// populate categories from single category
			p.Categories = []string{p.Category}
		}
	} else {
		// ensure primary category string is populated for backward compatibility
		if p.Category == "" && len(p.Categories) > 0 {
			p.Category = p.Categories[0]
		}
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

		// Support multiple file fields: 'images' (preferred) or repeated 'image'.
		var uploadedURLs []string
		var filenames []string

		// Helper to process a file header.
		saveFile := func(header *multipart.FileHeader) (string, string, error) {
			f, err := header.Open()
			if err != nil {
				return "", "", err
			}
			defer f.Close()
			ext := strings.ToLower(filepath.Ext(header.Filename))
			// If the uploaded file has no extension (common with browser blob uploads),
			// try to infer it from the Content-Type header. Fall back to .jpg.
			if ext == "" {
				if ct := header.Header.Get("Content-Type"); ct != "" {
					switch strings.ToLower(ct) {
					case "image/jpeg", "image/jpg":
						ext = ".jpg"
					case "image/png":
						ext = ".png"
					case "image/gif":
						ext = ".gif"
					case "image/webp":
						ext = ".webp"
					}
				}
			}
			if ext == "" {
				ext = ".jpg"
			}
			allowedExts := map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".gif": true, ".webp": true}
			if !allowedExts[ext] {
				return "", "", fmt.Errorf("unsupported file type")
			}
			filename := fmt.Sprintf("%s%s", uuid.New().String(), ext)
			if err := os.MkdirAll(cfg.UploadDir, 0755); err != nil {
				return "", "", err
			}
			dst, err := os.Create(filepath.Join(cfg.UploadDir, filename))
			if err != nil {
				return "", "", err
			}
			defer dst.Close()
			if _, err := io.Copy(dst, f); err != nil {
				return "", "", err
			}
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
			return imageURL, filename, nil
		}

		// Check 'images' first
		if r.MultipartForm != nil {
			if headers, ok := r.MultipartForm.File["images"]; ok && len(headers) > 0 {
				log.Printf("upload: received %d files in 'images' field", len(headers))
				for _, h := range headers {
					url, fname, err := saveFile(h)
					if err != nil {
						log.Printf("upload: saveFile error: %v", err)
						writeError(w, http.StatusBadRequest, "Unsupported file type or failed to save")
						return
					}
					log.Printf("upload: saved file %s -> %s", fname, url)
					uploadedURLs = append(uploadedURLs, url)
					filenames = append(filenames, fname)
				}
			} else if headers, ok := r.MultipartForm.File["image"]; ok && len(headers) > 0 {
				log.Printf("upload: received %d files in 'image' field", len(headers))
				for _, h := range headers {
					url, fname, err := saveFile(h)
					if err != nil {
						log.Printf("upload: saveFile error: %v", err)
						writeError(w, http.StatusBadRequest, "Unsupported file type or failed to save")
						return
					}
					log.Printf("upload: saved file %s -> %s", fname, url)
					uploadedURLs = append(uploadedURLs, url)
					filenames = append(filenames, fname)
				}
			}
		}

		if len(uploadedURLs) == 0 {
			writeError(w, http.StatusBadRequest, "No image files provided")
			return
		}

		// Return both array and first URL for backward compatibility.
		resp := map[string]any{"image_urls": uploadedURLs, "filenames": filenames, "image_url": uploadedURLs[0]}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	}
}

// writeError sends a JSON error response.
func writeError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(map[string]string{"error": message})
}
