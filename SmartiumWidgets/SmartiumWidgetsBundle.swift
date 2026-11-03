//
//  SmartiumWidgetsBundle.swift
//  SmartiumWidgets
//
//  Created by Luiz Neto on 27/10/26.
//

import SwiftUI
import WidgetKit

@main
struct SmartiumWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SmartiumOrbWidget()
        #if canImport(ActivityKit) && os(iOS)
        SmartiumLiveActivityWidget()
        #endif
        #if canImport(AlarmKit) && os(iOS)
        SmartiumTimerLiveActivityWidget()
        SmartiumTimerWidget()
        SmartiumTimerControl()
        #endif
        #if os(iOS)
        SmartiumOrbControl()
        SmartiumVoiceControl()
        SmartiumStagingControl()
        SmartiumMonitorControl()
        #endif
    }
}
