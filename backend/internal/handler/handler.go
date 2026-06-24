package handler

import (
	"crypto/sha1"
	"encoding/hex"
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
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/mux"
	"github.com/ptg14/simshop/backend/internal/db"
	"github.com/ptg14/simshop/backend/models"
)

// UploadConfig holds configuration for file uploads.
type UploadConfig struct {
	UploadDir     string
	MaxUploadSize int64
	// BaseURL is the public base URL used to construct absolute image URLs.
	// When set, it overrides Host/X-Forwarded-Host headers to prevent host header spoofing.
	BaseURL string
}

// ProductRepo re-exports the db.ProductRepo type so the router can reference it.
type ProductRepo = db.ProductRepo

// StoreRepo re-exports the db.StoreRepo type so the router can reference it.
type StoreRepo = db.StoreRepo

// maxJSONBodySize limits the size of JSON request bodies to 1 MB.
const maxJSONBodySize = 1 << 20

// readJSONBody reads and decodes a JSON request body with size limiting and
// Content-Type validation. It returns an error suitable for writeError.
func readJSONBody(r *http.Request, v any) error {
	ct := r.Header.Get("Content-Type")
	if ct != "" {
		// Strip parameters (e.g., "application/json; charset=utf-8")
		if i := strings.Index(ct, ";"); i != -1 {
			ct = strings.TrimSpace(ct[:i])
		}
		if ct != "application/json" {
			return fmt.Errorf("unsupported Content-Type: %s", ct)
		}
	}
	r.Body = http.MaxBytesReader(nil, r.Body, maxJSONBodySize)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(v); err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			return fmt.Errorf("request body too large (max %d bytes)", maxJSONBodySize)
		}
		return fmt.Errorf("invalid request body: %w", err)
	}
	return nil
}

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
		// Return simple list of category names for frontend compatibility.
		cats, err := repo.GetCategories()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to fetch categories")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"categories": cats})
	}
}

// GetCategoriesWithParentHandler returns all categories with their large category name.
func GetCategoriesWithParentHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		cats, err := repo.GetCategoriesWithParent()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to fetch categories with parent")
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
			Name          string `json:"name"`
			LargeCategory string `json:"large_category,omitempty"`
		}
		if err := readJSONBody(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		name := strings.TrimSpace(body.Name)
		if name == "" {
			writeError(w, http.StatusBadRequest, "name is required")
			return
		}
		// Use the method that can associate a large category if provided.
		if err := repo.AddCategoryWithParent(name, strings.TrimSpace(body.LargeCategory)); err != nil {
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

// GetLargeCategoriesHandler returns persisted large categories.
func GetLargeCategoriesHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		cats, err := repo.GetLargeCategories()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to fetch large categories")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]any{"large_categories": cats})
	}
}

// CreateLargeCategoryHandler persists a new large category.
func CreateLargeCategoryHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Name string `json:"name"`
		}
		if err := readJSONBody(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		name := strings.TrimSpace(body.Name)
		if name == "" {
			writeError(w, http.StatusBadRequest, "name is required")
			return
		}
		if err := repo.AddLargeCategory(name); err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to add large category")
			return
		}
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(map[string]string{"name": name})
	}
}

// DeleteLargeCategoryHandler deletes a persisted large category.
func DeleteLargeCategoryHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		name := mux.Vars(r)["name"]
		if name == "" {
			writeError(w, http.StatusBadRequest, "name required")
			return
		}
		if err := repo.DeleteLargeCategory(name); err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to delete large category")
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
		// Retrieve the fully persisted product (including generated option IDs) to return to the client.
		created, err := repo.GetByID(p.ID)
		if err != nil {
			// If fetching fails, fall back to returning the original payload.
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusCreated)
			json.NewEncoder(w).Encode(p)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(created)
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

// GetStoreInfoHandler returns the singleton site identity / branding row.
// The migration guarantees the row exists, so this never returns 404.
func GetStoreInfoHandler(repo *StoreRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		info, err := repo.Get()
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to load site info")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(info)
	}
}

