#if os(macOS)
    import Common
    import CryptoKit
    import Foundation

    actor SpatialSimulationCache {
        static let shared = SpatialSimulationCache()

        func download(
            soundFile: String,
            server: CreatureServerClient = .shared
        ) async throws -> URL {
            let remoteURL: URL
            switch server.getSoundURL(soundFile) {
            case .success(let url):
                remoteURL = url
            case .failure(let error):
                throw error
            }

            var request = server.createConfiguredURLRequest(for: remoteURL)
            request.cachePolicy = .reloadRevalidatingCacheData
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200...299).contains(httpResponse.statusCode)
            else {
                throw SpatialSimulationCacheError.downloadFailed
            }

            let cacheDirectory = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            .appendingPathComponent("SpatialStageSimulation", isDirectory: true)
            try FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )

            let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            let destination = cacheDirectory.appendingPathComponent(digest + ".wav")
            let staged = cacheDirectory.appendingPathComponent(UUID().uuidString + ".download")
            try FileManager.default.copyItem(at: temporaryURL, to: staged)
            defer {
                try? FileManager.default.removeItem(at: staged)
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staged)
            } else {
                try FileManager.default.moveItem(at: staged, to: destination)
            }
            return destination
        }
    }

    enum SpatialSimulationCacheError: LocalizedError {
        case downloadFailed

        var errorDescription: String? {
            "The server did not return the requested simulation WAV."
        }
    }
#endif
