import XCTest
@testable import RaylineCore

final class TCPProbeTests: XCTestCase {

    func testOutOfRangePortReturnsNilWithoutTrapping() async {
        // 99999 does not fit in UInt16 — the probe must return nil rather than
        // trapping on the UInt16 conversion (regression for the previous
        // force-unwrapped NWEndpoint.Port construction).
        let result = await TCPProbe.measure(host: "127.0.0.1", port: 99999, timeout: 0.2)
        XCTAssertNil(result)
    }

    func testNegativePortReturnsNil() async {
        let result = await TCPProbe.measure(host: "127.0.0.1", port: -1, timeout: 0.2)
        XCTAssertNil(result)
    }
}
