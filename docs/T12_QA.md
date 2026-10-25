# T12 — multiple windows

Implemented on 2026-10-25. Design: [T11 / T12](T11_T12_DESIGN.md).

Enable multiple scenes in the XcodeGen spec. Each window owns a LibraryViewModel, ModelContext, editor,
search/filter state and lifecycle observer; shared resources provide one ModelContainer and NotebookStore.
Use New Window in the library, Open in New Window in a notebook card's context menu, or the editor's Windows
menu. Arrange the resulting windows side by side with iPadOS window controls.

A registry keyed by package URL grants one writer. Opening the same notebook elsewhere synchronously
flushes the writer, then loads a read-only snapshot with an explanation. Read-only opens never quarantine
ink or repair a writer's manifest. Close and reopen the reader after the writer closes to acquire writing.
Rename/delete is rejected while a writer owns the notebook. Library changes refresh other library windows.

Inactive scenes flush their own editor. Closing/disconnecting a window releases ownership only after a
successful save. Closing first revokes the old editor's write capability, protecting against late canvas
callbacks during dismissal. A failed disconnected writer is retained, including its retry and ink, until a later open
can flush it and acquire ownership. Failed loads never reserve the notebook.

## Simulator verification

Xcode 27.1; iPad Pro 11-inch (M5), iPadOS 27.1.

- Ten MultipleWindowTests passed and cover: latest-ink snapshot, read-only mutation protection, independent notebooks
  and scene state, reader/writer close/reopen, cross-window rename/delete, failed load cleanup, failed close
  and disconnected retry, nonmutating damaged-ink reads, cross-context folder refresh, window request identity,
  and callbacks arriving after ownership transfers.
- MultipleWindowUITests passed: open the same notebook through the real Windows menu, verify Read-Only in
  the second scene, and retain a screenshot (visually inspected).
- The final recheck passed all 161 unit tests, including existing save-failure/recovery regressions.
  All 14 UI tests passed across runs, including all four accessibility audits.
- `swiftlint lint --quiet --strict --no-cache` and `git diff --check` passed.

Targeted result: `build/Logs/Test/Test-writePad-2026.10.25_19-25-09-+0300.xcresult`.
Full run: `build/Logs/Test/Test-writePad-2026.10.25_19-27-02-+0300.xcresult` (160 unit tests;
12 of 14 UI tests passed). The PDF UI test still expected the removed system palette; it now waits for
the favorite tray. The export test tapped before share-sheet dismissal finished; it now waits until the
sheet disappears and Export is hittable. Both passed on recheck, together with all 161 unit tests (the
extra test protects against callbacks from a closed canvas).

Final recheck: `build/Logs/Test/Test-writePad-2026.10.25_19-39-33-+0300.xcresult`.
Logs: `/tmp/writepad-t11-t12-full.log`, `/tmp/writepad-t11-t12-recheck.log`.

## Physical iPad work

Actual side-by-side window arrangement, simultaneous Pencil input/focus and full-storage scene teardown
remain pending in [DEVICE-CHECKS.md](DEVICE-CHECKS.md). Read-only windows show a snapshot and require a
close/reopen to reload or become writable; they are not live collaborative editors.
