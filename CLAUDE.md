# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` (Portuguese) has the style, commit, and PR conventions, and `README.md` has the feature list and the `settings.json` schema. This file covers what you need beyond those. Parts of `AGENTS.md` are out of date: it says AlarmKit isn't implemented, and its list of extension exclusions is incomplete. Where the two disagree, follow this file and the project file. Recent commits use a scope, `type(scope): resumo` (for example `feat(widget): …`, `chore(scheme): …`), and are mostly written in Portuguese.

`design/` holds snapshots of the Claude Design handoffs (`design/handoff-v0.X`), which the `handoff v0.X` file headers refer to. It's a manual backup that stays out of git: don't commit it.

## Commands

Toolchain: Xcode 27.2, iOS/macOS 27.2 deployment targets. Validation is done on the **physical iPhone** (widgets, Live Activities, AlarmKit, iCloud, and camera all need it). Use a simulator only for compile checks, and then use the one already selected or booted in Xcode.

```sh
xcrun devicectl list devices                     # find the iPhone's UDID

# Build the app (also builds the embedded SmartiumWidgetsExtension)
xcodebuild -project SmartiumTools.xcodeproj -scheme SmartiumTools -configuration Debug -destination 'id=<UDID>' build
xcodebuild -project SmartiumTools.xcodeproj -scheme SmartiumTools -configuration Debug -destination 'platform=macOS' build

# Build, install, and launch on the iPhone (uses the "App Debug" scheme; --console streams logs)
scripts/run_iphone_device.sh <UDID> [--console]
```

Shared schemes: `SmartiumTools`, `App Debug` / `App Release`, `SmartiumWidgetsExtension`, and `Widget Debug` / `Widget Release`. The Widget schemes launch the extension through SpringBoard with `_XCWidgetKind`-style environment variables. There's no formatter or linter.

**There's no test target**, and `spec/orbs-golden.json`, `spec/orbs-spec.json`, and `scripts/codegen-swift.ts` aren't in the repo, even though the ThinkingOrbsKit headers mention `OrbGoldenTests`. Don't claim that tests or golden parity passed. When you report results, say which you did: built, ran, or checked visually on the device.

## Project file format

`SmartiumTools.xcodeproj/project.xcproj` is a **JSON-style project description**, not a classic `project.pbxproj`. Membership is set per folder (`target-membership`), and per-target `membership-exceptions` list the files a target leaves out.

- Everything under `SmartiumTools/` compiles into **both** the app and `SmartiumWidgetsExtension` unless it appears in the extension's `exclusions` list. That list holds the app entry point, `ContentView`, `AlarmKitView`, `ICloudSettings`, `StSettingsStore`, `StagingCameraView`, `SpinComponent`, all of `Monitor/`, part of `DesignSystem/`, and the app assets. **A new file in `SmartiumTools/` ends up in the widget unless you add it to that list.** Check the list itself, not a copy.
- `SmartiumWidgets/` belongs to the extension only.
- The app target defines `SMARTIUM_APP`. Shared files use `#if SMARTIUM_APP` for code that needs app-only types; for example, intent bodies that call `StTimerService` or `LiveActivityManager`. Some app-only files are *not* in the exclusions list and are instead wrapped whole in `#if SMARTIUM_APP` (for example, `SmartiumCapabilities/StTimerService.swift`). Either approach works, but pick one per file.
- Platform guards: `#if canImport(ActivityKit) && os(iOS)` and `#if canImport(AlarmKit) && os(iOS)`, so the macOS build keeps compiling.

