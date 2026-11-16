import SwiftUI
import UIKit

// 首屏布局：K 线高度 = 屏幕高度 − 顶部栏/头部/工具条/底部栏，保证不滑动就能看到基础信息和完整 K 线
enum GMLayout {
    static var chartHeight: CGFloat {
        let h: CGFloat = UIScreen.main.bounds.height
        return max(240, min(560, h - 470))
    }
}

// 查币搜索（代币页顶部的搜索框收进这里，让出屏幕空间）
struct GMSearchSheet: View {
    @ObservedObject var vm: UTokenVM
    @Binding var hist: [HistoryItem]
    @Environment(\.dismiss) private var dismiss
    var onStart: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AvSearchBar(vm: vm, hist: $hist)
                    FavBar(vm: vm)
                    if !hist.isEmpty {
                        Card {
                            AvRecentStrip(items: Array(hist.prefix(12)), showTitle: true) { h in
                                vm.start(h.address)
                                onStart?()
                                dismiss()
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.page)
            .navigationTitle("查币")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: vm.loading) { _, l in
            if l {
                onStart?()
                dismiss()
            }
        }
    }
}

// MARK: - 下拉刷新（不用系统刷新控件，不把内容撑开）：下拉时 Logo 金币随距离翻转放大，松手后浮在顶部播放完整动画，刷新完自动消失
private struct GMPullView: View {
    @ObservedObject var st: LogoPullState

    var body: some View {
        ZStack {
            if st.spinning || st.pull > 0.05 {
                Circle()
                    .fill(Color.clear)
                    .frame(width: 52, height: 52)
                    .shadow(color: Color.clear, radius: 0)
                if st.spinning {
                    LogoLoader(size: 34)
                } else {
                    LogoLoaderFrame(t: 0, size: 34, pull: st.pull)
                }
            }
        }
        .frame(width: 80, height: 80)
        .opacity(st.spinning ? 1 : min(1, st.pull * 1.8))
    }
}

struct LogoRefreshHook: UIViewRepresentable {
    var action: @MainActor () async -> Void
    init(_ action: @escaping @MainActor () async -> Void) { self.action = action }
    var bind: Binding<Bool>? = nil
    init(refreshing: Binding<Bool>, _ action: @escaping @MainActor () async -> Void) {
        self.action = action
        self.bind = refreshing
    }

    func makeCoordinator() -> Coord { Coord() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ v: UIView, context: Context) {
        context.coordinator.action = action
        context.coordinator.bind = bind
        let c = context.coordinator
        DispatchQueue.main.async { c.attach(v) }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coord) {
        coordinator.teardown()
    }

    final class Coord: NSObject {
        var action: (@MainActor () async -> Void)?
        var bind: Binding<Bool>?
        private weak var scroll: UIScrollView?
        private var obs: NSKeyValueObservation?
        private var host: UIHostingController<GMPullView>?
        private let st = LogoPullState()
        private var refreshing = false
        private var armed = false

        func attach(_ v: UIView) {
            if scroll != nil { return }
            var p: UIView? = v
            while let x = p {
                if let s = x as? UIScrollView { install(s); return }
                p = x.superview
            }
        }

        private func install(_ s: UIScrollView) {
            scroll = s
            s.alwaysBounceVertical = true
            let h = UIHostingController(rootView: GMPullView(st: st))
            h.view.backgroundColor = .clear
            h.view.isUserInteractionEnabled = false
            h.view.bounds = CGRect(x: 0, y: 0, width: 80, height: 80)
            host = h
            (s.superview ?? s).addSubview(h.view)
            obs = s.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                self?.onScroll(sv)
            }
        }

        func teardown() {
            obs = nil
            host?.view.removeFromSuperview()
            host = nil
        }

        private func onScroll(_ sv: UIScrollView) {
            guard let h = host else { return }
            let top: CGFloat = sv.adjustedContentInset.top
            let pull: CGFloat = max(0, -(sv.contentOffset.y + top))
            let thr: CGFloat = 78
            if !refreshing {
                if sv.isDragging {
                    let was = armed
                    armed = pull > thr
                    if armed && !was { UISelectionFeedbackGenerator().selectionChanged() }
                } else if armed {
                    fire()
                }
                st.pull = min(1, Double(pull / thr))
            }
            let y: CGFloat = refreshing ? 27 : min(pull, 96) * 0.5 + 10
            h.view.center = CGPoint(x: sv.frame.midX, y: sv.frame.minY + top + y)
        }

        private func fire() {
            if refreshing { return }
            refreshing = true
            armed = false
            st.spinning = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { @MainActor in
                if let b = self.bind { withAnimation(.easeInOut(duration: 0.25)) { b.wrappedValue = true } }
                await self.action?()
                self.st.spinning = false
                self.st.pull = 0
                if let b = self.bind { withAnimation(.easeInOut(duration: 0.25)) { b.wrappedValue = false } }
                self.refreshing = false
            }
        }
    }
}

