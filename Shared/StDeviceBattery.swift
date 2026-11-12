//
//  StDeviceBattery.swift
//  SmartiumTools
//
//  Battery of each of the user's devices (handoff v0.11 §1): the model each
//  device publishes, the colors and texts every surface shows, the device
//  icons and the concentric rings of the watch and of the Monitor hero.
//  Shared by the app, the widget extension and the watch app.
//

import Foundation
import SwiftUI

// MARK: - Model

nonisolated struct StDeviceBattery: Codable, Sendable, Hashable, Identifiable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case iphone, watch, mac
    }

    /// Stable UUID per installation (`StDeviceIdentity`).
    var id: String
    var kind: Kind
    /// "iPhone", "Apple Watch" or the Mac's model name ("MacBook Pro").
    var name: String
    /// 0…1; nil: no battery (desktop Mac).
    var level: Double?
    /// Charging, or full on the charger.
    var isCharging: Bool
    var updatedAt: Date

    /// Entries older than this leave the list (§1.1).
    static let maxAge: TimeInterval = 30 * 24 * 3_600

    /// 20% or less, not charging (§1.4).
    var isLow: Bool {
        guard let level, !isCharging else { return false }
        return level <= 0.2
    }

    /// Whole percent, or nil without a battery.
    var percent: Int? {
        level.map { Int(($0 * 100).rounded()) }
    }

    /// "82%", or "—" without a battery.
    var percentText: String {
        percent.map { "\($0)%" } ?? "—"
    }

    /// Ring fill: full without a battery.
    var ringFraction: Double {
        min(max(level ?? 1, 0), 1)
    }

    /// "Carregando", "Carregada", "Na bateria" or "Na tomada".
    var stateText: String {
        guard let level else { return "Na tomada" }
        if isCharging { return level >= 0.995 ? "Carregada" : "Carregando" }
        return "Na bateria"
    }

    /// Device color: iPhone Sky, Apple Watch Menta, Mac Íris.
    var rgb: StRGB { kind.rgb }

    /// Ring and percent: Coral when low, otherwise the device color.
    var levelRGB: StRGB {
        isLow ? StTool.voice.rgb : kind.rgb
    }

    /// "iPhone, este aparelho, 82 por cento, na bateria" (§1.7).
    func spoken(isThisDevice: Bool) -> String {
        [
            name,
            isThisDevice ? "este aparelho" : nil,
            percent.map { "\($0) por cento" } ?? "sem bateria",
            stateText.lowercased()
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

extension StDeviceBattery.Kind {
    nonisolated var rgb: StRGB {
        switch self {
        case .iphone: StAccent.sky
        case .watch: StTool.timer.rgb
        case .mac: StTool.orb.rgb
        }
    }

    /// Order in lists and rings: iPhone, Apple Watch, Mac.
    nonisolated var rank: Int {
        switch self {
        case .iphone: 0
        case .watch: 1
        case .mac: 2
        }
    }

    /// Ring radius in the 100-unit viewBox, outside in (§1.5).
    nonisolated var ringRadius: CGFloat {
        switch self {
        case .iphone: 44
        case .watch: 35
        case .mac: 26
        }
    }
}

nonisolated enum StDeviceList {
    /// This device first, then iPhone, Watch and Mac, by name within a kind.
    /// Entries older than 30 days are dropped.
    static func ordered(_ devices: [StDeviceBattery], thisID: String?, now: Date = .now) -> [StDeviceBattery] {
        var seen = Set<String>()
        return devices
            .filter { $0.id == thisID || now.timeIntervalSince($0.updatedAt) <= StDeviceBattery.maxAge }
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                if (lhs.id == thisID) != (rhs.id == thisID) { return lhs.id == thisID }
                if lhs.kind != rhs.kind { return lhs.kind.rank < rhs.kind.rank }
                if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
                return lhs.id < rhs.id
            }
    }

    /// Replaces the entry with the same id, or adds it.
    static func merging(_ entry: StDeviceBattery, into devices: [StDeviceBattery]) -> [StDeviceBattery] {
        devices.filter { $0.id != entry.id } + [entry]
    }

    /// One device per kind for the concentric rings: the first in `ordered`.
    static func ringDevices(_ ordered: [StDeviceBattery]) -> [StDeviceBattery] {
        StDeviceBattery.Kind.allCases.compactMap { kind in ordered.first { $0.kind == kind } }
    }
}

/// Stable id of this installation, generated once and kept in the standard
/// defaults (the app's own, not the App Group).
nonisolated enum StDeviceIdentity {
    private static let key = "deviceBatteryID"

    static var id: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: key) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: key)
        return id
    }
}

// MARK: - Icon

/// Device outline in a 24-unit viewBox, stroked 1.9 (§1.4).
struct StDeviceIcon: View {
    let kind: StDeviceBattery.Kind
    var size: CGFloat = 18
    var color: Color

