# Repository Guidelines

## Objetivo e escopo

SmartiumTools é uma base SwiftUI para ferramentas futuras. Priorize recursos reutilizáveis e uma interface enxuta. Widgets, Live Activities, aparência via iCloud e orbes já existem; `VoiceRingView` é um placeholder e AlarmKit ainda não foi implementado. Consulte [README.md](README.md) para funcionalidades, configuração e execução.

## Estrutura e targets

- `SmartiumTools/`: app; entrada em `SmartiumToolsApp.swift`, raiz em `ContentView.swift`.
- `ThinkingOrbsKit/`: motor e renderer locais, compartilhados com a extensão.
- `SmartiumCapabilities/`: estado, aparência, AppIntents, widgets e Live Activity.
- `SmartiumWidgets/`: entrada e assets da extensão `SmartiumWidgetsExtension`.
- `SmartiumTools.xcodeproj/project.xcproj`: descrição de projeto com sintaxe semelhante a JSON, não um `project.pbxproj` tradicional.

A pasta do app pertence aos dois targets. Confira `membership-exceptions` antes de adicionar arquivos: entrada, interface principal, `ICloudSettings.swift`, `SpinComponent.swift` e assets do app estão excluídos da extensão. Não use APIs exclusivas do app em código da extensão. `SMARTIUM_APP` identifica a compilação do app.

## Desenvolvimento e validação

Use Xcode 27.2 e os deployment targets atuais, iOS/macOS 27.2. Valide no **dispositivo físico**, não adote simulador como padrão. No Xcode, selecione o scheme `SmartiumTools` e o iPhone conectado para executar.

```sh
xcrun devicectl list devices
xcodebuild -project SmartiumTools.xcodeproj -scheme SmartiumTools -configuration Debug -destination 'id=<UDID>' build
xcodebuild -project SmartiumTools.xcodeproj -scheme SmartiumTools -configuration Debug -destination 'platform=macOS' build
```

Substitua `<UDID>` pelo aparelho conectado. O build inclui a extensão. Para mudanças compartilhadas, confira ambos os targets e plataformas; para mudanças visuais, execute e obtenha captura ou confirmação no aparelho. Diferencie build, execução e validação visual ao relatar resultados.

Não há target de testes nem vetores golden no repositório. Não afirme que `xcodebuild test` ou paridade matemática foram aprovados. Fórmulas dos orbes usam `Double`; preserve a transcrição TypeScript e a proveniência das constantes. O gerador de `OrbSpec.swift` também não está disponível localmente. Evite importar o `ThinkingOrbsKit` remoto: o app usa a cópia local.

## Estado, aparência e concorrência

Mantenha compatibilidade Codable com dados existentes. `ToolSharedState` e `AppearanceSettings` usam o App Group. Preserve `group.dev.smartium.tests` e `iCloud.dev.smartium.tests`; não sobrescreva o `settings.json` do usuário. A aparência é relida ao ativar a cena.

Ativação e mudança de estado reiniciam os cinco segundos de cor de destaque e movimento da Live Activity. Mensagem, progresso e aparência não reiniciam o prazo. Preserve Reduzir Movimento, cancelamento de tarefas e encerramento do tempo em segundo plano.

Os targets usam isolamento padrão `MainActor` e approachable concurrency. Preserve `nonisolated`/`Sendable` nos modelos compartilhados e operações de disco fora da main thread. Isole ActivityKit com `#if canImport(ActivityKit) && os(iOS)`.

## Estilo e entrega

Use quatro espaços, tipos `PascalCase`, membros `camelCase` e arquivos nomeados pelo tipo principal. Não há formatter/linter configurado. Não adicione capabilities sem necessidade. Preserve alterações locais preexistentes.

Use commits curtos com `feat:`, `fix:`, `refactor:` ou `docs:`. PRs devem explicar comportamento, motivação, validação e limitações; inclua evidência visual quando aplicável. Não publique testes ou recursos planejados como se já estivessem implementados.
