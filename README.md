<div align="center">
  <img src="writePad/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" alt="writePad app icon" width="112" />

  <h1>writePad</h1>

  <p><strong>A notebook for your handwriting. A workspace for your PDFs.</strong></p>
  <p>A native iPad app built with SwiftUI, PencilKit, and PDFKit.</p>

  <p>
    <img src="https://img.shields.io/badge/platform-iPadOS%2018%2B-007AFF" alt="iPadOS 18 or later" />
    <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6" />
    <img src="https://img.shields.io/badge/status-in%20development-orange" alt="In development" />
  </p>

  <p><a href="#features">Features</a> · <a href="#getting-started">Getting started</a> · <a href="PLAN.md">Roadmap</a></p>
</div>

---

writePad brings handwritten notebooks and PDF annotation into one local library. Write with Apple Pencil, organize pages and folders, mark up documents, and share your work as PDF or PNG.

**Status:** an early development build. Core notebook, PDF, and export workflows are implemented; real iPad testing and further storage and performance work remain. See the [roadmap](PLAN.md) and [device checklist](docs/MILESTONE5_QA.md) for progress and known issues.

## Features

| | What you can do |
| --- | --- |
| **Handwriting** | Use PencilKit's pens, pencil, marker, eraser, lasso, and ruler, with undo/redo and an optional finger-drawing mode. |
| **Notebooks** | Write across vertically stacked pages, zoom and pan, and add, delete, reorder, or bookmark pages using the thumbnail sidebar. |
| **Paper** | Choose blank, lined, grid, dotted, Cornell, music staff, or weekly planner backgrounds. |
| **Library** | Create notebooks and folders, rename and move notebooks, search titles, and sort by name or date. |
| **PDF reading** | Import from Files or Open in writePad, then navigate with thumbnails, the document outline, and embedded-text search. |
| **PDF annotation** | Handwrite on pages, highlight, underline, strike through text, and add or edit sticky-note comments. Insert blank paper between PDF pages. |
| **Export** | Share a flattened PDF of the entire notebook or a PNG of the current page, including ink and annotations. |
| **Saving** | Autosave after editing, flush on backgrounding or closing, retry failed saves, and recover from supported damaged-file cases. |
| **Appearance** | Light and dark interfaces with white paper for consistent reading and export. |

Notes are stored locally as `.writepad` packages. The app uses Apple's frameworks without third-party runtime dependencies.

## Getting started

### Requirements

- macOS with **Xcode 27+** and an installed iOS Simulator runtime.
- An **iPad simulator**, or a real iPad running **iPadOS 18+**.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for regenerating the project and [SwiftLint](https://github.com/realm/SwiftLint) for linting.
- An Apple Pencil for checking handwriting behavior on a real device.

Install the development tools with Homebrew:

```sh
brew install xcodegen swiftlint
# Optional formatter:
brew install swiftformat
```

### Build and run

```sh
git clone https://github.com/kurniawan2805/writePad.git
cd writePad
open writePad.xcodeproj
```

Choose the **writePad** scheme and an **iPad** destination, then run with **⌘R**. For a physical iPad, select your development team in Signing & Capabilities and enable Developer Mode on the device.

The generated Xcode project is committed, so a fresh clone opens directly. After adding, removing, or moving source files, or changing project settings, edit `project.yml` and regenerate:

```sh
xcodegen generate
```

`project.yml` is the source of truth; edit it instead of the generated `.xcodeproj`.

### Try it out

1. Create a notebook in the library and choose a paper style.
2. Write with Apple Pencil, or use finger drawing in the simulator. Open the page sidebar to add or rearrange pages.
3. Import a PDF from the library. Turn off **Draw on PDF** to select text, then use **PDF Tools** for markup and comments.
4. Use **Export** to share the notebook as PDF or the current page as PNG.

See the [PDF workflow guide](docs/MILESTONE4_QA.md) for navigation, annotations, and storage details. PDF text search requires embedded text; OCR for scanned documents is planned.

## Development and testing

Unit tests use Swift Testing; UI tests use XCUITest. Run tests on an iPad simulator:

```sh
# Unit tests
xcodebuild test -project writePad.xcodeproj -scheme writePad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath build -collect-test-diagnostics never \
  -only-testing:writePadTests

# Unit and UI tests
xcodebuild test -project writePad.xcodeproj -scheme writePad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath build -parallel-testing-enabled NO \
  -collect-test-diagnostics never

swiftlint lint --quiet
```

If that simulator is unavailable, list installed devices with `xcrun simctl list devices available` and replace the destination with an available iPad name or `platform=iOS Simulator,id=<UUID>`.

UI tests launch with an isolated storage namespace through `XCUIApplication.isolated()` so they do not use personal notebooks. Keep this isolation when adding tests.

The simulator enables finger drawing by default. Apple Pencil pressure, tilt, palm rejection, and latency require a real iPad. Large PDFs, memory pressure, and interrupted-save scenarios also have a [device acceptance checklist](docs/MILESTONE5_QA.md).

## Architecture

| Area | Responsibility |
| --- | --- |
| `writePad/App/` | App entry, scene lifecycle, and storage location. |
| `writePad/Models/` | Versioned notebook manifests, pages, library metadata, and PDF markups. |
| `writePad/Storage/` | Package persistence, atomic writes, and damaged-file recovery. |
| `writePad/Features/Editor/` | PencilKit canvas, page geometry, backgrounds, thumbnails, and autosave. |
| `writePad/Features/Library/` | SwiftData library index, folders, search, and sorting. |
| `writePad/Features/PDF/` | PDFKit reader, per-page ink overlays, navigation, and annotations. |
| `writePad/Features/Export/` | Flattened PDF and PNG rendering, plus the share sheet. |
| `writePadTests/`, `writePadUITests/`, `TestSupport/` | Unit tests, UI tests, and shared fixtures. |

Swift 6 strict concurrency is enabled. SwiftUI provides the interface, with UIKit bridges for PencilKit and PDFKit. Large content stays in files; SwiftData indexes the library.

### Notebook format

Each notebook is a directory named `<UUID>.writepad`:

```text
<UUID>.writepad/
├── manifest.json         # Title, dates, version, and ordered pages
├── manifest.prev.json    # Previous valid manifest, when available
├── pages/
│   └── <pageID>.drawing  # PencilKit ink in page coordinates
├── source.pdf            # Imported original, for PDF notebooks
└── annotations.json      # PDF text markups and comments
```

The current manifest version is **4**. Imported PDFs are preserved as originals; ink and annotations are stored separately. Saves use atomic file writes, and recovery can fall back to a previous manifest, recover orphaned drawing pages, and quarantine undecodable files as `*.corrupt`.

## Roadmap and contributing

Upcoming work includes further storage hardening, performance improvements, richer page content and templates, handwriting search, and iCloud sync. See [PLAN.md](PLAN.md) for milestone checklists and longer-term ideas.

For changes, follow [AGENTS.md](AGENTS.md), keep work focused, and include tests for storage or view-model behavior. Bug reports are most useful with reproduction steps, the iPad and iPadOS version, and a sample document when relevant.