Both targets use `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency. Shared model types (`ToolSharedState`, `SmartiumActivityAttributes`, `StSettings`, snapshots, tokens) are marked `nonisolated`/`Sendable` on purpose; keep that when you add types. Keep disk I/O off the main thread.

The app also links the remote `Libraries.dev` package, which has its own `ThinkingOrbsKit` product. The code uses the **local** `SmartiumTools/ThinkingOrbsKit/` sources, the only copy the widget can see. Don't add `import ThinkingOrbsKit`.

## Architecture

### Tools and navigation
`ToolTab` (`ContentView.swift`) lists the tools (orb, voice, timer, staging, monitor). They map to `StTool` in `DesignSystem/StTokens.swift`, which supplies each tool's color. The tab order comes from `settings.json` `tabOrder`. iOS uses a `TabView`; macOS uses a custom toolbar pill switcher. `VoiceRingView` and staging are placeholders.

### Design system (`DesignSystem/`, `St*` prefix)
Tokens (`StRGB`, `StAccent`, `StTool`, `StRadius`, `StSpacing`, `StFont`) are defined in sRGB code rather than an asset catalog, because `StTokens.swift` also compiles into the widget. Components and modifiers like `.stBorderBeam(_:)` sit on top of the tokens. File headers cite the design handoff version they implement (`handoff v0.X`).

### State shared between the app and its surfaces (App Group `group.dev.smartium.tools`)
- `ToolSharedState` (`SmartiumSharedState.swift`): orb state as JSON in the App Group `UserDefaults`. `save()` reloads the WidgetKit timelines and posts `.smartiumOrbStateDidChange`. `CycleOrbStateIntent` is a `LiveActivityIntent` on iOS and a plain `AppIntent` elsewhere.
- `StLiveSurfaces` (`SmartiumLiveSurfaces.swift`): snapshots (`StTimerSnapshot`, `StMetricsSnapshot`, orb-activity flag, pending tool) that **the app writes and the extension only reads**, plus widget and control kinds and their reload helpers. When `OpenToolIntent` runs, it stores a pending tool and posts `.smartiumOpenToolRequested`; `ContentView` consumes the pending tool.
- `SmartiumToolIntents.swift`: Control Center and widget intents. They run in the app process.
- Live Activity: `SmartiumLiveActivity.swift` (`SmartiumActivityAttributes`, `@Observable LiveActivityManager.shared`, `StopLiveActivityIntent`). Starting the activity or changing state gives the orb 5 seconds of accent color and motion. A message or progress update does not reset that window. Keep Reduce Motion support and the task cancellation.
- Timer (Limitimer): `AlarmKitView` + `StTimerService` (app-only) schedule AlarmKit countdowns and keep `StLiveSurfaces.timer` up to date. `SmartiumAlarmActivity.swift` is shared: it holds the AlarmKit metadata and the timer's Live Activity / Dynamic Island UI.
- Timer on the Mac (`MacTimer/`, app-only, whole files under `#if SMARTIUM_APP && os(macOS)`): AlarmKit is iOS-only, so `StMacTimerService.shared` counts down in the app, schedules the end notification (`UserNotifications`, rescheduled on pause/resume/±), plays the `ringer` sound, restores a running timer from `StLiveSurfaces.timer` on launch, and writes that snapshot back. `MacTimerView` is a separate screen built from the same `St*` pieces (`AlarmKitView` routes to it on macOS); `MacTimerMenuBar` is a `MenuBarExtra` shown only while a timer is active. The Timer widget is still iOS-only (v0.12.4 §1 is on hold): on macOS a widget button's intent runs in the widget process, and `LiveActivityIntent`, which moves it to the app on iOS, is unavailable there, so Iniciar/Pausar/Zerar can't reach `StMacTimerService` without a hand-made bridge (App Group command plus a Darwin notification, or a deep link that brings the app forward).
- One timer across devices (v0.12): `StTimerSync` (app-only) puts the timer in the iCloud key-value store under `timer.state`, as an `StTimerEnvelope` (snapshot, `originID`, `updatedAt`). A device writes **only on a user action or the end** (`StTimerService.commit` / `recordSchedule` / `recordChange` on iOS, `StMacTimerService.commit()` on the Mac), never once a second. Reads come through `StDeviceSync` (opening, `didChangeExternally`, account change) and, on the Mac, on wake. The newest envelope wins; within 2 s of another device, the larger `originID`. Adopting (`StTimerService.adopt`, `StMacTimerService.adopt`) reschedules AlarmKit or the Mac counter and must never write back: the iOS mirror (`StTimerService.publish`) only forwards pause/resume from the system's buttons and the end, and not while `StTimerSync.isSettling`. Without iCloud each device keeps its own timer. The watch still mirrors the iPhone. Recents, end message and sound still sync through `settings.json`.
- Deep links: `smartium://tool/<id>` (scheme registered in `ICloudInfo.plist`; `StToolDestination.url` / `init?(url:)`, `StTool.deepLink`). Live Activities and widgets set `.widgetURL` so they open their own tool's tab, and `ContentView.onOpenURL` switches the tab (an unknown id keeps the current one). Control Center buttons use `OpenToolIntent` and the pending tool instead.
- Monitor: `StMonitorModel` samples `LiveMetricsProvider` and falls back to `SimulatedMetricsProvider` for any metric it can't read; those are shown with a `SIM` badge. It publishes `StLiveSurfaces.metrics` for the widgets. `StDeviceSync` copies the device batteries to `StLiveSurfaces.devices` for the Dispositivos widget (on the Mac too, in `activate()` and on every change, so the native macOS widget reads the same list; it only updates while the Mac app runs) and, on iPhone, drives the battery Live Activity (`StBatteryActivityManager`, `SmartiumBatteryActivity.swift`).
- Extension (`SmartiumWidgets/`): most of the orb widget and Live Activity definitions (`SmartiumOrbWidget`, `SmartiumLiveActivityWidget`) live in the shared `SmartiumCapabilities/SmartiumWidgetViews.swift`. The timer, monitor and devices widgets, the battery Live Activity and the controls live in `SmartiumWidgets/`. Every Home Screen widget uses the Orb's layout and follows the system theme through `SmartiumCapabilities/SmartiumWidgetChrome.swift` (`StWidgetTheme`, `.stWidgetBackground`, `StWidgetMediumLayout`, `StWidgetSmallLayout`); the app screens stay dark. Timer, Monitor and Dispositivos also have Lock Screen families (iOS only), which are monochrome: no colors of their own. `SmartiumWidgetsBundle` registers the orb, timer, monitor and devices widgets, the Live Activity widgets, and Control Center controls (`SmartiumControls.swift`).