// UpdateStoreInfoHandler replaces the editable fields on the site info row.
// Name is required; all other fields are optional (stored as empty strings
// when blank). Field-length limits match the handler-side validation below
// so a malformed client payload is rejected before reaching the DB.
func UpdateStoreInfoHandler(repo *StoreRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Name          string `json:"name"`
			Description   string `json:"description"`
			LogoURL       string `json:"logo_url"`
			Phone         string `json:"phone"`
			Email         string `json:"email"`
			Address       string `json:"address"`
			GoogleMapsURL string `json:"google_maps_url"`
		}
		if err := readJSONBody(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		if err := validateStoreInfo(&body); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		info, err := repo.Update(body.Name, body.Description, body.LogoURL, body.Phone, body.Email, body.Address, body.GoogleMapsURL)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to save site info")
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(info)
	}
}

// validateStoreInfo trims whitespace and enforces length limits. Name is
// the only required field; contact fields are optional but must fit within
// their cap so an attacker can't blow up the response payload.
func validateStoreInfo(body *struct {
	Name          string `json:"name"`
	Description   string `json:"description"`
	LogoURL       string `json:"logo_url"`
	Phone         string `json:"phone"`
	Email         string `json:"email"`
	Address       string `json:"address"`
	GoogleMapsURL string `json:"google_maps_url"`
}) error {
	body.Name = strings.TrimSpace(body.Name)
	body.Description = strings.TrimSpace(body.Description)
	body.LogoURL = strings.TrimSpace(body.LogoURL)
	body.Phone = strings.TrimSpace(body.Phone)
	body.Email = strings.TrimSpace(body.Email)
	body.Address = strings.TrimSpace(body.Address)
	body.GoogleMapsURL = strings.TrimSpace(body.GoogleMapsURL)

	if body.Name == "" {
		return errors.New("name is required")
	}
	var errs []string
	if len(body.Name) > 80 {
		errs = append(errs, "name must be 80 characters or fewer")
	}
	if len(body.Description) > 500 {
		errs = append(errs, "description must be 500 characters or fewer")
	}
	if len(body.LogoURL) > 1000 {
		errs = append(errs, "logo_url must be 1000 characters or fewer")
	}
	if len(body.Phone) > 50 {
		errs = append(errs, "phone must be 50 characters or fewer")
	}
	if len(body.Email) > 200 {
		errs = append(errs, "email must be 200 characters or fewer")
	}
	if len(body.Address) > 300 {
		errs = append(errs, "address must be 300 characters or fewer")
	}
	if len(body.GoogleMapsURL) > 1000 {
		errs = append(errs, "google_maps_url must be 1000 characters or fewer")
	}
	if len(errs) > 0 {
		return errors.New(strings.Join(errs, "; "))
	}
	return nil
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
	// Trim and validate options (support multiple image URLs)
	for i := range p.Options {
		p.Options[i].ID = strings.TrimSpace(p.Options[i].ID)
		p.Options[i].Name = strings.TrimSpace(p.Options[i].Name)
		// trim each image url
		for j := range p.Options[i].ImageURLs {
			p.Options[i].ImageURLs[j] = strings.TrimSpace(p.Options[i].ImageURLs[j])
		}
		if p.Options[i].ImageURLs == nil {
			p.Options[i].ImageURLs = []string{}
		}
		// ensure option has a name
		if p.Options[i].Name == "" {
			errs = append(errs, "option name is required")
		}
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
	// Categories are optional. For backward compatibility, if a single
	// `Category` string is provided but `Categories` slice is empty,
	// populate the slice. Do not require a category.
	if len(p.Categories) == 0 {
		if p.Category != "" {
			p.Categories = []string{p.Category}
		} else {
			p.Categories = []string{}
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

		// Read naming context from the form so we can build a descriptive
		// filename: YYYYMMDD-<slug>-<index>.<ext>.
		// - "product_name" / "product_id" are optional but recommended.
		// - "index" is the per-upload 1-based ordinal so multi-image
		//   uploads stay in order.
		productName := strings.TrimSpace(r.FormValue("product_name"))
		productID := strings.TrimSpace(r.FormValue("product_id"))
		// baseIndex lets the client request a specific starting ordinal
		// (e.g. when appending to an existing product's images). It
		// stays 0 if absent, in which case each upload gets ordinal = i+1.
		baseIndex := 0
		if v := r.FormValue("index"); v != "" {
			if n, err := strconv.Atoi(v); err == nil && n > 0 {
				baseIndex = n
			}
		}

		// Support multiple file fields: 'images' (preferred) or repeated 'image'.
		var uploadedURLs []string
		var filenames []string

		// Helper to process a file header.
		saveFile := func(header *multipart.FileHeader, ordinal int) (string, string, error) {
			f, err := header.Open()
			if err != nil {
				return "", "", err
			}
			defer f.Close()

			// Validate MIME type by reading the first 512 bytes to detect content type.
			// This prevents attackers from bypassing extension checks by renaming files.
			buf := make([]byte, 512)
			n, _ := io.ReadFull(f, buf)
			if n == 0 {
				return "", "", fmt.Errorf("empty file")
			}
			contentType := http.DetectContentType(buf[:n])
			allowedMIMEs := map[string]bool{
				"image/jpeg": true,
				"image/png":  true,
				"image/gif":  true,
				"image/webp": true,
			}
			if !allowedMIMEs[contentType] {
				return "", "", fmt.Errorf("unsupported file type: %s", contentType)
			}

			// Map detected MIME to safe extension — never trust the user-supplied filename.
			ext := ".jpg" // default
			switch contentType {
			case "image/jpeg":
				ext = ".jpg"
			case "image/png":
				ext = ".png"
			case "image/gif":
				ext = ".gif"
			case "image/webp":
				ext = ".webp"
			}

			// Seek back to beginning so io.Copy reads the full file.
			if _, err := f.Seek(0, io.SeekStart); err != nil {
				return "", "", err
			}

			filename := buildUploadFilename(productName, productID, ordinal, ext)
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
			// Construct the public URL for the uploaded file.
			// Prefer the configured BaseURL to prevent host header spoofing.
			var imageURL string
			if cfg.BaseURL != "" {
				imageURL = fmt.Sprintf("%s/uploads/%s", strings.TrimRight(cfg.BaseURL, "/"), filename)
			} else {
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
				imageURL = fmt.Sprintf("%s://%s/uploads/%s", scheme, host, filename)
			}
			return imageURL, filename, nil
		}

		// Check 'images' first
		if r.MultipartForm != nil {
			if headers, ok := r.MultipartForm.File["images"]; ok && len(headers) > 0 {
				log.Printf("upload: received %d files in 'images' field", len(headers))
				for i, h := range headers {
					ordinal := baseIndex + i + 1
					url, fname, err := saveFile(h, ordinal)
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
				for i, h := range headers {
					ordinal := baseIndex + i + 1
					url, fname, err := saveFile(h, ordinal)
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

// buildUploadFilename constructs a human-readable filename for an uploaded
// image using the format YYYYMMDD-<slug>-<index>.<ext>.
//
// The slug is derived from productName (with a short hash of productID
// appended when available) so that:
//   - Files are easy to scan in the uploads directory.
//   - Different products with similar names don't collide.
//   - Two uploads of the same image (same name+ID) still get unique names
//     thanks to the per-request uuid suffix.
//
// If productName is empty, falls back to "image".
func buildUploadFilename(productName, productID string, index int, ext string) string {
	date := time.Now().UTC().Format("20060102")
	slug := slugify(productName)
	if slug == "" {
		slug = "image"
	}
	if productID != "" {
		// Short hash of productID (8 hex chars) — keeps filenames unique
		// across products that share a name.
		h := sha1.Sum([]byte(productID))
		slug = fmt.Sprintf("%s-%s", slug, hex.EncodeToString(h[:])[:8])
	}
	// Ordinal ensures ordering within a multi-file upload (1-based).
	if index < 1 {
		index = 1
	}
	return fmt.Sprintf("%s-%s-%d-%s%s", date, slug, index, uuid.New().String()[:8], ext)
}

// slugify converts a product name into a URL- and filesystem-safe slug.
// Lowercases, strips diacritics is not attempted (kept simple), replaces
// any non-[a-z0-9]+ runs with a single dash, trims leading/trailing dashes,
// and caps length at 48 chars so the final filename stays manageable.
func slugify(name string) string {
	name = strings.ToLower(strings.TrimSpace(name))
	if name == "" {
		return ""
	}
	var b strings.Builder
	b.Grow(len(name))
	prevDash := false
	for _, r := range name {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
			prevDash = false
		case r == ' ' || r == '-' || r == '_':
			if !prevDash && b.Len() > 0 {
				b.WriteByte('-')
				prevDash = true
			}
		default:
			// drop diacritics / punctuation by skipping
		}
	}
	out := strings.TrimRight(b.String(), "-")
	if len(out) > 48 {
		out = strings.TrimRight(out[:48], "-")
	}
	return out
}
