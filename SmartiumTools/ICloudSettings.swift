//
//  ICloudSettings.swift
//  SmartiumTools
//

import Foundation
import OSLog

enum ICloudSettings {
    nonisolated private struct Document: Codable {
        var limitimer: LimitimerSettings?
    }

    /// Keys the app no longer uses; writes remove them from settings.json.
    nonisolated private static let obsoleteKeys = ["appearance"]

    nonisolated private struct LegacyRecentTimer: Decodable {
        let duration: TimeInterval
        let label: String?
    }

    nonisolated static func prepareTestFile() async {
        // Container lookup and coordinated disk access must run off the main thread.
        await Task.detached(priority: .utility) {
            let logger = Logger(subsystem: "dev.smartium.tools", category: "iCloudSettings")
            let fileManager = FileManager.default

            guard let containerURL = fileManager.url(
                forUbiquityContainerIdentifier: "iCloud.dev.smartium.tools"
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
            let logger = Logger(subsystem: "dev.smartium.tools", category: "iCloudSettings")
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
            writeKeys(["limitimer": settings], label: "Limitimer")
        }.value
    }

    /// App preferences (`tabOrder`, `monitor`) as read from settings.json.
    nonisolated enum AppSettingsRead: Sendable {
        /// iCloud is off, or the file couldn't be read or decoded.
        case unavailable
        /// The file has neither key yet, e.g. on the first device to sync.
        case absent
        case found(StSettings)
    }

    nonisolated static func loadAppSettings() async -> AppSettingsRead {
        await Task.detached(priority: .utility) {
            let (data, readError) = readData()
            guard let data else {
                if let readError {
                    Logger(subsystem: "dev.smartium.tools", category: "iCloudSettings")
                        .error("Falha ao ler ajustes: \(readError.localizedDescription, privacy: .public)")
                }
                return .unavailable
            }
            guard !data.isEmpty else { return .absent }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .unavailable
            }
            guard object["tabOrder"] != nil || object["monitor"] != nil else { return .absent }
            guard let settings = try? JSONDecoder().decode(StSettings.self, from: data) else {
                return .unavailable
            }
            return .found(settings)
        }.value
    }

    nonisolated static func saveAppSettings(_ settings: StSettings) async {
        await Task.detached(priority: .utility) {
            writeKeys(["tabOrder": settings.tabOrder, "monitor": settings.monitor], label: "ajustes")
        }.value
    }

    /// Replaces only `values`' top-level keys and keeps every other key in
    /// settings.json, including keys edited by hand (except `obsoleteKeys`). Skips the write when the
    /// file can't be read, so a sync problem never overwrites the user's file.
    nonisolated private static func writeKeys(_ values: [String: any Encodable], label: String) {
        let logger = Logger(subsystem: "dev.smartium.tools", category: "iCloudSettings")
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.dev.smartium.tools"
        ) else {
            logger.notice("iCloud indisponível; \(label, privacy: .public) não foi salvo em settings.json.")
            return
        }

        // Also downloads the file when it exists only in iCloud.
        let (_, readError) = readData()
        if let readError {
            logger.error("Não foi possível atualizar \(label, privacy: .public): \(readError.localizedDescription, privacy: .public)")
            return
        }

        let settingsURL = containerURL.appendingPathComponent("Documents/settings.json")
        var coordinationError: NSError?
        var writeError: Error?

        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: settingsURL, options: [], error: &coordinationError) { writableURL in
            do {
                var object: [String: Any] = [:]
                if let data = try? Data(contentsOf: writableURL), !data.isEmpty {
                    guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    object = existing
                }
                for key in obsoleteKeys {
                    object[key] = nil
                }
                for (key, value) in values {
                    let encoded = try JSONEncoder().encode(value)
                    object[key] = try JSONSerialization.jsonObject(with: encoded, options: .fragmentsAllowed)
                }
                let data = try JSONSerialization.data(
                    withJSONObject: object,
                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                )
                try data.write(to: writableURL)
            } catch {
                writeError = error
            }
        }

        if let error = coordinationError ?? writeError {
            logger.error("Falha ao salvar \(label, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated private static func readDocument() -> (Document?, Error?) {
        let (data, readError) = readData()
        guard let data else { return (nil, readError) }
        guard !data.isEmpty else { return (Document(limitimer: nil), nil) }
        do {
            return (try JSONDecoder().decode(Document.self, from: data), nil)
        } catch {
            return (nil, error)
        }
    }

    /// The raw settings.json, retried while iCloud downloads it.
    /// `(nil, nil)` when iCloud is unavailable.
    nonisolated private static func readData() -> (Data?, Error?) {
        let fileManager = FileManager.default
        guard let containerURL = fileManager.url(
            forUbiquityContainerIdentifier: "iCloud.dev.smartium.tools"
        ) else {
            return (nil, nil)
        }

        let settingsURL = containerURL.appendingPathComponent("Documents/settings.json")
        if fileManager.isUbiquitousItem(at: settingsURL) {
            try? fileManager.startDownloadingUbiquitousItem(at: settingsURL)
        }

        for attempt in 0..<3 {
            var coordinationError: NSError?
            var result: Data?
            var readError: Error?

            NSFileCoordinator().coordinate(readingItemAt: settingsURL, options: [], error: &coordinationError) { readableURL in
                do {
                    result = try Data(contentsOf: readableURL)
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
