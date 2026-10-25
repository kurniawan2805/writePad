# Task backlog

Phase 2 work (see `PLAN.md` §4) split into tasks any agent can pick up. Read `AGENTS.md` first.

**How to use this file**
- Claim a task by setting **Status** to `in progress (<agent>, <date>)` in the same commit as your first change, so two agents don't take it.
- Mark it `done (<commit>)` when its acceptance checks pass, and tick the matching line in `PLAN.md` if there is one.
- **Difficulty** guides who should take it:
  - **S**: one or two files, an existing pattern to copy. Good for Codex or a cheaper model.
  - **M**: several files, but the design is decided below. Codex is fine if it follows the notes.
  - **L**: design work, concurrency, PencilKit/PDFKit internals, or the file format. Leave these to the strongest model, or have it write the design first.
- Every task must keep the full test suite green (`AGENTS.md` → Commands) and add tests for its logic. UI-only changes need at least one UI test step or a screenshot check.
- Anything that changes the `.writepad` format must bump `NotebookManifest.currentVersion` and keep older files loading. Those tasks are **L** by default.

## Tasks

| ID | Task | Diff. | Suggested owner | Status |
|---|---|---|---|---|
| T1 | Shape snap: draw and hold to straighten lines, ellipses, rectangles, triangles | L | Claude | done (see T1 notes) |
| T2 | Page templates: Cornell, music staff, planner week | S | Codex / cheaper | done (b63e753) |
| T3 | Bookmarks: star pages, Bookmarks filter in the page sidebar | S | Codex / cheaper | done (7530063) |
| T4 | CI: GitHub Actions build + unit tests on every push | S | Codex / cheaper | done (bac103b, 73550ee) |
| T5 | `docs/DEVICE-CHECKS.md`: one checklist of every real-iPad check | S | Codex / cheaper | done (f56953c) |
| T6 | Accessibility audit in UI tests (light, dark, large text) | S | Codex / cheaper | done (a407927) |
| T7 | Recently Deleted: 30-day soft delete for notebooks | M | Codex | done (Codex, 2026-10-25; 115 unit + 10 UI tests passed) |
| T8 | Thumbnail cache on disk (`thumb.png` for the first page), library cards read it | M | Codex | done (Codex, 2026-10-25; 121 unit + 10 UI tests passed across runs) |
| T9 | Page items: text boxes and images on pages (format v5) | L | Codex after design | done (6733ddb; 138 unit + 12 UI tests passed) |
| T10 | Vector ink in PDF export (no rasterized strokes) | L | Codex after design | done (46fb94d; 145 unit + 12 UI tests passed across runs) |
| T11 | Custom pen tray (favorite pens) replacing `PKToolPicker` | L | Codex after design | done (aeb1707; 161 unit + 14 UI tests passed across runs) |
| T12 | Multiple windows / two notebooks side by side | M | Codex after design | done (31ff21e; 161 unit + 14 UI tests passed across runs) |
| T13 | Fix imported PDF library preview retaining its source document during rendering | S | Codex | done (78d4145; 121 unit tests passed) |

Verification: [T2–T6 simulator QA](T2-T6_QA.md).

## Task notes

### T1 Shape snap (L) — done
Hold the pen still for 0.45 s before lifting and the stroke becomes a clean line, circle/ellipse, rectangle or
triangle with the same ink. `ShapeRecognizer` (pure geometry, `ShapeRecognizerTests`), `ShapeSnapper` +
`StrokeHoldRecognizer` (canvas hook, `ShapeSnapperTests`), wired into the notebook canvas and every PDF page overlay.
Undo after a snap restores the hand-drawn stroke; undo again removes it. Toolbar toggle "Shape Snap" (on by default).
Verified with real touch gestures in the simulator: a held 2° line came out level, a quick one did not.
- Not done, possible follow-ups (S/M): arrows; snapping live while the pen is still down (today it snaps on lift);
  a UI test for snapping on a PDF page; tuning thresholds with real Apple Pencil handwriting (device check).

### T2 Page templates (S)
Add cases to `PageBackground` (`cornell`, `music`, `plannerWeek`) and draw them in
`PageBackgroundRenderer.patternPath`. Adding enum cases is **not** a format change for new files, but older builds
can't decode them: bump `NotebookManifest.currentVersion` to 4 and add a test that a v3 file still loads.
- Cornell: cue column line at x = 25% of width, summary line at y = 80% of height, ruled lines at 32 pt in the note area.
- Music: 10 staves of 5 lines, 8 pt apart, staves 72 pt apart, 48 pt margins.
- Planner week: 7 equal rows with a 1 pt divider and a 40 pt header band for the day name (no text, lines only).
- Accept: each template renders in the canvas, thumbnails and PDF export (`NotebookExporterTests` pattern), and appears in the paper menus.

