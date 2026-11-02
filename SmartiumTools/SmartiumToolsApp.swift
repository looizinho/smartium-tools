//
//  SmartiumToolsApp.swift
//  SmartiumTools
//
//  Created by Luiz Neto on 27/10/26.
//

import SwiftUI
import WidgetKit

@main
struct SmartiumToolsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appearance = AppearanceSettings.load()

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .toolbar(removing: .title)
                #endif
                .environment(\.smartiumAppearance, appearance)
                #if os(iOS)
                // The design is dark-only. The iCloud theme still applies to widgets and Live Activity.
                .preferredColorScheme(.dark)
                #else
                .preferredColorScheme(appearance.colorScheme)
                #endif
                .tint(appearance.accentColor)
                .task {
                    _ = await ICloudSettings.loadLimitimer()
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await ICloudSettings.prepareTestFile()
                    _ = await ICloudSettings.loadLimitimer()
                    guard let loaded = await ICloudSettings.loadAppearance(), !Task.isCancelled,
                          loaded != appearance else { return }
                    appearance = loaded
                    loaded.save()
                    WidgetCenter.shared.reloadAllTimelines()
                    #if canImport(ActivityKit) && os(iOS)
                    await LiveActivityManager.shared.refreshAppearance()
                    #endif
                }
        }
        #if os(macOS)
        // v0.2: content runs under the title bar; the sidebar starts 64pt down.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 740)
        #endif
    }
}
