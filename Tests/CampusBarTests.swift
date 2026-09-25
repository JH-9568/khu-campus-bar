import XCTest
@testable import CampusBar

final class CampusBarTests: XCTestCase {
    func testSessionCookieRoundTripAndSchoolScope() throws {
        let cookie = HTTPCookie(properties: [.domain: "e-campus.khu.ac.kr", .path: "/", .name: "test-session", .value: "fixture", .secure: "TRUE", HTTPCookiePropertyKey("HttpOnly"): "TRUE"])!
        let unrelated = HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "unrelated", .value: "fixture"])!
        let restored = SessionCookies.decode(try SessionCookies.encode([cookie, unrelated]))
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.value, cookie.value)
        XCTAssertEqual(restored.first?.domain, cookie.domain)
        XCTAssertTrue(restored[0].isSecure)
        XCTAssertEqual(restored[0].isHTTPOnly, cookie.isHTTPOnly)
    }

    func testDatesAndInvalidItems() {
        let local = RawCampusItem.parseDate("2026.10.01 23:59")
        let iso = RawCampusItem.parseDate("2026-10-01T14:59:00Z")
        XCTAssertEqual(local, iso)

        let invalid = RawCampusItem(kind: .video, title: "", course: "수업", date: nil, url: "https://khcanvas.khu.ac.kr/")
        XCTAssertNil(invalid.normalized())
    }
}
