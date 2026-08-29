import Foundation
@testable import GitMenuBar
import XCTest

final class MockURLProtocol: URLProtocol {
    private static let requestHandlerLock = NSLock()
    private nonisolated(unsafe) static var storedRequestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        get {
            requestHandlerLock.lock()
            defer { requestHandlerLock.unlock() }
            return storedRequestHandler
        }
        set {
            requestHandlerLock.lock()
            storedRequestHandler = newValue
            requestHandlerLock.unlock()
        }
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            let error = NSError(domain: "MockURLProtocol", code: 0, userInfo: [NSLocalizedDescriptionKey: "Missing request handler"])
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeMockedURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

func makeMockHTTPResponse(for request: URLRequest) throws -> HTTPURLResponse {
    let url = try XCTUnwrap(request.url)
    return try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
}

func requestBodyData(from request: URLRequest) -> Data {
    if let body = request.httpBody {
        return body
    }

    guard let bodyStream = request.httpBodyStream else {
        return Data()
    }

    bodyStream.open()
    defer { bodyStream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while bodyStream.hasBytesAvailable {
        let bytesRead = bodyStream.read(&buffer, maxLength: buffer.count)
        if bytesRead <= 0 {
            break
        }
        data.append(buffer, count: bytesRead)
    }
    return data
}

let gitRepoPathLock = NSLock()

/// Thread-safe box for capturing request payloads from `MockURLProtocol` handlers
/// that run on background `URLSession` threads.
final class PromptCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = ""

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ text: String) {
        lock.lock()
        storedValue = text
        lock.unlock()
    }

    func clear() {
        set("")
    }
}

/// Thread-safe list capture for handlers that record multiple request payloads.
final class PromptListCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedValues
    }

    func append(_ text: String) {
        lock.lock()
        storedValues.append(text)
        lock.unlock()
    }
}

@discardableResult
func runGit(_ args: [String], in directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = directory

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    if process.terminationStatus != 0 {
        throw NSError(domain: "GitTest", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output])
    }

    return output
}

func withGitRepoPath<T>(_ path: String, execute: () throws -> T) rethrows -> T {
    gitRepoPathLock.lock()
    defer { gitRepoPathLock.unlock() }

    let defaults = UserDefaults.standard
    let previous = defaults.string(forKey: AppPreferences.Keys.gitRepoPath)
    defaults.set(path, forKey: AppPreferences.Keys.gitRepoPath)

    defer {
        if let previous {
            defaults.set(previous, forKey: AppPreferences.Keys.gitRepoPath)
        } else {
            defaults.removeObject(forKey: AppPreferences.Keys.gitRepoPath)
        }
    }

    return try execute()
}

@MainActor
func withGitRepoPath<T>(_ path: String, execute: () async throws -> T) async rethrows -> T {
    let defaults = UserDefaults.standard
    let previous = defaults.string(forKey: AppPreferences.Keys.gitRepoPath)
    defaults.set(path, forKey: AppPreferences.Keys.gitRepoPath)

    defer {
        if let previous {
            defaults.set(previous, forKey: AppPreferences.Keys.gitRepoPath)
        } else {
            defaults.removeObject(forKey: AppPreferences.Keys.gitRepoPath)
        }
    }

    return try await execute()
}

extension XCTestCase {
    func temporaryTestPath(testName: String) -> URL {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitMenuBarTests", isDirectory: true)
            .appendingPathComponent(testName + "-" + UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: path)
        }
        return path
    }

    func makeTemporaryTestDirectory(testName: String) throws -> URL {
        let path = temporaryTestPath(testName: testName)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    func makeIsolatedTestDefaults(name: String) throws -> UserDefaults {
        let suiteName = name + "-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func addTemporaryGitWorktreeCleanup(_ path: URL, repositoryURL: URL) {
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: repositoryURL.path) {
                try? runGit(["worktree", "remove", "--force", path.path], in: repositoryURL)
            }
            try? FileManager.default.removeItem(at: path)
        }
    }

    func createTemporaryGitRepository(testName: String) throws -> URL {
        let tempRoot = try makeTemporaryTestDirectory(testName: testName)

        try runGit(["init"], in: tempRoot)
        try runGit(["config", "user.email", "test@example.com"], in: tempRoot)
        try runGit(["config", "user.name", "GitMenuBar Tests"], in: tempRoot)

        let baseFile = tempRoot.appendingPathComponent("README.md")
        try "base\n".write(to: baseFile, atomically: true, encoding: .utf8)

        try runGit(["add", "."], in: tempRoot)
        try runGit(["commit", "-m", "chore: initial"], in: tempRoot)

        return tempRoot
    }
}
