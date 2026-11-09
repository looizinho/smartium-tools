//
//  SmartiumWatchApp.swift
//  SmartiumWatch
//
//  Watch app (handoff v0.10): Voz, Timer and Monitor heroes mirroring the
//  iPhone. Read-only: nothing here changes the iPhone.
//

import SwiftUI

@main
struct SmartiumWatchApp: App {
    @State private var store = StWatchStore.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store)
                .font(StFont.body(15))
                .preferredColorScheme(.dark)
                .onAppear { store.activate() }
        }
    }
}
