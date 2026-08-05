@testable import GitMenuBar
import SQLite3
import XCTest

final class CursorAuthTokenReaderTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CursorAuthTokenReaderTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }

    func testReadAccessTokenReturnsStoredJWT() throws {
        let databaseURL = tempDirectory.appendingPathComponent("state.vscdb")
        let token = Self.fixtureJWT(sub: "auth0|user_redacted_123")
        try Self.createFixtureDatabase(at: databaseURL, accessToken: token)

        let configuration = CursorAuthTokenReader.Configuration(
            databaseURL: databaseURL,
            tempDirectory: tempDirectory
        )

        XCTAssertEqual(CursorAuthTokenReader.readAccessToken(configuration: configuration), token)
    }

    func testReadAccessTokenReturnsNilWhenKeyMissing() throws {
        let databaseURL = tempDirectory.appendingPathComponent("missing-key.vscdb")
        try Self.createFixtureDatabase(at: databaseURL, accessToken: nil)

        let configuration = CursorAuthTokenReader.Configuration(
            databaseURL: databaseURL,
            tempDirectory: tempDirectory
        )

        XCTAssertNil(CursorAuthTokenReader.readAccessToken(configuration: configuration))
    }

    func testReadAccessTokenReturnsNilWhenDatabaseMissing() {
        let databaseURL = tempDirectory.appendingPathComponent("does-not-exist.vscdb")
        let configuration = CursorAuthTokenReader.Configuration(
            databaseURL: databaseURL,
            tempDirectory: tempDirectory
        )

        XCTAssertNil(CursorAuthTokenReader.readAccessToken(configuration: configuration))
    }

    func testReadAccessTokenUsesInjectablePath() throws {
        let databaseURL = tempDirectory.appendingPathComponent("injectable.vscdb")
        let token = Self.fixtureJWT(sub: "auth0|injectable_user")
        try Self.createFixtureDatabase(at: databaseURL, accessToken: token)

        let configuration = CursorAuthTokenReader.Configuration(databaseURL: databaseURL)
        XCTAssertEqual(CursorAuthTokenReader.readAccessToken(configuration: configuration), token)
    }

    private static func createFixtureDatabase(at url: URL, accessToken: String?) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw NSError(domain: "CursorAuthTokenReaderTests", code: 1)
        }
        defer { sqlite3_close(database) }

        guard sqlite3_exec(database, "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT)", nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "CursorAuthTokenReaderTests", code: 2)
        }

        guard let accessToken else { return }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "INSERT INTO ItemTable (key, value) VALUES (?, ?)",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw NSError(domain: "CursorAuthTokenReaderTests", code: 3)
        }
        defer { sqlite3_finalize(statement) }

        let key = CursorAuthTokenReader.accessTokenKey
        _ = key.withCString { keyPointer in
            sqlite3_bind_text(statement, 1, keyPointer, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        _ = accessToken.withCString { valuePointer in
            sqlite3_bind_text(statement, 2, valuePointer, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw NSError(domain: "CursorAuthTokenReaderTests", code: 4)
        }
    }

    private static func fixtureJWT(sub: String) -> String {
        let header = Data("{}".utf8).base64EncodedString()
        guard let payloadData = try? JSONSerialization.data(withJSONObject: ["sub": sub]) else {
            return "invalid.invalid.invalid"
        }
        let payloadPart = payloadData.base64EncodedString()
        return "\(header).\(payloadPart).signature"
    }
}
