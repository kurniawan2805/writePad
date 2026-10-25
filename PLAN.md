# writePad — Development Plan

An iPad app for handwritten notes and PDF reading/annotation (in the spirit of GoodNotes / Notability / FreeNotes).

**Your machine (checked):** Apple M4, 16 GB RAM, macOS 26.5 — Homebrew and Command Line Tools are installed, but **full Xcode is not**. Installing Xcode is step 1.

---

## 0. Tech stack decision

| Concern | Choice | Why |
|---|---|---|
| Language / UI | **Swift + SwiftUI** (UIKit where needed) | Native, best Apple Pencil latency, no cross-platform overhead |
| Handwriting | **PencilKit** (`PKCanvasView`, `PKDrawing`, `PKToolPicker`) | Free low-latency inking, pressure/tilt, eraser, lasso, ruler, palm rejection |
| PDF | **PDFKit** (`PDFView`, `PDFDocument`, `PDFAnnotation`, `PDFPageOverlayViewProvider`) | Rendering, search, text selection, highlights, notes, outline |
| Library metadata | **SwiftData** | Folders, titles, tags, dates, thumbnails index |
| Note content | **Files on disk** (one package folder per notebook) | Large data stays out of the DB; easy export, backup, iCloud later |
| Min target | **iPadOS 18** | `PDFPageOverlayViewProvider` (16+), SwiftData (17+), modern SwiftUI |
| Sync (later) | iCloud Drive / CloudKit | No server to run |

Avoid Flutter / React Native for this app: ink latency and PDF annotation quality are the whole product, and native PencilKit + PDFKit gives them almost for free.

---

## 1. Install dev tools (Day 1)

Run in Terminal:

```bash
# 1. Xcode (required — ~15 GB). Either install from the Mac App Store, or:
brew install xcodes aria2
xcodes install --latest --experimental-unxip   # asks for your Apple ID
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch

# 2. iPad simulator runtime (Xcode > Settings > Components also works)
xcodebuild -downloadPlatform iOS

# 3. Helpful tools
brew install swiftlint swiftformat xcodegen git gh
brew install --cask sf-symbols          # Apple icon browser
brew install --cask figma               # optional: UI mockups

# 4. Git identity
git config --global user.name  "Your Name"
git config --global user.email "you@example.com"
```

Accounts & devices:
- **Apple ID** signed in to Xcode (Settings > Accounts) — free account can run on your own iPad (apps expire after 7 days).
- **Apple Developer Program** ($99/yr) — only needed for TestFlight / App Store. Delay until Phase 3.
- **A real iPad + Apple Pencil** — the simulator cannot test pressure, palm rejection, or latency. Enable *Developer Mode* on the iPad (Settings > Privacy & Security) after first connecting it to Xcode.

Verify:
```bash
xcodebuild -version
xcrun simctl list devices | grep iPad
```

---

## 2. Project setup (Day 2)

1. Xcode > New Project > iOS App, name `writePad`, interface SwiftUI, storage **SwiftData**, add Unit + UI tests.
2. Target settings: devices **iPad only**, min iPadOS 18, support all orientations, enable "Supports multiple windows" later.
3. `git init`, add a Swift `.gitignore`, first commit, push to a private GitHub repo (`gh repo create`).
4. Add `swiftlint` as a build phase.

Suggested folder layout:
```
writePad/
  App/              writePadApp.swift, AppState
  Models/           Notebook, Folder, Page, PageBackground (SwiftData + Codable)
  Storage/          NotebookStore (read/write packages), ThumbnailService
  Features/
    Library/        grid of notebooks, folders, create/import
    Editor/         NotebookEditorView, CanvasView (PencilKit wrapper), toolbar
    PDF/            PDFEditorView, overlay provider, annotations, comments
  Shared/           extensions, UI components
```

