import Foundation
import SQLite3

/// Reads Cursor IDE session tokens from the local VS Code SQLite state database.
/// Tokens are read fresh on each call and must never be persisted by callers.
enum CursorAuthTokenReader {
    static let accessTokenKey = "cursorAuth/accessToken"

    struct Configuration: Sendable {
        let databaseURL: URL
        let tempDirectory: URL

        init(
            databaseURL: URL? = nil,
            tempDirectory: URL? = nil
        ) {
            self.databaseURL = databaseURL ?? CursorAuthTokenReader.defaultDatabaseURL()
            self.tempDirectory = tempDirectory ?? FileManager.default.temporaryDirectory
        }
    }

    static func defaultDatabaseURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    static func readAccessToken(configuration: Configuration = Configuration()) -> String? {
        guard FileManager.default.fileExists(atPath: configuration.databaseURL.path) else {
            return nil
        }

        if let token = queryAccessToken(at: configuration.databaseURL), !token.isEmpty {
            return token
        }

        let copiedURL = configuration.tempDirectory
            .appendingPathComponent("gitmenubar-cursor-state-\(UUID().uuidString).vscdb")
        defer { removeCopiedDatabaseBundle(at: copiedURL) }

        guard copyDatabaseBundle(
            from: configuration.databaseURL,
            to: copiedURL
        ) else {
            return nil
        }

        guard let token = queryAccessToken(at: copiedURL), !token.isEmpty else {
            return nil
        }
        return token
    }

    private static func queryAccessToken(at databaseURL: URL) -> String? {
        var database: OpaquePointer?
        defer {
            if database != nil {
                sqlite3_close(database)
            }
        }

        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return nil
        }

        let query = "SELECT value FROM ItemTable WHERE key = ?"
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        let bindResult = accessTokenKey.withCString { keyPointer in
            sqlite3_bind_text(statement, 1, keyPointer, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        guard bindResult == SQLITE_OK else {
            return nil
        }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0)
        else {
            return nil
        }

        return String(cString: cString)
    }

    private static func copyDatabaseBundle(from source: URL, to destination: URL) -> Bool {
        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            return false
        }

        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: source.path + suffix)
            guard FileManager.default.fileExists(atPath: sidecar.path) else { continue }
            let copiedSidecar = URL(fileURLWithPath: destination.path + suffix)
            try? FileManager.default.removeItem(at: copiedSidecar)
            try? FileManager.default.copyItem(at: sidecar, to: copiedSidecar)
        }

        return true
    }

    private static func removeCopiedDatabaseBundle(at databaseURL: URL) {
        for path in [databaseURL.path, databaseURL.path + "-wal", databaseURL.path + "-shm"] {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
