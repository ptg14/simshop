package handler_test

import (
	"io"
	"net/http"
	"strings"
	"testing"
)

// TestArticleCreateRejectsEmptyID pins the contract that POST
// /api/articles must reject an empty/missing id. Without this guard
// the article row lands in the DB with PRIMARY KEY "", the admin UI
// shows it in the list, and clicking delete fires DELETE
// /api/articles/ (trailing slash, empty id) which 404s. The admin
// Flutter side always generates a microsecondsSinceEpoch id before
// POSTing, but we pin the server-side rule so a future client bug
// or a stray script can't poison the table.
func TestArticleCreateRejectsEmptyID(t *testing.T) {
	srv, _, cleanup := newTestServer(t)
	defer cleanup()

	// Empty string id.
	body := strings.NewReader(`{
		"id": "",
		"title": "Bài viết lỗi",
		"body_markdown": "",
		"product_ids": []
	}`)
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/articles", body)
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("POST: %v", err)
	}
	respBody, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("POST with empty id: status=%d want=400 body=%s", resp.StatusCode, string(respBody))
	}
	if !strings.Contains(string(respBody), "id is required") {
		t.Fatalf("POST with empty id: body=%q should mention 'id is required'", string(respBody))
	}

	// Missing id field entirely (Go JSON decoder leaves it as "").
	body2 := strings.NewReader(`{"title": "Bài viết thiếu id"}`)
	req2, _ := http.NewRequest(http.MethodPost, srv.URL+"/api/articles", body2)
	req2.Header.Set("Content-Type", "application/json")
	resp2, err := http.DefaultClient.Do(req2)
	if err != nil {
		t.Fatalf("POST no id: %v", err)
	}
	respBody2, _ := io.ReadAll(resp2.Body)
	resp2.Body.Close()
	if resp2.StatusCode != http.StatusBadRequest {
		t.Fatalf("POST without id: status=%d want=400 body=%s", resp2.StatusCode, string(respBody2))
	}
}