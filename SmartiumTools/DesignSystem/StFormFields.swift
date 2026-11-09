//
//  StFormFields.swift
//  SmartiumTools
//
//  Form field family (handoff v0.9): the `StField` shell with its neutral /
//  focus / error / valid states, and the controls that sit inside it. Errors
//  show only once a field is touched: typed fields on blur, choices on pick.
//  App-only: excluded from SmartiumWidgetsExtension.
//

import SwiftUI

// MARK: - Shared

/// When a field becomes touched: on leaving it, or on every user change.
enum StValidateOn {
  case blur
  case change
}

/// Visual state of the field container. Focus wins over error and valid.
enum StFieldState {
  case neutral, focus, error, valid

  init(isFocused: Bool, error: String?, isValid: Bool) {
    if isFocused {
      self = .focus
    } else if error != nil {
      self = .error
    } else if isValid {
      self = .valid
    } else {
      self = .neutral
    }
  }

  var stroke: Color {
    switch self {
    case .neutral: .white.opacity(0.07)
    case .focus: Color.stBrand.opacity(0.5)
    case .error: StFieldColor.coral.color(opacity: 0.75)
    case .valid: StFieldColor.mint.color(opacity: 0.5)
    }
  }
}

nonisolated enum StFieldColor {
  static let fill = StRGB(hex: 0x1F1B26)
  static let card = StRGB(hex: 0x17141D)
  static let coral = StTool.voice.rgb
  static let mint = StTool.timer.rgb
  static let iris = StTool.orb.rgb
  static let amber = StTool.fx.rgb
}

/// Reads the error aloud when a field is left with one (VoiceOver).
@MainActor
func stAnnounceFieldError(_ error: String?) {
  guard let error else { return }
  AccessibilityNotification.Announcement(error).post()
}

/// Error for a touched field; nil while untouched.
private func visibleError<Value>(_ value: Value, touched: Bool, validator: ((Value) -> String?)?) -> String? {
  guard touched, let validator else { return nil }
  return validator(value)
}

// MARK: - StField

/// Shell: label (+ Menta check when valid), 52 pt container and a reserved
/// 16 pt message line for the hint or the error.
struct StField<Content: View>: View {
  let label: String
  var hint: String?
  var error: String?
  var isValid = false
  var isFocused = false
  private let content: Content

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    _ label: String,
    hint: String? = nil,
    error: String? = nil,
    isValid: Bool = false,
    isFocused: Bool = false,
    @ViewBuilder content: () -> Content
  ) {
    self.label = label
    self.hint = hint
    self.error = error
    self.isValid = isValid
    self.isFocused = isFocused
    self.content = content()
  }

  private var state: StFieldState {
    StFieldState(isFocused: isFocused, error: error, isValid: isValid)
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 6) {
        Text(label)
          .font(StFont.body(13, .semibold))
          .foregroundStyle(Color.stTextPrimary.opacity(0.78))
        if state == .valid {
          Image(systemName: "checkmark.circle.fill")
            .font(StFont.body(14, .bold))
            .foregroundStyle(StFieldColor.mint.color)
            .transition(.opacity.combined(with: .scale(scale: 0.6)))
            .accessibilityHidden(true)
        }
      }
      .padding(.leading, 4)

      content
        .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
        .background(shape.fill(StFieldColor.fill.color))
        // Stroke, beam and glow are decoration: taps reach the control (v0.9.1).
        .overlay(shape.strokeBorder(state.stroke, lineWidth: 1).allowsHitTesting(false))
        .overlay {
          if state == .focus {
            Color.clear
              .stBorderBeam(primary: .stBrand, secondary: StFieldColor.iris.color, cornerRadius: 18)
              .transition(.opacity)
              .allowsHitTesting(false)
          }
        }
        .contentShape(shape)

      Text(error ?? hint ?? " ")
        .font(StFont.body(12.5))
        .foregroundStyle(error != nil ? StFieldColor.coral.color : Color.stTextPrimary.opacity(0.55))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(height: 16, alignment: .leading)
        .padding(.leading, 4)
        .accessibilityHidden(true)
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: state)
  }
}

