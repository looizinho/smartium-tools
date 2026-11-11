//
//  MonitorDevices.swift
//  SmartiumTools
//
//  Device batteries on the Monitor (handoff v0.11): the "Dispositivos" card
//  in the Controls (§1.4) and the Hero pager that swipes between the metric
//  and the batteries' concentric rings (§1.4.1).
//  App-only: the whole file is under `#if SMARTIUM_APP`.
//

#if SMARTIUM_APP
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

// MARK: - Dispositivos card

struct StDevicesSection: View {
  private var sync = StDeviceSync.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
#if os(iOS) && canImport(ActivityKit)
      HStack(alignment: .center) {
        StSectionLabel(title: "Dispositivos", dot: StTool.orb.tone)
        Spacer(minLength: 8)
        StBatteryActivityButton()
      }
#else
      StSectionLabel(title: "Dispositivos", dot: StTool.orb.tone)
#endif
      card
    }
  }

  private var card: some View {
    let devices = sync.devices
    let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
    return VStack(spacing: 0) {
      ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
        if index > 0 { divider }
        StDeviceRow(device: device, isThisDevice: device.id == sync.thisID)
      }
      if let notice = sync.notice {
        divider
        StDeviceNoticeRow(notice: notice)
      }
    }
    .padding(.horizontal, 14)
    .background(shape.fill(Color.stInk800))
    .overlay(shape.strokeBorder(.white.opacity(0.06), lineWidth: 1))
    .animation(.easeInOut(duration: 0.3), value: devices)
  }

  private var divider: some View {
    Rectangle()
      .fill(.white.opacity(0.06))
      .frame(height: 1)
  }
}

#if os(iOS) && canImport(ActivityKit)
/// Turns the batteries' Live Activity on and off (v0.12 §3.3), on iPhone.
private struct StBatteryActivityButton: View {
  private var manager = StBatteryActivityManager.shared

  var body: some View {
    let tone = StTool.orb
    let isOn = manager.isRunning
    Button {
      Task { await manager.toggle() }
    } label: {
      Label(isOn ? "Encerrar" : "Ao vivo", systemImage: isOn ? "stop.fill" : "dot.radiowaves.left.and.right")
        .font(StFont.body(12, .bold))
        .foregroundStyle(isOn ? Color.stTextPrimary : tone.tone)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Capsule().fill(isOn ? tone.opacity(0.85) : tone.opacity(0.14)))
        .overlay(Capsule().strokeBorder(tone.opacity(isOn ? 0 : 0.32), lineWidth: 1))
    }
    .buttonStyle(StPressStyle())
    .accessibilityLabel(isOn ? "Encerrar baterias ao vivo" : "Mostrar baterias na Ilha Dinâmica")
  }
}
#endif

/// 64 pt: ring with the device icon, name (and `ESTE`), state and percent.
private struct StDeviceRow: View {
  let device: StDeviceBattery
  let isThisDevice: Bool

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle()
          .stroke(device.rgb.color(opacity: 0.14), lineWidth: 4)
        Circle()
          .trim(from: 0, to: device.ringFraction)
          .stroke(device.levelRGB.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
          .rotationEffect(.degrees(-90))
        StDeviceIcon(kind: device.kind, size: 18, color: device.rgb.color)
      }
      .frame(width: 36, height: 36)
      .frame(width: 44, height: 44)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(device.name)
            .font(StFont.body(15, .bold))
            .foregroundStyle(Color.stTextPrimary)
            .lineLimit(1)
          if isThisDevice {
            Text("ESTE")
              .font(StFont.body(10, .heavy))
              .tracking(0.6)
              .foregroundStyle(Color.stTextPrimary.opacity(0.8))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Capsule().fill(.white.opacity(0.08)))
          }
        }
        HStack(spacing: 4) {
          if device.isCharging {
            Image(systemName: "bolt.fill")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(StTool.timer.tone)
          }
          Text(device.stateText)
            .font(StFont.body(13))
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
        }
      }

      Spacer(minLength: 8)

      Text(device.percentText)
        .font(StFont.body(22, .heavy))
        .monospacedDigit()
        .foregroundStyle(device.isLow ? device.levelRGB.color : Color.stTextPrimary)
        .lineLimit(1)
    }
    .frame(height: 64)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(device.spoken(isThisDevice: isThisDevice))
  }
}

