# Milestone 5 device checks

Export is available from the editor's Export menu. PDF includes every page in notebook order; PNG exports the current page. Both include white paper, the paper pattern or source PDF, and page-local ink. Highlights, underlines, strikethroughs and comments from `annotations.json`, plus sticky notes already inside `source.pdf`, are rendered into the exported page. Exports use a temporary folder removed when the share sheet closes.

Automated coverage includes unsaved ink, page order, paper patterns, PDF annotations, crop offsets and all four page rotations, missing source files, invalid drawings, and a 101-page notebook. This does not replace the real-device checks in [DEVICE-CHECKS.md](DEVICE-CHECKS.md).

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

All real-iPad acceptance checks and result records are maintained in [DEVICE-CHECKS.md](DEVICE-CHECKS.md).

## Known issues

- **Long press after clearing search opens the notebook.** In the library, while the search field is active with an empty query (tapped but nothing typed, or all text deleted), a long press on a notebook card opens it instead of showing the context menu. With text in the search field, or after tapping empty space to end the search, the menu appears normally. Hiding behavior of the navigation bar is not the cause (`searchPresentationToolbarBehavior(.avoidHidingContent)` did not change it). Harmless — nothing is modified — but worth revisiting. `LibraryUITests.testFolderSearchAndSort` ends the search before its long press for this reason.
