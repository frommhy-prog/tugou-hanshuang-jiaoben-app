import SwiftUI
import UIKit

struct WosServerResponse: Decodable {
    struct Item: Decodable {
        var code: String
        var firstSeen: Double?
        var sources: Int?
    }
    var codes: [Item]?
    var lastPollAt: Double?
}

struct CodeRow: Identifiable {
    let code: String
    var rewards: String?
    var status: String?
    var firstSeen: Date?
    var sources: Int?
    var id: String { code }
}

@MainActor
final class FrostVM: ObservableObject {
    static var autoRanThisLaunch = false

    @Published var player: WosPlayer?
    @Published var rows: [CodeRow] = []
    @Published var redeemUrl = "https://wos-giftcode.centurygame.com/"
    @Published var loading = false
    @Published var error: String?
    @Published var results: [String: WosResult] = WosStore.results
    @Published var running: Set<String> = []
    @Published var log: [String] = []
    @Published var lastPoll: Date?

    var fid: String? { player?.id }

    func append(_ s: String) {
        log.append(s)
        if log.count > 80 { log.removeFirst(log.count - 80) }
    }

    func load(poll: Bool = false) async {
        loading = true
        error = nil
        if poll {
            let _: API.Empty? = try? await API.get("/v1/wos/poll")
        }
        if let p: ProfileResponse = try? await API.get("/v1/config"), let pr = p.profile {
            player = pr
            if let u = pr.redeemUrl, !u.isEmpty { redeemUrl = u }
        }
        var merged: [CodeRow] = []
        if let s: WosServerResponse = try? await API.get("/v1/wos/codes") {
            if let t = s.lastPollAt { lastPoll = Date(timeIntervalSince1970: t / 1000) }
            for i in s.codes ?? [] where !merged.contains(where: { $0.code == i.code }) {
                let d: Date? = i.firstSeen.map { Date(timeIntervalSince1970: $0 / 1000) }
                merged.append(CodeRow(code: i.code, rewards: nil, status: nil, firstSeen: d, sources: i.sources))
            }
        }
        do {
            let r: WosCodesResponse = try await API.get("/api/wos-codes")
            if player == nil { player = r.player }
            for c in r.codes ?? [] {
                guard let code = c.code else { continue }
                if let idx = merged.firstIndex(where: { $0.code == code }) {
                    merged[idx].rewards = c.rewards
                    merged[idx].status = c.status
                } else {
                    merged.append(CodeRow(code: code, rewards: c.rewards, status: c.status, firstSeen: nil, sources: nil))
                }
            }
        } catch {
            if merged.isEmpty { self.error = error.localizedDescription }
        }
        rows = merged
        loading = false
    }

    func redeem(_ code: String) async {
        guard let fid = fid, !fid.isEmpty else { error = "缺少领主 ID"; return }
        if running.contains(code) { return }
        running.insert(code)
        append("—— 兑换 " + code)
        let r = await WosAPI.redeem(fid: fid, code: code) { [weak self] s in self?.append(s) }
        var all = WosStore.results
        all[code] = r
        WosStore.results = all
        results = all
        running.remove(code)
        append("结果：" + r.status.title + "（" + r.message + "）")
    }

