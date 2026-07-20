import XCTest
@testable import RaylineCore

/// Covers the SOCKS5 byte encoding, which is the part that can be wrong in a way
/// no integration run would explain clearly. The networking around it opens a
/// real connection and is verified by hand.
final class SocksProbeTests: XCTestCase {

    func testGreetingOffersOnlyNoAuthentication() {
        XCTAssertEqual(Array(SocksProbe.greeting()), [0x05, 0x01, 0x00])
    }

    func testGreetingAcceptedOnlyForSocks5NoAuth() {
        XCTAssertTrue(SocksProbe.isGreetingAccepted(Data([0x05, 0x00])))
        XCTAssertFalse(SocksProbe.isGreetingAccepted(Data([0x05, 0xFF])), "0xFF means no acceptable method")
        XCTAssertFalse(SocksProbe.isGreetingAccepted(Data([0x04, 0x00])), "Wrong protocol version")
        XCTAssertFalse(SocksProbe.isGreetingAccepted(Data([0x05])), "Truncated reply")
        XCTAssertFalse(SocksProbe.isGreetingAccepted(Data()))
    }

    func testConnectRequestEncodesDomainAndPort() throws {
        let request = try XCTUnwrap(SocksProbe.connectRequest(host: "example.com", port: 80))
        let bytes = Array(request)

        XCTAssertEqual(bytes[0], 0x05, "version")
        XCTAssertEqual(bytes[1], 0x01, "CONNECT")
        XCTAssertEqual(bytes[2], 0x00, "reserved")
        XCTAssertEqual(bytes[3], 0x03, "address type: domain")
        XCTAssertEqual(bytes[4], UInt8("example.com".utf8.count), "domain length")
        XCTAssertEqual(Array(bytes[5..<(5 + 11)]), Array("example.com".utf8))
        XCTAssertEqual(bytes.suffix(2), [0x00, 0x50], "port 80 big-endian")
    }

    func testConnectRequestEncodesHighPortBigEndian() throws {
        let request = try XCTUnwrap(SocksProbe.connectRequest(host: "a.io", port: 443))
        XCTAssertEqual(Array(request).suffix(2), [0x01, 0xBB], "443 = 0x01BB")
    }

    func testConnectRequestRejectsUnusableInput() {
        XCTAssertNil(SocksProbe.connectRequest(host: "", port: 80), "Empty host")
        XCTAssertNil(SocksProbe.connectRequest(host: String(repeating: "a", count: 256), port: 80),
                     "Domain longer than one length byte")
        XCTAssertNil(SocksProbe.connectRequest(host: "a.io", port: 70000), "Port out of range")
        XCTAssertNil(SocksProbe.connectRequest(host: "a.io", port: -1), "Negative port")
    }

    func testConnectRequestAcceptsMaximumLengthDomain() {
        let host = String(repeating: "a", count: 255)
        XCTAssertNotNil(SocksProbe.connectRequest(host: host, port: 80))
    }

    /// Only status 0x00 means the tunnel actually established the connection —
    /// every other code must read as failure, which is the whole point of this
    /// probe over a plain TCP check.
    func testConnectSucceededOnlyForStatusZero() {
        XCTAssertTrue(SocksProbe.isConnectSucceeded(Data([0x05, 0x00, 0x00, 0x01])))

        for status: UInt8 in [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08] {
            XCTAssertFalse(
                SocksProbe.isConnectSucceeded(Data([0x05, status, 0x00, 0x01])),
                "Status \(status) is a refusal and must not read as success"
            )
        }
    }

    func testConnectRepliesWithWrongVersionOrTruncationFail() {
        XCTAssertFalse(SocksProbe.isConnectSucceeded(Data([0x04, 0x00])))
        XCTAssertFalse(SocksProbe.isConnectSucceeded(Data([0x05])))
        XCTAssertFalse(SocksProbe.isConnectSucceeded(Data()))
    }

    func testHTTPRequestIsAWellFormedHeadRequest() {
        let text = String(decoding: SocksProbe.httpRequest(host: "example.com"), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HEAD / HTTP/1.1\r\n"))
        XCTAssertTrue(text.contains("Host: example.com\r\n"))
        XCTAssertTrue(text.contains("Connection: close\r\n"))
        XCTAssertTrue(text.hasSuffix("\r\n\r\n"), "Headers must be terminated")
    }

    /// Reading a status line back is the only step that proves the tunnel
    /// carries data: sing-box answers the SOCKS CONNECT before dialling the
    /// server, so a dead server still gets that far.
    func testHTTPResponseRecognisedOnlyForAStatusLine() {
        XCTAssertTrue(SocksProbe.isHTTPResponse(Data("HTTP/1.1 200 OK".utf8)))
        XCTAssertTrue(SocksProbe.isHTTPResponse(Data("HTTP/1.0 404 Not Found".utf8)))

        XCTAssertFalse(SocksProbe.isHTTPResponse(Data()), "Nothing came back")
        XCTAssertFalse(SocksProbe.isHTTPResponse(Data("HTTP".utf8)), "Truncated before the slash")
        XCTAssertFalse(SocksProbe.isHTTPResponse(Data([0x05, 0x00, 0x00, 0x01])),
                       "A SOCKS reply is not evidence of a served response")
        XCTAssertFalse(SocksProbe.isHTTPResponse(Data("garbage".utf8)))
    }

    func testTargetDefaultsAreUsable() {
        XCTAssertNotNil(
            SocksProbe.connectRequest(
                host: SocksProbe.defaultTargetHost,
                port: SocksProbe.defaultTargetPort
            ),
            "The built-in target must encode"
        )
    }

    func testMeasureRejectsOutOfRangeSocksPort() async {
        let result = await SocksProbe.measure(socksPort: 70000, timeout: 0.1)
        XCTAssertNil(result)
    }
}
