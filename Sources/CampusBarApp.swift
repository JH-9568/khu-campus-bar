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
    @Environment(\.openWindow) private var openWindow

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
                ForEach(store.dueItems.prefix(8)) { item in
                    itemRow(item)
                }
                if !store.announcementItems.isEmpty {
                    Divider()
                    Text("최근 공지").font(.subheadline.bold())
                    ForEach(store.announcementItems.prefix(3)) { item in
                        itemRow(item)
                    }
                }
                Text(store.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Button("앱에서 e-Campus 로그인") { openWindow(id: "login") }
                Spacer()
                Button("강의실 열기") {
                    NSWorkspace.shared.open(URL(string: "https://khcanvas.khu.ac.kr/")!)
                }
            }
            Button("앱 종료") { NSApp.terminate(nil) }
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

@main
struct CampusBarApp: App {
    @StateObject private var store = CampusStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            Label(store.menuTitle, systemImage: "books.vertical")
        }
        .menuBarExtraStyle(.window)

        Window("e-Campus 로그인", id: "login") {
            VStack(spacing: 0) {
                LoginView(webView: store.webView)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.status)
                        Text("현재: \(store.currentPage) · 결과는 메뉴 막대 책 아이콘에서 확인")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("강의실 확인") { store.refresh() }
                }
                .padding(10)
            }
            .frame(minWidth: 820, minHeight: 650)
        }
    }
}
