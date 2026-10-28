//
//  ICloudSettings.swift
//  My Game
//

import Foundation
import OSLog

enum ICloudSettings {
    nonisolated private struct Document: Decodable {
        let appearance: AppearanceSettings?
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
}
