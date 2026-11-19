import SwiftUI

// MARK: - 大户拆解（直接在页面里展开，不跳转）+ 没有 GMGN / OKX Key 时的本机推算指标
struct GXDerivedVals {
    var scanned: Int = 0          // 已拆解入场时点的大户数
    var sniperPct: Double = 0     // 1 分钟内入场的大户当前持仓合计
    var sniperN: Int = 0
    var earlyPct: Double = 0      // 10 分钟内入场
    var intelN: Int = 0           // 已出钱包情报的大户数（Solana）
    var smartN: Int = 0
    var smartPct: Double = 0
    var botN: Int = 0
    var botPct: Double = 0
    var freshN: Int = 0
    var freshPct: Double = 0
}

@MainActor
final class GXHoldersStore: ObservableObject {
    static let shared = GXHoldersStore()
    @Published var reports: [String: IntelReport] = [:]
    @Published var errors: [String: String] = [:]
    @Published var done = 0
    @Published var total = 0
    @Published var running = false
    @Published var derived = GXDerivedVals()
    private var key = ""

    func fetchOne(_ addr: String) async -> IntelReport? {
        if let r = reports[addr] { return r }
        do {
            let r: IntelReport = try await AIChain.timed(45) { try await IntelVM.shared.fetch(addr, pages: 2, fresh: false) }
            reports[addr] = r
            errors[addr] = nil
            return r
        } catch {
            errors[addr] = Net.message(error)
            return nil
        }
    }

    private func bump() { done += 1 }

    func run(vm: UTokenVM, force: Bool = false) async {
        let k: String = vm.chain.rawValue + ":" + vm.address
        if !force && k == key && (running || (total > 0 && done >= total)) {
            recompute(vm)
            return
        }
        key = k
        let owners: [String] = vm.holders.filter { $0.kind == "wallet" }.prefix(20).map { $0.owner }
        total = owners.count
        done = 0
        errors = [:]
        if vm.chain != .solana || owners.isEmpty {
            recompute(vm)
            done = total
            return
        }
        running = true
        let lanes: Int = 3
        await withTaskGroup(of: Void.self) { g in
            for lane in 0..<lanes {
                g.addTask { [weak self] in
                    var i: Int = lane
                    while i < owners.count {
                        _ = await self?.fetchOne(owners[i])
                        await self?.bump()
                        await self?.recompute(vm)
                        i += lanes
                    }
                }
            }
        }
        running = false
        recompute(vm)
    }

    func recompute(_ vm: UTokenVM) {
        var d = GXDerivedVals()
        let ws = vm.holders.filter { $0.kind == "wallet" }.prefix(20)
        for h in ws {
            let pct: Double = h.pct ?? 0
            let an: UHolderAnalysis? = vm.analyses[h.owner] ?? vm.analyses[h.owner.lowercased()]
            if let dm = an?.position?.delayMin {
                d.scanned += 1
                if dm <= 1 { d.sniperPct += pct; d.sniperN += 1 }
                if dm <= 10 { d.earlyPct += pct }
            }
            if let r = reports[h.owner] {
                d.intelN += 1
                if r.has("聪明钱（样本内）") { d.smartN += 1; d.smartPct += pct }
                if r.has("机器人") || r.has("狙击手 / 极短线") { d.botN += 1; d.botPct += pct }
                if r.has("新钱包") { d.freshN += 1; d.freshPct += pct }
            }
        }
        derived = d
    }

    // 顶部数据条：GMGN / 免费来源都没有这一项时，用本机链上推算顶上
    func override(_ id: String, vm: UTokenVM, gm: GMGNStore) -> GMVal? {
        let d: GXDerivedVals = derived
        let fs = GMFreeStore.shared
        switch id {
        case "sniper":
            if gm.num("sniper_count", "wallet_tags_stat.sniper_wallets") != nil || gm.sniperHold() != nil { return nil }
            if fs.v["sniper"] != nil || fs.v["sniperN"] != nil { return nil }
            if d.scanned < 1 { return nil }
            return GMVal(text: String(format: "%.1f%%", d.sniperPct), color: GMMetricCatalog.pctColor(d.sniperPct, 3, 10), rows: [
                ("1 分钟内入场的大户当前持仓", String(format: "%.2f%%", d.sniperPct)),
                ("其中钱包数", String(d.sniperN) + " 个"),
                ("10 分钟内入场的大户持仓", String(format: "%.2f%%", d.earlyPct)),
                ("统计范围", "前 " + String(d.scanned) + " 大户（已拆解入场时点），不含更小的钱包"),
                ("数据来源", "本机链上推算（不需要 GMGN / OKX Key）"),
            ])
        case "smart":
            if gm.num("wallet_tags_stat.smart_wallets") != nil || fs.v["smartN"] != nil || fs.v["kolN"] != nil { return nil }
            if d.intelN < 3 { return nil }
            return GMVal(text: String(d.smartN) + "/—", color: d.smartN > 0 ? Color.green : Color.secondary, rows: [
                ("样本内聪明钱大户", String(d.smartN) + " 个，合计持有 " + String(format: "%.2f%%", d.smartPct)),
                ("已查询大户", String(d.intelN) + " 个"),
                ("判定", "已平仓 ≥ 10 个、胜率 ≥ 55%、盈亏比 ≥ 1.5 且净盈利"),
                ("数据来源", "本机钱包情报引擎（样本内，不代表未来）"),
            ])
        case "fresh":
            if gm.num("stat.fresh_wallet_rate") != nil { return nil }
            if d.intelN < 3 { return nil }
            let p: Double = d.freshPct
            return GMVal(text: String(d.freshN) + " 个", color: GMMetricCatalog.pctColor(p, 5, 20), rows: [
                ("不到 7 天的新钱包大户", String(d.freshN) + " 个，合计持有 " + String(format: "%.2f%%", p)),
                ("已查询大户", String(d.intelN) + " 个"),
                ("数据来源", "本机钱包情报引擎"),
            ])
        default:
            return nil
        }
    }
}

