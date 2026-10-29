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
                .preferredColorScheme(appearance.colorScheme)
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
    }
}
