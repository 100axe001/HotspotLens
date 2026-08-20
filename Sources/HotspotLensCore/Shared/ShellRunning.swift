import Foundation

/// Abstraction over "run a command, get its stdout" so every parser in this
/// package can be unit tested against fixture text instead of the real
/// system state. `ProcessShellRunner` is the only conforming type used at
/// runtime; tests inject `FixtureShellRunner` (see test target).
public protocol ShellRunning: Sendable {
    /// Runs `path` with `arguments` and returns captured stdout as a UTF-8
    /// string. Throws `ShellError.nonZeroExit` if the process exits non-zero,
    /// and `ShellError.launchFailed` if the executable can't be launched
    /// (e.g. missing on this system).
    func run(_ path: String, arguments: [String]) throws -> String
}

public enum ShellError: Error, Equatable {
    case launchFailed(path: String, underlying: String)
    case nonZeroExit(path: String, status: Int32, stderr: String)
}

/// Real implementation backed by `Process`. Only usable on Darwin.
public struct ProcessShellRunner: ShellRunning {
    public init() {}

    public func run(_ path: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed(path: path, underlying: error.localizedDescription)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrText = String(data: stderrData, encoding: .utf8) ?? ""
            throw ShellError.nonZeroExit(path: path, status: process.terminationStatus, stderr: stderrText)
        }

        return String(data: stdoutData, encoding: .utf8) ?? ""
    }
}
