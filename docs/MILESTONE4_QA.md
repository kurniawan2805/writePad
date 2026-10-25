# Milestone 4: PDF reader and annotations

## Reading and annotating

Import a PDF from the library's Import PDF button or open a PDF in writePad from Files. Open its library card to read it.

- PDF Tools > Pages, Outline, Search & Comments opens the navigation sidebar. In portrait orientation, close the overlaid sidebar before using the reader toolbar.
- Pages shows thumbnails and supports insertion, deletion, and reordering. Add Page inserts blank paper after the current page.
- Outline follows the PDF's table of contents. PDFs without an outline show an empty state.
- Search finds embedded PDF text. Selecting a result also selects the text for markup. Scanned PDFs need embedded OCR text to be searchable.
- Turn off Draw on PDF to select text, then use PDF Tools to highlight, underline, or strike through the selection.
- Add Comment attaches a sticky note to the selected text or the current page's upper corner. Comments lists annotations with page jumps; new comments can be edited or deleted. Original sticky notes from the imported PDF are listed for reading.
- Turn on Draw on PDF for PencilKit ink. Draw with Finger defaults on in the simulator and off on a real iPad. Undo and redo apply to the active page's ink.
- Export PDF and Export Current Page as PNG flatten the source page, annotations, and ink.

## Storage

Manifest version 3 adds `annotations.json` inside each PDF notebook package. Each annotation stores a stable ID, page ID, kind, PDF-space bounds, and text. Missing annotation files in version 1 and 2 packages load as an empty annotation list; the next edit saves the current format version. An unreadable existing file fails opening instead of discarding its contents.

`source.pdf` remains the imported original. The manifest supplies the displayed order using stable source page indices, with no source index for inserted paper. Native text annotations use PDF coordinates; ink uses displayed page points, including crop and rotation, independent of zoom. Ink stays in `pages/<pageID>.drawing`.

Annotation and drawing writes are atomic, share the one-second autosave debounce, and flush when returning to the library or leaving the active scene. Failed writes remain retryable.

## Device checks

All real-iPad and Apple Pencil acceptance checks are tracked in [DEVICE-CHECKS.md](DEVICE-CHECKS.md).

## Simulator verification (2026-10-25)

Xcode 27.1, iOS 27.0, iPad Pro 11-inch (M5):

- All 55 unit tests passed across seven suites. PDF coverage includes page insertion and reorder, outline destinations, search, all three text markup kinds, comment editing/deletion, original sticky notes, per-page ink, offscreen canvas release/restoration, format migration, corrupt files, and failed-save retries. Export tests compare cropped/rotated annotation rendering at 0/90/180/270 degrees and check comments on inserted paper.
- `PDFUITests.testPDFReadingAnnotationsAndReopen` passed. It imports a PDF through Open in writePad, checks missing-selection feedback, navigates its outline, inserts paper, searches and highlights text, adds a comment, draws with a finger, relaunches, verifies saved annotations, and presents the annotated PDF share sheet. Captured screenshots were inspected to confirm the same ink stroke appears before and after reopening.
- Existing export PDF/PNG, Files picker presentation, and notebook library round-trip UI tests passed.
- SwiftLint and `git diff --check` passed.

The complete suite was run with:

```sh
xcodebuild test -project writePad.xcodeproj -scheme writePad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath build -parallel-testing-enabled NO -collect-test-diagnostics never
```

That full run was not green: the unchanged `LibraryUITests.testFolderSearchAndSort` failed at its Move to Folder context-menu lookup, and the PDF UI runner was terminated during a simulator interruption. The PDF test subsequently passed in a separate run after the simulator was booted again and its drawing gesture targeted the reader surface (PDFKit hides overlay canvases from the accessibility hierarchy).

Local result bundles: `/tmp/writepad-m4-final.xcresult` (full suite) and `/tmp/writepad-m4-pdf-surface.xcresult` (passing PDF UI test).
