import Foundation

/// XPC contract between HotspotLens.app and its privileged helper daemon.
///
/// This file is compiled into *both* the main app target and the
/// `HotspotLensHelper` daemon target (see `project.yml`) so the two never
/// drift out of sync. Nothing on this protocol grants the app itself any
/// privilege -- every privileged action (writing pf rules) happens only
/// inside the separately-signed, separately-launched helper process, which
/// verifies the caller's code signature before doing anything
/// (`HelperListenerDelegate` in the helper target).
///
/// Blocking operates on the device's *current IPv4 address*, not its MAC --
/// see README "Tech Stack" for why (macOS `pf` filters at the IP layer).
/// The `mac` parameter on block/unblock is carried through only for the
/// helper's own audit log, so a human auditing `/Library/Application
/// Support/HotspotLensHelper/audit.log` can see which device an IP-based
/// rule was meant for.
@objc public protocol HotspotLensHelperProtocol {
    /// Liveness/authorization check; also lets the app confirm the helper
    /// it's talking to is the one it expects before relying on it.
    func ping(reply: @escaping (Bool) -> Void)

    /// Installs a `pf` rule dropping all traffic to/from `ipv4`.
    /// `reply` is `(success, errorDescription)`.
    func blockIPv4(_ ipv4: String, mac: String, reply: @escaping (Bool, String?) -> Void)

    /// Removes a previously-installed block for `ipv4`, if any.
    func unblockIPv4(_ ipv4: String, reply: @escaping (Bool, String?) -> Void)

    /// Currently-blocked IPv4 addresses, as tracked by the helper's own pf
    /// anchor state (source of truth for "is this rule actually active",
    /// independent of what the app *thinks* it asked for).
    func currentlyBlockedIPv4Addresses(reply: @escaping ([String]) -> Void)
}

public enum HelperConstants {
    public static let machServiceName = "com.hotspotlens.helper"
    public static let daemonLabel = "com.hotspotlens.helper"
    /// Designated-requirement string the helper uses to verify a connecting
    /// client is genuinely the signed HotspotLens.app, not an impostor
    /// process reusing the mach service name. Filled in with the real Team
    /// ID at signing time -- see README "Signing & Notarization".
    public static let expectedClientRequirement =
        "anchor apple generic and identifier \"com.hotspotlens.app\" and certificate leaf[subject.OU] = \"$(DEVELOPMENT_TEAM)\""
}
