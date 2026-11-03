//
//  SmartiumToolsApp.swift
//  SmartiumTools
//
//  Created by Luiz Neto on 27/10/26.
//

import SwiftUI

@main
struct SmartiumToolsApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .toolbar(removing: .title)
                #endif
                // Default text font (v0.3): views without an explicit font use Nunito.
                .font(StFont.body(17))
                #if os(iOS)
                // The design is dark-only.
                .preferredColorScheme(.dark)
                #endif
                .tint(.purple)
                .task {
                    _ = await ICloudSettings.loadLimitimer()
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await ICloudSettings.prepareTestFile()
                    _ = await ICloudSettings.loadLimitimer()
                    await StSettingsStore.shared.syncWithICloud()
                }
        }
        #if os(macOS)
        // v0.2: content runs under the title bar; the sidebar starts 64pt down.
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 740)
        #endif
    }
}