    func redeemPending() async {
        for r in rows {
            if let res = results[r.code], res.status.isFinal { continue }
            if (r.status ?? "").contains("过期") { continue }
            await redeem(r.code)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }
}

struct WebTarget: Identifiable {
    let id = UUID()
    let code: String?
}

struct FrostView: View {
    @StateObject private var vm = FrostVM()
    @ObservedObject private var router = AppRouter.shared
    @AppStorage("wosMode", store: Cfg.defaults) private var mode = "manual"
    @State private var web: WebTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    lordCard
                    modeCard
                    if let e = vm.error { ErrorCard(text: e) { Task { await vm.load() } } }
                    codesCard
                    if !vm.log.isEmpty { logCard }
                }
                .padding(16)
            }
            .background(Color.page)
            .navigationTitle("寒霜启示录")
            .refreshable { await vm.load(poll: true) }
            .task {
                await vm.load()
                if let c = router.pendingCode {
                    await handleDeepLink(c)
                } else if mode == "auto" && !FrostVM.autoRanThisLaunch {
                    FrostVM.autoRanThisLaunch = true
                    await vm.redeemPending()
                }
            }
            .onChange(of: router.pendingCode) { _, new in
                guard let c = new, !c.isEmpty else { return }
                Task { await handleDeepLink(c) }
            }
            .sheet(item: $web) { t in
                WebRedeemSheet(url: URL(string: vm.redeemUrl) ?? URL(string: "https://wos-giftcode.centurygame.com/")!, fid: vm.fid ?? "", code: t.code)
            }
        }
    }

    private func handleDeepLink(_ code: String) async {
        router.pendingCode = nil
        await vm.load()
        if mode == "auto" { await vm.redeem(code) } else { web = WebTarget(code: code) }
    }

    private var lordCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "snowflake").font(.title2).foregroundStyle(Color.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.player?.name ?? "领主信息").font(.headline)
                        Text("联盟 " + (vm.player?.alliance ?? "—")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    StatTile(title: "ID", value: vm.player?.id ?? "—")
                    StatTile(title: "王国", value: kingdomText)
                }
                Button {
                    web = WebTarget(code: nil)
                } label: {
                    Label("打开官方兑换中心（已填好 ID）", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.player?.id == nil)
            }
        }
    }

    private var kingdomText: String {
        guard let k = vm.player?.kingdom else { return "—" }
        if let i = vm.player?.initialKingdom, !i.isEmpty { return k + "（初始 " + i + "）" }
        return k
    }

    private var modeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("兑换方式", systemImage: "slider.horizontal.3").font(.headline)
                Picker("兑换方式", selection: $mode) {
                    Text("手动").tag("manual")
                    Text("自动").tag("auto")
                }
                .pickerStyle(.segmented)
                Text(mode == "auto"
                     ? "自动：新码推送后点开 App，或你打开寒霜页时，自动识别验证码并兑换。识别失败会如实显示，可随时改手动。"
                     : "手动：新码只提醒，你点「手动兑换」后在应用内打开官方页，ID 和兑换码已填好，验证码你自己输。")
                    .font(.caption).foregroundStyle(.secondary)
                if mode == "auto" {
                    Button {
                        Task { await vm.redeemPending() }
                    } label: {
                        Label("立即自动兑换所有未处理的码", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!vm.running.isEmpty)
                }
            }
        }
    }

    private var codesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("兑换码", systemImage: "gift").font(.headline)
                    Spacer()
                    if vm.loading { ProgressView() }
                }
                if vm.rows.isEmpty && !vm.loading {
                    Text("暂无兑换码，下拉刷新会立即检测一次").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(vm.rows) { r in
                    codeRow(r)
                    Divider()
                }
                if let t = vm.lastPoll {
                    Text("服务器上次检测新码：" + t.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                }
                Text("新码来自多个社区站点的共识检测，可能漏报或误报，以兑换结果为准；发现新码时会推送到 Telegram / Bark。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func codeRow(_ r: CodeRow) -> some View {
        let res = vm.results[r.code]
        let busy = vm.running.contains(r.code)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.code).font(.system(.body, design: .monospaced).weight(.semibold))
                    if let rw = r.rewards, !rw.isEmpty { Text(rw).font(.caption).foregroundStyle(.secondary) }
                    if let d = r.firstSeen {
                        Text("发现于 " + d.formatted(date: .abbreviated, time: .shortened) + (r.sources.map { " · \($0) 个来源" } ?? ""))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let res = res { Pill(text: res.status.title, color: res.status.color) }
                else if let s = r.status { Pill(text: s, color: Color.gray) }
            }
            HStack(spacing: 10) {
                Button { web = WebTarget(code: r.code) } label: { Label("手动兑换", systemImage: "hand.tap") }
                    .buttonStyle(.bordered)
                Button { Task { await vm.redeem(r.code) } } label: {
                    if busy { ProgressView() } else { Label("自动兑换", systemImage: "bolt.fill") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
            }
            .controlSize(.small)
            if let res = res, res.status == .failed {
                Text(res.message).font(.caption2).foregroundStyle(Color.orange)
            }
        }
    }

    private var logCard: some View {
        Card {
            DisclosureGroup("兑换日志（排查用）") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(vm.log.enumerated()), id: \.offset) { _, s in
                        Text(s).font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    Button("复制日志") { UIPasteboard.general.string = vm.log.joined(separator: "\n") }
                        .font(.caption.weight(.semibold))
                }
                .padding(.top, 6)
            }
        }
    }
}
