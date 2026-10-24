# writePad

iPad app for handwritten notes and PDF annotation. See [PLAN.md](PLAN.md) for the roadmap.

## Requirements
- Xcode 27+, iPadOS 18+ target
- `brew install xcodegen swiftlint swiftformat`

## Build
The Xcode project is generated from `project.yml`. After adding/removing files or changing settings:

```bash
xcodegen generate
open writePad.xcodeproj
```

Run tests from the command line:

```bash
xcodebuild test -project writePad.xcodeproj -scheme writePad \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'
```
