package handler_test

import (
	"bytes"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"io"
	"mime/multipart"
	"net/http"
	"strings"
	"testing"
)

// TestUploadImageAbsoluteURL pins the contract that the upload
// response's image_url is an absolute URL derived from the request's
// Host when BASE_URL is not configured. Without this, dev sessions
// (flutter run -d chrome on :9090 against the BE on :8080) get a
// relative URL like /uploads/x.jpg, which the browser resolves
// against :9090 → 404 → uploaded image never shows.
func TestUploadImageAbsoluteURL(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	// Build a tiny in-memory PNG so http.DetectContentType sniffs
	// image/png from the first 512 bytes. A naked filename without
	// the magic header would trip the MIME allowlist in the handler.
	img := image.NewRGBA(image.Rect(0, 0, 2, 2))
	for y := 0; y < 2; y++ {
		for x := 0; x < 2; x++ {
			img.Set(x, y, color.RGBA{R: 200, G: 100, B: 50, A: 255})
		}
	}
	var pngBuf bytes.Buffer
	if err := png.Encode(&pngBuf, img); err != nil {
		t.Fatalf("encode png: %v", err)
	}

	var body bytes.Buffer
	mw := multipart.NewWriter(&body)
	fw, err := mw.CreateFormFile("image", "tiny.png")
	if err != nil {
		t.Fatalf("create form file: %v", err)
	}
	if _, err := fw.Write(pngBuf.Bytes()); err != nil {
		t.Fatalf("write png: %v", err)
	}
	mw.Close()

	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/upload", &body)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST: %v", err)
	}
	respBody, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("upload status=%d body=%s", resp.StatusCode, string(respBody))
	}
	var payload struct {
		ImageURL string `json:"image_url"`
	}
	if err := json.Unmarshal(respBody, &payload); err != nil {
		t.Fatalf("decode upload response: %v body=%s", err, string(respBody))
	}

	// The new contract: the URL must be absolute and live on the
	// same host as the test server. Relative paths (the old
	// behavior) silently broke the dev workflow described above.
	if !strings.HasPrefix(payload.ImageURL, srv.URL+"/uploads/") {
		t.Fatalf("upload returned relative or wrong-host URL %q (want prefix %q)", payload.ImageURL, srv.URL+"/uploads/")
	}
}