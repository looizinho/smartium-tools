//
//  SmartiumWatchWidgetsBundle.swift
//  SmartiumWatchWidgets
//
//  The watch's own complications (handoff v0.12.1 §0–2): Timer, Monitor and
//  Dispositivos in the accessory families, drawn by the same
//  `StComplication` views as the iPhone's Lock Screen. They read the
//  watch's App Group, which `StWatchStore` fills with what the iPhone sends
//  and reloads; the kinds match the iPhone's, so `StLiveSurfaces.reload*`
//  reaches them. Before this extension, the Smart Stack only showed the
//  iPhone's controls, mirrored by the system.
//
//  Tapping opens the watch app on the complication's page (v0.13 §5,
//  `smartium://tool/<id>`). The complications don't have buttons: the
//  watch doesn't send actions to the iPhone yet.
//

import SwiftUI
import WidgetKit

@main
struct SmartiumWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SmartiumWatchTimerWidget()
        SmartiumWatchMonitorWidget()
        SmartiumWatchDevicesWidget()
    }
}

private let complicationFamilies: [WidgetFamily] = [
    .accessoryCircular, .accessoryRectangular, .accessoryInline,
]

// MARK: - Timer

struct SmartiumWatchTimerEntry: TimelineEntry {
    let date: Date
    let snapshot: StTimerSnapshot
}

/// While counting, the ring and the clock count by themselves (§2.3); one
/// more entry at `fireDate` switches to "Encerrado!" without a reload, so
/// the count goes on without the iPhone nearby. The timeline asks again at
/// the end, or every 30 min, in case a reload gets lost.
struct SmartiumWatchTimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> SmartiumWatchTimerEntry {
        SmartiumWatchTimerEntry(date: .now, snapshot: StTimerSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (SmartiumWatchTimerEntry) -> Void) {
        completion(SmartiumWatchTimerEntry(date: .now, snapshot: StLiveSurfaces.timer))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SmartiumWatchTimerEntry>) -> Void) {
        let snapshot = StLiveSurfaces.timer
        let now = Date.now
        var entries = [SmartiumWatchTimerEntry(date: now, snapshot: snapshot)]
        var refresh = now.addingTimeInterval(30 * 60)
        if snapshot.phase(at: now) == .running, let fireDate = snapshot.fireDate {
            entries.append(SmartiumWatchTimerEntry(date: fireDate, snapshot: snapshot))
            refresh = fireDate.addingTimeInterval(1)
        }
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct SmartiumWatchTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: StLiveSurfaces.timerWidgetKind, provider: SmartiumWatchTimerProvider()) { entry in
            StTimerComplication(snapshot: entry.snapshot, date: entry.date)
                .widgetURL(StTool.timer.deepLink)
        }
        .configurationDisplayName("Timer")
        .description("Tempo restante do timer.")
        .supportedFamilies(complicationFamilies)
    }
}

// MARK: - Monitor

struct SmartiumWatchMonitorEntry: TimelineEntry {
    let date: Date
    let metrics: StMetricsSnapshot
    let metric: StWidgetMetric
}

/// The metric pinned in the app, like the watch's Monitor page.
struct SmartiumWatchMonitorProvider: TimelineProvider {
    func placeholder(in context: Context) -> SmartiumWatchMonitorEntry {
        SmartiumWatchMonitorEntry(date: .now, metrics: .placeholder, metric: .cpu)
    }

    func getSnapshot(in context: Context, completion: @escaping (SmartiumWatchMonitorEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SmartiumWatchMonitorEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func entry() -> SmartiumWatchMonitorEntry {
        SmartiumWatchMonitorEntry(
            date: .now,
            metrics: StLiveSurfaces.metrics ?? .placeholder,
            metric: StLiveSurfaces.pinnedWidgetMetric
        )
    }
}

struct SmartiumWatchMonitorWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: StLiveSurfaces.monitorWidgetKind, provider: SmartiumWatchMonitorProvider()) { entry in
            StMonitorComplication(metric: entry.metric, metrics: entry.metrics)
                .widgetURL(StTool.monitor.deepLink)
        }
        .configurationDisplayName("Monitor")
        .description("A métrica fixada no app.")
        .supportedFamilies(complicationFamilies)
    }
}

// MARK: - Dispositivos

struct SmartiumWatchDevicesEntry: TimelineEntry {
    let date: Date
    let devices: [StDeviceBattery]
}

/// Every known device, one per kind, iPhone first (the automatic choice).
struct SmartiumWatchDevicesProvider: TimelineProvider {
    func placeholder(in context: Context) -> SmartiumWatchDevicesEntry {
        SmartiumWatchDevicesEntry(date: .now, devices: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (SmartiumWatchDevicesEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SmartiumWatchDevicesEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func entry() -> SmartiumWatchDevicesEntry {
        SmartiumWatchDevicesEntry(date: .now, devices: StDeviceList.ringDevices(StLiveSurfaces.devices))
    }
}

struct SmartiumWatchDevicesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: StLiveSurfaces.devicesWidgetKind, provider: SmartiumWatchDevicesProvider()) { entry in
            StDevicesComplication(devices: entry.devices)
                .widgetURL(StTool.monitor.deepLink)
        }
        .configurationDisplayName("Dispositivos")
        .description("Bateria do iPhone, do Apple Watch e do Mac.")
        .supportedFamilies(complicationFamilies)
    }
}
