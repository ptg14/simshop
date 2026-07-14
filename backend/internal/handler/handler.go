package handler

import (
	"crypto/sha1"
	"database/sql"
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
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/gorilla/mux"
	"github.com/ptg14/simshop/backend/internal/db"
	"github.com/ptg14/simshop/backend/internal/uploadfs"
	"github.com/ptg14/simshop/backend/models"
	"golang.org/x/sync/semaphore"
)

// UploadConfig is an alias for [uploadfs.UploadConfig] so existing
// call sites that reference handler.UploadConfig (router, server,
// handler_test, the upload handler itself) keep compiling after the
// helper moved out to break the db↔handler import cycle.
type UploadConfig = uploadfs.UploadConfig

// categoryNameRe is the canonical "what category names look like"
// charset: letters (any script), digits, space, underscore, hyphen.
// Rejects control characters, punctuation, and emoji — those make
// the admin dashboard harder to scan and would risk stored-XSS if any
// future export path renders the value as HTML. Length is capped at
// [maxCategoryNameLen].
var categoryNameRe = regexp.MustCompile(`^[\p{L}\p{N} _-]+$`)

const maxCategoryNameLen = 64

// validateCategoryName trims whitespace, enforces the length cap, and
// rejects any character outside the safe charset. Returns the
// canonical (trimmed) value on success; on failure the error message
// is safe to surface to the admin UI verbatim.
func validateCategoryName(raw string) (string, error) {
	s := strings.TrimSpace(raw)
	if s == "" {
		return "", errors.New("name is required")
	}
	if len(s) > maxCategoryNameLen {
		return "", fmt.Errorf("name must be %d characters or fewer", maxCategoryNameLen)
	}
	if !categoryNameRe.MatchString(s) {
		return "", errors.New("name contains disallowed characters")
	}
	return s, nil
}

// uploadSem caps concurrent in-flight upload files across the whole
// process. Without this an attacker could open many slow multipart
// streams simultaneously and pin goroutines / disk. The cap is on
// files (not requests) because a single request may carry multiple.
var uploadSem = semaphore.NewWeighted(4)

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
//
// Each product is decorated at read time with `effective_price` and
// `current_event`: the underlying product row is never mutated by
// promotions, so when an event expires the discount disappears
// automatically on the next request without any background job.
func GetProductsHandler(repo *ProductRepo, eventRepo *EventRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		filter := parseProductFilter(r)

		result, err := repo.GetAllFiltered(filter)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "Failed to fetch products")
			return
		}
		decorated := decorateProductsWithEvents(result.Products, eventRepo)
		result.Products = nil
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(struct {
			Products   []productWithEvent `json:"products"`
			Total      int                `json:"total"`
			Page       int                `json:"page"`
			PageSize   int                `json:"page_size"`
			TotalPages int                `json:"total_pages"`
		}{
			Products:   decorated,
			Total:      result.Total,
			Page:       result.Page,
			PageSize:   result.PageSize,
			TotalPages: result.TotalPages,
		})
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
		name, err := validateCategoryName(body.Name)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
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
		name, err := validateCategoryName(body.Name)
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
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

// GetProductHandler returns a single product by ID. The product is
// decorated with `effective_price` and `current_event` exactly like
// the list endpoint so the detail screen and the list agree on
// what the customer should pay.
func GetProductHandler(repo *ProductRepo, eventRepo *EventRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := mux.Vars(r)["id"]
		product, err := repo.GetByID(id)
		if err != nil {
			writeError(w, http.StatusNotFound, "Product not found")
			return
		}
		wrapped := decorateProductsWithEvents([]models.Product{*product}, eventRepo)
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(wrapped[0])
	}
}

