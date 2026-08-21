import Foundation

/// Shared destination plumbing for commands that save server files locally
/// (`sounds download/share`, `exchanges download`). One set of rules for how
/// `--output` and `--overwrite` behave everywhere.

/// Resolve where a download should land: an explicit file path is used as-is,
/// an existing directory (or a trailing `/`) gets the default file name
/// appended, and no `--output` at all means the current directory.
func resolveDownloadDestination(output: String?, fileName: String) -> URL {
    let fileManager = FileManager.default

    if let output {
        var outputURL = URL(fileURLWithPath: output)

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: outputURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        {
            return outputURL.appendingPathComponent(fileName)
        }

        if output.hasSuffix("/") {
            outputURL.appendPathComponent(fileName)
            return outputURL
        }

        return outputURL
    } else {
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        return cwd.appendingPathComponent(fileName)
    }
}

/// Create the parent directory and enforce the `--overwrite` contract.
func ensureDownloadDestinationWritable(_ url: URL, overwrite: Bool) throws {
    let fileManager = FileManager.default
    let parent = url.deletingLastPathComponent()
    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

    if fileManager.fileExists(atPath: url.path) {
        guard overwrite else {
            throw failWithMessage(
                "Destination \(url.path) already exists. Use --overwrite to replace it.")
        }
        try fileManager.removeItem(at: url)
    }
}
