//
//  StSwipeToDelete.swift
//  SmartiumTools
//
//  Swipe left to delete, for custom stacks that are not a `List` (handoff v0.3).
//  Past 40pt the row locks open at −76 and shows a 56pt Coral trash button
//  (scale 0.6→1 and opacity follow the drag); past 200pt it deletes at once.
//  Tapping the open row closes it.
//

import SwiftUI

struct StSwipeToDelete<Content: View>: View {
  @Binding private var isOpen: Bool
  private let onDelete: () -> Void
  private let content: Content

  /// Live offset while dragging; nil at rest.
  @State private var dragOffset: CGFloat?
  /// Decided on the first drag change, so vertical scrolling still works.
  @State private var isHorizontalDrag: Bool?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static var openOffset: CGFloat { -76 }
  private static var openThreshold: CGFloat { -40 }
  private static var deleteThreshold: CGFloat { -200 }

  init(isOpen: Binding<Bool>, onDelete: @escaping () -> Void, @ViewBuilder content: () -> Content) {
    self._isOpen = isOpen
    self.onDelete = onDelete
    self.content = content()
  }

  private var offset: CGFloat {
    dragOffset ?? (isOpen ? Self.openOffset : 0)
  }

  var body: some View {
    let reveal = min(1, max(0, -offset / -Self.openOffset))
    ZStack(alignment: .trailing) {
      Button(action: onDelete) {
        Image(systemName: "trash")
          .font(StFont.body(20, .semibold))
          .foregroundStyle(.white)
          .frame(width: 56, height: 56)
          .background(Circle().fill(StTool.voice.tone))
          .shadow(color: StTool.voice.opacity(0.35), radius: 9, y: 6)
      }
      .buttonStyle(.plain)
      .scaleEffect(0.6 + 0.4 * reveal)
      .opacity(reveal)
      .frame(width: -Self.openOffset)
      .accessibilityHidden(true)

      content
        .overlay {
          if isOpen {
            // While open, a tap on the row closes it instead of reaching its buttons.
            Color.clear
              .contentShape(Rectangle())
              .onTapGesture { setOpen(false) }
          }
        }
        .offset(x: offset)
        .simultaneousGesture(drag)
    }
    .accessibilityAction(named: "Apagar", onDelete)
  }

  private var drag: some Gesture {
    DragGesture(minimumDistance: 12)
      .onChanged { value in
        if isHorizontalDrag == nil {
          isHorizontalDrag = abs(value.translation.width) > abs(value.translation.height)
        }
        guard isHorizontalDrag == true else { return }
        let base = isOpen ? Self.openOffset : 0
        dragOffset = min(0, max(-280, base + value.translation.width))
      }
      .onEnded { _ in
        isHorizontalDrag = nil
        guard let dragOffset else { return }
        if dragOffset < Self.deleteThreshold {
          self.dragOffset = nil
          onDelete()
        } else {
          withAnimation(animation) {
            isOpen = dragOffset < Self.openThreshold
            self.dragOffset = nil
          }
        }
      }
  }

  private var animation: Animation? {
    reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7)
  }

  private func setOpen(_ value: Bool) {
    withAnimation(animation) { isOpen = value }
  }
}
