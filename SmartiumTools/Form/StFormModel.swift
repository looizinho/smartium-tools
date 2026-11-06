//
//  StFormModel.swift
//  SmartiumTools
//
//  State of the Form tool (handoff v0.9): values, touched fields, the sent
//  flag and the validation rules from the field catalog (§4).
//  App-only: excluded from SmartiumWidgetsExtension.
//

import Foundation
import Observation

/// Sections of the form, in chip order.
enum StFormSection: CaseIterable, Hashable {
  case text, choice, settings, rating

  var title: String {
    switch self {
    case .text: "Texto"
    case .choice: "Escolha"
    case .settings: "Ajustes"
    case .rating: "Avaliação"
    }
  }

  var color: StRGB {
    switch self {
    case .text: StAccent.brand
    case .choice: StTool.orb.rgb
    case .settings: StAccent.sky
    case .rating: StTool.fx.rgb
    }
  }
}

/// The seven required fields.
enum StFormField: CaseIterable, Hashable {
  case name, email, phone, password, role, birthDate, rating
}

/// Field values, starting at the v0.9 initial values.
struct StFormValues: Equatable {
  var name = ""
  var email = ""
  var phone = ""
  var password = ""
  var role = ""
  var birthDate: Date?
  var volume: Double = 60
  var notifications = true
  var accent = StFormRules.swatches[0]
  var rating = 0
}

@Observable
final class StFormModel {
  /// Kept in memory so the values survive switching tabs (the Mac rebuilds
  /// the tool view). Not persisted.
  static let shared = StFormModel()

  var values = StFormValues() {
    didSet {
      // Any edit after a successful submit goes back to "PREENCHIDO".
      if values != oldValue { sent = false }
    }
  }
  var touched: Set<StFormField> = []
  private(set) var sent = false
  var showsPassword = false

  static let requiredCount = StFormField.allCases.count

  /// Error for a required field, or nil when it is valid. Ignores `touched`.
  func error(for field: StFormField) -> String? {
    switch field {
    case .name: StFormRules.name(values.name)
    case .email: StFormRules.email(values.email)
    case .phone: StFormRules.phone(values.phone)
    case .password: StFormRules.password(values.password)
    case .role: StFormRules.role(values.role)
    case .birthDate: StFormRules.birthDate(values.birthDate)
    case .rating: StFormRules.rating(values.rating)
    }
  }

  /// Valid required fields, recomputed on every change (touched or not).
  var validCount: Int {
    StFormField.allCases.count { error(for: $0) == nil }
  }

  var progress: Double {
    Double(validCount) / Double(Self.requiredCount)
  }

  /// Marks every required field as touched; completes only when all are valid.
  func submit() {
    touched = Set(StFormField.allCases)
    sent = validCount == Self.requiredCount
  }

  func reset() {
    values = StFormValues()
    touched = []
    sent = false
    showsPassword = false
  }
}

// MARK: - Rules (§4)

nonisolated enum StFormRules {
  static let roles: [(value: String, label: String)] = [
    ("design", "Design"),
    ("engineering", "Engenharia"),
    ("product", "Produto"),
    ("other", "Outro"),
  ]

  /// Swatch palette, in order.
  static let swatches: [StRGB] = [
    StTool.orb.rgb, StAccent.brand, StAccent.sky, StTool.timer.rgb, StTool.fx.rgb, StTool.voice.rgb,
  ]

  static let swatchNames = ["Íris", "Magenta", "Sky", "Menta", "Âmbar", "Coral"]

  static func name(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "Informe seu nome" }
    if trimmed.count < 2 { return "Mínimo de 2 letras" }
    return nil
  }

  static func email(_ value: String) -> String? {
    if value.isEmpty { return "Informe seu e-mail" }
    if value.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]{2,}/) == nil { return "E-mail inválido" }
    return nil
  }

  /// Normalized while typing: trim + lowercase.
  static func normalizeEmail(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  static func phone(_ value: String) -> String? {
    let digits = value.filter(\.isASCIIDigit)
    if digits.isEmpty { return "Informe seu telefone" }
    if digits.count < 10 { return "Telefone incompleto" }
    return nil
  }

  /// `(DD`, `(DD) XXXX`, `(DD) XXXX-XXXX`, `(DD) XXXXX-XXXX`; at most 11 digits.
  /// Works on pasted, already formatted numbers too.
  static func maskPhone(_ value: String) -> String {
    let digits = Array(value.filter(\.isASCIIDigit).prefix(11))
    guard !digits.isEmpty else { return "" }
    let ddd = String(digits.prefix(2))
    guard digits.count > 2 else { return "(" + ddd }
    let rest = digits.dropFirst(2)
    if digits.count <= 6 { return "(\(ddd)) " + String(rest) }
    let split = digits.count == 11 ? 5 : 4
    return "(\(ddd)) " + String(rest.prefix(split)) + "-" + String(rest.dropFirst(split))
  }

  static func password(_ value: String) -> String? {
    if value.isEmpty { return "Crie uma senha" }
    if value.count < 8 { return "Mínimo de 8 caracteres" }
    if !value.contains(where: \.isLetter) || !value.contains(where: \.isNumber) { return "Use letras e números" }
    return nil
  }

  static func role(_ value: String) -> String? {
    value.isEmpty ? "Escolha uma função" : nil
  }

  static func birthDate(_ value: Date?, now: Date = .now) -> String? {
    guard let value else { return "Informe a data" }
    let calendar = Calendar.current
    if calendar.startOfDay(for: value) > calendar.startOfDay(for: now) { return "A data não pode ser futura" }
    return nil
  }

  static func rating(_ value: Int) -> String? {
    value == 0 ? "Dê uma nota" : nil
  }
}

private extension Character {
  var isASCIIDigit: Bool { isASCII && isNumber }
}
