# T10 — Vector ink in PDF export

Design: [T10_DESIGN.md](T10_DESIGN.md).

## Behavior

**Export PDF** writes pen, monoline and marker ink as vector shapes. Textured and unknown ink types retain PencilKit raster rendering in their original stacking order. PNG export continues to use native PencilKit rendering. Paper, source PDFs, markups, and page text/images keep their existing layering. Notebook storage stays at version 5.

`PDFInkRenderer` samples public B-spline interpolation, applies stroke transforms and pre-transform masks (including even-odd holes), and joins/merges pen/monoline coverage before filling it, preserving hairline continuity at high zoom. Marker accumulates broad nib stamps, with the ink color's alpha applied once to the completed stroke in a PDF transparency group. Marker opacity varies through disjoint vector bands; this avoids PDF gradient alpha limitations. Texture runs rasterize only their visible bounds at the existing export scale cap.

## Fidelity checks

`VectorInkExportTests` renders actual exported PDFs at 2 pixels per page point and compares them with `PKDrawing.image` on white paper. It covers all three vector inks with straight lines, tapered curves, dots, elliptical nibs/azimuth changes, affine transforms and erased holes, self-overlap, faint colors, thin lines/hairlines, and changing point opacity. Hairline center pixels are separately checked at 8× zoom to detect gaps between samples. Other checks cover separate translucent strokes, mixed vector/textured stacking and light/dark appearance.

The tests measure mean absolute RGB error on the union of ink pixels, excluding empty paper. The limit is **18/255 per channel**. At least **95%** of native/exported ink pixels must have corresponding ink within **one output pixel** (0.5 page points), allowing native edge softening. Raw coverage IoU is also printed; thin solid strokes have lower raw IoU because PencilKit softens their edges over extra pixels. These are explicit approximation tolerances, not a claim of identical raster output.

PDF resources are recursively inspected, including nested forms and transparency masks. Vector-only fixtures must have **zero image XObjects**; pencil, crayon, watercolor and fountain pen fixtures must retain image XObjects. Existing exporter tests cover PNG, page items, PDF markups, source preservation, page order, invalid content and cleanup. Added coordinate checks place vector ink on cropped source PDFs at 0°, 90°, 180° and 270°.

## Rendering limits

PencilKit does not publish its rendered stroke outline or marker particle shader. Pen/monoline coverage and marker nib density are fitted approximations guarded by the pixel tests. Marker grain is averaged, and opacity bands can differ from native pigment at very high zoom. PNG retains the native appearance. Real Pencil pressure/tilt, moved/resized ink and PDF-reader interoperability remain pending in [DEVICE-CHECKS.md](DEVICE-CHECKS.md), including validation on supported older iPadOS versions.

## Verification

Implementation: `46fb94d`. All **145 unit tests passed** on the iPad Pro 11-inch (M5), iOS 27.0 simulator. The 30 vector fidelity fixtures produced these maxima/minima:

| Ink | Fixtures | Highest mean RGB error /255 | Lowest 1px coverage |
| --- | --- | --- | --- |
| pen | 10 | 13.095 | 98.50% |
| monoline | 10 | 13.095 | 98.50% |
| marker | 10 | 16.904 | 99.87% |

Pen/monoline hairline centers remained fully colored across the inspected span at 8× zoom. Texture comparisons had mean error below 0.008/255. Strict SwiftLint and `git diff --check` passed; XcodeGen regenerated the committed project.

All **12 UI test scenarios passed across runs**. The full suite passed 145 unit tests and nine UI tests, including PDF/PNG sharing, library workflows, PDF annotations/ink, page items and templates/bookmarks. Three accessibility audits initially failed in the library; they reproduced on a newly created iPad simulator. Screenshots showed the long randomized fixture title and a contrast report on black date text against a light background.

Commit `f69218f` keeps the visible fixture title `Accessibility PDF` stable while preserving uniqueness in its parent folder. No audit types or issue checks were removed or newly excluded. All four accessibility tests then passed on the dedicated simulator, auditing library, notebook and PDF in light/dark appearance and the largest text sizes. The dedicated simulator was removed after QA; the existing simulator/data were preserved.

The full run is **not** reported as one green run: its three original audit failures remain in the result bundle. The follow-up run verifies all corrected audit cases; the other UI scenarios and the application build are unchanged.

Commands:

```sh
xcodebuild test -project writePad.xcodeproj -scheme writePad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath build -parallel-testing-enabled NO \
  -collect-test-diagnostics never

xcodebuild test -project writePad.xcodeproj -scheme writePad \
  -destination 'platform=iOS Simulator,id=5CED9E63-68CD-4936-90F4-1DBBE27AF184' \
  -derivedDataPath build -resultBundlePath build/T10-accessibility-stable.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -only-testing:writePadUITests/AccessibilityUITests
```

Results on 2026-10-25:

- `build/Logs/Test/Test-writePad-2026.10.25_18-11-24-+0300.xcresult`: 145 unit tests passed; 9 UI passed, 3 accessibility failures before the fixture fix. UI duration 760.7 seconds.
- `build/T10-accessibility-clean.xcresult`: the original three audit failures reproduced on the dedicated simulator.
- `build/T10-accessibility-stable.xcresult`: **TEST SUCCEEDED**, all four accessibility tests passed, 243.4 seconds.
- `build/T10-accessibility-passed/`: exported screenshots for all 12 audited surfaces and their manifest; these remain ignored local build artifacts.

Commits: `f7540ae` design/claim, `46fb94d` vector rendering/tests, `f69218f` stable audit fixtures.