    var body: some View {
        Self.path(kind)
            .stroke(color, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
            .frame(width: 24, height: 24)
            .scaleEffect(size / 24)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    nonisolated static func path(_ kind: StDeviceBattery.Kind) -> Path {
        var path = Path()
        switch kind {
        case .iphone:
            path.addRoundedRect(
                in: CGRect(x: 6.5, y: 2.5, width: 11, height: 19),
                cornerSize: CGSize(width: 2.6, height: 2.6),
                style: .continuous
            )
            path.move(to: CGPoint(x: 10.5, y: 18.5))
            path.addLine(to: CGPoint(x: 13.5, y: 18.5))
        case .watch:
            path.addRoundedRect(
                in: CGRect(x: 6, y: 6, width: 12, height: 12),
                cornerSize: CGSize(width: 3.2, height: 3.2),
                style: .continuous
            )
            path.move(to: CGPoint(x: 8.5, y: 6))
            path.addLine(to: CGPoint(x: 9.2, y: 2.5))
            path.addLine(to: CGPoint(x: 14.8, y: 2.5))
            path.addLine(to: CGPoint(x: 15.5, y: 6))
            path.move(to: CGPoint(x: 8.5, y: 18))
            path.addLine(to: CGPoint(x: 9.2, y: 21.5))
            path.addLine(to: CGPoint(x: 14.8, y: 21.5))
            path.addLine(to: CGPoint(x: 15.5, y: 18))
        case .mac:
            path.addRoundedRect(
                in: CGRect(x: 4, y: 4.5, width: 16, height: 11.5),
                cornerSize: CGSize(width: 1.8, height: 1.8),
                style: .continuous
            )
            path.move(to: CGPoint(x: 2, y: 19.5))
            path.addLine(to: CGPoint(x: 22, y: 19.5))
        }
        return path
    }
}

// MARK: - Concentric rings

/// Rings only, for the widgets and the battery Live Activity (v0.12 §3.2):
/// iPhone r 44, Apple Watch r 33, Mac r 22, stroke 7 in a 100-unit viewBox,
/// one ring per kind; a missing kind has no ring and a device without a
/// battery gets a full one. Low battery in Coral.
///
/// `byPosition` (v0.12.3): the devices the user chose for the widget, in
/// their order. The first gets r 44, the second r 33 and the third r 22,
/// whatever their kind; anything past the third is left out.
struct StDeviceRingsMark: View {
    /// Already ordered (`StDeviceList.ordered`); one ring per kind.
    let devices: [StDeviceBattery]
    /// Track color: the widget theme's, or the device color at 16%.
    var track: Color? = nil
    var byPosition = false

    nonisolated static let positionRadii: [CGFloat] = [44, 33, 22]

    private var rings: [(device: StDeviceBattery, radius: CGFloat)] {
        if byPosition {
            return zip(devices, Self.positionRadii).map { ($0, $1) }
        }
        return StDeviceList.ringDevices(devices).map { ($0, Self.radius($0.kind)) }
    }

    nonisolated static func radius(_ kind: StDeviceBattery.Kind) -> CGFloat {
        switch kind {
        case .iphone: 44
        case .watch: 33
        case .mac: 22
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height) / 100
            ZStack {
                ForEach(rings, id: \.device.id) { ring in
                    let device = ring.device
                    let size = ring.radius * 2 * unit
                    let lineWidth = 7 * unit
                    ZStack {
                        Circle()
                            .stroke(track ?? device.rgb.color(opacity: 0.16), lineWidth: lineWidth)
                        Circle()
                            .trim(from: 0, to: device.ringFraction)
                            .stroke(device.levelRGB.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: size, height: size)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Watch "Dispositivos" view and the Monitor hero's second view (§1.4.1,
/// §1.5): one ring per kind in a 100-unit viewBox, stroke 6.5, track at 16%,
/// iPhone outside (r 44), Apple Watch (35), Mac (26). A kind missing from the
/// list has no ring; without a battery the ring is full. In the center, one
/// line per device: icon, percent and the Menta bolt while charging.
struct StDeviceRings: View {
    /// Already ordered (`StDeviceList.ordered`); one ring per kind is drawn.
    let devices: [StDeviceBattery]
    let diameter: CGFloat
    /// Percent size as a fraction of the diameter: 0.075 hero, 0.085 watch.
    var numberScale: CGFloat = 0.085
    var showsHalo = true

    var body: some View {
        let ringDevices = StDeviceList.ringDevices(devices)
        let unit = diameter / 100
        ZStack {
            if showsHalo {
                // The Monitor hero's halo: Sky, then Íris.
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: StTool.monitor.opacity(0.24), location: 0),
                                .init(color: StTool.monitor.secondaryRGB.color(opacity: 0.10), location: 0.5),
                                .init(color: StTool.monitor.opacity(0), location: 0.7)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: diameter * 0.62
                        )
                    )
                    .frame(width: diameter * 1.12, height: diameter * 1.12)
                    .allowsHitTesting(false)
            }
            ForEach(ringDevices) { device in
                let size = device.kind.ringRadius * 2 * unit
                let lineWidth = 6.5 * unit
                ZStack {
                    Circle()
                        .stroke(device.rgb.color(opacity: 0.16), lineWidth: lineWidth)
                    Circle()
                        .trim(from: 0, to: device.ringFraction)
                        .stroke(device.levelRGB.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: size, height: size)
            }
            VStack(spacing: diameter * 0.012) {
                ForEach(ringDevices) { device in
                    line(device)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.4), value: ringDevices)
    }

    private func line(_ device: StDeviceBattery) -> some View {
        let number = max((diameter * numberScale).rounded(), 9)
        return HStack(spacing: number * 0.22) {
            StDeviceIcon(kind: device.kind, size: number * 0.95, color: device.rgb.color)
            Text(device.percentText)
                .font(StFont.body(number, .heavy))
                .monospacedDigit()
                .foregroundStyle(device.isLow ? device.levelRGB.color : .white)
                .lineLimit(1)
                .fixedSize()
            if device.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: number * 0.7, weight: .bold))
                    .foregroundStyle(StTool.timer.tone)
            }
        }
    }
}
