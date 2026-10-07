import Foundation
import os
import SwiftUI
import WebKit

@MainActor
final class CampusStore: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler, WKHTTPCookieStoreObserver {
    @Published private(set) var items: [CampusItem] = []
    @Published private(set) var status = "e-Campus에 로그인해 주세요"
    @Published private(set) var currentPage = "연결 전"
    @Published private(set) var lastUpdated: Date?
    @Published var showConnection = true
    @Published private(set) var automaticLoginEnabled = UserDefaults.standard.bool(forKey: "automaticLoginEnabled")
    @Published private(set) var automaticLoginPaused = UserDefaults.standard.bool(forKey: "automaticLoginPaused")
    let webView: WKWebView

    private let homeURL = URL(string: "https://e-campus.khu.ac.kr/index.php")!
    private let classroomURL = URL(string: "https://e-campus.khu.ac.kr/redirect/lms")!
    private let dashboardURL = URL(string: "https://khcanvas.khu.ac.kr/accounts/1/external_tools/184?launch_type=global_navigation")!
    private var canvasItems: [CampusItem] = []
    private var learningItems: [CampusItem] = []
    private var refreshTimer: Timer?
    private var homepageRedirects = 0
    private var openedDashboard = false
    private var sourceErrors: [String: String] = [:]
    private var clearingSession = false
    private var connectionWindow: NSWindow?
    private var promptedLogin = false
    private var settingsWindow: NSWindow?
    private var loginPolicy = AutoLoginPolicy(paused: UserDefaults.standard.bool(forKey: "automaticLoginPaused"))
    private var authenticating = false
    private var needsManualLogin = false
    private var loginTimeout: Task<Void, Never>?
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
            Task { @MainActor in
                guard let self, !self.needsManualLogin else { return }
                self.refresh()
            }
        }
        Task { @MainActor in
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let saved = SessionCookies.load()
            for cookie in saved { await cookieStore.setCookie(cookie) }
            logger.info("Restored \(saved.count) school session cookies")
            cookieStore.add(self)
            refresh()
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard !clearingSession else { return }
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self, !self.clearingSession else { return }
            let result = SessionCookies.save(cookies)
            if result != errSecSuccess { self.logger.error("Session save failed: \(result)") }
        }
    }

    func clearLogin() {
        clearingSession = true
        Task { @MainActor in
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            for cookie in await cookieStore.allCookies() { await cookieStore.deleteCookie(cookie) }
            SessionCookies.clear()
            do { try await SchoolCredentials.shared.clear() }
            catch { status = error.localizedDescription; clearingSession = false; return }
            automaticLoginEnabled = false
            UserDefaults.standard.set(false, forKey: "automaticLoginEnabled")
            resetLoginAttempt()
            canvasItems = []
            learningItems = []
            sourceErrors = [:]
            items = []
            lastUpdated = nil
            promptedLogin = false
            clearingSession = false
            refresh()
        }
    }

    func showWindow(connection: Bool = true) {
        showConnection = connection
        if connectionWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "CampusBar"
            window.contentView = NSHostingView(rootView: CampusWindowContent(store: self))
            window.isReleasedWhenClosed = false
            window.center()
            connectionWindow = window
        }
        connectionWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 330),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "CampusBar 설정"
            window.contentView = NSHostingView(rootView: CampusSettingsView(store: self))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func saveAutomaticLogin(username: String, password: String) async throws {
        try await SchoolCredentials.shared.save(SchoolLogin(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password))
        automaticLoginEnabled = true
        UserDefaults.standard.set(true, forKey: "automaticLoginEnabled")
        resetLoginAttempt()
        needsManualLogin = false
        promptedLogin = false
        refresh()
    }

    func disableAutomaticLogin() async throws {
        try await SchoolCredentials.shared.clear()
        automaticLoginEnabled = false
        UserDefaults.standard.set(false, forKey: "automaticLoginEnabled")
        resetLoginAttempt()
    }

    private func resetLoginAttempt() {
        loginTimeout?.cancel()
        authenticating = false
        loginPolicy.reset()
        automaticLoginPaused = false
        UserDefaults.standard.set(false, forKey: "automaticLoginPaused")
    }

    private func requireManualLogin(_ message: String, pause: Bool = false) {
        loginTimeout?.cancel()
        authenticating = false
        needsManualLogin = true
        status = message
        if pause {
            loginPolicy.fail()
            automaticLoginPaused = true
            UserDefaults.standard.set(true, forKey: "automaticLoginPaused")
        }
        if !promptedLogin {
            promptedLogin = true
            showWindow()
        }
    }

    private func handleLoginPage() {
        if loginPolicy.attempted {
            requireManualLogin("자동 로그인 실패 · 학교 연결에서 직접 로그인하거나 설정에서 정보를 수정해 주세요", pause: true)
            return
        }
        guard automaticLoginEnabled, !loginPolicy.paused else {
            requireManualLogin(automaticLoginPaused ? "자동 로그인 일시 중지 · 설정에서 로그인 정보를 확인해 주세요" : "학교 로그인이 필요합니다 · 설정에서 자동 로그인을 켤 수 있습니다")
            return
        }
        guard !authenticating else { return }
        authenticating = true
        Task { @MainActor in
            do {
                guard let login = try await SchoolCredentials.shared.load() else {
                    requireManualLogin("저장된 로그인 정보가 없습니다 · 설정에서 등록해 주세요")
                    return
                }
                guard automaticLoginEnabled, AutoLoginPolicy.isLoginPage(webView.url), loginPolicy.begin() else {
                    authenticating = false
                    return
                }
                // If the app exits during authentication, do not retry unattended on every launch.
                UserDefaults.standard.set(true, forKey: "automaticLoginPaused")
                status = "학교 세션 만료 · 자동 로그인 중…"
                let submitted = try await webView.callAsyncJavaScript(CampusScripts.autoLogin,
                    arguments: ["username": login.username, "password": login.password], in: nil, contentWorld: .page)
                guard submitted as? Bool == true else {
                    requireManualLogin("로그인 화면 변경 또는 추가 인증 · 학교 연결에서 확인해 주세요", pause: true)
                    return
                }
                guard loginPolicy.attempted, !loginPolicy.paused else { return }
                loginTimeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(25)) } catch { return }
                    guard let self, self.authenticating else { return }
                    self.requireManualLogin("자동 로그인 확인 시간 초과 · 학교 연결에서 확인해 주세요", pause: true)
                }
            } catch {
                // A successful redirect may finish before WebKit returns the JS result.
                guard authenticating else { return }
                requireManualLogin("자동 로그인 실패 · 키체인 접근 또는 학교 연결을 확인해 주세요", pause: true)
            }
        }
    }

    func refreshIfNeeded() {
        guard !needsManualLogin else { return }
        if lastUpdated.map({ Date().timeIntervalSince($0) < 300 }) != true { refresh() }
    }

    func refresh() {
        guard !authenticating, !clearingSession else { return }
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
        if AutoLoginPolicy.isLoginPage(webView.url) {
            handleLoginPage()
            return
        }
        if webView.url?.host == "e-campus.khu.ac.kr",
           ["/", "/index.php"].contains(webView.url?.path ?? "") {
            let loadedURL = webView.url
            webView.evaluateJavaScript("Boolean(document.querySelector('button[title=\"사용자 메뉴\"]'))") { [weak self] result, _ in
                guard let self, self.webView.url == loadedURL else { return }
                let signedIn = result as? Bool == true
                self.logger.info("e-Campus signed in: \(signedIn, privacy: .public)")
                guard signedIn else {
                    self.status = "학교 세션을 확인하는 중…"
                    self.webView.load(URLRequest(url: URL(string: "https://e-campus.khu.ac.kr/xn-sso/login.php")!))
                    return
                }
                self.resetLoginAttempt()
                self.needsManualLogin = false
                self.promptedLogin = false
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
            status = "학교 로그인을 마치면 자동으로 정보를 가져옵니다"
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
        if authenticating {
            requireManualLogin("로그인 도중 연결 실패 · 학교 연결에서 확인해 주세요", pause: true)
            return
        }
        status = "페이지 연결 실패: \(error.localizedDescription)"
        logger.error("Navigation failed: \(error.localizedDescription, privacy: .public)")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == "khcanvas.khu.ac.kr",
              ["canvasData", "learningX"].contains(message.name), let json = message.body as? String,
              let data = json.data(using: .utf8) else { return }
        if let payload = try? JSONDecoder().decode(CampusPayload.self, from: data) {
            let incoming = payload.items.compactMap { $0.normalized() }
            sourceErrors.removeValue(forKey: message.name)
            if message.name == "canvasData" { canvasItems = incoming }
            else { learningItems = incoming }
            var merged: [String: CampusItem] = [:]
            for item in canvasItems + learningItems where merged[item.id] == nil {
                merged[item.id] = item
            }
            items = Array(merged.values)
            lastUpdated = Date()
            logger.info("Collected \(message.name, privacy: .public): \(incoming.count) items; upcoming \(self.dueItems.count), announcements \(self.announcementItems.count)")
            updateCollectionStatus()
        } else if let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            let error = object["error"] ?? "강의실 응답을 읽지 못했습니다"
            sourceErrors[message.name] = error
            logger.error("Collection failed \(message.name, privacy: .public): \(error, privacy: .public)")
            updateCollectionStatus()
        }
    }

    private func updateCollectionStatus() {
        let summary = "마감 \(dueItems.count)건 · 공지 \(announcementItems.count)건"
        status = sourceErrors.isEmpty ? "업데이트 완료 · \(summary)" : "\(summary) · 일부 수집 실패: \(sourceErrors.values.sorted().joined(separator: "; "))"
    }
}
