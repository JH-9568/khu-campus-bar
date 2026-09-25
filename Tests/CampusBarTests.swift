import XCTest
@testable import CampusBar

final class CampusBarTests: XCTestCase {
    func testDatesAndInvalidItems() {
        let local = RawCampusItem.parseDate("2026.10.01 23:59")
        let iso = RawCampusItem.parseDate("2026-10-01T14:59:00Z")
        XCTAssertEqual(local, iso)

        let invalid = RawCampusItem(kind: .video, title: "", course: "수업", date: nil, url: "https://khcanvas.khu.ac.kr/")
        XCTAssertNil(invalid.normalized())
    }
}