The App Group and the iCloud container `iCloud.dev.smartium.tools` must stay identical across both entitlements files and the code.

### Settings synced through iCloud
`ICloudSettings` reads and writes `Documents/settings.json` in the iCloud container through coordinated file access. `StSettingsStore.shared` (`tabOrder`, `monitor`) and `LimitimerSettings` (key `limitimer`: `end-message`, `recents`, and the Mac-only `ringer`) each write **only their own key**, (`saveAppSettings` / `saveLimitimer`, both going through the private `writeKeys` merge), and preserve the rest, including keys the user edited by hand. Never overwrite the user's file. A local copy in Application Support serves as a cache. The app re-reads settings when the scene becomes active. Keep `Codable` compatible with existing data: a missing field falls back to its default. `StSettingsStore` also mirrors `monitor.pinnedMetric` into the App Group (`StLiveSurfaces.publishPinnedMetric`) so the small Monitor widget's "Fixada no app" option can read it.

### ThinkingOrbsKit (local, shared)
A pure-math engine plus a SwiftUI renderer, ported from the TypeScript `thinking-orbs` package.

- `OrbSpec.swift` is **generated**; don't edit it by hand. It defines `OrbState` (9 states), `OrbSize`, the internal `OrbMode`, and the tuning tables.
- Flow: `OrbState` → `state.mode` → `resolvePreset(state, size)` (`Presets.swift`, cached behind a lock) → `orbFrame(...)` → the per-mode `frameX` (`Orbits`, `Lattice`, `Web`, `Strands`, `Morph`) → `OrbFrame` of `Dot`s/`Line`s. Shared helpers live in `Core.swift`.
- `ThinkingOrb.swift`: `TimelineView(.animation)` + `Canvas`, with Reduce Motion support. `.orbFrozenTime(_:)` and `OrbSnapshot` produce deterministic frames.
- Parity rule: change a formula only by transcribing the TS source verbatim, use `Double` throughout, and keep track of where each constant came from.

UI strings are in Portuguese.
