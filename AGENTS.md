# Repository Guidelines

## Project Structure & Module Organization

This is an Xcode project with two targets:

- `My Game/` — Main SwiftUI app. App entry point is `My_GameApp.swift` with `ContentView.swift` as the root view.
- `My Game/ThinkingOrbsKit/` — Shared 3D thought-orb engine (`Core.swift`, `Orbits.swift`, `Morph.swift`, `Presets.swift`, etc.). It is hand-transcribed from a TypeScript source; every formula must match the original exactly because golden-vector tests compare output dot by dot. Use `Double` (not `Float`) for trig-heavy math to avoid precision drift.
- `My Game/SmartiumCapabilities/` — Widget views, Live Activity, and shared state exposed to the widget extension.
- `SmartiumWidgets/` — WidgetKit extension target (`SmartiumWidgetsBundle.swift`).
- `My Game.xcodeproj/` — Project configuration. Assets live in `Assets.xcassets` within each target.

## Build, Test, and Development Commands

- `xcodebuild -project "My Game.xcodeproj" -scheme "My Game" -destination 'platform=iOS Simulator,name=iPhone 16' build` — Build the app.
- `xcodebuild -project "My Game.xcodeproj" -scheme "My Game" -destination 'platform=iOS Simulator,name=iPhone 16' test` — Run tests.
- Open `My Game.xcodeproj` in Xcode for daily development and simulator previews.

## Coding Style & Naming Conventions

- Swift with SwiftUI; four-space indentation.
- Types use `PascalCase`; properties, methods, and variables use `camelCase`. Files are named after their primary type (underscores only where Xcode generates them, e.g. `My_GameApp.swift`).
- Header comments follow Xcode's standard `//  FileName.swift` block.
- Golden-test-critical constants: transcribe from the TypeScript source verbatim and note the provenance in the file's header comment.

## Testing Guidelines

- Tests compare `ThinkingOrbsKit` output against golden vectors (`spec/orbs-golden.json`) with a `1e-4` tolerance. Any change to orb math requires regenerating or consciously updating golden data.
- Name test types after the subject, e.g. `OrbGoldenTests`.
- Run the golden tests whenever formulas, constants, or presets in `ThinkingOrbsKit` change.

## Commit & Pull Request Guidelines

- History is early-stage; use short imperative subjects (e.g. `Add Live Activity setup`) or Conventional Commits prefixes (`feat:`, `fix:`, `chore:`) consistently.
- Pull requests should describe what changed and why, link related issues, and include a simulator screenshot or short clip for any visual change to orbs, widgets, or Live Activities.

## Security & Configuration Tips

- Entitlements live in `SmartiumWidgetsExtension.entitlements` and `My Game/My Game.entitlements`. Do not add capabilities unless required — most UI work needs none.
