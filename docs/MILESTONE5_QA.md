# Milestone 5 device checks

Export is available from the editor's Export menu. PDF includes every page in notebook order; PNG exports the current page. Both include white paper, the paper pattern or source PDF, and page-local ink. PDF annotations stored in `source.pdf` are rendered into the exported page. Exports use a temporary folder removed when the share sheet closes.

Automated coverage includes unsaved ink, page order, paper patterns, PDF annotations, crop offsets and all four page rotations, missing source files, invalid drawings, and a 101-page notebook. This does not replace the real-device checks below.

## Simulator verification (25 October 2026)

Built with Xcode 27.1 on iPad Pro 13-inch (M5), using a separate simulator and `build/milestone5` while Milestone 4 used the 11-inch simulator.

- SwiftLint and `git diff --check`: passed.
- Unit tests: all 42 tests in 6 suites passed. The autosave regression first reproduced deletion of persisted ink when the manifest write failed; the fix saves the manifest before deleting drawing files.
- Export UI test: passed for both PDF and current-page PNG in dark appearance, including share-sheet dismissal and return to the editor. Screenshots confirmed the PDF and PNG document types and native sharing actions. Light appearance and the installed app icon were also inspected.
- The full suite was run. Its first export UI failure was a locator mismatch: iPadOS exposes Copy as a cell. That test passed after correcting the locator. Two existing Library UI tests also failed on this simulator: `testFolderSearchAndSort` could not open Move to Folder, and `testImportPDFPresentsFilesPicker` could not find Cancel. Their test code was left unchanged by Milestone 5.

```bash
xcodebuild test -project writePad.xcodeproj -scheme writePad \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -derivedDataPath build/milestone5 -parallel-testing-enabled NO

xcodebuild test -project writePad.xcodeproj -scheme writePad \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  -derivedDataPath build/milestone5 -parallel-testing-enabled NO \
  -only-testing:writePadUITests/ExportUITests
```

## Real iPad acceptance checklist

- [ ] Import a PDF with at least 100 pages, including landscape, cropped, and rotated pages. Navigate and annotate throughout it as Milestone 4 becomes available.
- [ ] Export that PDF, save it to Files, and open it in another PDF reader. Check page count, order, orientation, comments, markup, and ink placement.
- [ ] Create a long notebook with ink on the first, middle, and last pages. Reorder pages, export PDF, then export a selected page as PNG. Check paper and ink alignment.
- [ ] Switch between light and dark appearance. Check the library, empty folder, search with no results, editor controls, white paper, share sheet, and Home Screen icon.
- [ ] Write, immediately background the app, terminate it, and reopen. Check that the last stroke and page changes survived.
- [ ] Repeat exports and background saves while memory is constrained, and inspect Xcode's memory graph for retained export buffers after sharing closes.
- [ ] With an Apple Pencil, check pressure, palm rejection, and writing latency.

Record iPad model, iPadOS version, source page count, observed memory use, and any failure before checking off the real-device item in PLAN.md.
