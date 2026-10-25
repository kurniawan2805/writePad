# T9 — Text boxes and images

Design: [T9_DESIGN.md](T9_DESIGN.md).

## Usage

Open **Items → Text Box**, enter text, and tap **Done**. **Cancel** discards the draft. Select **Image from Files** or **Photo Library** to insert an image. Imported images are normalized to PNG, with a maximum dimension of 2048 points.

**Edit Items** enables selection. Drag an item to move it; drag its blue bottom-right handle to resize its frame. Images keep their aspect ratio inside the frame. **Edit Selected Item** changes text, font size, and precise position/size. **Delete Selected Item**, **Undo**, and **Redo** operate on items while Edit Items is on. Turn it off to return to handwriting/PDF reading. Page structure changes clear item and ink undo history.

Text and images appear over ink in paper notebooks and imported PDFs, including cropped/rotated pages. They also appear in page/library thumbnails and flattened PDF/current-page PNG export.

## Storage and limits

Format v5 adds `PageInfo.itemsRevision`, pointing to `pages/<pageID>.items-<revision>.json`; image bytes live in `images/<assetID>.png`. Existing v1–v4 pages default to no items and upgrade on an editor save. Items use displayed page coordinates.

Revisions and images are immutable and written atomically before the manifest references them. Old revisions/assets remain until package purge so interrupted saves, previous manifests, and undo retain their data. This uses extra disk space; garbage collection is deferred. Missing or malformed item documents/images stop opening without overwriting them. Newer-format notebooks remain protected from writes.

## Verification

All **138 unit tests passed** on the iPad Pro 11-inch (M5), iOS 27.0 simulator. Coverage includes old-format load, text/image reopen, undo/redo, frame limits, page reorder/delete, failed-manifest retry, autosave flush, previous-manifest item recovery, unreadable content preservation, read-only protection, hit testing, and pixel checks for paper/PDF/PNG/thumbnails at all four PDF rotations.

`swiftlint lint --strict --quiet --no-cache` and `git diff --check` passed. The project was regenerated with XcodeGen; existing Xcode signing settings were preserved in `project.yml`.

All **12 UI tests passed** in the same full-suite run, including two new item scenarios: paper text creation/move/resize/undo/redo/delete/reopen, and PDF item move/zoom/reopen. The other ten cover accessibility, library, export, PDF annotation/ink, templates and bookmarks.

Command:

```sh
xcodebuild test -project writePad.xcodeproj -scheme writePad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath build -parallel-testing-enabled NO \
  -collect-test-diagnostics never
```

Result: **TEST SUCCEEDED**, implementation `6733ddb`, on 2026-10-25. Bundle:
`build/Logs/Test/Test-writePad-2026.10.25_17-07-07-+0300.xcresult`.

The PDF ink UI scenario took 522 seconds because the simulator repeatedly waited for PencilKit palette animation notifications; it completed with no assertion failures. The full UI run took 992 seconds. Earlier QA caught missing overlay accessibility and a stale text binding; both were corrected before this successful run.

Screenshots exported locally (ignored build artifacts):

- `build/T9-QA/B72340C1-6B21-4D43-9D04-7615704FFFA8.png` — paper text moved and resized.
- `build/T9-QA/CB13BC33-D9AA-4F71-BEE8-D65DC9C6E6A3.png` — PDF item after moving and zooming.

Real Pencil pressure, palm rejection, latency, and photo-provider behavior on hardware remain in [DEVICE-CHECKS.md](DEVICE-CHECKS.md).
