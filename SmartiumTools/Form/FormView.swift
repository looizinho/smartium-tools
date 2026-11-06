//
//  FormView.swift
//  SmartiumTools
//
//  Form tool (handoff v0.9): Hero ring with the share of valid required
//  fields, section chips, the active section's fields, and Enviar / Reset.
//  App-only: excluded from SmartiumWidgetsExtension.
//

import SwiftUI

struct FormView: View {
  @Bindable private var model = StFormModel.shared
  @State private var section = StFormSection.text

  var body: some View {
    StAdaptiveToolLayout(tool: .form, tag: ToolTab.form.title) { size in
      StFormRing(size: size, validCount: model.validCount, sent: model.sent)
    } controls: {
      StToolHeader(
        title: ToolTab.form.title,
        subtitle: model.sent
          ? "Enviado · tudo válido"
          : "\(model.validCount) de \(StFormModel.requiredCount) campos válidos",
        tool: .form,
        status: model.sent ? .active : .ready
      )

      StChipSection(
        title: "Seções",
        dot: StTool.form.secondary,
        items: StFormSection.allCases,
        label: \.title,
        color: \.color,
        isOn: { $0 == section },
        select: { section = $0 }
      )

      sectionCard

      actions
        .padding(.top, 4)
    }
  }

  // MARK: Section card

  private var sectionCard: some View {
    let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
    return VStack(spacing: 16) {
      switch section {
      case .text: textFields
      case .choice: choiceFields
      case .settings: settingsFields
      case .rating: ratingFields
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity)
    .background(shape.fill(StFieldColor.card.color))
    .overlay(shape.strokeBorder(.white.opacity(0.06), lineWidth: 1))
  }

  @ViewBuilder
  private var textFields: some View {
    StTextField(
      label: "Nome",
      text: $model.values.name,
      touched: touched(.name),
      placeholder: "Como quer ser chamado",
      kind: .name,
      validator: StFormRules.name
    )
    StTextField(
      label: "E-mail",
      text: $model.values.email,
      touched: touched(.email),
      placeholder: "voce@exemplo.com",
      kind: .email,
      normalize: StFormRules.normalizeEmail,
      validator: StFormRules.email
    )
    StTextField(
      label: "Telefone",
      text: $model.values.phone,
      touched: touched(.phone),
      placeholder: "(11) 91234-5678",
      hint: "DDD + número",
      kind: .phone,
      mask: StFormRules.maskPhone,
      validator: StFormRules.phone
    )
    StSecureField(
      label: "Senha",
      text: $model.values.password,
      touched: touched(.password),
      showsText: $model.showsPassword,
      placeholder: "Crie uma senha",
      hint: "Mínimo de 8 caracteres, com letras e números",
      validator: StFormRules.password
    )
  }

  @ViewBuilder
  private var choiceFields: some View {
    StSelect(
      label: "Função",
      selection: $model.values.role,
      touched: touched(.role),
      options: StFormRules.roles,
      validator: StFormRules.role
    )
    StDateField(
      label: "Nascimento",
      date: $model.values.birthDate,
      touched: touched(.birthDate),
      validator: { StFormRules.birthDate($0) }
    )
  }

  @ViewBuilder
  private var settingsFields: some View {
    StSlider(label: "Volume", value: $model.values.volume)
    StToggleRow(label: "Notificações", isOn: $model.values.notifications)
    StColorSwatches(
      label: "Cor de destaque",
      selection: $model.values.accent,
      palette: StFormRules.swatches,
      names: StFormRules.swatchNames
    )
  }

  @ViewBuilder
  private var ratingFields: some View {
    StRating(
      label: "Avaliação",
      rating: $model.values.rating,
      touched: touched(.rating),
      validator: StFormRules.rating
    )
  }

  // MARK: Actions

  private var actions: some View {
    HStack(spacing: 10) {
      StButton(
        model.sent ? "Enviado" : "Enviar",
        systemImage: "arrow.right",
        kind: .primary(.form)
      ) {
        model.submit()
        if !model.sent { announceFirstError() }
      }

      StButton(systemImage: "arrow.counterclockwise", kind: .iconTinted(.voice)) {
        model.reset()
      }
      .accessibilityLabel("Limpar formulário")
    }
  }

  /// After a failed submit, reads the first error (VoiceOver).
  private func announceFirstError() {
    stAnnounceFieldError(StFormField.allCases.lazy.compactMap(model.error(for:)).first)
  }

  private func touched(_ field: StFormField) -> Binding<Bool> {
    Binding(
      get: { model.touched.contains(field) },
      set: { isTouched in
        if isTouched {
          model.touched.insert(field)
        } else {
          model.touched.remove(field)
        }
      }
    )
  }
}

// MARK: - Hero

/// Magenta progress ring with an Íris tick ring: label, percent and caption.
struct StFormRing: View {
  let size: CGFloat
  let validCount: Int
  let sent: Bool

  var body: some View {
    let form = StTool.form
    let iris = form.secondaryRGB
    let total = StFormModel.requiredCount
    let percent = Int((Double(validCount) / Double(total) * 100).rounded())
    StDialRing(
      size: size,
      fraction: Double(validCount) / Double(total),
      ringColor: form.tone,
      trackColor: form.opacity(0.14),
      tickColor: iris.color(opacity: 0.5),
      halo: [
        .init(color: form.opacity(0.24), location: 0),
        .init(color: iris.color(opacity: 0.09), location: 0.5),
        .init(color: form.opacity(0), location: 0.7)
      ],
      animationDuration: 0.5
    ) {
      VStack(spacing: 2) {
        Text(sent ? "ENVIADO" : "PREENCHIDO")
          .font(.stTag)
          .tracking(1.4)
          .foregroundStyle(iris.color)
        StBigNumber(value: percent, unit: .percent, size: (size * 0.2).rounded())
        Text("\(validCount) de \(total) obrigatórios")
          .font(StFont.body(13))
          .foregroundStyle(Color.stTextPrimary.opacity(0.55))
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(validCount) de \(total) obrigatórios preenchidos")
      .accessibilityValue(sent ? "Enviado" : "")
    }
  }
}
