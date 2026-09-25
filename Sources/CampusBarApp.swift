import AppKit
import SwiftUI
import WebKit

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
    @State private var showConnection = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CampusBar").font(.headline)
                Spacer()
                Button("요약") { showConnection = false }
                Button("학교 연결 / 학기 선택") { showConnection = true }
            }
            .padding(12)
            Divider()
            ZStack {
                LoginView(webView: store.webView)
                    .opacity(showConnection ? 1 : 0)
                    .allowsHitTesting(showConnection)
                    .accessibilityHidden(!showConnection)
                if !showConnection {
                    VStack {
                        MenuContent(store: store, connect: { showConnection = true })
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
                    if showConnection {
                        Text("현재: \(store.currentPage)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("새로고침") { store.refresh() }
            }
            .padding(10)
        }
        .frame(minWidth: 820, minHeight: 650)
        .onAppear { showConnection = store.lastUpdated == nil }
        .onChange(of: store.lastUpdated) { _, _ in
            if !store.dueItems.isEmpty || !store.announcementItems.isEmpty { showConnection = false }
        }
    }
}

@main
struct CampusBarApp: App {
    @StateObject private var store = CampusStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Label {
                Text(store.menuTitle)
            } icon: {
                Image(nsImage: NSImage(named: "MenuIcon") ?? NSImage(systemSymbolName: "books.vertical", accessibilityDescription: nil)!)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 15)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
