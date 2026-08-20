import Foundation

/// Observable state of macOS Internet Sharing.
public enum HotspotState: Equatable, Sendable {
    /// `bridge100` exists and is up -- sharing is actively bridging clients.
    case active(interface: String)
    /// Internet Sharing is turned off (no bridge interface present). This
    /// is the common, expected state, not an error.
    case inactive
    /// The bridge interface exists but couldn't be fully inspected (e.g.
    /// permission denied reading its state). Distinguished from `.inactive`
    /// so the UI doesn't claim "sharing is off" when it actually doesn't
    /// know.
    case indeterminate(reason: String)
}

/// Determines whether macOS Internet Sharing is currently active by
/// checking for the `bridge100` interface via `ifconfig`, which is the same
/// inspectable signal `system_profiler`/Network preferences ultimately
/// reflect -- no private frameworks involved.
public struct HotspotMonitor: Sendable {
    private let shell: ShellRunning
    private let bridgeInterface: String

    public init(shell: ShellRunning = ProcessShellRunner(), bridgeInterface: String = "bridge100") {
        self.shell = shell
        self.bridgeInterface = bridgeInterface
    }

    public func currentState() -> HotspotState {
        let output: String
        do {
            output = try shell.run("/sbin/ifconfig", arguments: [bridgeInterface])
        } catch ShellError.nonZeroExit {
            // `ifconfig <name>` exits non-zero when the interface doesn't
            // exist at all -- this is the normal "sharing is off" path.
            return .inactive
        } catch {
            return .indeterminate(reason: "Could not run ifconfig: \(error)")
        }
        return Self.parse(output, interfaceName: bridgeInterface)
    }

    /// Pure parser over `ifconfig bridge100` output, e.g.:
    ///   `bridge100: flags=8a63<UP,BROADCAST,SMART,RUNNING,...> mtu 1500`
    public static func parse(_ output: String, interfaceName: String) -> HotspotState {
        guard let firstLine = output.split(separator: "\n").first else {
            return .indeterminate(reason: "Empty ifconfig output")
        }
        guard firstLine.hasPrefix("\(interfaceName):") else {
            return .indeterminate(reason: "Unexpected ifconfig output")
        }
        guard let flagsRange = firstLine.range(of: "flags=") else {
            return .indeterminate(reason: "No flags field in ifconfig output")
        }
        let afterFlags = firstLine[flagsRange.upperBound...]
        guard let angleOpen = afterFlags.firstIndex(of: "<"),
              let angleClose = afterFlags.firstIndex(of: ">") else {
            return .indeterminate(reason: "Malformed flags field")
        }
        let flags = afterFlags[afterFlags.index(after: angleOpen)..<angleClose]
            .split(separator: ",").map(String.init)

        guard flags.contains("UP") else {
            return .inactive
        }
        return .active(interface: interfaceName)
    }
}