### Notebook file format (`MyNote.writepad/` package folder)
```
manifest.json       { id, title, version, pages: [{id, background, pdfPageIndex?}] }
source.pdf          (only for imported PDFs)
pages/<pageId>.drawing   PKDrawing.dataRepresentation()
pages/<pageId>.json      text boxes / images / comments (later)
thumb.png
```
Store a `version` field from day one so you can migrate the format later.

---

## 3. MVP (≈ 6–8 weeks, part-time)

Goal: *"I can create a notebook, write on it with Pencil, import a PDF, mark it up and add comments, and find it again tomorrow."*

### Milestone 1 — Ink canvas (week 1–2)
- [x] `UIViewRepresentable` wrapper around `PKCanvasView`
- [x] `PKToolPicker` (pen, pencil, marker, eraser, lasso, ruler)
- [x] `drawingPolicy = .pencilOnly` + toggle "draw with finger"
- [x] Undo / redo
- [x] Save `PKDrawing` on change (debounced ~1 s) and on app background
- ✅ Done when: write a page, kill the app, reopen — ink is there.

### Milestone 2 — Notebooks & pages (week 2–3)
- [x] Notebook = list of pages; vertical scroll of pages (A4 / Letter size)
- [x] Page backgrounds: blank, lined, grid, dotted (drawn as a background layer, not in the drawing)
- [x] Add / delete / reorder pages, page thumbnails sidebar
- [x] Zoom & pan

### Milestone 3 — Library (week 3–4)
- [x] Grid of notebooks with thumbnails, folders, rename, delete, search by title
- [x] Create notebook (choose paper), create folder
- [x] Sort by date / name

### Milestone 4 — PDF read & annotate (week 4–6)
- [x] Import PDF via `.fileImporter` / Files app / Share sheet ("Open in writePad")
- [x] Display with `PDFView` (continuous scroll, thumbnails, outline/TOC, text search)
- [x] **Handwriting on PDF**: `PDFPageOverlayViewProvider` gives a `PKCanvasView` per page; store one `PKDrawing` per page
- [x] Text highlight / underline / strikethrough via selection → `PDFAnnotation`
- [x] **Comments**: sticky note (`PDFAnnotation` subtype `.text`) + a comments side panel listing all notes with jump-to-page
- [x] Insert blank page between PDF pages

Usage, storage format, simulator results, and remaining Pencil checks: [Milestone 4 QA](docs/MILESTONE4_QA.md).

### Milestone 5 — Export & polish (week 6–8)
- [x] Export notebook / annotated PDF as flattened PDF (render page + drawing into `UIGraphicsPDFRenderer`) and share sheet
- [x] Export single page as PNG
- [x] Light/dark mode, app icon, empty states, crash-free autosave
- [ ] Test on real iPad: 100+ page PDF, long notebook, low memory

Simulator verification and the remaining device checklist: [Milestone 5 QA](docs/MILESTONE5_QA.md).

### Milestone 6 — Storage hardening
Goal: *"a crash, a full disk, or a damaged file never costs ink, and a failed save recovers on its own."*
Rationale and the OwlLuna code these ideas come from: [OwlLuna audit](docs/OWLLUNA_AUDIT.md). Re-implement from the ideas; if any code is copied, keep OwlLuna's MIT notice.
- [x] Quarantine undecodable manifest / drawing files as `*.corrupt` instead of failing or overwriting them
- [x] Keep `manifest.prev.json` and fall back to it when `manifest.json` can't be decoded
- [x] Reject a `PKDrawing` that decodes as empty but lacks PencilKit's header (it returns an empty drawing instead of throwing)
- [x] Cap save latency: debounce stays 1 s, but a pending save starts at most ~5 s after the first unsaved edit (today every edit restarts the timer)
- [x] Retry failed saves with backoff (1 s doubling, capped at 60 s) and show a non-blocking notice; keep pages dirty until written
- [x] Recover pages whose drawing file is newer than the manifest but missing from it (crash between the two writes)
- [ ] Move save IO and thumbnail refresh off the main actor (`saveNow` currently writes synchronously on `@MainActor`)
- [ ] Preserve unknown manifest fields on load/save so newer files survive an older build; open newer-than-supported manifests read-only (bump `NotebookManifest.currentVersion` if the format changes)
- [x] Tests in `writePadTests/`: corrupt manifest, corrupt drawing, `prev` fallback, orphan recovery, retry after a failed write, latency cap (`NotebookStoreRecoveryTests`, `AutosaveSafetyTests`)
- [ ] Test on real iPad: kill the app mid-stroke and mid-save, fill storage, confirm nothing is lost (Pencil/device only)
- ✅ Done when: with a corrupted manifest or a forced write failure, the notebook still opens with all ink and the app reports what happened.