// MARK: - StTextField

/// Keyboard and autofill hints, mapped per platform.
enum StTextKind {
  case plain, name, email, phone

#if os(iOS)
  var keyboardType: UIKeyboardType {
    switch self {
    case .plain, .name: .default
    case .email: .emailAddress
    case .phone: .phonePad
    }
  }

  var contentType: UITextContentType? {
    switch self {
    case .plain: nil
    case .name: .name
    case .email: .emailAddress
    case .phone: .telephoneNumber
    }
  }
#endif
}

/// Shared text style: 16 pt, weight 500, `#F6F3FA`, Magenta cursor. No
/// native bezel and no system focus ring (v0.9.1): on the Mac both follow
/// the system theme and drew a box inside the container.
private extension View {
  func stFieldText() -> some View {
    textFieldStyle(.plain)
      .focusEffectDisabled()
      .font(StFont.body(16, .medium))
      .foregroundStyle(Color.stTextPrimary)
      .tint(Color.stBrand)
  }
}

/// Placeholder color (v0.9.1).
private let stPlaceholderColor = Color.white.opacity(0.35)

private func stPrompt(_ text: String) -> Text {
  Text(text).foregroundStyle(stPlaceholderColor)
}

struct StTextField: View {
  let label: String
  @Binding var text: String
  @Binding var touched: Bool
  var placeholder = ""
  var hint: String?
  var kind: StTextKind = .plain
  /// Applied on every change, for example the phone mask.
  var mask: ((String) -> String)?
  /// Applied on every change, for example lowercase e-mail.
  var normalize: ((String) -> String)?
  var validator: ((String) -> String?)?
  var validateOn: StValidateOn = .blur
  /// Reports focus changes, so the form knows which field is focused (v0.9.3).
  var onFocusChange: ((Bool) -> Void)?

  /// What the TextField shows. Kept apart from `text` so a mask that rejects
  /// a keystroke (the 12th phone digit) still redraws the field.
  @State private var draft = ""
  @FocusState private var isFocused: Bool
  @Environment(\.stIsActiveTab) private var isActiveTab

  var body: some View {
    let error = visibleError(text, touched: touched, validator: validator)
    StField(label, hint: hint, error: error, isValid: touched && error == nil && validator != nil, isFocused: isFocused) {
      TextField(label, text: $draft, prompt: stPrompt(placeholder))
        .labelsHidden()
        .stFieldText()
        .focused($isFocused)
        .autocorrectionDisabled(kind != .plain)
#if os(iOS)
        .keyboardType(kind.keyboardType)
        .textContentType(kind.contentType)
        .textInputAutocapitalization(kind == .name ? .words : .never)
#endif
        .padding(.leading, 16)
        .padding(.trailing, 8)
    }
    .accessibilityHint(error ?? hint ?? "")
    .onAppear { draft = text }
    .onChange(of: draft) { _, newValue in
      var shaped = newValue
      if let normalize { shaped = normalize(shaped) }
      if let mask { shaped = mask(shaped) }
      if shaped != newValue { draft = shaped }
      if text != shaped {
        text = shaped
        if validateOn == .change { touched = true }
      }
    }
    .onChange(of: text) { _, newValue in
      if draft != newValue { draft = newValue }
    }
    .onChange(of: isFocused) { wasFocused, focused in
      onFocusChange?(focused)
      guard wasFocused, !focused, validateOn == .blur else { return }
      touched = true
      stAnnounceFieldError(validator?(text))
    }
    // A hidden iOS tab stays loaded (v0.9.2): let go of the keyboard there.
    // Dropping focus also runs the blur above (v0.9.3).
    .onChange(of: isActiveTab) { _, active in
      if !active { isFocused = false }
    }
  }
}

// MARK: - StSecureField

