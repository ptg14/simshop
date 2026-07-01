#!/usr/bin/env bash
#
# Production web build for simshop.
#
# Runs `flutter build web --release` and then strips the debug-only
# `.symbols` files Flutter ships into `build/web/canvaskit/`. Those
# files duplicate the line-number tables of the Skia canvaskit / skwasm
# / wimp WebAssembly modules and are ~8 MB on disk. They are intended
# for local symbolication; shipping them to users adds hundreds of
# milliseconds to the bootstrap download with no client-visible benefit.
#
# Usage:  ./tool/build_web.sh
# Output: ./build/web/
#
# The dev workflow (`flutter run -d chrome`) and CI checks
# (`flutter analyze`, `flutter test`) are unchanged. This script is
# only for the *release* build that gets uploaded to a CDN.
set -euo pipefail

# Find the Flutter SDK the way the user invokes flutter on the CLI.
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

echo "→ flutter build web --release"
"$FLUTTER_BIN" build web --release

echo "→ stripping debug .symbols files from build/web/"
# Flutter does not have a public flag for this; rather than fork the
# tool we delete the files we know are debug-only. Add to this list
# when new renderers ship.
# Note: avoids `find ... -delete` because some shells (and wrappers
# like `rtk`) intercept compound predicates — a plain loop is robust.
while IFS= read -r -d '' f; do rm -- "$f"; done < <(find build/web -type f -name '*.symbols' -print0)
# `.map` files (JS source maps) are similarly unused by end users.
while IFS= read -r -d '' f; do rm -- "$f"; done < <(find build/web -type f -name '*.map' -print0)

# Report the post-strip size so build logs surface regressions.
SIZE=$(du -sh build/web | cut -f1)
echo "✓ build/web size: ${SIZE}"
