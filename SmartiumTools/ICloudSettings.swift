//
//  ICloudSettings.swift
//  SmartiumTools
//

import Foundation
import OSLog

enum ICloudSettings {
    nonisolated private struct Document: Codable {
        let appearance: AppearanceSettings?
        var limitimer: LimitimerSettings?
    }

    nonisolated private struct LegacyRecentTimer: Decodable {
        let duration: TimeInterval
        let label: String?
    }

    nonisolated static func loadAppearance() async -> AppearanceSettings? {
        await Task.detached(priority: .utility) {
            let manager = FileManager.default
            guard let container = manager.url(forUbiquityContainerIdentifier: "iCloud.dev.smartium.tests") else {
                return nil
            }
            let url = container.appendingPathComponent("Documents/settings.json")
            // Download on demand when the file exists only in iCloud.
            if manager.isUbiquitousItem(at: url) {
                try? manager.startDownloadingUbiquitousItem(at: url)
            }
            for attempt in 0..<3 {
                var coordinationError: NSError?
                var result: AppearanceSettings?
                var readError: Error?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
                    do {
                        let data = try Data(contentsOf: readableURL)
                        result = data.isEmpty ? AppearanceSettings() : try JSONDecoder().decode(Document.self, from: data).appearance ?? AppearanceSettings()
                    } catch {
                        readError = error
                    }
                }
                if let result { return result }
                if attempt == 2, let error = coordinationError ?? readError {
                    Logger(subsystem: "dev.smartium.tests", category: "iCloudSettings")
                        .error("Falha ao ler aparência: \(error.localizedDescription, privacy: .public)")
                } else {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            return nil
        }.value
    }

    nonisolated static func prepareTestFile() async {
        // Container lookup and coordinated disk access must run off the main thread.
        await Task.detached(priority: .utility) {
            let logger = Logger(subsystem: "dev.smartium.tests", category: "iCloudSettings")
            let fileManager = FileManager.default

            guard let containerURL = fileManager.url(
                forUbiquityContainerIdentifier: "iCloud.dev.smartium.tests"
            ) else {
                logger.notice("iCloud indisponível. Verifique a conta e o iCloud Drive; tente abrir o app novamente.")
                return
            }

            let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
            let settingsURL = documentsURL.appendingPathComponent("settings.json")
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var writeError: Error?
            var created = false

            coordinator.coordinate(writingItemAt: documentsURL, options: .forMerging, error: &coordinationError) { directoryURL in
                do {
                    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                    // Directory enumeration also detects iCloud files that aren't downloaded yet.
                    let existingFiles = try fileManager.contentsOfDirectory(
                        at: directoryURL,
                        includingPropertiesForKeys: nil
                    )
                    guard !existingFiles.contains(where: { $0.lastPathComponent == "settings.json" }) else {
                        return
                    }

                    let fileURL = directoryURL.appendingPathComponent("settings.json")
                    try Data().write(to: fileURL, options: .withoutOverwriting)
                    created = true
                } catch {
                    writeError = error
                }
            }

            if let error = coordinationError ?? writeError {
                logger.error("Falha ao preparar settings.json: \(error.localizedDescription, privacy: .public)")
            } else if created {
                logger.info("settings.json vazio criado: \(settingsURL.path, privacy: .public). Upload gerenciado pelo iCloud.")
            } else {
                logger.info("settings.json já existe no iCloud e foi preservado.")
            }
        }.value
    }

    nonisolated static func loadLimitimer() async -> LimitimerSettings {
        await Task.detached(priority: .utility) {
            let logger = Logger(subsystem: "dev.smartium.tests", category: "iCloudSettings")
            let (document, readError) = readDocument()

            if let limitimer = document?.limitimer {
                return limitimer
            }

            if let readError {
                logger.error("Falha ao ler Limitimer: \(readError.localizedDescription, privacy: .public)")
            }

            let defaults = UserDefaults(suiteName: ToolSharedState.appGroupIdentifier) ?? .standard
            let legacyRecents = defaults.data(forKey: "dev.smartium.tools.timerRecents")
                .flatMap { try? JSONDecoder().decode([LegacyRecentTimer].self, from: $0) }
                .map { recents in
                    recents.prefix(LimitimerSettings.maximumRecents).map { recent in
                        LimitimerRecent(duration: recent.duration, message: recent.label ?? "")
                    }
                } ?? []

            let settings = LimitimerSettings(recents: legacyRecents)
            await saveLimitimer(settings)
            return settings
        }.value
    }

    nonisolated static func saveLimitimer(_ settings: LimitimerSettings) async {
        await Task.detached(priority: .utility) {
            let (document, readError) = readDocument()
            guard readError == nil else {
                Logger(subsystem: "dev.smartium.tests", category: "iCloudSettings")
                    .error("Não foi possível atualizar Limitimer: \(readError?.localizedDescription ?? "desconhecido", privacy: .public)")
                return
            }

            var updatedDocument = document ?? Document(appearance: nil, limitimer: nil)
            updatedDocument.limitimer = settings

            guard let containerURL = FileManager.default.url(
                forUbiquityContainerIdentifier: "iCloud.dev.smartium.tests"
            ) else {
                Logger(subsystem: "dev.smartium.tests", category: "iCloudSettings")
                    .notice("iCloud indisponível; Limitimer não foi salvo em settings.json.")
                return
            }

            let settingsURL = containerURL.appendingPathComponent("Documents/settings.json")
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var writeError: Error?

            coordinator.coordinate(writingItemAt: settingsURL, options: [], error: &coordinationError) { writableURL in
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(updatedDocument)
                    try data.write(to: writableURL)
                } catch {
                    writeError = error
                }
            }

            if let error = coordinationError ?? writeError {
                Logger(subsystem: "dev.smartium.tests", category: "iCloudSettings")
                    .error("Falha ao salvar Limitimer: \(error.localizedDescription, privacy: .public)")
            }
        }.value
    }

    nonisolated private static func readDocument() -> (Document?, Error?) {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.url(
            forUbiquityContainerIdentifier: "iCloud.dev.smartium.tests"
        ) else {
            return (nil, nil)
        }

        let settingsURL = containerURL.appendingPathComponent("Documents/settings.json")
        if fileManager.isUbiquitousItem(at: settingsURL) {
            try? fileManager.startDownloadingUbiquitousItem(at: settingsURL)
        }

        for attempt in 0..<3 {
            var coordinationError: NSError?
            var result: Document?
            var readError: Error?

            NSFileCoordinator().coordinate(readingItemAt: settingsURL, options: [], error: &coordinationError) { readableURL in
                do {
                    let data = try Data(contentsOf: readableURL)
                    result = data.isEmpty ? Document(appearance: nil, limitimer: nil) : try JSONDecoder().decode(Document.self, from: data)
                } catch {
                    readError = error
                }
            }

            if let result {
                return (result, nil)
            }

            if attempt == 2 {
                return (nil, coordinationError ?? readError)
            }

            Thread.sleep(forTimeInterval: 1)
        }

        return (nil, nil)
    }
}
