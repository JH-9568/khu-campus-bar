import Foundation
import os
import SwiftUI
import WebKit

@MainActor
final class CampusStore: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKHTTPCookieStoreObserver {
    @Published private(set) var items: [CampusItem] = []
    @Published private(set) var status = "저장된 학교 세션 복원 중…"
    @Published private(set) var currentPage = "연결 전"
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var manualCompletions = UserDefaults.standard.dictionary(forKey: "manualCompletions") as? [String: Double] ?? [:]
    private var completionSnapshots: [String: CampusItem] = UserDefaults.standard.data(forKey: "completionSnapshots")
        .flatMap { try? JSONDecoder().decode([String: CampusItem].self, from: $0) } ?? [:]
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
    private var restoringSession = true
    private var connectionWindow: NSWindow?
    private var promptedLogin = false
    private var settingsWindow: NSWindow?
    private var loginPolicy = AutoLoginPolicy(paused: UserDefaults.standard.bool(forKey: "automaticLoginPaused"))
    private var authenticating = false
    private var loginFailureNotice: String?
    private var needsManualLogin = false
    private var loginTimeout: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.jh9568.CampusBar", category: "navigation")

    var dueItems: [CampusItem] {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? .distantFuture
        return items.filter { $0.kind != .announcement && !isCompleted($0) && ($0.date ?? .distantPast) >= now && ($0.date ?? .distantFuture) <= end }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    func isCompleted(_ item: CampusItem) -> Bool { item.completed || manualCompletions[item.id] != nil }

    func toggleCompletion(_ item: CampusItem) {
        guard item.kind != .announcement, !item.completed else { return }
        if manualCompletions[item.id] == nil {
            manualCompletions[item.id] = Date().timeIntervalSince1970
            completionSnapshots[item.id] = item
        } else {
            manualCompletions.removeValue(forKey: item.id)
            completionSnapshots.removeValue(forKey: item.id)
        }
        if let data = try? JSONEncoder().encode(completionSnapshots) {
            UserDefaults.standard.set(data, forKey: "completionSnapshots")
        }
        UserDefaults.standard.set(manualCompletions, forKey: "manualCompletions")
        updateCollectionStatus()
    }

    var overdueItems: [CampusItem] {
        let start = Date().addingTimeInterval(-30 * 86400), now = Date()
        return items.filter { $0.kind != .announcement && !isCompleted($0) && ($0.date ?? .distantFuture) < now && ($0.date ?? .distantPast) >= start }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
    var undatedItems: [CampusItem] {
        items.filter { $0.kind != .announcement && !isCompleted($0) && $0.date == nil }.sorted { $0.course + $0.title < $1.course + $1.title }
    }
    var futureItems: [CampusItem] {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? .distantFuture
        return items.filter { $0.kind != .announcement && !isCompleted($0) && ($0.date ?? .distantPast) > end }
            .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
    var pendingCount: Int { overdueItems.count + dueItems.count + futureItems.count + undatedItems.count }
    var completedItems: [CampusItem] {
        let start = Date().addingTimeInterval(-30 * 86400)
        func date(_ item: CampusItem) -> Date {
            manualCompletions[item.id].map(Date.init(timeIntervalSince1970:)) ?? item.completedAt ?? item.date ?? .distantPast
        }
        let currentIDs = Set(items.map(\.id))
        let retained = completionSnapshots.values.filter { !currentIDs.contains($0.id) }
        return (items + retained).filter { $0.kind != .announcement && isCompleted($0) && date($0) >= start }
            .sorted { date($0) > date($1) }
    }

    var announcementItems: [CampusItem] {
        items.filter { $0.kind == .announcement }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var menuTitle: String {
        let count = pendingCount
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
        webView.uiDelegate = self
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.needsManualLogin else { return }
                self.refresh()
            }
        }
        Task { @MainActor in
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let saved = await SessionPersistence.shared.load()
            for cookie in saved { await cookieStore.setCookie(cookie) }
            logger.info("Restored \(saved.count) school session cookies")
            cookieStore.add(self)
            restoringSession = false
            refresh()
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard !clearingSession else { return }
        cookieStore.getAllCookies { [weak self] cookies in
            guard let self, !self.clearingSession else { return }
            Task { @MainActor in
                guard !self.clearingSession else { return }
                let result = await SessionPersistence.shared.save(cookies)
                if result != errSecSuccess { self.logger.error("Session save failed: \(result)") }
            }
        }
    }

    func clearLogin() {
        clearingSession = true
        Task { @MainActor in
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            for cookie in await cookieStore.allCookies() { await cookieStore.deleteCookie(cookie) }
            await SessionPersistence.shared.clear()
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
        reconnectWithSavedLogin()
    }

    func reconnectWithSavedLogin() {
        guard automaticLoginEnabled, !authenticating, !restoringSession else { return }
        resetLoginAttempt()
        needsManualLogin = false
        promptedLogin = false
        status = "저장된 계정으로 로그인 확인 중…"
        showWindow()
        webView.load(URLRequest(url: URL(string: "https://e-campus.khu.ac.kr/xn-sso/login.php")!))
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
        loginFailureNotice = nil
        automaticLoginPaused = false
        UserDefaults.standard.set(false, forKey: "automaticLoginPaused")
    }

    private func requireManualLogin(_ message: String, pause: Bool = false) {
        loginTimeout?.cancel()
        authenticating = false
        needsManualLogin = true
        status = message
        logger.info("Manual login needed; automatic retries paused: \(pause, privacy: .public)")
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

    private func verifyLoginSession() {
        guard loginPolicy.beginSessionVerification() else {
            requireManualLogin(loginFailureNotice ?? "로그인이 확인되지 않았습니다 · 학교 연결 또는 설정에서 정보를 확인해 주세요", pause: true)
            return
        }
        // The school can leave login.php displayed after accepting the POST.
        // Check the authenticated homepage once; never submit the password again.
        status = "로그인 제출 완료 · 학교 세션 확인 중…"
        homepageRedirects = 0
        openedDashboard = false
        webView.load(URLRequest(url: homeURL, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    private func handleLoginPage() {
        if loginPolicy.attempted {
            verifyLoginSession()
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
                status = "저장된 계정으로 자동 로그인 중…"
                logger.info("Automatic login: submitting school form")
                let submitted = try await webView.callAsyncJavaScript(CampusScripts.autoLogin,
                    arguments: ["username": login.username, "password": login.password], in: nil, contentWorld: .page)
                logger.info("Automatic login: form accepted \(submitted as? Bool == true, privacy: .public)")
                guard submitted as? Bool == true else {
                    requireManualLogin("로그인 화면 변경 또는 추가 인증 · 학교 연결에서 확인해 주세요", pause: true)
                    return
                }
                guard loginPolicy.attempted, !loginPolicy.paused else { return }
                loginTimeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(25)) } catch { return }
                    guard let self, self.authenticating else { return }
                    self.verifyLoginSession()
                }
            } catch {
                // A successful redirect may finish before WebKit returns the JS result.
                guard authenticating else { return }
                if loginPolicy.attempted { verifyLoginSession() }
                else { requireManualLogin("자동 로그인 실패 · 키체인 접근을 확인해 주세요", pause: true) }
            }
        }
    }

    func refreshIfNeeded() {
        guard !needsManualLogin else { return }
        if lastUpdated.map({ Date().timeIntervalSince($0) < 300 }) != true { refresh() }
    }

    func refresh() {
        guard !authenticating, !clearingSession, !restoringSession else { return }
        status = "강의실을 확인하는 중…"
        homepageRedirects = 0
        openedDashboard = false
        webView.load(URLRequest(url: homeURL))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.targetFrame?.isMainFrame == true,
           navigationAction.request.httpMethod == "POST",
           AutoLoginPolicy.isLoginPage(navigationAction.request.url), !authenticating {
            // A user can sign in manually after an automatic attempt was paused.
            // Verify that POST too, rather than preserving the previous failure.
            resetLoginAttempt()
            _ = loginPolicy.begin()
            authenticating = true
        }
        return .allow
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
                    if self.loginPolicy.attempted {
                        self.requireManualLogin(self.loginFailureNotice ?? "학교 로그인이 완료되지 않았습니다 · 로그인 정보를 확인해 주세요", pause: true)
                        self.webView.load(URLRequest(url: URL(string: "https://e-campus.khu.ac.kr/xn-sso/login.php")!))
                        return
                    }
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

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        if frame.isMainFrame, AutoLoginPolicy.isLoginPage(frame.request.url) {
            loginFailureNotice = "학교 로그인 안내: " + message
            if authenticating { status = loginFailureNotice! }
            else { requireManualLogin(loginFailureNotice!, pause: true) }
        } else {
            showWindow()
            let alert = NSAlert()
            alert.messageText = "학교 사이트 안내"
            alert.informativeText = message
            alert.beginSheetModal(for: connectionWindow!) { _ in completionHandler() }
            return
        }
        completionHandler()
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
            if let warning = payload.warning, !warning.isEmpty { sourceErrors[message.name] = warning }
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
        let summary = "할 일 \(pendingCount)건 · 완료 \(completedItems.count)건 · 공지 \(announcementItems.count)건"
        status = sourceErrors.isEmpty ? "업데이트 완료 · \(summary)" : "\(summary) · 일부 수집 실패: \(sourceErrors.values.sorted().joined(separator: "; "))"
    }
}
