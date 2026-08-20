import XCTest
@testable import HotspotLensCore

final class HotspotMonitorTests: XCTestCase {
    func testActiveWhenUpFlagPresent() {
        let output = "bridge100: flags=8a63<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500\n\toptions=3<RXCSUM,TXCSUM>"
        let state = HotspotMonitor.parse(output, interfaceName: "bridge100")
        XCTAssertEqual(state, .active(interface: "bridge100"))
    }

    func testInactiveWhenUpFlagAbsent() {
        let output = "bridge100: flags=8802<BROADCAST,SIMPLEX,MULTICAST> mtu 1500"
        let state = HotspotMonitor.parse(output, interfaceName: "bridge100")
        XCTAssertEqual(state, .inactive)
    }

    func testIndeterminateOnEmptyOutput() {
        let state = HotspotMonitor.parse("", interfaceName: "bridge100")
        if case .indeterminate = state {
            // expected
        } else {
            XCTFail("Expected .indeterminate, got \(state)")
        }
    }

    func testInactiveWhenInterfaceMissing() {
        let shell = FixtureShellRunner()
        shell.stub("/sbin/ifconfig", nonZeroExit: 1, stderr: "ifconfig: interface bridge100 does not exist")
        let monitor = HotspotMonitor(shell: shell)
        XCTAssertEqual(monitor.currentState(), .inactive)
    }
}
