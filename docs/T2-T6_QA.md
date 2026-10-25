# T2–T6 verification

Test environment: Xcode 27.1, iOS 27.0, iPad Pro 11-inch (M5) simulator, 25 October 2026.

| Task | Coverage |
| --- | --- |
| T2 | Geometry checks for Cornell divisions, 10 five-line staves, and seven planner rows; pixel checks in thumbnails, PDF, and PNG; version 3 loading and upgrade to version 4; paper-menu UI steps and inspected canvas screenshots for all three templates. |
| T3 | Bookmark/unbookmark persistence, reordering, filtered real page indices, older pages without the new key, and read-only guards; UI scenario filters out other pages, jumps to page 2 of 3, reopens, removes the bookmark through its context menu, and restores All. |
| T4 | Workflow YAML parsed; simulator selector checked against fixture inventories and the installed simulators; hosted workflow checks Xcode, generates the project, runs strict lint, then builds/runs unit tests. UI tests are a separate opt-in `workflow_dispatch` job. |
| T5 | Links checked; all physical-device acceptance steps consolidated in DEVICE-CHECKS.md with model, iPadOS, date, and result columns. Device results remain pending. |
| T6 | Library, notebook, and PDF audited in light and dark appearance at default and accessibility XXXL text sizes: four UI tests, twelve audits. Tests set and restore device appearance, apply a Debug-only color-scheme override restricted to isolated storage launches, and assert the rendered sidebar brightness before each audit. |

The accessibility work fixes date-caption and sidebar contrast, wrapping sidebar text, large-text library layout,
and the editor page-position control. The Pages button announces its current/total page value, opens navigation,
and uses an icon at accessibility text sizes. Library titles expand instead of being limited to two lines.

Two narrow exclusions are documented in `AccessibilityUITests`:

- Hit-region reports for PencilKit's **Tool palette handle** only; its geometry and gestures belong to PencilKit.
- Text-clipping reports for the current **native navigation-bar title** only. UIKit intentionally uses a single line;
  the full title remains in its accessibility label and the library card. Library-card text is not excluded.

## Results

- Complete local suite: **111 Swift Testing tests in 11 suites and 10 UI tests passed**, with zero failures.
- All four rendered-appearance scenarios passed: light/dark at default and accessibility XXXL text sizes, with three audits per scenario.
- Strict SwiftLint, `git diff --check`, and deterministic XcodeGen regeneration passed.
- [Hosted GitHub CI](https://github.com/kurniawan2805/writePad/actions/runs/40183465734) passed all **111 unit tests** on implementation commit `73550ee`, including autosave and thumbnail regressions.
- Local result bundle: `/tmp/writepad-t2-t6-complete.xcresult`. Retained attachments include the three template screenshots and every audit surface.

Synchronous PencilKit/PDFKit thumbnail rendering runs on a dedicated serial background queue and streams images
to the main actor. This keeps blocking framework work off Swift's cooperative executor. The hosted run before
this correction stalled at the thumbnail wait and failed autosave timing checks; its logs motivated this change.
A regression also checks that pending renders cannot restore thumbnails for deleted pages.

The complete local suite is run with:

```sh
xcodebuild test -project writePad.xcodeproj -scheme writePad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath build -resultBundlePath /tmp/writepad-t2-t6-complete.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never
```

Physical Apple Pencil pressure, tilt, palm rejection, latency, and device stress checks were not performed.
Record those results in [DEVICE-CHECKS.md](DEVICE-CHECKS.md).
