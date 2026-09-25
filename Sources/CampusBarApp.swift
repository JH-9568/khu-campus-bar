import AppKit
import SwiftUI
import WebKit

@MainActor
final class CampusStore: ObservableObject {
    @Published var status = "e-Campus에 로그인해 주세요"
    let webView: WKWebView

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.load(URLRequest(url: URL(string: "https://e-campus.khu.ac.kr/index.php")!))
    }
}

struct LoginView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct MenuContent: View {
    @ObservedObject var store: CampusStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("이번 주 강의실")
                .font(.headline)
            Text(store.status)
                .foregroundStyle(.secondary)
            Divider()
            Button("e-Campus 로그인") { openWindow(id: "login") }
            Button("강의실 열기") {
                NSWorkspace.shared.open(URL(string: "https://khcanvas.khu.ac.kr/")!)
            }
        }
        .padding(18)
        .frame(width: 320, alignment: .leading)
    }
}

@main
struct CampusBarApp: App {
    @StateObject private var store = CampusStore()

    var body: some Scene {
        MenuBarExtra("강의실", systemImage: "books.vertical") {
            MenuContent(store: store)
        }
        .menuBarExtraStyle(.window)

        Window("e-Campus 로그인", id: "login") {
            LoginView(webView: store.webView)
                .frame(minWidth: 820, minHeight: 650)
        }
    }
}
