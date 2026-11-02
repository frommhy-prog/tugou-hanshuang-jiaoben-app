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

// 本机保存的领主资料：服务端没返回的字段（例如王国）用这里兜底，也可以手动修改
struct LordLocal: Codable {
    var id = "726154631"
    var name = "[ONE]卡皮巴拉"
    var kingdom = "4124"
    var initialKingdom = "4186"
    var alliance = "ONE"
}

enum LordStore {
    static var value: LordLocal {
        get {
            guard let d = Cfg.defaults.data(forKey: "lord"), let v = try? JSONDecoder().decode(LordLocal.self, from: d) else { return LordLocal() }
            return v
        }
        set { Cfg.defaults.set(try? JSONEncoder().encode(newValue), forKey: "lord") }
    }
}

@MainActor
final class FrostVM: ObservableObject {
    static var autoRanThisLaunch = false

    @Published var player: WosPlayer?
    @Published var lord = LordStore.value
    @Published var rows: [CodeRow] = []
    @Published var redeemUrl = "https://wos-giftcode.centurygame.com/"
    @Published var loading = false
    @Published var error: String?
    @Published var results: [String: WosResult] = WosStore.results
    @Published var running: Set<String> = []
    @Published var log: [String] = []
    @Published var lastPoll: Date?

    private func pick(_ a: String?, _ b: String) -> String {
        if let a = a, !a.trimmingCharacters(in: .whitespaces).isEmpty { return a }
        return b
    }

    var fid: String { pick(player?.id, lord.id) }
    var nameText: String { pick(player?.name, lord.name) }
    var allianceText: String { pick(player?.alliance, lord.alliance) }
    var kingdomText: String {
        let k = pick(player?.kingdom, lord.kingdom)
        let i = pick(player?.initialKingdom, lord.initialKingdom)
        if k.isEmpty { return "未填写" }
        return i.isEmpty || i == k ? k : k + "（初始 " + i + "）"
    }

    func saveLord(_ l: LordLocal) {
        lord = l
        LordStore.value = l
    }

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

    // 一键兑换：先自动（本机识别验证码），失败由界面自动转到官方页（ID 和兑换码已填好）
    @discardableResult
    func redeem(_ code: String) async -> WosResult? {
        let id = fid
        if id.isEmpty { error = "缺少领主 ID：点「编辑领主资料」填写"; return nil }
        if running.contains(code) { return nil }
        running.insert(code)
        append("—— 兑换 " + code)
        let r = await WosAPI.redeem(fid: id, code: code) { [weak self] s in self?.append(s) }
        var all = WosStore.results
        all[code] = r
        WosStore.results = all
        results = all
        running.remove(code)
        append("结果：" + r.status.title + "（" + r.message + "）")
        return r
    }

    func redeemPending() async -> String? {
        for r in rows {
            if let res = results[r.code], res.status.isFinal { continue }
            if (r.status ?? "").contains("过期") { continue }
            let res = await redeem(r.code)
            if let res = res, res.status == .failed { return r.code }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        return nil
    }
}

struct WebTarget: Identifiable {
    let id = UUID()
    let code: String?
}

struct FrostView: View {
    @StateObject private var vm = FrostVM()
    @ObservedObject private var router = AppRouter.shared
    @AppStorage("wosAuto", store: Cfg.defaults) private var autoOn = false
    @State private var web: WebTarget?
    @State private var editing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    lordCard
                    autoCard
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
                } else if autoOn && !FrostVM.autoRanThisLaunch {
                    FrostVM.autoRanThisLaunch = true
                    if let failed = await vm.redeemPending() { web = WebTarget(code: failed) }
                }
            }
            .onChange(of: router.pendingCode) { _, new in
                guard let c = new, !c.isEmpty else { return }
                Task { await handleDeepLink(c) }
            }
            .sheet(item: $web) { t in
                WebRedeemSheet(url: URL(string: vm.redeemUrl) ?? URL(string: "https://wos-giftcode.centurygame.com/")!, fid: vm.fid, code: t.code)
            }
            .sheet(isPresented: $editing) { LordEditor(lord: vm.lord) { vm.saveLord($0) } }
        }
    }

    private func handleDeepLink(_ code: String) async {
        router.pendingCode = nil
        await vm.load()
        await oneKey(code, forceAuto: autoOn)
    }

    // 自动开启时直接兑换；没开时直接打开官方页。自动失败一律转官方页
    private func oneKey(_ code: String, forceAuto: Bool) async {
        if forceAuto {
            if let r = await vm.redeem(code), r.status == .failed { web = WebTarget(code: code) }
        } else {
            web = WebTarget(code: code)
        }
    }

    private var lordCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "snowflake").font(.title2).foregroundStyle(Color.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.nameText).font(.headline)
                        Text("联盟 " + vm.allianceText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("编辑") { editing = true }.font(.footnote.weight(.semibold))
                }
                HStack(spacing: 10) {
                    StatTile(title: "ID", value: vm.fid)
                    StatTile(title: "王国", value: vm.kingdomText)
                }
                Button {
                    web = WebTarget(code: nil)
                } label: {
                    Label("打开官方兑换中心（已填好 ID）", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var autoCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $autoOn) { Label("发现新码时自动兑换", systemImage: "bolt.fill").font(.headline) }
                Text("打开寒霜页或点开新码推送时，自动在本机识别验证码并兑换；没识别出来或登录失败，会自动打开官方兑换页，ID 和兑换码已填好，你只需输验证码。关掉则只提醒，点「兑换」时直接打开官方页。")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    Task { if let failed = await vm.redeemPending() { web = WebTarget(code: failed) } }
                } label: {
                    Label("立即兑换所有未处理的码", systemImage: "gift.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!vm.running.isEmpty || vm.rows.isEmpty)
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
                    Text("服务器上次检测新码：" + TZ.format(t)).font(.caption2).foregroundStyle(.secondary)
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
                        Text("发现于 " + TZ.format(d) + (r.sources.map { " · \($0) 个来源" } ?? ""))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let res = res { Pill(text: res.status.title, color: res.status.color) }
                else if let s = r.status { Pill(text: s, color: Color.gray) }
            }
            HStack(spacing: 10) {
                Button { Task { await oneKey(r.code, forceAuto: true) } } label: {
                    if busy { ProgressView() } else { Label("兑换", systemImage: "bolt.fill") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
                Button { web = WebTarget(code: r.code) } label: { Label("官方页", systemImage: "safari") }
                    .buttonStyle(.bordered)
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

struct LordEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var lord: LordLocal
    var onSave: (LordLocal) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("领主资料（保存在本机，服务端没返回的字段用这里的）") {
                    TextField("领主 ID", text: $lord.id).keyboardType(.numberPad)
                    TextField("昵称", text: $lord.name)
                    TextField("当前王国", text: $lord.kingdom).keyboardType(.numberPad)
                    TextField("初始王国", text: $lord.initialKingdom).keyboardType(.numberPad)
                    TextField("联盟", text: $lord.alliance)
                }
            }
            .navigationTitle("编辑领主资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { onSave(lord); dismiss() } }
            }
        }
    }
}
