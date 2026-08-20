import Foundation
import Security

/// Entry point for the `com.hotspotlens.helper` daemon, launched by
/// `launchd` via `SMAppService.daemon`. This process runs as root; its only
/// job is to listen on the mach service, verify each connecting client's
/// code signature, and expose `HotspotLensHelperProtocol`. It has no UI, no
/// network access, and reads nothing except what's needed to manage its pf
/// anchor.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard Self.callerSatisfiesRequirement(newConnection, requirement: HelperConstants.expectedClientRequirement) else {
            NSLog("HotspotLensHelper: rejected connection from unverified client (pid \(newConnection.processIdentifier))")
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: HotspotLensHelperProtocol.self)
        newConnection.exportedObject = HelperService()
        newConnection.resume()
        return true
    }

    /// Confirms the connecting process is signed as the genuine
    /// HotspotLens.app main bundle before trusting anything it asks for.
    /// This is what makes it safe for the app to hand the helper an IP to
    /// block: an unrelated process on the machine can't just open the same
    /// mach service and start issuing commands.
    private static func callerSatisfiesRequirement(_ connection: NSXPCConnection, requirement: String) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: connection.processIdentifier] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else {
            return false
        }

        var secRequirement: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &secRequirement) == errSecSuccess,
              let secRequirement
        else {
            return false
        }

        return SecCodeCheckValidity(code, [], secRequirement) == errSecSuccess
    }
}

let delegate = HelperListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
