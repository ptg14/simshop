# Dead Code & Trash Comments Cleanup — Design

**Date:** 2026-07-22
**Scope:** Toàn bộ `lib/` (Dart), `backend/` (Go), `test/` (Dart)
**Approach:** A — Tool-assisted sweep + manual review, gộp commit theo module

---

## Goal

Dọn dẹp toàn bộ project để loại bỏ:
- **Dead code**: import/private function/private class không được dùng, biến không đọc, tham số bỏ qua, nhánh `if (false)` / code đã comment-out lâu ngày.
- **Trash comments**: comment giải thích hiển nhiên (`// constructor`, `// set state`), comment lặp lại code ngay bên dưới, comment thừa nhưng không có giá trị (chỉ chừa lại `///` doc comment trên public API).
- **Debug leftovers**: `print()` trong code release, `// TODO` / `// FIXME` cũ nếu đã stale.
- **Formatting nhiễu**: blank line thừa, trailing whitespace, inconsistent indentation.

**Không động vào:**
- Logic nghiệp vụ.
- Public API (export của file, signature của class/function public).
- Architecture / dependency wiring.
- Test case (chỉ sửa nếu cleanup phá test → giữ nguyên test).

---

## Approach

1. **Auto-fix trước** — chạy `dart fix --apply`, `gofmt -w`, `goimports -w` để tool sửa những gì nó biết chắc (unused imports, format).
2. **Manual sweep từng file** trong scope — đọc file, xoá dead code/comment rác. Công cụ hỗ trợ: `flutter analyze` (bắt unused), `rg "^\s*//.*" -n` (liệt kê comments), IDE "Find usages".
3. **Verify mỗi commit** — `flutter analyze` và `go vet ./...` phải 0 error. KHÔNG chạy test (theo yêu cầu user).
4. **Commit gộp theo module** — không 1 file = 1 commit. Nếu 1 module quá lớn (>20 file hoặc diff >500 LOC) → chia nhỏ thêm.

---

## Commit Plan (thứ tự, mỗi mục = 1 commit)

### Flutter (lib/)

| # | Scope | Files dự kiến | Ghi chú |
|---|---|---|---|
| 1 | `lib/main.dart`, `lib/config/`, `lib/theme/`, `lib/utils/` | ~10 files | Foundation, ít phụ thuộc → sửa trước |
| 2 | `lib/models/` | ~10 files | Plain Dart classes, dễ quét dead |
| 3 | `lib/services/` | ~10 files | Service layer, có thể có helper private thừa |
| 4 | `lib/viewmodels/` | ~15 files | Provider ViewModels |
| 5 | `lib/widgets/` | ~15 files | Reusable widgets |
| 6 | `lib/views/` (chia sub-commit nếu >20 files) | ~15 files | Screens |
| 7 | `lib/support/` | ~3 files | Helpers |

### Backend (backend/)

| # | Scope | Files dự kiến |
|---|---|---|
| 8 | `backend/cmd/`, `backend/main.go` | ~3 files |
| 9 | `backend/internal/handler/` | ~10 files |
| 10 | `backend/internal/services/`, `backend/internal/models/` | ~15 files |
| 11 | `backend/internal/utils/` | ~5 files |

### Tests (test/)

| # | Scope | Ghi chú |
|---|---|---|
| 12 | `test/` | Chỉ sửa nếu cleanup trước đó vô tình phá import. Không sửa logic test. |

### Final

| # | Scope | Ghi chú |
|---|---|---|
| 13 | Final analyze sweep | `dart fix --apply` cuối + `flutter analyze` + `gofmt -w` + `go vet ./...` |

---

## Quy tắc xoá (Definition of Done cho mỗi file)

**XOÁ:**
- Import không dùng.
- Private function/class không được reference trong file (verified bằng grep toàn `lib/` và `backend/`).
- Biến local không đọc sau khi gán.
- Comment `//` chỉ lặp lại code ngay dưới (vd: `i++; // increment i`).
- Comment block (>3 dòng) đã comment-out code.
- `print()`, `debugPrint()`, `fmt.Println()` không có mục đích (trong release path).
- Blank line thừa (>2 liên tiếp), trailing whitespace.

**GIỮ:**
- `///` doc comment trên public class/function (per `package_api_docs` lint).
- `//` comment giải thích "tại sao" (không phải "cái gì").
- `// TODO: <ticket>` nếu vẫn còn active trong issue tracker (mặc định: GIỮ nếu không chắc).
- Section header comments (`// === Section ===`) nếu giúp đọc file dài.

**KHÔNG ĐỤNG:**
- Tên biến, tên hàm public, signature.
- Thứ tự method trong class (trừ khi cần để sắp xếp constructor lên đầu — theo lint `sort_constructors_first`).
- Logic.

---

## Definition of Done (toàn task)

- [ ] Mọi commit đã push hoặc sẵn sàng push, không có commit rỗng.
- [ ] `flutter analyze` trả về **0 error** (warning được phép nếu pre-existing, không tự thêm).
- [ ] `go vet ./...` trả về **0 issue**.
- [ ] `dart fix --apply` đã chạy cuối cùng, không còn gì để fix.
- [ ] `gofmt -l backend/` trả về rỗng (mọi file đã formatted).
- [ ] Diff tổng hợp có thể review được (không >~500 LOC mỗi commit).
- [ ] Không có file bị xoá nguyên (trừ khi file rỗng hoặc chỉ chứa dead code 100%).

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Xoá nhầm function private mà test refer (gián tiếp qua reflection?) | Trước khi xoá private function: grep kỹ trong toàn bộ `lib/` + `backend/` + `test/` |
| Diff quá lớn trong 1 commit | Rule: >500 LOC → chia nhỏ theo sub-folder |
| `dart fix` thay đổi signature | Review `dart fix --apply` output thủ công, không `--apply` mù quáng |
| Mất commit message context | Mỗi commit có body giải thích "xoá gì, tại sao" |

---

## Out of Scope

- Refactor logic / đổi architecture.
- Đổi lint rules trong `analysis_options.yaml`.
- Update dependencies (`pubspec.yaml`, `go.mod`).
- Thêm test mới.
- Sửa bug phát hiện trong lúc đọc (ghi nhận vào TODO list riêng, xử lý sau).
