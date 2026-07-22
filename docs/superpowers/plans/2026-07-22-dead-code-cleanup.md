# Dead Code & Trash Comments Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove dead code, trash comments, debug leftovers, and formatting noise from `lib/` (Dart), `backend/` (Go), and `test/` (Dart) — without changing any behavior or public API.

**Architecture:** Tool-assisted auto-fix first (`dart fix --apply`, `gofmt -w`, `goimports -w`), then file-by-file manual sweep, committing per module. No logic changes. Verification gate: `flutter analyze` = 0 error, `go vet ./...` = 0 issue. Tests NOT run (per user).

**Tech Stack:** Flutter/Dart 3, Go 1.x, `dart fix`, `gofmt`, `go vet`, ripgrep (`rg`), git.

**Spec:** `docs/superpowers/specs/2026-07-22-dead-code-cleanup-design.md`

## Global Constraints

- **Scope:** `lib/`, `backend/`, `test/`. Out of scope: `android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/`, `docker/`, `tool/`, `assets/`, `build/`, `.dart_tool/`, `.idea/`, `.github/`, `pubspec.yaml`, `go.mod`, `analysis_options.yaml`.
- **DO NOT change:** public class/function signatures, exported symbols, business logic, test assertions, lint rules, dependencies.
- **DO change:** unused imports, unused private functions/classes, dead local variables, comments that just restate code, `print()`/`debugPrint()`/`fmt.Println()` debug leftovers, commented-out code blocks, blank line clusters (>2), trailing whitespace, inconsistent formatting.
- **KEEP:** `///` doc comments on public API, comments explaining "why" (not "what"), `// TODO: <ticket>` with a real ticket reference, section header comments in long files.
- **Commit convention:** `chore(cleanup): <scope> — <one-line summary>`. Body lists what was removed.
- **Per-commit gate:** `flutter analyze` returns 0 error AND `go vet ./...` returns 0 issue. If only Dart files changed, skip go vet. If only Go files changed, skip flutter analyze.
- **Split rule:** If a single module produces >500 LOC diff, split by sub-folder into a follow-up commit (notify user before pushing).
- **No test runs.** `flutter analyze` and `go vet` only.

---

## Task 1: Baseline + auto-fix snapshot

**Files:**
- Touch: all Dart files in `lib/`, all Go files in `backend/`
- No test changes

**Interfaces:**
- Consumes: current dirty state
- Produces: a known-clean baseline that subsequent manual sweeps can diff against

- [ ] **Step 1: Capture current analyze state**

```bash
flutter analyze 2>&1 | tee /tmp/cleanup-baseline-analyze.txt
go vet ./... 2>&1 | tee /tmp/cleanup-baseline-vet.txt
```

Expected: both commands exit 0 (project was clean before this task). Note the line counts for later comparison.

- [ ] **Step 2: Run dart fix**

```bash
dart fix --apply
```

Review the output. If dart fix proposes signature changes (rare), REJECT that file via `git checkout -- <file>` and add it to the out-of-scope list in the final report.

- [ ] **Step 3: Run gofmt + goimports**

```bash
gofmt -w backend/
which goimports && goimports -w backend/ || echo "goimports not installed, skipping"
```

If `goimports` not installed, skip — `gofmt` alone handles formatting; `go vet` will catch missing imports.

- [ ] **Step 4: Verify nothing broke**

```bash
flutter analyze 2>&1 | tail -5
go vet ./... 2>&1 | tail -5
```

Expected: same line counts as baseline (or fewer). Both exit 0.

- [ ] **Step 5: Commit auto-fix**

```bash
git add lib/ backend/
git diff --cached --stat | tail -5
git commit -m "chore(cleanup): auto-fix dart fix + gofmt baseline" -m "Ran dart fix --apply and gofmt -w. No manual edits. Reviewers: diff should be mechanical (imports/order/formatting only)."
```

---

## Task 2: Clean `lib/main.dart`, `lib/config/`, `lib/theme/`, `lib/utils/`

**Files:**
- Modify: ~10 files in `lib/main.dart`, `lib/config/`, `lib/theme/`, `lib/utils/`
- LOC budget: ~1100 (main.dart=378, responsive.dart=283, plus small config/theme/utils)

