//
//  ICloudSettings.swift
//  My Game
//

import Foundation
import OSLog

enum ICloudSettings {
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
