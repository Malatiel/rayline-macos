import XCTest
@testable import RaylineCore

/// The failover group is addressed by tag, and neither `sing-box check` nor
/// startup catches a tag that points at nothing — so the wiring between the
/// group, its members and the route has to be asserted here.
final class FailoverConfigTests: XCTestCase {

    private func profile(_ uri: String) throws -> ProxyConfig {
        try ProxyParser.parse(uri)
    }

    private func twoProfiles() throws -> [ProxyConfig] {
        [
            try profile("vless://a1a1a1a1-b2b2-c3c3-d4d4-e5e5e5e5e5e5@one.example:443?security=tls"),
            try profile("trojan://pw@two.example:443?security=tls"),
        ]
    }

    private func root(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }

    private func outbounds(_ json: String) -> [[String: Any]] {
        root(json)["outbounds"] as? [[String: Any]] ?? []
    }

    /// A group of one has nothing to switch to, and would only add recurring
    /// probe traffic for no benefit.
    func testSingleProfileProducesNoGroup() throws {
        let one = [try profile("trojan://pw@only.example:443?security=tls")]
        XCTAssertNil(ProxyConfig.singBoxFailoverConfig(profiles: one))
        XCTAssertNil(ProxyConfig.singBoxFailoverConfig(profiles: []))
    }

    func testGroupListsEveryMemberByTag() throws {
        let json = try XCTUnwrap(ProxyConfig.singBoxFailoverConfig(profiles: try twoProfiles()))
        let group = try XCTUnwrap(outbounds(json).first { $0["type"] as? String == "urltest" })

        XCTAssertEqual(group["tag"] as? String, "proxy", "Routing addresses the group as 'proxy'")
        XCTAssertEqual(group["outbounds"] as? [String], ["proxy-0", "proxy-1"])
    }

    /// Every tag the group names must exist as a real outbound. A dangling tag
    /// here would start cleanly and fail only when traffic is sent.
    func testEveryGroupMemberTagResolvesToAnOutbound() throws {
        let json = try XCTUnwrap(ProxyConfig.singBoxFailoverConfig(profiles: try twoProfiles()))
        let all = outbounds(json)
        let group = try XCTUnwrap(all.first { $0["type"] as? String == "urltest" })
        let memberTags = try XCTUnwrap(group["outbounds"] as? [String])
        let presentTags = Set(all.compactMap { $0["tag"] as? String })

        for tag in memberTags {
            XCTAssertTrue(presentTags.contains(tag), "Group references missing outbound \(tag)")
        }
    }

    func testRouteFinalPointsAtTheGroup() throws {
        let json = try XCTUnwrap(ProxyConfig.singBoxFailoverConfig(profiles: try twoProfiles()))
        let route = try XCTUnwrap(root(json)["route"] as? [String: Any])
        XCTAssertEqual(route["final"] as? String, "proxy")
    }

    /// Failover must not cost the local-network routing fixed earlier.
    func testPrivateAddressesStillGoDirect() throws {
        let json = try XCTUnwrap(ProxyConfig.singBoxFailoverConfig(profiles: try twoProfiles()))
        let route = try XCTUnwrap(root(json)["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let privateRule = rules.first { $0["ip_is_private"] as? Bool == true }

        XCTAssertEqual(privateRule?["outbound"] as? String, "direct")
        XCTAssertTrue(outbounds(json).contains { $0["tag"] as? String == "direct" })
    }

    func testMembersKeepTheirOwnEndpoints() throws {
        let json = try XCTUnwrap(ProxyConfig.singBoxFailoverConfig(profiles: try twoProfiles()))
        let all = outbounds(json)

        let first = try XCTUnwrap(all.first { $0["tag"] as? String == "proxy-0" })
        XCTAssertEqual(first["server"] as? String, "one.example")
        XCTAssertEqual(first["type"] as? String, "vless")

        let second = try XCTUnwrap(all.first { $0["tag"] as? String == "proxy-1" })
        XCTAssertEqual(second["server"] as? String, "two.example")
        XCTAssertEqual(second["type"] as? String, "trojan")
    }

    func testGroupCarriesProbeSettings() throws {
        let json = try XCTUnwrap(ProxyConfig.singBoxFailoverConfig(profiles: try twoProfiles()))
        let group = try XCTUnwrap(outbounds(json).first { $0["type"] as? String == "urltest" })

        XCTAssertEqual(group["url"] as? String, FailoverSettings.default.testURL)
        XCTAssertEqual(group["interval"] as? String, FailoverSettings.default.interval)
        XCTAssertEqual(group["tolerance"] as? Int, FailoverSettings.default.tolerance)
    }

    func testGeneratedFailoverConfigIsValidJSON() throws {
        let json = try XCTUnwrap(ProxyConfig.singBoxFailoverConfig(profiles: try twoProfiles()))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(json.utf8)))
    }
}