/// "Sem iCloud" or "Sincronização indisponível": cloud with a slash, Âmbar
/// title, caption at 60%. No modal alert.
private struct StDeviceNoticeRow: View {
  let notice: StDeviceSync.Notice

  private var title: String {
    switch notice {
    case .noICloud: "Sem iCloud"
    case .syncUnavailable: "Sincronização indisponível"
    }
  }

  private var caption: String {
    switch notice {
    case .noICloud:
#if os(macOS)
      "O iPhone e o Apple Watch não aparecem porque este Mac está sem iCloud."
#else
      "O Mac não aparece porque este \(UIDevice.current.model) está sem iCloud."
#endif
    case .syncUnavailable:
      "A bateria deste aparelho não está sendo enviada."
    }
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "icloud.slash")
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(StTool.fx.tone)
        .frame(width: 44)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(StFont.body(13, .bold))
          .foregroundStyle(StTool.fx.tone)
        Text(caption)
          .font(StFont.body(12))
          .foregroundStyle(.white.opacity(0.6))
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 12)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Hero pager

/// Which Hero view is showing. Kept while the app runs; a new launch opens
/// on the metric (§1.4.1).
@Observable
final class StMonitorHeroState {
  static let shared = StMonitorHeroState()
  var showsBatteries = false
}

/// Monitor Hero with two views: the metric (`metric`) and the device
/// batteries. Swipe left for the batteries, right to go back: at least 40 pt,
/// more horizontal than vertical so it never fights the vertical scroll. On
/// the Mac, a mouse drag or a two-finger trackpad swipe.
struct StMonitorHeroPager<Metric: View>: View {
  let size: CGFloat
  @ViewBuilder let metric: () -> Metric

  private var state = StMonitorHeroState.shared
  private var sync = StDeviceSync.shared
  @Environment(\.stLayoutMode) private var mode
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static var threshold: CGFloat { 40 }

  init(size: CGFloat, @ViewBuilder metric: @escaping () -> Metric) {
    self.size = size
    self.metric = metric
  }