### T3 Bookmarks (S)
Add `isBookmarked: Bool` to `PageInfo` (decode with default `false` so older files still load; no version bump
needed). Star toggle in the page context menu and in the editor toolbar for the current page. A segmented filter
"All / Bookmarked" at the top of `PageSidebarView`. Persist through `structureDidChange()`.
- Accept: bookmark survives reopen; filter hides other pages; jump-to-page still uses the real page index.

### T4 CI (S)
`.github/workflows/ci.yml`: `macos-latest` (or the newest image with Xcode 27), `brew install xcodegen swiftlint`,
`xcodegen generate`, `swiftlint lint --strict`, then the unit-test command from `AGENTS.md` with
`-only-testing:writePadTests`. UI tests are too slow for every push; run them in a separate `workflow_dispatch` job.
Set `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` only if the build is warning-free.

### T5 Device checklist (S)
Merge the real-device items from `PLAN.md`, `docs/MILESTONE4_QA.md`, `docs/MILESTONE5_QA.md` and Milestone 6 into
`docs/DEVICE-CHECKS.md`: one table with check, steps, expected result, and columns for iPad model, iPadOS, date,
result. Link it from `PLAN.md` and remove the duplicate lists (keep a one-line pointer).

### T6 Accessibility audit (S)
In `writePadUITests`, a test that opens the library, a notebook and a PDF and calls
`try app.performAccessibilityAudit()` in light mode, dark mode and the largest Dynamic Type size. Fix what it finds or
list justified exclusions in the test with a comment.

### T7 Recently Deleted (M)
Deleting a notebook moves its package to `<root>/.Trash/<id>.writepad` and records the date (a `deletedAt` field in
the library index, not in the package). A "Recently Deleted" row in the library sidebar lists them with Restore and
Delete Now. Purge items older than 30 days on launch. `NotebookStore.listNotebooks()` must not see `.Trash`.
- Accept: delete → restore round trip keeps ink and annotations; purge test with an injected date.

Implementation and full-suite simulator verification: [T7 QA](T7_QA.md). All 115 unit tests and 10 UI tests passed.

### T8 Thumbnail cache (M)
After each successful save, write `thumb.png` (first page) into the package off the main actor (reuse
`PageThumbnailJob`). `LibraryViewModel.loadThumbnail` reads it when its mtime is newer than `manifest.json`,
otherwise renders and writes it. Not part of the format: a missing or stale file is always regenerated.

Implementation and simulator verification: [T8 QA](T8_QA.md).

### T9 Page items (L)
Design: [T9 design](T9_DESIGN.md); implementation may follow this settled design.
Text boxes and images on paper and PDF pages, with move/resize, text editing, undo/redo, thumbnails and PDF/PNG export.
Format v5 stores immutable item revisions per page and image assets in the package; v1–v4 still load.
Implementation and full-suite simulator verification: [T9 QA](T9_QA.md).

### T10 Vector ink in PDF export (L)
Draw `PKStroke` paths as vector shapes in `NotebookExporter` for pen, monoline and marker inks; keep raster for
textured inks (pencil, crayon, watercolor). Needs pixel-diff tests against `PKDrawing.image`.
Design: [T10 design](T10_DESIGN.md). Implementation, pixel metrics and simulator verification: [T10 QA](T10_QA.md).

### T11 Custom pen tray (L)
Design: [T11 / T12 design](T11_T12_DESIGN.md).
Own toolbar with up to 8 pen presets (ink, width, color), eraser and lasso, persisted per user. Must handle Apple
Pencil double-tap / squeeze (`UIPencilInteraction`) previously handled by `PKToolPicker`.
Implementation and simulator verification: [T11 QA](T11_QA.md). Physical Pencil checks remain in [DEVICE-CHECKS.md](DEVICE-CHECKS.md).

### T12 Multiple windows (M)
Design: [T11 / T12 design](T11_T12_DESIGN.md).
`UIApplicationSupportsMultipleScenes`, one `LibraryViewModel` per scene sharing one store, and a guard so the same
notebook can't be open for writing in two windows at once (second opens read-only). Design the guard before coding.
Implementation and simulator verification: [T12 QA](T12_QA.md). Physical side-by-side and Pencil focus checks remain in [DEVICE-CHECKS.md](DEVICE-CHECKS.md).

### T13 PDF preview document lifetime (S) — done
The shared `PageThumbnailJob.render` retains its private `PDFDocument` with `withExtendedLifetime` while
rendering the PDF page. This fix and the library PDF preview regression check shipped with T8 in `78d4145`.
All 121 unit tests passed, including PDF preview shape/content and cached PDF markup rendering checks;
see [T8 QA](T8_QA.md) for the result bundle.
