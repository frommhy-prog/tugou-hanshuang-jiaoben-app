import SwiftUI
import UIKit
import ActivityKit
import WidgetKit

@main
struct TSTZMApp: App {
    @AppStorage("theme") private var theme = "system"
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { Deeplink.handle($0) }
                .onAppear { Theme.apply(theme) }
                .onChange(of: theme) { _, new in Theme.apply(new) }
                .onChange(of: phase) { _, new in
                    if new == .active { Theme.apply(theme) }
                }
        }
    }
}

// 主题：直接写所有窗口和已弹出的页面，避免弹窗不跟随
enum Theme {
    static func apply(_ mode: String) {
        let style: UIUserInterfaceStyle = mode == "light" ? .light : (mode == "dark" ? .dark : .unspecified)
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows {
                w.overrideUserInterfaceStyle = style
                var vc = w.rootViewController?.presentedViewController
                while let v = vc {
                    v.overrideUserInterfaceStyle = style
                    vc = v.presentedViewController
                }
            }
        }
    }
}

extension Notification.Name {
    static let cfgChanged = Notification.Name("tstzm.cfgChanged")
}

// tstzm://setup?token=xxxx  一键写入令牌
enum Deeplink {
    static func handle(_ url: URL) {
        guard url.scheme == "tstzm", url.host == "setup" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let t = items.first(where: { $0.name == "token" })?.value, !t.isEmpty { Cfg.token = t }
        if let b = items.first(where: { $0.name == "base" })?.value, !b.isEmpty { Cfg.base = b }
        NotificationCenter.default.post(name: .cfgChanged, object: nil)
    }
}

struct RootView: View {
    @AppStorage("currency", store: Cfg.defaults) private var currency = "USD"
    @State private var needSetup = Cfg.token.isEmpty

    var body: some View {
        TabView {
            TokenView()
                .tabItem { Label("体检", systemImage: "waveform.path.ecg") }
            WalletsView()
                .tabItem { Label("钱包", systemImage: "wallet.pass") }
            FrostView()
                .tabItem { Label("寒霜", systemImage: "snowflake") }
            AlertsView()
                .tabItem { Label("提醒", systemImage: "bell.badge") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .id(currency)
        .sheet(isPresented: $needSetup) { ConnectView(onDone: { needSetup = false }) }
        .onReceive(NotificationCenter.default.publisher(for: .cfgChanged)) { _ in
            needSetup = Cfg.token.isEmpty
        }
        .task { await FX.refresh() }
    }
}

// 首次连接：粘贴令牌，或点令牌链接自动写入
struct ConnectView: View {
    var onDone: () -> Void
    @State private var token = ""
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        BrandMark(size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("连接 TSTZ-M 服务").font(.headline)
                            Text("填入令牌后即可使用全部功能").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("令牌") {
                    SecureField("粘贴令牌", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("从剪贴板粘贴") { token = UIPasteboard.general.string ?? token }
                }
                if let s = status { Section { Text(s).font(.footnote) } }
                Section {
                    Button { Task { await connect() } } label: {
                        HStack { Text("连接"); if busy { Spacer(); ProgressView() } }
                    }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
            }
            .navigationTitle("欢迎")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(Cfg.token.isEmpty)
    }

    private func connect() async {
        busy = true; status = nil
        Cfg.token = token
        do {
            let p: Ping = try await API.get("/v1/ping")
            if p.ok == true { onDone() } else { status = "服务无响应" }
        } catch {
            Cfg.token = ""
            status = error.localizedDescription
        }
        busy = false
    }
}

// 灵动岛盯盘：只在 App 前台时每 15 秒更新一次（免费账号没有远程推送通道）
@MainActor
final class LiveWatch: ObservableObject {
    static let shared = LiveWatch()
    @Published var running = false
    private var activity: Activity<WatchAttributes>?
    private var loop: Task<Void, Never>?

    func start(chain: Chain, address: String, symbol: String, price: Double, change: Double?, liq: Double?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        stop()
        let attrs = WatchAttributes(symbol: symbol, chain: chain.title)
        let st = WatchAttributes.ContentState(price: price, change24h: change, liquidity: liq, updated: Date())
        do {
            activity = try Activity.request(attributes: attrs, content: ActivityContent(state: st, staleDate: nil), pushType: nil)
            running = true
        } catch {
            running = false
            return
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { return }
                let t: TokenResponse? = try? await API.get("/api/token-fast", ["chain": chain.rawValue, "address": address])
                if let p = t?.price?.priceUsd {
                    let s = WatchAttributes.ContentState(price: p, change24h: t?.price?.priceChange24hPct, liquidity: t?.price?.liquidityUsd, updated: Date())
                    await self?.push(s)
                }
            }
        }
    }

    private func push(_ s: WatchAttributes.ContentState) async {
        await activity?.update(ActivityContent(state: s, staleDate: nil))
    }

    func stop() {
        loop?.cancel()
        loop = nil
        let a = activity
        activity = nil
        running = false
        Task { await a?.end(nil, dismissalPolicy: .immediate) }
    }
}
