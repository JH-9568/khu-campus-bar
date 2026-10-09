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

    func testAutoLoginOnlyTargetsSchoolLoginAndStopsAfterFailure() {
        XCTAssertEqual(AutoLoginPolicy.entryURL.absoluteString, "https://e-campus.khu.ac.kr/login")
        XCTAssertFalse(AutoLoginPolicy.isLoginPage(AutoLoginPolicy.entryURL), "Entry must run SSO setup before displaying the form")
        XCTAssertTrue(AutoLoginPolicy.isLoginPage(URL(string: "https://e-campus.khu.ac.kr/xn-sso/login.php?return_url=https%3A%2F%2Fe-campus.khu.ac.kr%2Flogin%2Fcallback")))
        XCTAssertTrue(AutoLoginPolicy.isLoginPage(URL(string: "https://e-campus.khu.ac.kr/xn-sso/login.php")))
        for url in ["http://e-campus.khu.ac.kr/xn-sso/login.php", "https://e-campus.khu.ac.kr.evil.test/xn-sso/login.php", "https://e-campus.khu.ac.kr:444/xn-sso/login.php", "https://khcanvas.khu.ac.kr/xn-sso/login.php", "https://e-campus.khu.ac.kr/index.php"] {
            XCTAssertFalse(AutoLoginPolicy.isLoginPage(URL(string: url)))
        }
        var policy = AutoLoginPolicy()
        XCTAssertTrue(policy.begin())
        XCTAssertFalse(policy.begin())
        policy.fail()
        XCTAssertFalse(policy.begin())
        var restored = AutoLoginPolicy(paused: true)
        XCTAssertFalse(restored.begin())
        policy.reset()
        XCTAssertTrue(policy.begin())
    }

    func testReturnedLoginPageVerifiesSessionOnceWithoutResubmittingPassword() {
        var policy = AutoLoginPolicy()
        XCTAssertFalse(policy.beginSessionVerification())
        XCTAssertTrue(policy.begin())
        XCTAssertTrue(policy.beginSessionVerification())
        XCTAssertFalse(policy.paused, "Returning to login.php is not proof of failure")
        XCTAssertFalse(policy.begin(), "Session verification must not resubmit credentials")
        XCTAssertFalse(policy.beginSessionVerification(), "Do not loop between home and login")
        policy.fail()
        XCTAssertFalse(policy.beginSessionVerification())
        policy.reset()
        XCTAssertTrue(policy.begin())
        XCTAssertTrue(policy.beginSessionVerification())
    }

    func testCompletionPayloadAndSavedSnapshot() throws {
        let json = #"{"items":[{"kind":"assignment","title":"Submitted","course":"Fixture","date":null,"url":"https://khcanvas.khu.ac.kr/courses/1/assignments/2","completed":true,"completionLabel":"제출 완료","completedAt":"2026-10-01T14:59:00Z"},{"kind":"video","title":"Video","course":"Fixture","url":"https://khcanvas.khu.ac.kr/video/1"}]}"#
        let payload = try JSONDecoder().decode(CampusPayload.self, from: Data(json.utf8))
        let submitted = try XCTUnwrap(payload.items[0].normalized())
        XCTAssertTrue(submitted.completed)
        XCTAssertEqual(submitted.completionLabel, "제출 완료")
        XCTAssertNotNil(submitted.completedAt)
        XCTAssertFalse(try XCTUnwrap(payload.items[1].normalized()).completed)
        let snapshot = try JSONDecoder().decode(CampusItem.self, from: JSONEncoder().encode(submitted))
        XCTAssertEqual(snapshot, submitted)
    }

    func testDatesAndInvalidItems() {
        let local = RawCampusItem.parseDate("2026.10.01 23:59")
        let iso = RawCampusItem.parseDate("2026-10-01T14:59:00Z")
        XCTAssertEqual(local, iso)

        let invalid = RawCampusItem(kind: .video, title: "", course: "수업", date: nil, url: "https://khcanvas.khu.ac.kr/")
        XCTAssertNil(invalid.normalized())
    }
}