  var body: some View {
    ZStack {
      if state.showsBatteries {
        batteries
          .transition(transition(fromTrailing: true))
      } else {
        metric()
          .transition(transition(fromTrailing: false))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .simultaneousGesture(
      DragGesture(minimumDistance: 20).onEnded { value in
        swipe(dx: value.translation.width, dy: value.translation.height)
      }
    )
#if os(macOS)
    .modifier(StTrackpadSwipe { dx, dy in swipe(dx: dx, dy: dy) })
#endif
    .overlay(alignment: .bottom) {
      StHeroDots(second: state.showsBatteries)
        .padding(.bottom, mode == .mac ? 20 : 6)
    }
    .accessibilityElement(children: .combine)
    .accessibilityAction(named: "Mostrar baterias") { show(batteries: true) }
    .accessibilityAction(named: "Mostrar métrica") { show(batteries: false) }
    // v0.12 §1.5: only on the batteries view; its own accessibility element.
    .overlay(alignment: .topTrailing) {
      if state.showsBatteries {
        StBatteryRefreshButton()
          .padding(mode == .mac ? 20 : 8)
          .transition(.opacity)
      }
    }
  }

  private var batteries: some View {
    GeometryReader { proxy in
      let inset: CGFloat = mode == .mac ? 48 : 0
      let diameter = max(0, min(size, proxy.size.width - inset, proxy.size.height - inset))
      StDeviceRings(devices: sync.devices, diameter: diameter, numberScale: 0.075)
        .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      (["Baterias dos dispositivos"] + StDeviceList.ringDevices(sync.devices).map {
        $0.spoken(isThisDevice: $0.id == sync.thisID)
      }).joined(separator: "; ")
    )
  }

  /// Fade with a slight sideways move (0.3 s); fade only with Reduce Motion.
  private func transition(fromTrailing: Bool) -> AnyTransition {
    guard !reduceMotion else { return .opacity }
    return .opacity.combined(with: .offset(x: fromTrailing ? 28 : -28))
  }

  private func swipe(dx: CGFloat, dy: CGFloat) {
    guard abs(dx) >= Self.threshold, abs(dx) > abs(dy) else { return }
    show(batteries: dx < 0)
  }

  private func show(batteries: Bool) {
    guard batteries != state.showsBatteries else { return }
    withAnimation(.easeInOut(duration: 0.3)) { state.showsBatteries = batteries }
  }
}

/// Refresh on the batteries view (v0.12 §1.5): a 34 pt Sky circle. A tap
/// spins the icon (0.7 s a turn, at least 1 s; no spin with Reduce Motion),
/// reads this device's battery and publishes it, and reads the others again.
/// At 50% and disabled until the reading is back.
private struct StBatteryRefreshButton: View {
  @State private var isRefreshing = false
  @State private var angle: Double = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let turn: Duration = .milliseconds(700)

  var body: some View {
    let sky = StAccent.sky
    Button(action: refresh) {
      Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
        .font(.system(size: 19, weight: .semibold))
        .foregroundStyle(sky.color)
        .rotationEffect(.degrees(angle))
        .frame(width: 34, height: 34)
        .background(Circle().fill(sky.color(opacity: 0.14)))
        .overlay(Circle().strokeBorder(sky.color(opacity: 0.32), lineWidth: 1))
        .contentShape(Circle())
    }
    .buttonStyle(StPressStyle())
    .focusEffectDisabled()
    .disabled(isRefreshing)
    .opacity(isRefreshing ? 0.5 : 1)
    .accessibilityLabel("Atualizar baterias")
  }

  private func refresh() {
    guard !isRefreshing else { return }
    isRefreshing = true
    let reduceMotion = reduceMotion
    Task {
      let started = ContinuousClock.now
      if !reduceMotion { spin() }
      StDeviceSync.shared.refreshNow()
      // At least 1 s, so the tap never looks ignored; a turn ends whole.
      while ContinuousClock.now - started < .seconds(1) {
        try? await Task.sleep(for: Self.turn)
        if !reduceMotion, ContinuousClock.now - started < .seconds(1) { spin() }
      }
      isRefreshing = false
      AccessibilityNotification.Announcement("Baterias atualizadas").post()
    }
  }

  private func spin() {
    withAnimation(.linear(duration: 0.7)) { angle += 360 }
  }
}

/// Two dots centered at the foot of the Hero: 5 pt tall, the active one
/// 14 pt wide and white, the other 5 pt at 35%.
private struct StHeroDots: View {
  let second: Bool

  var body: some View {
    HStack(spacing: 5) {
      dot(isActive: !second)
      dot(isActive: second)
    }
    .animation(.easeInOut(duration: 0.3), value: second)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func dot(isActive: Bool) -> some View {
    Capsule()
      .fill(.white.opacity(isActive ? 1 : 0.35))
      .frame(width: isActive ? 14 : 5, height: 5)
  }
}

#if os(macOS)
/// Two-finger horizontal swipes on the trackpad while the pointer is over
/// the view: scroll events are summed from `began` to `ended` and reported
/// in finger direction. Events are never consumed.
private struct StTrackpadSwipe: ViewModifier {
  let onSwipe: (CGFloat, CGFloat) -> Void

  @State private var tracker = Tracker()

  func body(content: Content) -> some View {
    content
      .onHover { tracker.isHovering = $0 }
      .onAppear { tracker.start(onSwipe) }
      .onDisappear { tracker.stop() }
  }

  final class Tracker {
    var isHovering = false
    private var monitor: Any?
    private var dx: CGFloat = 0
    private var dy: CGFloat = 0
    private var onSwipe: ((CGFloat, CGFloat) -> Void)?

    func start(_ onSwipe: @escaping (CGFloat, CGFloat) -> Void) {
      self.onSwipe = onSwipe
      guard monitor == nil else { return }
      monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
        MainActor.assumeIsolated { self?.handle(event) }
        return event
      }
    }

    func stop() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }

    private func handle(_ event: NSEvent) {
      guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
      if event.phase.contains(.began) {
        dx = 0
        dy = 0
      }
      guard isHovering || !(dx == 0 && dy == 0) else { return }
      // Natural scrolling reports deltas in finger direction already.
      let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
      dx += event.scrollingDeltaX * sign
      dy += event.scrollingDeltaY * sign
      if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
        if isHovering { onSwipe?(dx, dy) }
        dx = 0
        dy = 0
      }
    }
  }
}
#endif
#endif
