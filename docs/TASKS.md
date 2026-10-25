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

## Open tasks

| ID | Task | Diff. | Suggested owner | Status |
|---|---|---|---|---|
| T1 | Shape snap: draw and hold to straighten lines, ellipses, rectangles, triangles | L | Claude | done (see T1 notes) |
| T2 | Page templates: Cornell, music staff, planner week | S | Codex / cheaper | in progress (Codex, 2026-10-25) |
| T3 | Bookmarks: star pages, Bookmarks filter in the page sidebar | S | Codex / cheaper | in progress (Codex, 2026-10-25) |
| T4 | CI: GitHub Actions build + unit tests on every push | S | Codex / cheaper | in progress (Codex, 2026-10-25) |
| T5 | `docs/DEVICE-CHECKS.md`: one checklist of every real-iPad check | S | Codex / cheaper | in progress (Codex, 2026-10-25) |
| T6 | Accessibility audit in UI tests (light, dark, large text) | S | Codex / cheaper | in progress (Codex, 2026-10-25) |
| T7 | Recently Deleted: 30-day soft delete for notebooks | M | Codex | open |
| T8 | Thumbnail cache on disk (`thumb.png` per page), library cards read it | M | Codex | open |
| T9 | Page items: text boxes and images on pages (format v4) | L | Claude | open |
| T10 | Vector ink in PDF export (no rasterized strokes) | L | Claude | open |
| T11 | Custom pen tray (favorite pens) replacing `PKToolPicker` | L | Claude | open |
| T12 | Multiple windows / two notebooks side by side | M | Claude or Codex after design | open |

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

### T8 Thumbnail cache (M)
After each successful save, write `thumb.png` (first page) into the package off the main actor (reuse
`PageThumbnailJob`). `LibraryViewModel.loadThumbnail` reads it when its mtime is newer than `manifest.json`,
otherwise renders and writes it. Not part of the format: a missing or stale file is always regenerated.

### T9 Page items (L)
Text boxes and images positioned on pages, stored per page in the package. Needs a design note first (model, file
layout, hit testing vs. PencilKit gestures, export, undo). Format v4.

### T10 Vector ink in PDF export (L)
Draw `PKStroke` paths as vector shapes in `NotebookExporter` for pen, monoline and marker inks; keep raster for
textured inks (pencil, crayon, watercolor). Needs pixel-diff tests against `PKDrawing.image`.

### T11 Custom pen tray (L)
Own toolbar with up to 8 pen presets (ink, width, color), eraser and lasso, persisted per user. Must handle Apple
Pencil double-tap / squeeze (`UIPencilInteraction`) that `PKToolPicker` handles today.

### T12 Multiple windows (M)
`UIApplicationSupportsMultipleScenes`, one `LibraryViewModel` per scene sharing one store, and a guard so the same
notebook can't be open for writing in two windows at once (second opens read-only). Design the guard before coding.
