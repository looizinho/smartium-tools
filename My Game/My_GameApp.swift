//
//  My_GameApp.swift
//  My Game
//
//  Created by Luiz Neto on 27/10/26.
//

import SwiftUI

@main
struct My_GameApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    await ICloudSettings.prepareTestFile()
                }
        }
    }
}