// MARK: - 设置页新增分组：代币页信息显示、GMGN Key、提醒（提醒页从底部标签移到这里，可选通道）
struct GMSettingsSections: View {
    @AppStorage("gmgnKey", store: Cfg.defaults) private var gmgnKey = ""
    @AppStorage("alertCh.local", store: Cfg.defaults) private var chLocal = true
    @State private var test: String?
    @State private var testing = false
    @State private var showEditor = false
    @State private var showAlerts = false
    @State private var tgOK: Bool?
    @State private var barkOK: Bool?
    @State private var pushInfo: String?

    private let pubKey = "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAqnZdV/OvVE2OmSlRh/0JOrqeRF2YtiLe7IhCI0LmJHk=\n-----END PUBLIC KEY-----"

    private func statusText(_ v: Bool?) -> String {
        guard let v = v else { return "读取中" }
        return v ? "已绑定·已开启" : "未绑定·未开启"
    }

    private func loadKeys() async {
        do {
            let k: KeysResponse = try await API.get("/v1/keys")
            let has = { (id: String) -> Bool in k.providers.first { $0.id == id }?.present ?? false }
            tgOK = has("telegram_token") && has("telegram_chat")
            barkOK = has("bark")
        } catch {
            tgOK = nil
            barkOK = nil
        }
    }

    private func testGMGN() async {
        testing = true
        test = nil
        let r = await GMGNApi.fetch("/v1/token/info", ["chain": "sol", "address": "So11111111111111111111111111111111111111112"])
        switch r {
        case .success: test = "GMGN 连接正常，代币页顶部数据条会自动带上 GMGN 的完整数据"
        case .failure(let e): test = e.localizedDescription
        }
        testing = false
    }

    private func testPush() async {
        struct R: Decodable { var telegram: Bool?; var bark: Bool? }
        do {
            let r: R = try await API.get("/v1/push/test")
            if r.telegram == nil && r.bark == nil { pushInfo = "还没配置推送通道" }
            else { pushInfo = "测试已发送：Telegram " + (r.telegram.map { $0 ? "成功" : "失败" } ?? "未配置") + "，Bark " + (r.bark.map { $0 ? "成功" : "失败" } ?? "未配置") }
        } catch { pushInfo = error.localizedDescription }
    }

    var body: some View {
        Group {
            Section("代币页信息") {
                Button { showEditor = true } label: {
                    Label("调整顶部数据的显示项和顺序", systemImage: "slider.horizontal.3")
                }
                .sheet(isPresented: $showEditor) { GMMetricEditor() }
                Text("钱包占比、捆绑、狙击、老鼠仓、钓鱼、税率、Dev 持仓、Dex 付费等都可以开关、拖动排序；代币页顶部的「调」按钮也能进入。").font(.caption).foregroundStyle(.secondary)
            }
            Section("GMGN 数据（免费 API Key）") {
                SecureField(gmgnKey.isEmpty ? "粘贴 GMGN API Key" : "Key 已保存（粘贴新 Key 可替换）", text: $gmgnKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button("测试连接") { Task { await testGMGN() } }.disabled(testing || gmgnKey.isEmpty)
                    if testing { Spacer(); ProgressView() }
                }
                if let t = test { Text(t).font(.footnote).foregroundStyle(.secondary) }
                Text("获取方法：打开 gmgn.ai/ai → 创建 API Key → 把下面这段公钥粘贴进去 → 把生成的 API Key 填到上面。只读数据不需要私钥。GMGN 只支持 IPv4，连不上时试试 Wi-Fi。").font(.caption).foregroundStyle(.secondary)
                Text(pubKey).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                Button("复制公钥") { UIPasteboard.general.string = pubKey }
            }
            GMTabSettings()
            GMFreeSettings()
            Section("提醒") {
                Toggle("本地通知（App 在前台时监控收藏）", isOn: $chLocal)
                HStack { Text("Telegram 推送"); Spacer(); Text(statusText(tgOK)).font(.footnote).foregroundStyle(.secondary) }
                HStack { Text("Bark 推送"); Spacer(); Text(statusText(barkOK)).font(.footnote).foregroundStyle(.secondary) }
                NavigationLink("绑定 / 更换 Telegram 和 Bark") { KeysView() }
                Button { showAlerts = true } label: {
                    Label("我的提醒规则（价格、涨跌、流动性）", systemImage: "bell.badge")
                }
                .sheet(isPresented: $showAlerts) { AlertsView() }
                Button("发送测试推送") { Task { await testPush() } }
                if let p = pushInfo { Text(p).font(.footnote).foregroundStyle(.secondary) }
                Text("三个通道可以同时开启：本地通知用上面的开关控制；Telegram / Bark 绑定密钥就开启、删除密钥就关闭，由服务器每 5 分钟检查提醒规则并推送。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await loadKeys() }
    }
}
