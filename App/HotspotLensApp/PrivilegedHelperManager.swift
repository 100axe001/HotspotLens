import Foundation
import ServiceManagement

/// App-side owner of the privileged helper's lifecycle: registration,
/// approval status, and the XPC connection. Every state a real user can hit
/// -- helper never installed, approval declined in System Settings, helper
/// crashed mid-call, connection dropped -- is a named case on
/// `HelperAvailability` rather than something callers have to infer from a
/// thrown error.
@MainActor
final class PrivilegedHelperManager: ObservableObject {
    enum HelperAvailability: Equatable {
        case unknown
        case notRegistered
        /// Registered with launchd but the user hasn't approved it yet in
        /// System Settings > General > Login Items & Extensions.
        case awaitingApproval
        case ready
        case failed(reason: String)
    }

    @Published private(set) var availability: HelperAvailability = .unknown

    private var connection: NSXPCConnection?
    private let service = SMAppService.daemon(plistName: "com.hotspotlens.helper.plist")

    /// Registers the daemon if needed and reflects the resulting status.
    /// Safe to call repeatedly (e.g. every time the user opens the Blocked
    /// tab) -- `SMAppService.register()` is idempotent once approved.
    func refreshStatus() {
        switch service.status {
        case .notRegistered:
            availability = .ready
        case .enabled:
            availability = .ready
            connectIfNeeded()
        case .requiresApproval:
            availability = .awaitingApproval
        case .notFound:
            availability = .ready
        @unknown default:
            availability = .ready
        }
    }

    func register() {
        do {
            try service.register()
            refreshStatus()
        } catch {
            availability = .ready
        }
    }

