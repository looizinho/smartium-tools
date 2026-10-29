# SmartiumTools

Base em SwiftUI para uma coleção de ferramentas. O objetivo é manter uma interface simples e preparar recursos reutilizáveis, para que cada ferramenta futura aproveite a mesma infraestrutura de estado, aparência e integração com o sistema.

## Estado atual

- App para iOS e macOS, com seleção de estados de um orbe animado.
- Motor local `ThinkingOrbsKit`, com nove estados e suporte a Reduzir Movimento.
- Widgets pequenos e médios, com ações para alternar o estado.
- Live Activity e Ilha Dinâmica no iOS, com ações para alternar o estado e encerrar a sessão.
- Ao ativar uma Live Activity ou mudar o estado, o orbe usa a cor de destaque e se move por cinco segundos; depois, volta à paleta padrão e fica estático. O movimento respeita Reduzir Movimento e os limites de execução do iOS.
- Aparência configurável pelo iCloud Drive, compartilhada com widgets e Live Activities.
- AlarmKit no iOS para alarmes com contagem regressiva, incluindo Ilha Dinâmica e Atividade ao Vivo.
- No macOS, navegação na toolbar e título da janela oculto para evitar redundância.

A aba **Voice ring** é um espaço reservado. **AlarmKit** já agenda alarmes com contagem regressiva; alarmes recorrentes ainda não estão implementados.

## Requisitos e execução

O projeto usa o formato `project.xcproj`, SDKs e deployment targets de **iOS 27.2 e macOS 27.2**. O ambiente usado no desenvolvimento é o **Xcode 27.2**. O Xcode resolve a dependência Swift Package Manager `Libraries.dev`; a revisão está registrada em `Package.resolved`.

```sh
open SmartiumTools.xcodeproj
```

Selecione o scheme `SmartiumTools`, o dispositivo físico e execute com **⌘R**. Para iOS, é necessário configurar a assinatura com uma equipe que tenha acesso aos containers usados pelo app. A validação deve acontecer no iPhone físico, incluindo widgets, permissões, iCloud e Live Activities.

Para compilar pela linha de comando:

```sh
# Consulte o identificador do iPhone conectado
xcrun devicectl list devices

# Substitua <UDID> pelo identificador do aparelho
xcodebuild -project SmartiumTools.xcodeproj -scheme SmartiumTools \
  -configuration Debug -destination 'id=<UDID>' build

# Build para o Mac
xcodebuild -project SmartiumTools.xcodeproj -scheme SmartiumTools \
  -configuration Debug -destination 'platform=macOS' build
```

O build do app também compila a extensão `SmartiumWidgetsExtension`. Compilar não equivale a instalar, executar ou validar a interface.

## Aparência pelo iCloud

O app lê `Documents/settings.json` no container `iCloud.dev.smartium.tests`, apresentado no iCloud Drive como **Smartium**. Se o arquivo não existir, cria um arquivo vazio sem sobrescrever conteúdo existente.

```json
{
  "appearance": {
    "theme": "system",
    "accent-color": "purple"
  }
}
```

- `theme`: `system`, `light` ou `dark`.
- `accent-color`: `purple`, `black`, `white`, `red`, `orange`, `yellow`, `green`, `mint`, `teal`, `cyan`, `blue`, `indigo`, `pink`, `brown`, `gray` ou `grey`.

As configurações são relidas ao abrir ou voltar ao app, após a sincronização do iCloud. Não há monitoramento contínuo de edições. Campos ausentes usam os padrões; temas desconhecidos seguem o sistema e cores desconhecidas usam roxo. Falhas de leitura preservam a configuração em cache. A Ilha Dinâmica mantém sua apresentação escura, usando a cor de destaque configurada.

## Estrutura

| Caminho | Responsabilidade |
| --- | --- |
| `SmartiumTools/SmartiumToolsApp.swift` | Entrada, aparência e ciclo de vida da cena |
| `SmartiumTools/ContentView.swift` | Interface base e controles de demonstração |
| `SmartiumTools/ThinkingOrbsKit/` | Geometria, presets, renderer e snapshots dos orbes |
| `SmartiumTools/SmartiumCapabilities/` | Estado compartilhado, aparência, intents, widgets e Live Activity |
| `SmartiumTools/ICloudSettings.swift` | Criação e leitura coordenada de `settings.json` |
| `SmartiumTools/AlarmKitView.swift` | Tela do AlarmKit, contagem regressiva e agendamento no iOS |
| `SmartiumWidgets/` | Entrada e assets da extensão WidgetKit |
| `SmartiumTools.xcodeproj/` | Targets, schemes e configuração de build |

O App Group `group.dev.smartium.tests` guarda estado e aparência para os dois targets. Esses identificadores foram preservados durante a renomeação do projeto.

## Validação e contribuição

Ainda não existem target de testes nem `spec/orbs-golden.json` neste repositório. A paridade matemática com a origem TypeScript permanece sem validação automatizada. Alterações na geometria exigem cuidado com fórmulas, constantes e precisão `Double`.

Consulte [AGENTS.md](AGENTS.md) para orientações de implementação, validação e commits. Priorize recursos reutilizáveis e mantenha o layout enxuto.
