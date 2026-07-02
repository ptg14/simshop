// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web implementation of [setBrowserDocumentTitle].
///
/// Writes the supplied [title] to `document.title`, which is
/// what the browser renders in the tab strip and the window
/// title bar. The web build is the only one that imports this
/// file — see the conditional `export` in
/// `document_title.dart`.
///
/// We re-throw no exceptions: a DOM write that fails (e.g. the
/// document is in an unusual state) shouldn't crash the app, and
/// the AppBar title still shows the right value regardless.
void setBrowserDocumentTitle(String title) {
  html.document.title = title;
}
