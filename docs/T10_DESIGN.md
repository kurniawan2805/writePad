# T10 — Vector ink in PDF export

## Scope

PDF export uses vector coverage shapes for pen, monoline and marker strokes. PNG export continues to use PencilKit. Textured and unknown ink types use PencilKit raster rendering. No storage or editor changes and no format bump.

## Rendering

A focused `PDFInkRenderer` consumes page-coordinate drawings in stroke order after the page background/PDF/markups and before page items. Sample the public B-spline interpolation API and apply each stroke transform and its pre-transform mask (including even-odd holes). Pen/monoline use overlapping elliptical nib coverage aligned with the path tangent, joined between samples and normalized into one filled path so hairlines stay continuous and alpha does not darken at sample overlaps. Marker uses translucent nib stamps aligned with Pencil azimuth, preserving the accumulation of ink along a stroke. Nib geometry and marker density are approximations validated against native rendering, rather than undocumented PencilKit APIs. Resolve colors in light appearance, as existing exports do.

Keep textured runs in their original stacking order and rasterize only their visible page region, at the existing bounded export scale. Preserve PencilKit appearance within those runs. Check cancellation between strokes/runs. No change to atomic export staging or source-PDF handling.

## Acceptance

- Render exported PDF back to pixels and compare with `PKDrawing.image` on white paper. Measure error over ink coverage, not mostly empty page pixels.
- Cover straight/curved/tapered and elliptical nibs, dots, transparent/overlapping ink, transforms, erased masks with holes, light/dark appearance, and mixtures of vector/textured inks.
- Recursively inspect PDF resources, including transparency forms: vector-only ink must render visibly with no image XObjects; textured ink must contain image XObjects. Check PDF/PNG source rotation, layering and page clipping.
- Run strict lint, unit tests and the full simulator suite. Record numerical fidelity tolerances and known rendering approximations in T10 QA. Add real-Pencil export comparison to the device checklist.

## Fidelity limits

PencilKit does not expose its rendered outline or marker particle shader. The solid nib excludes its rendering padding; marker approximates the native broad nib and average opacity without reproducing randomized pigment texture. Keep ink-area pixel error and coverage assertions in the suite, and validate real Pencil samples on hardware. Native raster rendering remains available in PNG exports.

## API sources

Apple PencilKit headers in the installed Xcode SDK and [PKStroke](https://developer.apple.com/documentation/pencilkit/pkstroke-swift.struct), fetched with Context7. The mask is explicitly pre-transform; path points are B-spline control points and must be interpolated. PencilKit does not expose its native rendered outline, so the vector renderer approximates coverage using public stroke samples. Pixel comparisons must validate this approximation before claiming completion.
