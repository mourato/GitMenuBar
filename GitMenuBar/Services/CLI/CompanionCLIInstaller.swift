import Foundation

/// Installs the bundled `gitmenubar` binary onto the user's PATH via `~/.local/bin`.
/// Search order mirrors `scripts/install-cli.sh`, with the running app bundle first for Settings.
enum CompanionCLIInstaller {
    enum InstallError: LocalizedError {
        case binaryNotFound
        case filesystemError(String)

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                return """
                Could not find gitmenubar in GitMenuBar.app. Build or install the app first, \
                then try again or run make install-cli from the project.
                """
            case let .filesystemError(message):
                return message
            }
        }
    }

    enum InstallResult: Equatable {
        case installed(destination: URL, source: URL)
        case alreadyInstalled(destination: URL, source: URL)
    }

    private static let appBundleName = "GitMenuBar.app"
    private static let bundledCLIName = "gitmenubar"

    static func appBundleCandidates(projectRoot: URL? = nil) -> [URL] {
        var candidates: [URL] = [Bundle.main.bundleURL]

        if let root = projectRoot {
            let distDirectory = root.appendingPathComponent("dist", isDirectory: true)
            if let distApps = try? FileManager.default.contentsOfDirectory(
                at: distDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for app in distApps where app.pathExtension == "app" {
                    candidates.append(app)
                }
            }

            candidates.append(URL(fileURLWithPath: "/Applications/\(appBundleName)", isDirectory: true))
            candidates.append(
                root.appendingPathComponent(".xcode-build/Build/Products/Release/\(appBundleName)", isDirectory: true)
            )
            candidates.append(
                root.appendingPathComponent(".xcode-build/Build/Products/Debug/\(appBundleName)", isDirectory: true)
            )
        } else {
            candidates.append(URL(fileURLWithPath: "/Applications/\(appBundleName)", isDirectory: true))
        }

        return candidates
    }

    static func locateBundledCLI(projectRoot: URL? = nil) -> URL? {
        for appBundle in appBundleCandidates(projectRoot: projectRoot) {
            let cli = appBundle
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent(bundledCLIName, isDirectory: false)
            if FileManager.default.isExecutableFile(atPath: cli.path) {
                return cli
            }
        }
        return nil
    }

    static func install(projectRoot: URL? = nil) throws -> InstallResult {
        guard let source = locateBundledCLI(projectRoot: projectRoot) else {
            throw InstallError.binaryNotFound
        }

        let fileManager = FileManager.default
        let installDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin", isDirectory: true)
        let destination = installDirectory.appendingPathComponent(bundledCLIName, isDirectory: false)

        do {
            try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        } catch {
            throw InstallError.filesystemError("Could not create \(installDirectory.path): \(error.localizedDescription)")
        }

        if fileManager.fileExists(atPath: destination.path) {
            if let existingTarget = try? fileManager.destinationOfSymbolicLink(atPath: destination.path),
               URL(fileURLWithPath: existingTarget).standardizedFileURL == source.standardizedFileURL {
                return .alreadyInstalled(destination: destination, source: source)
            }

            do {
                try fileManager.removeItem(at: destination)
            } catch {
                throw InstallError.filesystemError("Could not replace \(destination.path): \(error.localizedDescription)")
            }
        }

        do {
            try fileManager.createSymbolicLink(at: destination, withDestinationURL: source)
        } catch {
            throw InstallError.filesystemError("Could not install CLI: \(error.localizedDescription)")
        }

        return .installed(destination: destination, source: source)
    }

    static func uninstall() throws {
        let destination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/\(bundledCLIName)", isDirectory: false)
        guard FileManager.default.fileExists(atPath: destination.path) else { return }

        do {
            try FileManager.default.removeItem(at: destination)
        } catch {
            throw InstallError.filesystemError("Could not remove \(destination.path): \(error.localizedDescription)")
        }
    }
}