struct StSecureField: View {
  let label: String
  @Binding var text: String
  @Binding var touched: Bool
  @Binding var showsText: Bool
  var placeholder = ""
  var hint: String?
  var validator: ((String) -> String?)?
  var validateOn: StValidateOn = .blur
  /// Reports focus changes, so the form knows which field is focused (v0.9.3).
  var onFocusChange: ((Bool) -> Void)?

  private enum Focus { case secure, plain }
  @FocusState private var focus: Focus?
  @Environment(\.stIsActiveTab) private var isActiveTab

  var body: some View {
    let error = visibleError(text, touched: touched, validator: validator)
    StField(label, hint: hint, error: error, isValid: touched && error == nil && validator != nil, isFocused: focus != nil) {
      HStack(spacing: 0) {
        Group {
          if showsText {
            TextField(label, text: $text, prompt: stPrompt(placeholder))
              .focused($focus, equals: .plain)
          } else {
            SecureField(label, text: $text, prompt: stPrompt(placeholder))
              .focused($focus, equals: .secure)
          }
        }
        .labelsHidden()
        .stFieldText()
        .autocorrectionDisabled()
#if os(iOS)
        .textContentType(.newPassword)
        .textInputAutocapitalization(.never)
#endif

        Button {
          let hadFocus = focus != nil
          showsText.toggle()
          // Move focus to the swapped field so toggling is not a blur.
          if hadFocus { focus = showsText ? .plain : .secure }
        } label: {
          Image(systemName: showsText ? "eye.slash" : "eye")
            .font(StFont.body(20, .medium))
            .foregroundStyle(showsText ? Color.stBrand : Color.stTextPrimary.opacity(0.55))
            .frame(width: 38, height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityLabel(showsText ? "Ocultar senha" : "Mostrar senha")
      }
      .padding(.leading, 16)
      .padding(.trailing, 8)
    }
    .accessibilityHint(error ?? hint ?? "")
    .onChange(of: text) {
      if validateOn == .change { touched = true }
    }
    .onChange(of: focus) { old, new in
      if (old != nil) != (new != nil) { onFocusChange?(new != nil) }
      guard old != nil, new == nil, validateOn == .blur else { return }
      touched = true
      stAnnounceFieldError(validator?(text))
    }
    .onChange(of: isActiveTab) { _, active in
      if !active { focus = nil }
    }
  }
}

// MARK: - StSelect

struct StSelect: View {
  let label: String
  @Binding var selection: String
  @Binding var touched: Bool
  let options: [(value: String, label: String)]
  var placeholder = "Selecione…"
  var hint: String?
  var validator: ((String) -> String?)?
  var validateOn: StValidateOn = .change

  private var selectedLabel: String? {
    options.first { $0.value == selection }?.label
  }

  var body: some View {
    let error = visibleError(selection, touched: touched, validator: validator)
    let choice = Binding(
      get: { selection },
      set: { newValue in
        selection = newValue
        touched = true
      }
    )
    StField(label, hint: hint, error: error, isValid: touched && error == nil && validator != nil) {
      Menu {
        Picker(label, selection: choice) {
          ForEach(options, id: \.value) { option in
            Text(option.label).tag(option.value)
          }
        }
        .pickerStyle(.inline)
        .labelsHidden()
      } label: {
        HStack(spacing: 8) {
          Text(selectedLabel ?? placeholder)
            .font(StFont.body(16, .medium))
            .foregroundStyle(selectedLabel == nil ? stPlaceholderColor : Color.stTextPrimary)
          Spacer(minLength: 0)
          Image(systemName: "chevron.down")
            .font(StFont.body(16, .semibold))
            .foregroundStyle(Color.stTextPrimary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .focusEffectDisabled()
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label)
    .accessibilityValue(selectedLabel ?? placeholder)
    .accessibilityHint(error ?? hint ?? "")
  }
}

// MARK: - StDateField

/// Optional date (v0.9.1). The whole container is a button that opens a
/// graphical calendar capped at `maximum`: a popover on the Mac and iPad, a
/// sheet on the iPhone. The calendar edits a draft (v0.9.3): OK saves it,
/// Cancelar or dismissing discards it. Any close marks the field as touched
/// (its blur).
struct StDateField: View {
  let label: String
  @Binding var date: Date?
  @Binding var touched: Bool
  var maximum: Date = .now
  var placeholder = "Selecionar data"
  var hint: String?
  var validator: ((Date?) -> String?)?

  @State private var isPresented = false
  /// What the calendar edits while open; saved to `date` only by OK.
  @State private var draft = Date.now
  @Environment(\.stIsActiveTab) private var isActiveTab

  private static let display: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "pt_BR")
    formatter.dateFormat = "dd/MM/yyyy"
    return formatter
  }()

  var body: some View {
    let error = visibleError(date, touched: touched, validator: validator)
    StField(
      label,
      hint: hint,
      error: error,
      isValid: touched && error == nil && validator != nil,
      isFocused: isPresented
    ) {
      Button {
        draft = min(date ?? maximum, maximum)
        isPresented = true
      } label: {
        HStack(spacing: 8) {
          Text(date.map(Self.display.string(from:)) ?? placeholder)
            .font(StFont.body(16, .medium))
            .monospacedDigit()
            .foregroundStyle(date == nil ? stPlaceholderColor : Color.stTextPrimary)
          Spacer(minLength: 0)
          Image(systemName: "calendar")
            .font(StFont.body(17, .medium))
            .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
      .popover(isPresented: $isPresented, arrowEdge: .bottom) {
        calendar
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(label)
    .accessibilityValue(date?.formatted(date: .long, time: .omitted) ?? "não informado")
    .accessibilityHint(error ?? hint ?? "")
    .accessibilityAddTraits(.isButton)
    .onChange(of: isPresented) { wasPresented, presented in
      guard wasPresented, !presented else { return }
      touched = true
      stAnnounceFieldError(validator?(date))
    }
    // Do not leave the calendar open over another tab (v0.9.3).
    .onChange(of: isActiveTab) { _, active in
      if !active { isPresented = false }
    }
  }

  private var calendar: some View {
    VStack(spacing: 12) {
      // Changing month, year or day only moves the draft: nothing closes.
      DatePicker(label, selection: $draft, in: ...maximum, displayedComponents: .date)
        .datePickerStyle(.graphical)
        .labelsHidden()
        .tint(Color.stBrand)

      HStack {
        Button {
          isPresented = false
        } label: {
          Text("Cancelar")
            .font(StFont.body(15, .semibold))
            .foregroundStyle(Color.white.opacity(0.6))
            .padding(.horizontal, 8)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .keyboardShortcut(.cancelAction)

        Spacer(minLength: 12)

        Button {
          date = draft
          isPresented = false
        } label: {
          Text("OK")
            .font(StFont.body(15, .bold))
            .foregroundStyle(Color.stInk900)
            .padding(.horizontal, 28)
            .frame(height: 44)
            .background(Capsule().fill(Color.stBrand))
            .contentShape(Capsule())
        }
        .keyboardShortcut(.defaultAction)
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
    }
    .padding(16)
    .frame(minWidth: 300)
    .preferredColorScheme(.dark)
    // Room for the whole calendar plus the buttons, without clipping.
    .presentationDetents([.large])
    .presentationCompactAdaptation(.sheet)
    .presentationBackground(StFieldColor.card.color)
  }
}

// MARK: - StSlider

struct StSlider: View {
  let label: String
  @Binding var value: Double
  var hint: String?

  var body: some View {
    StField(label, hint: hint) {
      HStack(spacing: 12) {
        Slider(value: $value, in: 0...100, step: 1)
          .tint(Color.stBrand)
          .labelsHidden()
          .accessibilityLabel(label)
        Text("\(Int(value.rounded()))%")
          .font(StFont.body(15, .bold))
          .monospacedDigit()
          .foregroundStyle(Color.stTextPrimary)
          .frame(width: 44, alignment: .trailing)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, 16)
    }
  }
}

// MARK: - StToggleRow

/// 52×32 track, 28 pt knob with 2 pt inset. The whole container is tappable.
struct StToggleRow: View {
  let label: String
  @Binding var isOn: Bool
  var onText = "Ativadas"
  var offText = "Desativadas"
  var hint: String?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    StField(label, hint: hint) {
      Button {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.2)) {
          isOn.toggle()
        }
      } label: {
        HStack {
          Text(isOn ? onText : offText)
            .font(StFont.body(16, .medium))
            .foregroundStyle(Color.stTextPrimary)
          Spacer(minLength: 8)
          Capsule()
            .fill(isOn ? Color.stBrand : Color.white.opacity(0.14))
            .frame(width: 52, height: 32)
            .overlay(alignment: isOn ? .trailing : .leading) {
              Circle()
                .fill(.white)
                .frame(width: 28, height: 28)
                .padding(2)
                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusEffectDisabled()
    }
    .accessibilityRepresentation {
      Toggle(label, isOn: $isOn)
        .accessibilityValue(isOn ? onText : offText)
    }
  }
}

// MARK: - StColorSwatches

/// 28 pt circles spread edge to edge. The selected one gets a 2 pt ring in
/// its own color with a 2 pt `#17141D` gap.
struct StColorSwatches: View {
  let label: String
  @Binding var selection: StRGB
  let palette: [StRGB]
  let names: [String]
  var hint: String?

  var body: some View {
    StField(label, hint: hint) {
      HStack(spacing: 0) {
        ForEach(Array(palette.enumerated()), id: \.offset) { index, color in
          if index > 0 { Spacer(minLength: 4) }
          swatch(color, name: index < names.count ? names[index] : "")
        }
      }
      .padding(.horizontal, 12)
    }
  }

  private func swatch(_ color: StRGB, name: String) -> some View {
    let isSelected = color == selection
    return Button {
      selection = color
    } label: {
      ZStack {
        if isSelected {
          Circle().strokeBorder(color.color, lineWidth: 2)
          Circle().strokeBorder(StFieldColor.card.color, lineWidth: 2).padding(2)
        }
        Circle().fill(color.color).frame(width: 28, height: 28)
      }
      .frame(width: 36, height: 36)
      .contentShape(Circle())
    }
    .buttonStyle(StPressStyle())
    .focusEffectDisabled()
    .accessibilityLabel(name)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

// MARK: - StRating

/// 1–5 stars, 30 pt with 8 pt spacing. Âmbar up to the rating. Adjustable
/// for VoiceOver.
struct StRating: View {
  let label: String
  @Binding var rating: Int
  @Binding var touched: Bool
  var maximum = 5
  var hint: String?
  var validator: ((Int) -> String?)?
  var validateOn: StValidateOn = .change

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let error = visibleError(rating, touched: touched, validator: validator)
    StField(label, hint: hint, error: error, isValid: touched && error == nil && validator != nil) {
      HStack(spacing: 8) {
        ForEach(1...maximum, id: \.self) { star in
          Button {
            set(star)
          } label: {
            Image(systemName: "star.fill")
              .font(.system(size: 26))
              .foregroundStyle(star <= rating ? StFieldColor.amber.color : Color.white.opacity(0.14))
              .frame(width: 30, height: 30)
              .contentShape(Rectangle())
          }
          .buttonStyle(StPressStyle())
          .focusEffectDisabled()
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 16)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityValue(rating == 0 ? "Sem nota" : "\(rating) de \(maximum) estrelas")
    .accessibilityHint(error ?? hint ?? "")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: set(min(rating + 1, maximum))
      case .decrement: set(max(rating - 1, 1))
      @unknown default: break
      }
    }
  }

  private func set(_ value: Int) {
    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
      rating = value
    }
    if validateOn == .change { touched = true }
  }
}
