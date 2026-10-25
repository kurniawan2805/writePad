# T7 — Recently Deleted

Completed 2026-10-25. Notebook deletion moves the entire package into `.Trash` beneath the storage root. The library index stores `deletedAt`; package contents and format version stay unchanged. Refresh (including launch) removes packages after 30 elapsed days.

The sidebar offers Recently Deleted. Long-press a notebook there to Restore or Delete Now. Permanent deletion requires confirmation. Restoring preserves its original folder when that folder still exists.

If the app exits after moving a package but before saving metadata, refresh reconciles the index with the package location. A trashed package without a deletion date receives a new retention period rather than being removed immediately.

## Verification

The full suite passed on the iPad Pro 11-inch (M5), iOS 27.0 simulator, using Xcode 27.1.0:

```sh
xcodebuild test -project writePad.xcodeproj -scheme writePad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath build -parallel-testing-enabled NO -collect-test-diagnostics never
```

- **115 unit tests in 11 suites passed.** Coverage includes soft deletion, exclusion from active listings, byte-preserving restoration of PDF/ink/comments, folder preservation, thumbnail rendering in trash, the 30-day retention boundary with an injected date, recovery of an unindexed trash move, permanent deletion, and deletion-date persistence across a persistent-container reopen.
- **10 UI tests passed with zero failures.** Includes all four accessibility scenarios (light/dark, default/largest text), export, folder/search/sort, file import, PDF reading/annotation/handwriting/reopen/export, page templates/bookmarks, and the extended library round trip: delete → Recently Deleted → restore → reopen a two-page notebook → delete permanently.
- `swiftlint lint --quiet --no-cache` and `git diff --check`: passed.
- Final run completed at 15:23 Asia/Riyadh in approximately 508 seconds. Result: `build/Logs/Test/Test-writePad-2026.10.25_15-14-50-+0300.xcresult`. Console log: `/tmp/writepad-t7-final-full.log`.

## Validation fixes

The initial large-text accessibility failure came from fixture setup: the notebook form remained open after a simulated Save tap, so the later PDF import dismissed the unsaved form. The test now submits through the form's existing Return action and verifies notebook creation before importing the PDF. Library forms use a full-height sheet at accessibility text sizes. Audits stop at the first failure; no new audit exclusions were added.

The new Recently Deleted sidebar row uses the same selected/unselected backgrounds as the existing rows. The final full run completed the previously stalled PDF scenario in approximately 100 seconds, without changing that test or disabling animations.

Real iPad: not run. Pencil pressure, palm rejection, and latency remain on [the device checklist](DEVICE-CHECKS.md).