Order of work: corrupt-file handling and `prev` fallback first, then latency cap and retry, then orphan recovery; the main-thread and unknown-field items last because they change more code.

### Out of scope for MVP
Sync, handwriting search/OCR, shapes, audio, templates marketplace, collaboration, Mac app.

---

## 4. Post-MVP roadmap

### Phase 2 — Make it pleasant (1–2 months)
- Text boxes, image/photo insertion, sticker/clip from camera
- Shape recognition (hold to snap line/circle/rect) — custom on top of `PKStroke`
- Custom toolbar (favorite pens, colors, sizes) instead of only `PKToolPicker`
- Lasso: move, resize, recolor, copy between pages
- Page templates (Cornell, planner, music), custom page sizes, infinite canvas option
- Tabs / split view (two notebooks side by side), multiple windows
- Bookmarks & page links, outline for notebooks
- Performance: lazy-load drawings for visible pages only, cached thumbnails

### Phase 3 — Beta & App Store (1 month)
- Join Apple Developer Program, TestFlight with 10–20 students/friends
- Crash reporting (Xcode Organizer / MetricKit), basic analytics (privacy-friendly)
- Onboarding, App Store screenshots, privacy policy, App Store review

### Phase 4 — Smart features
- Handwriting search: Vision `VNRecognizeTextRequest` on rendered pages → index in SwiftData
- Convert handwriting to text
- PDF text OCR for scanned docs; document scanner (`VNDocumentCameraViewController`)
- Audio recording synced to ink (Notability-style playback)
- AI: summarize notes, generate flashcards / quiz from PDF + notes (optional, on-device via Apple Foundation Models or cloud API)

### Phase 5 — Sync & platforms
- iCloud Drive sync of `.writepad` packages (`NSFileCoordinator`, conflict handling)
- Mac app via Mac Catalyst / native macOS target, iPhone read-mostly layout
- Share notebook as PDF or `.writepad` file; later real-time collaboration (CloudKit sharing)

### Phase 6 — Monetization (if desired)
- Free tier (N notebooks) + one-time unlock or subscription via **StoreKit 2**

---

## 5. Key technical risks (tackle early)

1. **Ink on PDF at scale** — test overlay canvases with a 300-page PDF in week 4; only keep canvases for visible pages.
2. **Data safety** — atomic writes (`Data.write(options: .atomic)`), autosave on `scenePhase == .background`, never lose ink.
3. **Coordinate systems** — PDF points vs view points vs zoom; keep drawings in page coordinates so export matches screen.
4. **Format versioning** — `manifest.version` from v1 to allow migrations.

---

## 6. Learning resources
- Apple: *PencilKit* docs + WWDC19 "Introducing PencilKit", WWDC20 "What's new in PencilKit"
- Apple: *PDFKit* docs + WWDC22 "What's new in PDFKit" (overlay views for drawing on PDFs)
- Apple sample code: "Drawing with PencilKit", "Adopting drag and drop"
- *Hacking with Swift* — 100 Days of SwiftUI (if you're new to Swift)
- SwiftData: WWDC23 "Meet SwiftData"

---

## 7. Immediate next steps
1. Install Xcode (section 1) — today.
2. Create the Xcode project (section 2) and commit.
3. Build Milestone 1: a single PencilKit canvas that saves and reloads.
