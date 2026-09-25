import Foundation

enum CampusKind: String, Decodable {
    case assignment
    case video
    case activity
    case announcement

    var symbol: String {
        switch self {
        case .assignment: "doc.text"
        case .video: "play.rectangle"
        case .activity: "calendar"
        case .announcement: "megaphone"
        }
    }
}

struct CampusItem: Identifiable, Equatable {
    let id: String
    let kind: CampusKind
    let title: String
    let course: String
    let date: Date?
    let url: String
}

struct CampusPayload: Decodable {
    let items: [RawCampusItem]
}

struct RawCampusItem: Decodable {
    let kind: CampusKind
    let title: String
    let course: String
    let date: String?
    let url: String

    func normalized() -> CampusItem? {
        guard !title.isEmpty, !url.isEmpty else { return nil }
        return CampusItem(
            id: url,
            kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            course: course,
            date: date.flatMap(Self.parseDate),
            url: url
        )
    }

    static func parseDate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }

        let local = DateFormatter()
        local.locale = Locale(identifier: "ko_KR")
        local.timeZone = TimeZone(identifier: "Asia/Seoul")
        local.dateFormat = "yyyy.MM.dd HH:mm"
        return local.date(from: value)
    }
}
