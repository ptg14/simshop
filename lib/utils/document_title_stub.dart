/// Non-web implementation of [setBrowserDocumentTitle].
///
/// This file is selected by the conditional `export` in
/// `document_title.dart` on every platform *except* the web
/// (`dart.library.html` is unavailable). The function is a
/// no-op because the OS reads the app's launcher name (set
/// once via `MaterialApp.title`) — not `document.title` — so
/// updating it would be wasted work.
void setBrowserDocumentTitle(String title) {
  // Intentionally empty — see file header.
}
