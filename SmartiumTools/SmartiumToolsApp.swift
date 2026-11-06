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
    #if os(macOS)
    @NSApplicationDelegateAdaptor(SmartiumAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .toolbar(removing: .title)
                #endif
                // Default text font (v0.3): views without an explicit font use Nunito.
                .font(StFont.body(17))
                // The design is dark-only, on every platform (v0.9.1).
                .preferredColorScheme(.dark)
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

        #if os(macOS)
        // v0.7: the Mac timer's menu bar item, shown while a timer is active.
        MacTimerMenuBar()
        #endif
    }
}

#if os(macOS)
/// Forces Dark Aqua before any window opens (v0.9.1), so popovers, menus and
/// the DatePicker calendar never follow a light system theme.
final class SmartiumAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}
#endif
