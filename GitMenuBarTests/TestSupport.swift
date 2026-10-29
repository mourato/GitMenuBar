import Foundation
@testable import GitMenuBar
import Observation
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

func makeIsolatedGitEnvironment(inheriting environment: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
    var isolated = environment

    isolated.removeValue(forKey: "GIT_DIR")
    isolated.removeValue(forKey: "GIT_WORK_TREE")
    isolated.removeValue(forKey: "GIT_INDEX_FILE")
    isolated.removeValue(forKey: "GIT_OBJECT_DIRECTORY")
    isolated.removeValue(forKey: "GIT_ALTERNATE_OBJECT_DIRECTORIES")
    isolated.removeValue(forKey: "GIT_COMMON_DIR")
    isolated.removeValue(forKey: "GIT_TEMPLATE_DIR")
    isolated.removeValue(forKey: "GIT_CONFIG")
    isolated.removeValue(forKey: "GIT_CONFIG_PARAMETERS")

    isolated.removeValue(forKey: "GIT_CONFIG_COUNT")
    for key in Array(isolated.keys) where key.hasPrefix("GIT_CONFIG_KEY_") || key.hasPrefix("GIT_CONFIG_VALUE_") {
        isolated.removeValue(forKey: key)
    }

    isolated["GIT_CONFIG_GLOBAL"] = "/dev/null"
    isolated["GIT_CONFIG_SYSTEM"] = "/dev/null"
    isolated["GIT_CONFIG_NOSYSTEM"] = "1"
    isolated["GIT_TERMINAL_PROMPT"] = "0"
    isolated["GIT_AUTHOR_NAME"] = "GitMenuBar Tests"
    isolated["GIT_AUTHOR_EMAIL"] = "test@example.com"
    isolated["GIT_COMMITTER_NAME"] = "GitMenuBar Tests"
    isolated["GIT_COMMITTER_EMAIL"] = "test@example.com"

    return isolated
}

@discardableResult
func runGit(_ args: [String], in directory: URL, environment: [String: String]? = nil) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = directory
    process.environment = environment ?? makeIsolatedGitEnvironment()

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

/// Re-evaluates `condition` under observation tracking, so a change made after the
/// check always re-runs it. Checking outside tracking could miss a background change.
@MainActor
private final class ObservedConditionWatcher {
    private let condition: @MainActor () -> Bool
    private let satisfied: XCTestExpectation
    private var isDone = false

    init(condition: @escaping @MainActor () -> Bool, satisfied: XCTestExpectation) {
        self.condition = condition
        self.satisfied = satisfied
    }

    func observe() {
        guard !isDone else { return }
        let isSatisfied = withObservationTracking {
            condition()
        } onChange: {
            Task { @MainActor in self.observe() }
        }
        if isSatisfied {
            isDone = true
            satisfied.fulfill()
        }
    }
}

extension XCTestCase {
    /// Waits for `condition` by observing `@Observable` reads instead of polling.
    /// Fails the test when the condition does not hold within `timeout`.
    @MainActor
    func waitForObservedCondition(
        timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let satisfied = expectation(description: "observed condition")
        ObservedConditionWatcher(condition: condition, satisfied: satisfied).observe()
        await fulfillment(of: [satisfied], timeout: timeout)
    }

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

        try runGit(["init", "-b", "main"], in: tempRoot)
        try runGit(["config", "user.email", "test@example.com"], in: tempRoot)
        try runGit(["config", "user.name", "GitMenuBar Tests"], in: tempRoot)

        let baseFile = tempRoot.appendingPathComponent("README.md")
        try "base\n".write(to: baseFile, atomically: true, encoding: .utf8)

        try runGit(["add", "."], in: tempRoot)
        try runGit(["commit", "-m", "chore: initial"], in: tempRoot)

        return tempRoot
    }
}
