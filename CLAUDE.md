# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

See `AGENTS.md` for style, commit, and PR conventions. This file covers what you need to know beyond that.

## Commands

```sh
# Build the app (also builds the embedded widget extension)
xcodebuild -project "SmartiumTools.xcodeproj" -scheme "SmartiumTools" -destination 'platform=iOS Simulator,name=iPhone 16' build

# Build only the widget extension
xcodebuild -project "SmartiumTools.xcodeproj" -scheme "SmartiumWidgetsExtension" -destination 'platform=iOS Simulator,name=iPhone 16' build

# macOS is a supported platform too
xcodebuild -project "SmartiumTools.xcodeproj" -scheme "SmartiumTools" -destination 'platform=macOS' build

# Tests (one class or one method)
xcodebuild ... test -only-testing:"<TestTarget>/OrbGoldenTests"
xcodebuild ... test -only-testing:"<TestTarget>/OrbGoldenTests/<testMethod>"
```

**There is no test target yet**, and `spec/orbs-golden.json` is not in the repo, even though `AGENTS.md` and the ThinkingOrbsKit headers mention `OrbGoldenTests`. Golden parity can't be checked locally until someone adds both.

## Project file format

`SmartiumTools.xcodeproj/project.xcproj` is a **JSON-style project description**, not a classic `project.pbxproj`. Target membership is set per folder: a folder lists its targets in `target-membership`, and per-target `membership-exceptions` list the files a target leaves out. When you add a file, check whether it belongs in both targets:

- Everything under `SmartiumTools/` compiles into **both** the app and `SmartiumWidgetsExtension`, except `ContentView.swift`, `SmartiumToolsApp.swift`, `SpinComponent.swift`, `Assets.xcassets`, and the entitlements. So `ThinkingOrbsKit/` and `SmartiumCapabilities/` are shared source, not a framework. A new file in `SmartiumTools/` ends up in the widget unless you add it to the exclusions.
- `SmartiumWidgets/` belongs to the extension only.

Both targets build with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency. Types used from non-main contexts (for example `ToolSharedState`, `SmartiumActivityAttributes`) are marked `nonisolated` on purpose. Keep that in mind when you add model or engine types. Deployment targets are iOS/macOS 27.2.

The app target also links the remote `Libraries.dev` package (products include a `ThinkingOrbsKit` with the same name, plus BorderBeam/Voice* kits). The app code doesn't `import ThinkingOrbsKit`; it uses the **local** `SmartiumTools/ThinkingOrbsKit/` sources, which are the only copy the widget extension can see. If you add `import ThinkingOrbsKit`, expect the package's types to clash with the local ones.

## Architecture

### ThinkingOrbsKit (local, shared)
A pure-math engine plus a SwiftUI renderer, ported from the TypeScript `thinking-orbs` package (`src/engine/*.ts`).

- `OrbSpec.swift` is **generated** (`scripts/codegen-swift.ts` from `spec/orbs-spec.json`; neither is in this repo). Don't edit it by hand. It defines `OrbState` (the 9 user-facing states), `OrbSize`, the internal `OrbMode`, and all tuning tables.
- Data flow: `OrbState` → `state.mode` → `resolvePreset(state, size)` (`Presets.swift`: merges base profile with per-size preset, scaling counts/radii, cached behind a lock) → `orbFrame(...)` dispatches to a per-mode `frameX(size, t, opts)` function → `OrbFrame` of `Dot`s/`Line`s.
- Mode files: `Orbits`, `Lattice` (globe/rubik/wave), `Web`, `Strands` (braid/ribbon; `ring` reuses ribbon via the `faceOn` flag), `Morph`. Shared helpers (`hashD`, `vnoise`, `fibDir`, `Projector`, `radiusScale`, `finalizeFrame`) live in `Core.swift`.
- `ThinkingOrb.swift`: `TimelineView(.animation)` + `Canvas`. Respects Reduce Motion and the color scheme. `.orbFrozenTime(_:)` pins time so `OrbSnapshot` (`Snapshot.swift`, uses `ImageRenderer`) can produce deterministic frames for comparison with the web build.
- The parity rule from `AGENTS.md` applies: change formulas only by transcribing the TS source verbatim, and use `Double` throughout.

### SmartiumCapabilities (shared app ↔ widget state)
- `ToolSharedState` (`SmartiumSharedState.swift`) is the single source of truth. It's stored as JSON in `UserDefaults(suiteName: "group.dev.smartium.tests")`, and `save()` reloads all WidgetKit timelines. Changes are announced in-process through `Notification.Name.smartiumOrbStateDidChange`. `ContentView` re-reads state on appear, on that notification, and when the scene becomes active.
- `CycleOrbStateIntent` advances the orb state from widgets and Live Activities. On iOS it's a `LiveActivityIntent` (runs in the app process); elsewhere it's a plain `AppIntent`.
- `SmartiumLiveActivity.swift`: `SmartiumActivityAttributes` and an `@Observable` `LiveActivityManager.shared` (start/toggle/update/sync), plus `StopLiveActivityIntent`.
- `SmartiumWidgetViews.swift`: `SmartiumOrbWidget` (Home Screen) and `SmartiumLiveActivityWidget` (Lock Screen / Dynamic Island). `SmartiumWidgetsBundle` registers them.
- ActivityKit code is wrapped in `#if canImport(ActivityKit) && os(iOS)` so macOS builds still compile. Follow the same guard pattern.

### App UI
`ContentView` uses a `TabView` on iOS and a custom toolbar pill switcher on macOS (`#if os(macOS)`). `ThinkingOrbsView` cycles states on tap and writes them to shared state and the Live Activity. `VoiceRingView` is a placeholder. Some UI strings are in Portuguese ("Ativar na Ilha Dinâmica").

The App Group `group.dev.smartium.tests` (and the app's iCloud container) must stay identical across both entitlements files and `ToolSharedState.appGroupIdentifier`.