struct GXHoldersInline: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var hs = GXHoldersStore.shared
    @State private var open: Set<String> = []

    private func chip(_ e: String, _ t: String, _ c: Color) -> some View {
        HStack(spacing: 3) {
            Text(e).font(.caption2)
            Text(t).font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(c.opacity(0.15), in: Capsule())
        .foregroundStyle(c)
    }

    @ViewBuilder
    private var summary: some View {
        let d: GXDerivedVals = hs.derived
        if d.scanned > 0 || d.intelN > 0 {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if d.scanned > 0 {
                            chip("🎯", "1分钟内入场 " + String(format: "%.1f%%", d.sniperPct) + "（" + String(d.sniperN) + "个）", d.sniperPct >= 10 ? Color.red : Color.orange)
                            chip("⚡", "10分钟内 " + String(format: "%.1f%%", d.earlyPct), Color.orange)
                        }
                        if d.intelN > 0 {
                            chip("🧠", "聪明钱 " + String(d.smartN), Color.green)
                            chip("🤖", "机器人/狙击手 " + String(d.botN) + "（" + String(format: "%.1f%%", d.botPct) + "）", Color.orange)
                            chip("🌱", "新钱包 " + String(d.freshN) + "（" + String(format: "%.1f%%", d.freshPct) + "）", Color.green)
                        }
                    }
                }
                Text("统计范围：前 " + String(max(d.scanned, d.intelN)) + " 个大户。这些数字会自动补到代币页顶部对应的格子（没有 GMGN / OKX Key 时）。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func state(_ h: UHolder) -> String {
        if let r = hs.reports[h.owner] { return r.labels.isEmpty ? "无特征标签" : r.labels.map { $0.name }.joined(separator: "、") }
        if let e = hs.errors[h.owner] { return "读取失败：" + e }
        if vm.chain != .solana { return "EVM：见下方成本盈亏拆解" }
        return hs.running ? "排队 / 读取中…" : "未查询"
    }

    @ViewBuilder
    private func detail(_ h: UHolder) -> some View {
        if let r = hs.reports[h.owner] {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(r.labels) { l in
                    Text("· " + l.name + "：" + l.basis).font(.caption2).foregroundStyle(.secondary)
                }
                if let s = r.score { Text("跟单价值分 " + String(s) + "（样本内表现，不是买卖建议）").font(.caption.weight(.semibold)) }
                ForEach(Array(r.metrics.prefix(6).enumerated()), id: \.offset) { _, m in
                    HStack { Text(m[0]).font(.caption).foregroundStyle(.secondary); Spacer(); Text(m[1]).font(.caption.weight(.semibold)) }
                }
                ForEach(r.signals.prefix(4)) { s in
                    Text("⚠︎ " + s.title + "：" + s.text).font(.caption2).foregroundStyle(Color.orange)
                }
                Text("钱包头像点开可看完整情报与一键跳转。").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func row(_ h: UHolder) -> some View {
        let tags: [GXTag] = GXWalletTags.tags(chain: vm.chain, addr: h.owner, vm: vm)
        let p = (vm.analyses[h.owner] ?? vm.analyses[h.owner.lowercased()])?.position
        let isOpen: Bool = open.contains(h.owner)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("#" + String(h.rank)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                GXWalletLabel(chain: vm.chain, addr: h.owner)
                Spacer()
                Text(h.pct.map { String(format: "%.2f%%", $0) } ?? "—").font(.caption.weight(.semibold).monospacedDigit())
                if let r = p?.roi {
                    Text(String(format: "%+.0f%%", r * 100)).font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(r >= 0 ? Color.green : Color.red)
                }
                Button {
                    if isOpen { open.remove(h.owner) } else { open.insert(h.owner) }
                } label: {
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tags) { t in
                            HStack(spacing: 3) {
                                if let b = t.brand { GMBrandIcon(key: b, size: 11) } else { Text(t.emoji).font(.system(size: 10)) }
                                Text(t.text).font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(t.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(t.color)
                        }
                    }
                }
            }
            Text(state(h)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            if isOpen { detail(h) }
            Divider()
        }
    }

    var body: some View {
        let ws: [UHolder] = Array(vm.holders.filter { $0.kind == "wallet" }.prefix(20))
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("大户情报（直接拆解）", systemImage: "person.3.sequence.fill").font(.headline)
                    Spacer()
                    if hs.running { ProgressView() }
                    Text(hs.total > 0 ? "已查 " + String(min(hs.done, hs.total)) + "/" + String(hs.total) : "").font(.caption).foregroundStyle(.secondary)
                    Button { Task { await hs.run(vm: vm, force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(hs.running)
                }
                if ws.isEmpty {
                    Text(vm.holderNote ?? "读取链上持有人…").font(.footnote).foregroundStyle(.secondary)
                } else {
                    summary
                    ForEach(ws, id: \.owner) { h in row(h) }
                    Text("点钱包头像 → 钱包卡片（标签、完整情报、跳转 GMGN / AVE / 欧易 / 币安 …）；点右侧箭头展开这个大户的指标和行为信号。聪明钱、机器人、新钱包都由本机按链上成交算出，只代表这段样本。").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: vm.address + "|" + String(vm.holders.count)) {
            if !vm.holders.isEmpty { await hs.run(vm: vm) }
        }
    }
}