// CreateProductHandler creates a new product.
func CreateProductHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// [removed_image_urls] is accepted on create for symmetry with
		// the update path but is no-op in practice — there's no
		// pre-existing image to delete on a brand-new product.
		var body struct {
			models.Product
			RemovedImageURLs []string `json:"removed_image_urls"`
		}
		if err := readJSONBody(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		p := body.Product

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
//
// The request body may include a top-level [removed_image_urls] array
// listing image URLs the admin dropped from the gallery. After the
// DB UPDATE commits, each of those files is best-effort deleted from
// disk so /uploads/ doesn't fill up with orphan images.
func UpdateProductHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := mux.Vars(r)["id"]
		var body struct {
			models.Product
			RemovedImageURLs []string `json:"removed_image_urls"`
		}
		if err := readJSONBody(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		p := body.Product

		if err := validateProduct(&p); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}

		// Ensure primary image_url is set from images if missing
		if p.ImageURL == "" && len(p.Images) > 0 {
			p.ImageURL = p.Images[0]
		}

		if err := repo.Update(id, &p, body.RemovedImageURLs); err != nil {
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

// DeleteProductHandler deletes a product. Returns 404 when no product
// with the given id exists (mirrors DeleteBanner/DeleteArticle so an
// admin can tell a successful delete from a no-op).
func DeleteProductHandler(repo *ProductRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := mux.Vars(r)["id"]
		if err := repo.Delete(id); err == sql.ErrNoRows {
			writeError(w, http.StatusNotFound, "product not found")
			return
		} else if err != nil {
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
//
// [body.OldBannerURL] is the banner URL the row held before this update.
// When the admin replaces the banner, the previous file is best-effort
// deleted from disk after the UPDATE commits — see store_repo for the
// exact diff logic. Omitting the field is back-compat: the old file is
// simply left in place.
func UpdateStoreInfoHandler(repo *StoreRepo) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Name          string `json:"name"`
			Description   string `json:"description"`
			BannerURL     string `json:"banner_url"`
			Phone         string `json:"phone"`
			Email         string `json:"email"`
			Address       string `json:"address"`
			GoogleMapsURL string `json:"google_maps_url"`
			OldBannerURL  string `json:"old_banner_url"`
		}
		if err := readJSONBody(r, &body); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		if err := validateStoreInfo(&body); err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		info, err := repo.Update(body.Name, body.Description, body.BannerURL, body.Phone, body.Email, body.Address, body.GoogleMapsURL, body.OldBannerURL)
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
	BannerURL     string `json:"banner_url"`
	Phone         string `json:"phone"`
	Email         string `json:"email"`
	Address       string `json:"address"`
	GoogleMapsURL string `json:"google_maps_url"`
	OldBannerURL  string `json:"old_banner_url"`
}) error {
	body.Name = strings.TrimSpace(body.Name)
	body.Description = strings.TrimSpace(body.Description)
	body.BannerURL = strings.TrimSpace(body.BannerURL)
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
	if len(body.BannerURL) > 1000 {
		errs = append(errs, "banner_url must be 1000 characters or fewer")
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
	// Description is optional — do not require it.
	// Image is optional — do not require it. The previous
	// "at least one image is required" check was a regression for
	// admins creating text-only drafts: the admin UI would submit
	// a product with an empty gallery, the server rejected it with
	// 400, and the only recourse was to upload a placeholder image
	// and edit it later. Letting the product persist without any
	// image URL matches what the home grid already does when
	// `image_url == ""` (it shows an "Sản phẩm chưa có ảnh"
	// placeholder). Pinned by
	// TestProductCreateAcceptsNoImage + the negative half
	// TestProductCreateStillRequiresNameAndPrice (which locks the
	// name + price checks so a future refactor can't accidentally
	// widen the relaxation to *all* fields).
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

		// Helper to process a file header. Acquires [uploadSem] so
		// at most a small number of files are being read+written
		// concurrently across the whole server — bounds the resource
		// consumption of an attacker pinning slow multipart streams.
		saveFile := func(header *multipart.FileHeader, ordinal int) (string, string, error) {
			if err := uploadSem.Acquire(r.Context(), 1); err != nil {
				return "", "", fmt.Errorf("upload concurrency limit reached: %w", err)
			}
			defer uploadSem.Release(1)
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
			// Priority:
			//   1. cfg.BaseURL (configured public origin).
			//   2. Emitted relative URL — safer than honoring the
			//      spoofable Host / X-Forwarded-Host headers when the
			//      deployment isn't behind a TRUSTED_PROXIES-allow-listed
			//      proxy. Browsers resolve the relative URL against the
			//      current page origin.
			//
			// The host-header fallback is preserved for backward compat
			// because the rate-limiter proxy gating (TRUSTED_PROXIES) is
			// not yet threaded through to this handler. Operators who
			// set cfg.BaseURL get the absolute URL; everyone else gets a
			// relative URL plus a one-shot warning.
			var imageURL string
			if cfg.BaseURL != "" {
				imageURL = fmt.Sprintf("%s/uploads/%s", strings.TrimRight(cfg.BaseURL, "/"), filename)
			} else {
				log.Printf("upload: BASE_URL not configured; emitting relative URL for %q. Set BASE_URL (or TRUSTED_PROXIES for the rate limiter) to control absolute URLs.", filename)
				imageURL = "/uploads/" + filename
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
//
// Lowercases the input, transliterates Vietnamese letters to their ASCII
// equivalents (ă→a, â→a, đ→d, ơ→o, ư→u, plus all tone marks → base
// letter), collapses runs of whitespace/'-'/'_' into a single dash,
// trims leading/trailing dashes, and caps the result at 48 chars so the
// final upload filename stays manageable.
//
// Vietnamese map is intentionally inline (no external dep) because:
//   - It's the dominant language in this catalog, so a generic
//     transliteration library would add weight for no extra accuracy.
//   - The mapping is exhaustive for the 134 Vietnamese pre-composed
//     letters (a-z, A-Z control) and easy to audit in code review.
func slugify(name string) string {
	name = strings.ToLower(strings.TrimSpace(name))
	if name == "" {
		return ""
	}
	var b strings.Builder
	b.Grow(len(name))
	prevDash := false
	for _, r := range name {
		// Vietnamese pre-composed letters → ASCII base letter.
		// Listed in Vietnamese alphabetical order for easy audit.
		// (Uppercase keys are unreachable after ToLower, but we keep the
		// map cover both cases defensively for future callers.)
		if mapped, ok := vnLetterMap[r]; ok {
			b.WriteRune(mapped)
			prevDash = false
			continue
		}
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
			// drop any other punctuation / emoji / etc.
		}
	}
	out := strings.TrimRight(b.String(), "-")
	if len(out) > 48 {
		out = strings.TrimRight(out[:48], "-")
	}
	return out
}

// vnLetterMap transliterates Vietnamese pre-composed letters to ASCII.
// Each key is one of the 134 Vietnamese pre-composed codepoints
// (U+00C0..U+024F range plus U+1EA0..U+1EF9); the value is the ASCII
// base letter that should appear in the slug. Tone marks are stripped
// entirely (sắc, huyền, hỏi, ngã, nặng all collapse to the base letter).
//
// Why a flat map and not NFD-strip:
//   - NFD decomposition strips tone marks but still leaves ơ, ư, đ
//     untouched, producing slugs like "ao-so-mi-nam" that miss the
//     vowel entirely (e.g. "sơ" → "so"). The flat map keeps the vowel.
//   - It also avoids pulling in golang.org/x/text/unicode/norm just
//     for this one helper.
//
// Source of truth: TCVN 6909:2001 / Unicode Latin Extended-A/B blocks
// covering the modern Vietnamese alphabet.
var vnLetterMap = map[rune]rune{
	// a / ă / â (with all 6 tone marks each)
	//   plain: a ă â
	'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
	'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
	'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
	// ă / â bare (no tone) — pre-composed forms
	'ă': 'a', 'â': 'a',
	// đ / Đ
	'đ': 'd', 'Đ': 'd',
	// e / ê (with all 6 tone marks each)
	'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
	'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
	'ê': 'e',
	// i (with all 6 tone marks)
	'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
	// o / ô / ơ (with all 6 tone marks each)
	'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
	'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
	'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
	'ô': 'o', 'ơ': 'o',
	// u / ư (with all 6 tone marks each)
	'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
	'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
	'ư': 'u',
	// y (with all 6 tone marks)
	'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
	// Uppercase forms — reachable only if a future caller passes an
	// un-lowered string. Kept so the map is "complete".
	'À': 'a', 'Á': 'a', 'Ả': 'a', 'Ã': 'a', 'Ạ': 'a',
	'Ằ': 'a', 'Ắ': 'a', 'Ẳ': 'a', 'Ẵ': 'a', 'Ặ': 'a',
	'Ầ': 'a', 'Ấ': 'a', 'Ẩ': 'a', 'Ẫ': 'a', 'Ậ': 'a',
	'Ă': 'a', 'Â': 'a',
	'È': 'e', 'É': 'e', 'Ẻ': 'e', 'Ẽ': 'e', 'Ẹ': 'e',
	'Ề': 'e', 'Ế': 'e', 'Ể': 'e', 'Ễ': 'e', 'Ệ': 'e',
	'Ê': 'e',
	'Ì': 'i', 'Í': 'i', 'Ỉ': 'i', 'Ĩ': 'i', 'Ị': 'i',
	'Ò': 'o', 'Ó': 'o', 'Ỏ': 'o', 'Õ': 'o', 'Ọ': 'o',
	'Ồ': 'o', 'Ố': 'o', 'Ổ': 'o', 'Ỗ': 'o', 'Ộ': 'o',
	'Ờ': 'o', 'Ớ': 'o', 'Ở': 'o', 'Ỡ': 'o', 'Ợ': 'o',
	'Ô': 'o', 'Ơ': 'o',
	'Ù': 'u', 'Ú': 'u', 'Ủ': 'u', 'Ũ': 'u', 'Ụ': 'u',
	'Ừ': 'u', 'Ứ': 'u', 'Ử': 'u', 'Ữ': 'u', 'Ự': 'u',
	'Ư': 'u',
	'Ỳ': 'y', 'Ý': 'y', 'Ỷ': 'y', 'Ỹ': 'y', 'Ỵ': 'y',
}
