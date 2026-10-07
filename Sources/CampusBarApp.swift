import AppKit
import SwiftUI
import WebKit
import Combine

struct LoginView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct MenuContent: View {
    @ObservedObject var store: CampusStore
    var connect: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("앞으로 7일").font(.headline)
                Spacer()
                Button { store.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("새로고침")
            }

            if store.items.isEmpty {
                VStack(spacing: 4) {
                    Text(store.status)
                    Text(store.currentPage).font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .center)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if store.dueItems.isEmpty {
                            Text("앞으로 7일 이내 마감 항목이 없습니다.").foregroundStyle(.secondary)
                        }
                        ForEach(store.dueItems) { item in itemRow(item) }
                        if !store.announcementItems.isEmpty {
                            Divider()
                            Text("최근 공지").font(.subheadline.bold())
                            ForEach(store.announcementItems) { item in itemRow(item) }
                        }
                    }
                }
                .frame(maxHeight: 440)
                Text(store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Button("학교 연결 / 학기 선택") {
                    if let connect { connect() } else { store.showWindow() }
                }
                Spacer()
                Button("강의실 열기") {
                    NSWorkspace.shared.open(URL(string: "https://khcanvas.khu.ac.kr/")!)
                }
            }
            HStack {
                Button("설정…") { store.showSettings() }
                Button("로그인 정보 지우기") { store.clearLogin() }
                Spacer()
                Button("앱 종료") { NSApp.terminate(nil) }
            }
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 350, alignment: .leading)
        .onAppear { store.refreshIfNeeded() }
    }

    private func itemRow(_ item: CampusItem) -> some View {
        Button {
            if let url = URL(string: item.url), url.host == "khcanvas.khu.ac.kr" {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.kind.symbol)
                    .foregroundStyle(item.kind == .announcement ? .blue : .orange)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).lineLimit(2)
                    HStack {
                        Text(item.course).lineLimit(1)
                        Spacer()
                        if let date = item.date {
                            Text(date, format: .dateTime.month().day().hour().minute())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct CampusWindowContent: View {
    @ObservedObject var store: CampusStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CampusBar").font(.headline)
                Spacer()
                Button("요약") { store.showConnection = false }
                Button("학교 연결 / 학기 선택") { store.showConnection = true }
            }
            .padding(12)
            Divider()
            ZStack {
                LoginView(webView: store.webView)
                    .opacity(store.showConnection ? 1 : 0)
                    .allowsHitTesting(store.showConnection)
                    .accessibilityHidden(!store.showConnection)
                if !store.showConnection {
                    VStack {
                        MenuContent(store: store, connect: { store.showConnection = true })
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.status)
                    if store.showConnection {
                        Text("현재: \(store.currentPage)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("새로고침") { store.refresh() }
            }
            .padding(10)
        }
        .frame(minWidth: 820, minHeight: 650)

        .onChange(of: store.lastUpdated) { _, _ in
            if !store.dueItems.isEmpty || !store.announcementItems.isEmpty { store.showConnection = false }
        }
    }
}

struct CampusSettingsView: View {
    @ObservedObject var store: CampusStore
    @State private var username = ""
    @State private var password = ""
    @State private var saving = false
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("자동 로그인").font(.title2.bold())
            Text("학교 세션이 만료되면 저장한 계정으로 다시 로그인합니다. ID와 비밀번호는 이 Mac의 키체인에만 보관합니다.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("학교 ID 또는 학번", text: $username).textFieldStyle(.roundedBorder)
            SecureField("학교 비밀번호", text: $password).textFieldStyle(.roundedBorder)
            Text(store.automaticLoginPaused ? "자동 로그인 일시 중지 · 정보를 확인하고 다시 저장해 주세요" : store.automaticLoginEnabled ? "자동 로그인 켜짐" : "자동 로그인 꺼짐")
                .font(.caption).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).font(.caption).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("저장 정보 삭제 · 끄기") {
                    saving = true
                    Task {
                        do { try await store.disableAutomaticLogin(); message = "자동 로그인 정보를 삭제했습니다." }
                        catch { message = error.localizedDescription }
                        saving = false
                    }
                }.disabled(saving || !store.automaticLoginEnabled)
                Spacer()
                Button("저장하고 연결") {
                    saving = true
                    Task {
                        do {
                            try await store.saveAutomaticLogin(username: username, password: password)
                            username = ""; password = ""
                            message = "키체인에 저장했습니다. 실제 로그인을 확인합니다."
                        } catch { message = error.localizedDescription }
                        saving = false
                    }
                }.buttonStyle(.borderedProminent).disabled(saving || username.isEmpty || password.isEmpty)
            }
            Button("저장된 정보로 다시 로그인") { store.reconnectWithSavedLogin() }
                .disabled(saving || !store.automaticLoginEnabled)
            Text(store.status).font(.caption).fixedSize(horizontal: false, vertical: true)
            Text("비밀번호 오류나 추가 인증이 나오면 자동 재시도를 멈춥니다.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 460)
    }
}

@MainActor
final class CampusAppDelegate: NSObject, NSApplicationDelegate {
    private var store: CampusStore!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var subscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: "com.jh9568.CampusBar")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }
        store = CampusStore()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let icon = NSImage(named: "MenuIcon") ?? NSImage(systemSymbolName: "books.vertical", accessibilityDescription: "CampusBar")!
            icon.size = NSSize(width: 22, height: 15)
            icon.isTemplate = true
            button.image = icon
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("CampusBar")
            button.toolTip = "CampusBar · 클릭: 요약 / 우클릭: 메뉴"
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuContent(store: store))
        if !UserDefaults.standard.bool(forKey: "automaticLoginSetupShown") {
            UserDefaults.standard.set(true, forKey: "automaticLoginSetupShown")
            store.showSettings()
        }
        subscription = store.$items.sink { [weak self] _ in
            Task { @MainActor in self?.statusItem.button?.title = " " + (self?.store.menuTitle ?? "강의실") }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store?.showWindow(connection: false)
        return true
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            popover.performClose(nil)
            let menu = NSMenu()
            add("요약 창 열기", action: #selector(openSummary), to: menu)
            add("학교 연결 / 학기 선택…", action: #selector(openConnection), to: menu)
            menu.addItem(.separator())
            add("새로고침", action: #selector(refresh), to: menu)
            add("설정…", action: #selector(settings), to: menu)
            menu.addItem(.separator())
            add("강의실 웹사이트 열기", action: #selector(openClassroom), to: menu)
            menu.addItem(.separator())
            add("CampusBar 종료", action: #selector(quit), to: menu)
            // Open the menu directly: performClick re-enters button tracking and
            // can discard a right-mouse-up event before the menu starts tracking.
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }
    @objc private func openSummary() { store.showWindow(connection: false) }
    @objc private func openConnection() { store.showWindow() }
    @objc private func refresh() { store.refresh() }
    @objc private func settings() { store.showSettings() }
    @objc private func openClassroom() { NSWorkspace.shared.open(URL(string: "https://khcanvas.khu.ac.kr/")!) }
    @objc private func quit() { NSApp.terminate(nil) }
}

@main
struct CampusBarApp: App {
    @NSApplicationDelegateAdaptor(CampusAppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}
