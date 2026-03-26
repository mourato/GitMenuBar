import Foundation
@testable import GitMenuBar
import XCTest

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

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

let gitRepoPathLock = NSLock()

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

func withGitRepoPath<T>(_ path: String, execute: () async throws -> T) async rethrows -> T {
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

    return try await execute()
}

func createTemporaryGitRepository(testName: String) throws -> URL {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("GitMenuBarTests")
        .appendingPathComponent(testName + "-" + UUID().uuidString)

    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

    try runGit(["init"], in: tempRoot)
    try runGit(["config", "user.email", "test@example.com"], in: tempRoot)
    try runGit(["config", "user.name", "GitMenuBar Tests"], in: tempRoot)

    let baseFile = tempRoot.appendingPathComponent("README.md")
    try "base\n".write(to: baseFile, atomically: true, encoding: .utf8)

    try runGit(["add", "."], in: tempRoot)
    try runGit(["commit", "-m", "chore: initial"], in: tempRoot)

    return tempRoot
}
