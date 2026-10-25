# T11 — favorite pen tray

Implemented on 2026-10-25. Design: [T11 / T12](T11_T12_DESIGN.md).

The notebook and every PDF overlay now use the custom tray instead of PKToolPicker. It has up to eight
favorites, pen/pencil/marker/monoline ink, color and width controls, bitmap eraser and PencilKit lasso.
UserDefaults stores favorites independently of notebook files; UI tests use their own preference suite.
Favorites are shared between windows, while current/previous tools belong to each editor.

UIPencilInteraction honors double-tap and squeeze preferences, including eraser/previous-tool switching,
palette actions, Off and system shortcuts. Squeeze acts only on ended. Only the focused window and active
PDF canvas can handle a gesture; read-only, PDF reading and item editing modes ignore it.

## Simulator verification

Xcode 27.1; iPad Pro 11-inch (M5), iPadOS 27.1.

- Six new PenTrayTests passed: persistence, tool mapping, capacity, invalid/duplicate preference fallback,
  invalid edit rejection, selection fallback, gesture actions and independent active tools.
- PenTrayUITests passed: choose favorites/eraser/lasso, add a favorite, change width, relaunch, verify persistence.
  Inspected the retained screenshot of the tray.
- The final recheck passed all 161 unit tests. All 14 UI tests passed across runs, including all four
  light/dark and largest-text accessibility audits.
- `swiftlint lint --quiet --strict --no-cache` and `git diff --check` passed.

Targeted result: `build/Logs/Test/Test-writePad-2026.10.25_19-22-47-+0300.xcresult`.
Full run: `build/Logs/Test/Test-writePad-2026.10.25_19-27-02-+0300.xcresult` (160 unit tests;
12 of 14 UI tests passed). The PDF UI test still expected the removed system palette; it now waits for
the favorite tray. The export test tapped before share-sheet dismissal finished; it now waits until the
sheet disappears and Export is hittable. Both passed on recheck, together with all 161 unit tests (the
extra test protects against callbacks from a closed canvas).

Final recheck: `build/Logs/Test/Test-writePad-2026.10.25_19-39-33-+0300.xcresult`.
Logs: `/tmp/writepad-t11-t12-full.log`, `/tmp/writepad-t11-t12-recheck.log`.

## Physical iPad work

Apple Pencil double-tap/squeeze, pressure, tilt, palm rejection, latency and focus between physical windows
remain pending in [DEVICE-CHECKS.md](DEVICE-CHECKS.md). The simulator cannot exercise those Pencil gestures.
