# T11 / T12 design

## T11 — custom pen tray

Replace every system tool picker with one SwiftUI tray, including PDF overlays. Keep 1–8 Codable
presets (ink, width in page points, RGBA color) in UserDefaults, outside notebook packages. A shared
observable favorites collection synchronizes edits across windows; each editor keeps its own active
and previous tool. Invalid preferences fall back to safe defaults. UI tests use a namespaced suite.
Offer preset selection, editing, adding/removing favorites, bitmap eraser and PencilKit lasso.
Attach one UIPencilInteraction to each canvas and honor the system's preferred double-tap/squeeze
action; process squeeze only on ended. Palette actions show the preset editor. Ignore disabled/system
shortcut actions. Disable interactions in read-only, item editing and PDF reading modes.

## T12 — scene ownership and write guard

Each WindowGroup instance owns its LibraryViewModel, ModelContext, editor and scene lifecycle.
An app resource object shares one ModelContainer and NotebookStore. Window requests carry a unique
request ID plus an optional notebook ID, allowing the same notebook to be requested in another window.

Before loading an editor, consult a main-actor registry keyed by standardized package URL. A writer
is retained by the registry until an explicit successful synchronous flush and close. A second opener
flushes the writer before reading disk and opens an immutable read-only editor; failed flush stops the
open. Read-only editors do not acquire write ownership and are never promoted in place: close/reopen
to acquire it. Independent notebooks have independent writers. Every library rejects rename/delete
for any notebook with an open writer; folder metadata stays independent of package writes.

Scene background/inactivation flushes its own editor. Scene disconnection flushes and releases a
successful writer. Failed saves retain the editor and lock so its existing retry can preserve ink;
a subsequent open retries a disconnected writer before allowing ownership transfer. Editor load
failures never acquire ownership. No scene teardown cancels or abandons an unsaved writer.

Validation: preference round trips, capacity and invalid-data handling, tool/gesture transitions,
canvas and PDF tool application, independent scene state, duplicate opening, lock release/load failure,
failed-save ownership, protected library mutations, ink round trip, UI tray persistence and multiwindow
entry points. Real Pencil double-tap/squeeze, pressure, palm rejection, latency and physical iPad
window arrangement remain device checks.
