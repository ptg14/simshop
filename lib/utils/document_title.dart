// Cross-platform helper for updating the browser tab / window
// title.
//
// On web this sets `document.title` (the title the browser
// shows in the tab and window header). On mobile and desktop
// this is a no-op — the OS doesn't read `document.title`; it
// uses the app's launcher name (set in
// `MaterialApp.title`) which is configured once at app boot
// and doesn't change at runtime.
//
// We use a conditional export so the non-web build never
// references `dart:html` (which would fail to compile on
// mobile/desktop). The two implementations are:
//
//   * document_title_web.dart    — uses `dart:html` on web
//   * document_title_stub.dart   — no-op everywhere else
export 'document_title_stub.dart'
    if (dart.library.html) 'document_title_web.dart';
