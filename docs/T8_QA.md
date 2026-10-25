# T8 — Disk thumbnail cache

Verified on 2026-10-25 with the iPad Pro 11-inch (M5) simulator, iOS 27.0 / Xcode 27.1.

## Behavior

- A successful `NotebookStore.write` refreshes the first page's `thumb.png` after ink, annotations, manifest and removed-page writes finish.
- Rendering and PNG IO run on `PageThumbnailJob`'s serial utility queue. Library loading awaits this queue without blocking the main actor.
- Library cards reuse decodable PNGs whose modification date is newer than `manifest.json`; absent, stale or corrupt PNGs are regenerated.
- Cache timestamps track the captured manifest with a microsecond allowance for timestamp rounding. A changed manifest prevents publishing an obsolete render.
- PDF previews include markups, retain a private document during rendering and leave `source.pdf` untouched.
- Cache write failures do not fail an ink save. Newer-format notebooks can render previews without writing a cache.
- Library refresh cancels superseded preview results through a generation counter; card tasks restart for the new generation.
- The preview image is decorative for accessibility; the notebook title and date remain exposed.
- Cache files are disposable and require no file-format version change.

## Verification

`swiftlint lint --quiet --no-cache` passed. `xcodegen generate` regenerated the project after adding `ThumbnailCacheTests.swift`.

All **121 unit tests passed**, including six new cache tests: fresh-cache reuse without rewriting, stale/corrupt regeneration, save and first-page reorder, PDF markup rendering/source preservation, cache-write failure, and read-only newer formats. Pixel comparisons normalize renderer-backed and PNG-backed images before comparing exact pixel data.

Command:

```sh
xcodebuild test -project writePad.xcodeproj -scheme writePad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath build -parallel-testing-enabled NO \
  -collect-test-diagnostics never -only-testing:writePadTests
```

Result: `build/Logs/Test/Test-writePad-2026.10.25_16-34-09-+0300.xcresult`.

All **10 UI tests passed across runs**:

- Four accessibility audits (light/dark, normal/largest text) and export passed in the full-suite attempt. That run later stopped because CoreSimulator lost its `host_support` service.
- All remaining five tests (three library tests, PDF reading/annotations/reopen, templates/bookmark persistence) passed on retry with the accessibility and export suites skipped.
- The subsequent timestamp-rounding correction was verified by the final complete unit-test run.

UI result bundles:

- `build/Logs/Test/Test-writePad-2026.10.25_16-16-30-+0300.xcresult`
- `build/Logs/Test/Test-writePad-2026.10.25_16-22-18-+0300.xcresult`

No real iPad checks were performed for this cache change.
