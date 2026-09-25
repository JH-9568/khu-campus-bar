import Foundation
import SwiftUI
import WebKit

@MainActor
final class CampusStore: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    @Published private(set) var items: [CampusItem] = []
    @Published private(set) var status = "e-Campus에 로그인해 주세요"
    @Published private(set) var lastUpdated: Date?
    let webView: WKWebView

    private let dashboardURL = URL(string: "https://khcanvas.khu.ac.kr/accounts/1/external_tools/184?launch_type=global_navigation")!

    var dueItems: [CampusItem] {
        items.filter { $0.kind != .announcement && ($0.date ?? .distantPast) >= Date() }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    var announcementItems: [CampusItem] {
        items.filter { $0.kind == .announcement }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var menuTitle: String {
        let count = dueItems.count
        return count == 0 ? "강의실" : "할 일 \(count)"
    }

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.configuration.userContentController.add(self, name: "canvasData")
        webView.navigationDelegate = self
        refresh()
    }

    func refreshIfNeeded() {
        if lastUpdated.map({ Date().timeIntervalSince($0) < 300 }) != true { refresh() }
    }

    func refresh() {
        status = "강의실을 확인하는 중…"
        webView.load(URLRequest(url: dashboardURL))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.host == "khcanvas.khu.ac.kr" else {
            status = "학교 로그인 후 강의실 확인을 눌러 주세요"
            return
        }
        webView.evaluateJavaScript(CampusScripts.canvas) { [weak self] _, error in
            if let error { self?.status = "데이터 요청 실패: \(error.localizedDescription)" }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "canvasData", let json = message.body as? String,
              let data = json.data(using: .utf8) else { return }
        if let payload = try? JSONDecoder().decode(CampusPayload.self, from: data) {
            items = Array(Dictionary(grouping: payload.items.compactMap { $0.normalized() }, by: \.id)
                .compactMap { $0.value.first })
            lastUpdated = Date()
            status = "방금 업데이트됨"
        } else if let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            status = object["error"] ?? "강의실 응답을 읽지 못했습니다"
        }
    }
}