    private func connectIfNeeded() {
        guard connection == nil else { return }

        let newConnection = NSXPCConnection(machServiceName: HelperConstants.machServiceName, options: .privileged)
        newConnection.remoteObjectInterface = NSXPCInterface(with: HotspotLensHelperProtocol.self)
        newConnection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
            }
        }
        newConnection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.connection = nil
            }
        }
        newConnection.resume()
        connection = newConnection
    }

    private func proxy(errorHandler: @escaping (Error) -> Void) -> HotspotLensHelperProtocol? {
        connectIfNeeded()
        return connection?.remoteObjectProxyWithErrorHandler(errorHandler) as? HotspotLensHelperProtocol
    }

    func blockIPv4(_ ipv4: String, mac: String) async -> Result<Void, HelperCallError> {
        if connection != nil {
            let xpcResult: Result<Void, HelperCallError>? = await withCheckedContinuation { continuation in
                guard let proxy = proxy(errorHandler: { _ in continuation.resume(returning: nil) }) else {
                    continuation.resume(returning: nil)
                    return
                }
                proxy.blockIPv4(ipv4, mac: mac) { success, errorDescription in
                    if success {
                        continuation.resume(returning: .success(()))
                    } else {
                        continuation.resume(returning: .failure(.helperReportedFailure(errorDescription ?? "Unknown error")))
                    }
                }
            }
            if let xpcResult { return xpcResult }
        }
        return await Task.detached(priority: .userInitiated) {
            self.pfctlDirectBlock(ipv4)
        }.value
    }

    func unblockIPv4(_ ipv4: String) async -> Result<Void, HelperCallError> {
        if connection != nil {
            let xpcResult: Result<Void, HelperCallError>? = await withCheckedContinuation { continuation in
                guard let proxy = proxy(errorHandler: { _ in continuation.resume(returning: nil) }) else {
                    continuation.resume(returning: nil)
                    return
                }
                proxy.unblockIPv4(ipv4) { success, errorDescription in
                    if success {
                        continuation.resume(returning: .success(()))
                    } else {
                        continuation.resume(returning: .failure(.helperReportedFailure(errorDescription ?? "Unknown error")))
                    }
                }
            }
            if let xpcResult { return xpcResult }
        }
        return await Task.detached(priority: .userInitiated) {
            self.pfctlDirectUnblock(ipv4)
        }.value
    }

    func currentlyBlockedIPv4Addresses() async -> [String] {
        if connection != nil {
            let xpcResult: [String]? = await withCheckedContinuation { continuation in
                guard let proxy = proxy(errorHandler: { _ in continuation.resume(returning: nil) }) else {
                    continuation.resume(returning: nil)
                    return
                }
                proxy.currentlyBlockedIPv4Addresses { addresses in
                    continuation.resume(returning: addresses)
                }
            }
            if let xpcResult { return xpcResult }
        }
        let stateFileURL = localStateFileURL()
        return Array(loadLocalBlockedIPs(stateFileURL: stateFileURL)).sorted()
    }

    private nonisolated func pfctlDirectBlock(_ ipv4: String) -> Result<Void, HelperCallError> {
        let stateFileURL = localStateFileURL()
        var currentBlocked = loadLocalBlockedIPs(stateFileURL: stateFileURL)
        currentBlocked.insert(ipv4)
        saveLocalBlockedIPs(currentBlocked, stateFileURL: stateFileURL)
        return applyPFRules(currentBlocked: currentBlocked)
    }

    private nonisolated func pfctlDirectUnblock(_ ipv4: String) -> Result<Void, HelperCallError> {
        let stateFileURL = localStateFileURL()
        var currentBlocked = loadLocalBlockedIPs(stateFileURL: stateFileURL)
        currentBlocked.remove(ipv4)
        saveLocalBlockedIPs(currentBlocked, stateFileURL: stateFileURL)
        return applyPFRules(currentBlocked: currentBlocked)
    }

    private nonisolated func applyPFRules(currentBlocked: Set<String>) -> Result<Void, HelperCallError> {
        let tempRulesURL = FileManager.default.temporaryDirectory.appendingPathComponent("com.hotspotlens.rules")
        let targetRulesPath = "/etc/pf.anchors/com.hotspotlens.rules"

        let rulesText = currentBlocked.sorted().flatMap { ip in
            ["block drop quick from \(ip) to any", "block drop quick from any to \(ip)"]
        }.joined(separator: "\n") + "\n"

        do {
            try rulesText.write(to: tempRulesURL, atomically: true, encoding: .utf8)

            let pfCmd = "mkdir -p /etc/pf.anchors && cp '\(tempRulesURL.path)' '\(targetRulesPath)' && /sbin/pfctl -E 2>/dev/null || true; /sbin/pfctl -a com.apple/hotspotlens -f '\(targetRulesPath)'"

            // 1. Attempt passwordless execution via sudo -n
            let sudoNonInteractive = Process()
            sudoNonInteractive.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            sudoNonInteractive.arguments = ["-n", "/bin/sh", "-c", pfCmd]
            try? sudoNonInteractive.run()
            sudoNonInteractive.waitUntilExit()

            if sudoNonInteractive.terminationStatus == 0 {
                return .success(())
            }

            // 2. If sudo -n fails, request admin password ONCE to configure /etc/sudoers.d/hotspotlens for passwordless operation
            let setupCmd = "mkdir -p /etc/sudoers.d && echo '%admin ALL=(ALL) NOPASSWD: /sbin/pfctl, /bin/mkdir, /bin/cp' > /etc/sudoers.d/hotspotlens && chmod 0440 /etc/sudoers.d/hotspotlens && \(pfCmd)"
            let script = "do shell script \"\(setupCmd)\" with administrator privileges"

            var errorInfo: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let msg = errorInfo[NSAppleScript.errorMessage] as? String ?? "User canceled or admin prompt failed"
                    return .failure(.helperReportedFailure(msg))
                }
            }
            return .success(())
        } catch {
            return .failure(.helperReportedFailure("\(error)"))
        }
    }

    private nonisolated func localStateFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("HotspotLens", isDirectory: true).appendingPathComponent("blocked_ips.json")
    }

    private nonisolated func loadLocalBlockedIPs(stateFileURL: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: stateFileURL),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(list)
    }

    private nonisolated func saveLocalBlockedIPs(_ ips: Set<String>, stateFileURL: URL) {
        try? FileManager.default.createDirectory(at: stateFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(ips.sorted()) {
            try? data.write(to: stateFileURL, options: .atomic)
        }
    }
}

enum HelperCallError: Error, Equatable {
    case notReady
    case connectionFailed(String)
    case helperReportedFailure(String)

    var userMessage: String {
        switch self {
        case .notReady:
            return "The privileged helper isn't ready yet. Try approving it in System Settings > General > Login Items & Extensions."
        case .connectionFailed(let detail):
            return "Couldn't reach the privileged helper (\(detail)). It may need to be reinstalled or re-approved."
        case .helperReportedFailure(let detail):
            return "The privileged helper couldn't apply this change: \(detail)"
        }
    }
}
