# Instruções do repositório

## Projeto e limites de compilação

- A fonte de verdade é `SmartiumTools.xcodeproj/project.xcproj`: formato JSON-like com vírgulas finais, não `project.pbxproj`. README e CLAUDE.md têm versões/caminhos antigos; confira configuração e membership no projeto antes de segui-los.
- `SmartiumTools/` compila no app **e na extensão** por padrão. Um arquivo novo exclusivo do app exige entrada em `membership-exceptions` da extensão ou proteção integral com `#if SMARTIUM_APP`. Não copie listas de exclusão da documentação.
- `Shared/` (tokens, fontes, snapshots e modelos de transporte Watch) pertence aos três targets: app, `SmartiumWidgetsExtension` e `SmartiumWatch`. Não introduza dependências exclusivas de iOS/macOS ali. `SmartiumWidgets/` e `SmartiumWatch/` pertencem somente aos respectivos targets.
- Entrada do app: `SmartiumTools/SmartiumToolsApp.swift` → `ContentView.swift`; entrada Watch: `SmartiumWatch/SmartiumWatchApp.swift`. Estado/intents/Live Activities ficam em `SmartiumTools/SmartiumCapabilities/`; tipos de snapshot compartilhados ficam em `Shared/StSharedSnapshots.swift`.
- Todos os targets usam isolamento padrão `MainActor` e approachable concurrency. Preserve `nonisolated`/`Sendable` nos modelos compartilhados e I/O coordenado fora da main thread. Proteja ActivityKit e AlarmKit com `canImport(...) && os(iOS)`.
- O app vincula `Libraries.dev` via SPM, com revisão em `SmartiumTools.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Orbes usam **fontes locais** em `SmartiumTools/ThinkingOrbsKit/`, também compiladas na extensão; não adicione `import ThinkingOrbsKit` do pacote remoto.

## Compilar e validar

- Ambiente atual: Xcode **27.3** (`xcodebuild -version`); deployment targets iOS/macOS/watchOS **27.2**. Não confunda versão do Xcode com deployment target.
- Execute a validação no **iPhone físico**, não adote simulador como padrão. Assinatura precisa de equipe com acesso aos containers existentes. O app compila/embute a extensão; a dependência e o embedding do Watch existem **somente no iOS**. Mudanças em `Shared/` exigem verificar os três targets (um build macOS não verifica Watch).
- O projeto tem configuração padrão **Release**; passe `-configuration Debug` explicitamente nos builds de desenvolvimento.

```sh
xcrun devicectl list devices
xcodebuild -project SmartiumTools.xcodeproj -scheme SmartiumTools -configuration Debug -destination 'id=<UDID>' build
xcodebuild -project SmartiumTools.xcodeproj -scheme SmartiumTools -configuration Debug -destination 'platform=macOS' build
# Compila App Debug, instala e abre no iPhone desbloqueado; --console é opcional.
scripts/run_iphone_device.sh <UDID> --console
```

- O script usa `-allowProvisioningUpdates` e o DerivedData configurado no Xcode. `App Debug` e `SmartiumTools` executam o app; `SmartiumWatch` executa o Watch; `Widget Debug`/`Widget Release` executam a extensão via SpringBoard, não o app.
- MCP Xcode: se faltar aprovação, use `XcodeOpenWorkspace` com o caminho absoluto do `.xcodeproj`; listar workspaces não solicita a autorização. Descubra o workspace/destino ativo, não reutilize identificadores de outra sessão.
- Não há target de testes, formatter/linter ou vetores golden locais. Não trate `xcodebuild test` ou paridade TypeScript como aprovados. Relate separadamente build, execução e validação visual; para UI, obtenha captura ou confirmação no aparelho.

## Contratos de estado

- Preserve `group.dev.smartium.tools` (app/extensão) e `iCloud.dev.smartium.tools` (app). `StLiveSurfaces` publica snapshots no App Group; Watch recebe esses dados por WatchConnectivity, não por acesso ao App Group.
- `ICloudSettings` mescla apenas as chaves de cada subsistema em `Documents/settings.json`: `saveAppSettings` grava `tabOrder`/`monitor`, `saveLimitimer` grava `limitimer`. Preserve chaves desconhecidas (exceto `obsoleteKeys`, hoje `appearance`) e cache em Application Support. Não substitua o documento por um encode dos ajustes; falhas de leitura devem impedir a gravação. Ajustes são relidos quando a cena fica ativa; campos Codable ausentes devem usar padrões compatíveis.
- AlarmKit **já está implementado**: `AlarmKitView` + `StTimerService` no iOS. macOS usa `MacTimer/` com notificações e menu bar; não tente usar AlarmKit no Mac. O timer ativo é por dispositivo, não sincronizado via iCloud.
- Watch é espelho **somente leitura** de voz/timer/monitor (`StWatchSync` → `StWatchStore`); só o pedido de estado “hello” volta ao iPhone. Preserve o limite de 30 s para contextos de amostras do Monitor e mensagens imediatas quando alcançável.
- Deep links: `smartium://tool/<id>`, registrados em `ICloudInfo.plist` e interpretados por `StToolDestination`/`ContentView`. Controles usam `OpenToolIntent` e pending tool no App Group.
- Live Activity do orbe: início/mudança de estado reiniciam os 5 s de destaque e movimento; mensagem/progresso não. Preserve Reduzir Movimento, cancelamento e expiração via `staleDate` sem depender de execução contínua em background.

## Orbes e interface

- `OrbSpec.swift` é gerado: não edite manualmente. `scripts/codegen-swift.ts`, `spec/orbs-spec.json` e `spec/orbs-golden.json` não estão disponíveis neste repo. Fórmulas locais devem preservar a transcrição TypeScript, constantes e precisão `Double`.
- Tokens reutilizáveis estão em `Shared/StTokens.swift`, não no antigo `DesignSystem/StTokens.swift`. Componentes do app ficam em `SmartiumTools/DesignSystem/`. A interface é em português e intencionalmente dark-only.
- `design/` contém backups manuais de handoffs; não os inclua em commits, mesmo aparecendo como untracked (não está no `.gitignore`).
