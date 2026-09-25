import Foundation
import os
import SwiftUI
import WebKit

@MainActor
final class CampusStore: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    @Published private(set) var items: [CampusItem] = []
    @Published private(set) var status = "e-Campus에 로그인해 주세요"
    @Published private(set) var currentPage = "연결 전"
    @Published private(set) var lastUpdated: Date?
    let webView: WKWebView

    private let homeURL = URL(string: "https://e-campus.khu.ac.kr/index.php")!
    private let classroomURL = URL(string: "https://e-campus.khu.ac.kr/redirect/lms")!
    private let dashboardURL = URL(string: "https://khcanvas.khu.ac.kr/accounts/1/external_tools/184?launch_type=global_navigation")!
    private var canvasItems: [CampusItem] = []
    private var learningItems: [CampusItem] = []
    private var refreshTimer: Timer?
    private var homepageRedirects = 0
    private var openedDashboard = false
    private let logger = Logger(subsystem: "com.jh9568.CampusBar", category: "navigation")

    var dueItems: [CampusItem] {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? .distantFuture
        return items.filter { $0.kind != .announcement && ($0.date ?? .distantPast) >= now && ($0.date ?? .distantFuture) <= end }
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
        configuration.userContentController.addUserScript(
            WKUserScript(source: CampusScripts.learningX, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.configuration.userContentController.add(self, name: "canvasData")
        webView.configuration.userContentController.add(self, name: "learningX")
        webView.navigationDelegate = self
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func refreshIfNeeded() {
        if lastUpdated.map({ Date().timeIntervalSince($0) < 300 }) != true { refresh() }
    }

    func refresh() {
        status = "강의실을 확인하는 중…"
        homepageRedirects = 0
        openedDashboard = false
        webView.load(URLRequest(url: homeURL))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url {
            currentPage = (url.host ?? "알 수 없음") + url.path
            logger.info("Loaded \(self.currentPage, privacy: .public)")
        }
        if webView.url?.host == "e-campus.khu.ac.kr",
           ["/", "/index.php"].contains(webView.url?.path ?? "") {
            let loadedURL = webView.url
            webView.evaluateJavaScript("Boolean(document.querySelector('button[title=\"사용자 메뉴\"]'))") { [weak self] result, _ in
                guard let self, self.webView.url == loadedURL else { return }
                let signedIn = result as? Bool == true
                self.logger.info("e-Campus signed in: \(signedIn, privacy: .public)")
                guard signedIn else {
                    self.status = "앱 안에서 e-Campus 로그인이 필요합니다 (Chrome와 별개)"
                    return
                }
                guard self.homepageRedirects < 2 else {
                    self.status = "학교 로그인 완료 · Canvas 연결 실패"
                    return
                }
                self.homepageRedirects += 1
                self.status = "로그인 완료 · 강의실로 이동 중…"
                self.webView.load(URLRequest(url: self.classroomURL))
            }
            return
        }
        guard webView.url?.host == "khcanvas.khu.ac.kr" else {
            status = "학교 로그인 후 강의실 확인을 눌러 주세요"
            return
        }
        if webView.url?.path == "/" && !openedDashboard {
            openedDashboard = true
            status = "강의실 연결 완료 · 학습 정보를 읽는 중…"
            webView.load(URLRequest(url: dashboardURL))
            return
        }
        webView.evaluateJavaScript(CampusScripts.canvas) { [weak self] _, error in
            if let error { self?.status = "데이터 요청 실패: \(error.localizedDescription)" }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        status = "페이지 연결 실패: \(error.localizedDescription)"
        logger.error("Navigation failed: \(error.localizedDescription, privacy: .public)")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard ["canvasData", "learningX"].contains(message.name), let json = message.body as? String,
              let data = json.data(using: .utf8) else { return }
        if let payload = try? JSONDecoder().decode(CampusPayload.self, from: data) {
            let incoming = payload.items.compactMap { $0.normalized() }
            if message.name == "canvasData" { canvasItems = incoming }
            else { learningItems = incoming }
            var merged: [String: CampusItem] = [:]
            for item in canvasItems + learningItems where merged[item.id] == nil {
                merged[item.id] = item
            }
            items = Array(merged.values)
            lastUpdated = Date()
            status = "방금 업데이트됨 · Canvas \(canvasItems.count)건 · 학습 \(learningItems.count)건"
        } else if let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            status = object["error"] ?? "강의실 응답을 읽지 못했습니다"
        }
    }
}