- [ ] **Step 1: List files in scope**

```bash
ls lib/main.dart lib/config/ lib/theme/ lib/utils/
```

- [ ] **Step 2: For each file, read in full**

Use Read tool on each file. For each file:
1. Identify unused imports (`import` lines whose symbols aren't referenced).
2. Identify `//` comments that just restate the next line of code. Remove them.
3. Identify `print()` / `debugPrint()` calls. If they look like debug leftovers (no log framework, not in error handler), remove them. Keep them if in catch blocks logging real errors.
4. Identify unused private functions (`_foo()` with no callers — grep with `rg "_foo" lib/`).
5. Identify commented-out code blocks (>2 consecutive lines starting with `//` that look like code, not prose). Remove.
6. Identify blank line clusters (>2 newlines in a row). Collapse to max 2.
7. Remove trailing whitespace.

- [ ] **Step 3: Apply edits with Edit tool**

For each file, make targeted Edit calls. Do NOT rewrite the whole file. Each edit must keep:
- Public class/function signatures.
- `///` doc comments.
- Comments that explain "why" (intent, trade-off, constraint).

- [ ] **Step 4: Run analyze**

```bash
flutter analyze 2>&1 | tail -10
```

Expected: 0 errors. Warnings allowed if pre-existing.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart lib/config/ lib/theme/ lib/utils/
git diff --cached --stat
git commit -m "chore(cleanup): lib foundation — main, config, theme, utils" -m "Removed unused imports, debug prints, comments restating code, trailing whitespace."
```

If `git diff --cached --stat` shows >500 changed lines, STOP and split: commit `lib/utils/` separately first, then `lib/main.dart`, then `lib/config/`+`lib/theme/`.

---

## Task 3: Clean `lib/models/`

**Files:**
- Modify: all files in `lib/models/` (~10 files)
- LOC budget: ~1500

- [ ] **Step 1: List models**

```bash
ls lib/models/
```

- [ ] **Step 2: Per-file sweep (same checklist as Task 2)**

For each model file (`product.dart`, `article.dart`, `event.dart`, etc.):
1. Unused imports → remove.
2. Unused private getters/methods → verify with `rg "<name>" lib/` (must have zero non-definition hits before deleting).
3. `// constructor`, `// fromJson`, `// toJson` style comments that just label methods → remove (method name already says it).
4. Blank line clusters → collapse.
5. Trailing whitespace → strip.
6. `///` doc comments on public classes/fields → KEEP.

- [ ] **Step 3: Analyze**

```bash
flutter analyze 2>&1 | tail -10
```

Expected: 0 errors.

- [ ] **Step 4: Commit**

```bash
git add lib/models/
git diff --cached --stat
git commit -m "chore(cleanup): lib/models — remove dead imports, label comments"
```

If >500 LOC diff → split alphabetically (e.g. `lib/models/a-c.dart` vs `lib/models/d-z.dart`).

---

## Task 4: Clean `lib/services/`

**Files:**
- Modify: all in `lib/services/` (~10 files; top: `product_service.dart`=443, `article_service.dart`=351)
- LOC budget: ~2000

- [ ] **Step 1: List**

```bash
ls lib/services/
```

- [ ] **Step 2: Per-file sweep**

Same checklist. Extra care for services:
- Private helper functions are common here — verify each has callers via `rg "<name>" lib/`.
- HTTP-related helpers may have commented-out retry/timeout code from earlier iterations.
- Watch for `// ignore: unused_element` comments that explain WHY something is kept (e.g. for interface conformance). KEEP these.

- [ ] **Step 3: Analyze**

```bash
flutter analyze 2>&1 | tail -10
```

- [ ] **Step 4: Commit**

```bash
git add lib/services/
git diff --cached --stat
git commit -m "chore(cleanup): lib/services — dead helpers, debug logs, label comments"
```

If >500 LOC → split per-file into separate commits within this task.

---

## Task 5: Clean `lib/viewmodels/`

**Files:**
- Modify: all in `lib/viewmodels/` (~15 files; top: `admin_viewmodel.dart`=880, `articles_viewmodel.dart`=317, `home_viewmodel.dart`=279)
- LOC budget: ~2500

- [ ] **Step 1: Split by size before starting**

```bash
ls -la lib/viewmodels/ | sort -k5 -rn
```

`admin_viewmodel.dart` alone may exceed budget. Plan two commits:
1. `admin_viewmodel.dart` (one file, big).
2. Remaining viewmodels together.

- [ ] **Step 2: Sweep admin_viewmodel.dart**

Read full file. Apply checklist. Special attention:
- `admin_viewmodel.dart` is the largest file in the project — likely contains the most accumulated cruft.
- Look for unused private methods specific to old flows (e.g., legacy add/edit dialog logic replaced by newer pattern).

- [ ] **Step 3: Commit admin_viewmodel first (it's big)**

```bash
git add lib/viewmodels/admin_viewmodel.dart
git diff --cached --stat
git commit -m "chore(cleanup): lib/viewmodels/admin_viewmodel — sweep 880 LOC" -m "Removed dead private helpers from old flows, label comments, debug prints."
```

- [ ] **Step 4: Sweep remaining viewmodels**

Same checklist per file.

- [ ] **Step 5: Analyze + commit rest**

```bash
flutter analyze 2>&1 | tail -10
git add lib/viewmodels/  # all remaining changes
git diff --cached --stat
git commit -m "chore(cleanup): lib/viewmodels — remaining ViewModels"
```

---

## Task 6: Clean `lib/widgets/`

**Files:**
- Modify: all in `lib/widgets/` (~15 files; top: `image_carousel.dart`=538, `product_card.dart`=337, `home_skeleton.dart`=218, `site_info_footer.dart`=199, `category_selector.dart`=192)
- LOC budget: ~2500

- [ ] **Step 1: Per-file sweep**

Same checklist. Widget files often have:
- Commented-out animation/debug border code (`// debugPrint(...);` `// print('hit');`).
- Unused private build helper methods.
- Old `// ignore_for_file: ...` comments that are no longer needed.

- [ ] **Step 2: Analyze**

```bash
flutter analyze 2>&1 | tail -10
```

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/
git diff --cached --stat
git commit -m "chore(cleanup): lib/widgets — dead build helpers, debug borders"
```

If >500 LOC → split: `image_carousel.dart` alone, then rest.

---

## Task 7: Clean `lib/views/`

**Files:**
- Modify: ~15 files across `lib/views/` and `lib/views/admin/...`
- LOC budget: ~3000 (top: `product_detail_screen.dart`=696, `home_screen.dart`=356, plus many 200-500 LOC admin screens)

This is the largest module — likely 2-3 commits.

- [ ] **Step 1: List structure**

```bash
find lib/views -type f -name "*.dart" | xargs wc -l | sort -rn | head -20
```

- [ ] **Step 2: Commit 7a — top-level views**

```bash
git add lib/views/product_detail_screen.dart lib/views/home_screen.dart lib/views/article_screen.dart
```

Sweep each. Commit:
```bash
git commit -m "chore(cleanup): lib/views — top-level screens (product, home, article)"
```

- [ ] **Step 3: Commit 7b — admin screens (excluding sub-folders)**

```bash
git add lib/views/admin/admin_shell.dart lib/views/admin/admin_articles/ lib/views/admin/admin_events/ lib/views/admin/admin_categories/
```

Sweep. Commit:
```bash
git commit -m "chore(cleanup): lib/views/admin — shell, articles, events, categories"
```

- [ ] **Step 4: Commit 7c — admin_product (largest sub-folder)**

`admin_product/` likely has the most files and lines (edit_product_dialog.dart=386, options_editor_with_images.dart=503, etc.).

```bash
git add lib/views/admin/admin_product/
git commit -m "chore(cleanup): lib/views/admin/admin_product — sweep product admin screens"
```

If this commit still >500 LOC, split per-file.

- [ ] **Step 5: Commit 7d — admin_settings (if exists)**

```bash
git add lib/views/admin/admin_settings/
git commit -m "chore(cleanup): lib/views/admin/admin_settings"
```

- [ ] **Step 6: Final analyze for this module**

```bash
flutter analyze 2>&1 | tail -10
```

Expected: 0 errors across all 7a-7d.

---

## Task 8: Clean `lib/support/`

**Files:**
- Modify: files in `lib/support/` (~3 files)
- LOC budget: ~500

- [ ] **Step 1: List + sweep**

```bash
ls lib/support/
```

Apply standard checklist per file.

- [ ] **Step 2: Analyze + commit**

```bash
flutter analyze 2>&1 | tail -10
git add lib/support/
git commit -m "chore(cleanup): lib/support — final Dart module"
```

---

## Task 9: Clean `backend/cmd/` and `backend/main.go`

**Files:**
- Modify: `backend/main.go` (~30 lines), `backend/cmd/admincurl/main.go` (295), `backend/cmd/keygen/main.go` (82)
- LOC budget: ~500

- [ ] **Step 1: Sweep each file**

Checklist:
- Unused imports.
- `fmt.Println` debug output in CLI tools — KEEP if it's the tool's actual output (admincurl prints responses, that's its job). Remove if it's leftover debug.
- Commented-out flags/options from earlier versions.

- [ ] **Step 2: go vet + commit**

```bash
go vet ./...
git add backend/main.go backend/cmd/
git commit -m "chore(cleanup): backend entrypoints — main, admincurl, keygen"
```

---

## Task 10: Clean `backend/internal/handler/`

**Files:**
- Modify: ~10 files (top: `handler.go`=981, `admin_auth.go`=396, `article_handler.go`=393, `event_handler.go`=253)
- LOC budget: ~3000
- Test files (`*_test.go`) included in sweep but logic untouched.

- [ ] **Step 1: List non-test files first**

```bash
ls backend/internal/handler/*.go | grep -v _test
```

- [ ] **Step 2: Sweep non-test files**

Standard Go checklist:
- Unused imports (`go vet` will flag these).
- Unused helper functions (`rg "<name>" backend/` to verify).
- Commented-out middleware/auth branches.
- Debug `log.Println` calls (keep error logging via `log.Printf` in catch blocks).

- [ ] **Step 3: Commit non-test files**

```bash
go vet ./...
git add backend/internal/handler/  # only non-_test.go
git commit -m "chore(cleanup): backend/handler — production code"
```

- [ ] **Step 4: Sweep test files (lighter touch)**

Test files: only remove obvious junk (commented-out assertions, debug prints). DO NOT remove tests even if they look stale.

```bash
git add backend/internal/handler/*_test.go
git commit -m "chore(cleanup): backend/handler — tests (label comments only)"
```

---

## Task 11: Clean `backend/internal/db/`

**Files:**
- Modify: ~10 files (top: `product_repo.go`=791, `article_repo.go`=392, `dialect.go`=335, `event_repo.go`=274, `schema.go`=217)
- LOC budget: ~2500

- [ ] **Step 1: Sweep non-test files**

Same Go checklist. Repos often have:
- Commented-out prepared-statement variants.
- Unused helper queries.

- [ ] **Step 2: Commit**

```bash
go vet ./...
git add backend/internal/db/
git commit -m "chore(cleanup): backend/db — repos, dialect, schema"
```

If >500 LOC, split: `db.go`+`schema.go` first, then each repo separately.

---

## Task 12: Clean remaining `backend/internal/` (services, middleware, config, router, server, uploadfs)

**Files:**
- Modify: ~15 files across `services/`, `middleware/`, `config/`, `router/`, `server/`, `uploadfs/`
- LOC budget: ~1500

- [ ] **Step 1: Sweep each sub-package**

Per-package:
- `config/`: pure config struct, usually small. Likely clean already.
- `middleware/`: `cors.go`, `ratelimit.go`. Check for unused headers/options.
- `router/`: `router.go`. Routes are core — only remove obvious label comments.
- `server/`: `server.go`. Setup/teardown code.
- `uploadfs/`: file upload helper. May have commented-out size-limit variations.
- `services/`: if exists, business logic. Touch lightly.

- [ ] **Step 2: One commit per sub-package**

```bash
go vet ./...
git add backend/internal/config/
git commit -m "chore(cleanup): backend/internal/config"

git add backend/internal/middleware/
git commit -m "chore(cleanup): backend/internal/middleware"

git add backend/internal/router/ backend/internal/server/
git commit -m "chore(cleanup): backend/internal — router + server"

git add backend/internal/uploadfs/
git commit -m "chore(cleanup): backend/internal/uploadfs"

git add backend/internal/services/ 2>/dev/null || echo "no services dir"
git commit -m "chore(cleanup): backend/internal/services" || true
```

(Adjust if some dirs don't exist.)

---

## Task 13: Clean `backend/models/`

**Files:**
- Modify: any `*.go` in `backend/models/` (e.g. `event_test.go`=91 — likely a small package)

- [ ] **Step 1: List + sweep**

```bash
ls backend/models/
```

- [ ] **Step 2: vet + commit**

```bash
go vet ./...
git add backend/models/
git commit -m "chore(cleanup): backend/models"
```

---

## Task 14: Clean `test/` (Dart)

**Files:**
- Modify: ~38 files in `test/`
- LOC budget: ~500 (very light touch)

- [ ] **Step 1: Run analyze to establish baseline**

```bash
flutter analyze 2>&1 | tail -10
```

- [ ] **Step 2: Per-file sweep — ONLY label comments**

For test files, only remove:
- `// test X` comments immediately above the test whose name already says it.
- Multi-line `//` blocks that are obviously just narration of what the test does below.
- Blank line clusters.
- Trailing whitespace.

DO NOT remove:
- `// arrange`, `// act`, `// assert` style comments (those help readability in tests).
- Any commented-out test code (might be intentional for known-flaky scenarios — surface to user instead of deleting).
- Setup/teardown code that looks unused (might be referenced via reflection in mock libraries).

- [ ] **Step 3: Commit**

```bash
flutter analyze 2>&1 | tail -10
git add test/
git diff --cached --stat
git commit -m "chore(cleanup): test/ — label comments and whitespace only"
```

If a test file is broken by analyze (rare — only if an unused import existed), revert that file:
```bash
git checkout -- test/<broken_file>
```

---

## Task 15: Final sweep — analyze + vet + format

**Files:** none modified unless issues found

- [ ] **Step 1: Full analyze**

```bash
flutter analyze 2>&1 | tee /tmp/cleanup-final-analyze.txt
```

Expected: 0 errors. Compare error count vs `/tmp/cleanup-baseline-analyze.txt`.

- [ ] **Step 2: Full vet**

```bash
go vet ./... 2>&1 | tee /tmp/cleanup-final-vet.txt
```

Expected: 0 issues.

- [ ] **Step 3: Final format pass**

```bash
dart format lib/ test/
gofmt -l backend/
```

Expected: `gofmt -l` returns empty (everything formatted). `dart format` may modify files; review the diff.

- [ ] **Step 4: Commit any formatting fixes**

```bash
git add lib/ test/ backend/
git diff --cached --stat
git commit -m "chore(cleanup): final format pass" -m "dart format lib test; gofmt -w backend (already clean). No semantic changes."
```

Only commit if there are changes. If nothing changed, skip.

- [ ] **Step 5: Summary report to user**

Print to terminal:
- Total commits added (count from `git log --oneline <first-baseline-commit>..HEAD`).
- Final LOC change (`git diff --shortstat <first-baseline-commit>..HEAD`).
- Any files that were skipped (e.g. test files reverted in Task 14).
- Confirmation that `flutter analyze` = 0 errors, `go vet ./...` = 0 issues.

---

## Definition of Done (final)

- [ ] All 15 tasks committed.
- [ ] `flutter analyze` → 0 errors (warnings allowed if pre-existing).
- [ ] `go vet ./...` → 0 issues.
- [ ] No file >500 LOC diff in any single commit (split where needed).
- [ ] No public API changed (spot-check by `git diff <baseline>..HEAD --stat` on signature lines).
- [ ] No test logic changed (verify with `git diff test/ | grep -E "^\+.*expect"` — should be empty).
- [ ] User briefed on results.

---

## Self-Review Notes

- Spec coverage: every spec section ("auto-fix", "module commits", "DOD", "risks") maps to a task.
- Placeholders: none — every step has concrete commands or checklist items.
- Type/symbol consistency: not applicable (no signature changes).
- Risk mitigation: Task 1 captures baseline so any regression is detectable; Task 14 explicitly reverts broken test files instead of guessing.
