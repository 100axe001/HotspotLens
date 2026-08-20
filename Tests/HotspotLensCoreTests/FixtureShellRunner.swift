import Foundation
@testable import HotspotLensCore

/// Injectable `ShellRunning` for tests: returns canned output per
/// executable path instead of running real commands, and can also simulate
/// launch/exit failures.
final class FixtureShellRunner: ShellRunning, @unchecked Sendable {
    enum Response {
        case output(String)
        case nonZeroExit(status: Int32, stderr: String)
        case launchFailed(String)
    }

    private var responses: [String: Response] = [:]

    func stub(_ path: String, output: String) {
        responses[path] = .output(output)
    }

    func stub(_ path: String, nonZeroExit status: Int32, stderr: String = "") {
        responses[path] = .nonZeroExit(status: status, stderr: stderr)
    }

    func stub(_ path: String, launchFailed message: String) {
        responses[path] = .launchFailed(message)
    }

    func run(_ path: String, arguments: [String]) throws -> String {
        switch responses[path] {
        case .output(let text):
            return text
        case .nonZeroExit(let status, let stderr):
            throw ShellError.nonZeroExit(path: path, status: status, stderr: stderr)
        case .launchFailed(let message):
            throw ShellError.launchFailed(path: path, underlying: message)
        case .none:
            throw ShellError.launchFailed(path: path, underlying: "no stub configured")
        }
    }
}

enum FixtureLoader {
    static func text(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: nil)
        else {
            fatalError("Missing fixture: \(name)")
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }
}
