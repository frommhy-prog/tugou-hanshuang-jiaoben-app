import SwiftUI

// MARK: - EVM 钱包分析（引擎 /e/evm/wallet）。字段全部可选：缺字段显示「未知」，不编数
struct EvmStats: Codable {
    var xferN: Int?
    var hashN: Int?
    var pages: Int?
    var complete: Bool?
    var tradeN: Int?
    var approxN: Int?
    var multiSkipped: Int?
    var inboundN: Int?
    var from: Double?
    var to: Double?
    var spanDays: Double?
    var tokensTraded: Int?
    var realizedN: Int?
    var winN: Int?
    var winRate: Double?
    var realizedNative: Double?
    var realizedUsd: Double?
    var closedN: Int?
    var medHoldSec: Double?
    var medBuyNative: Double?
    var medBuyUsd: Double?
    var perDay: Double?
    var uncoveredTokens: Int?
    var nativeQuoteTrades: Int?
    var usdQuoteTrades: Int?
}

struct EvmPosition: Codable, Identifiable {
    var token: String
    var sym: String?
    var q: String?
    var buys: Int?
    var sells: Int?
    var boughtAmt: Double?
    var soldAmt: Double?
    var realized: Double?
    var remainingQty: Double?
    var remainingCost: Double?
    var unrealized: Double?
    var bestTx: String?
    var worstTx: String?
    var id: String { token + (q ?? "") }
}

struct EvmTrade: Codable, Identifiable {
    var tx: String
    var t: Double
    var token: String
    var side: String
    var qty: Double?
    var amt: Double?
    var q: String?
    var approx: Bool?
    var sym: String?
    var id: String { tx + token }
}

struct EvmWallet: Codable {
    var chain: String?
    var address: String?
    var native: String?
    var stats: EvmStats?
    var tags: [SolTag]?
    var notes: [String]?
    var sample: String?
    var positions: [EvmPosition]?
    var trades: [EvmTrade]?
    var error: String?
    var detail: String?
}

struct EvmFacts: Encodable {
    var address: String
    var chain: String
    var native: String?
    var stats: EvmStats?
    var tags: [SolTag]
    var notes: [String]
    var sample: String?
    var topPositions: [EvmPosition]
}

enum EvmScan {
    static func host(_ c: String) -> String {
        switch c {
        case "bsc": return "bscscan.com"
        case "base": return "basescan.org"
        case "arbitrum": return "arbiscan.io"
        case "optimism": return "optimistic.etherscan.io"
        case "polygon": return "polygonscan.com"
        default: return "etherscan.io"
        }
    }
    static func tx(_ c: String, _ h: String) -> URL? { URL(string: "https://" + host(c) + "/tx/" + h) }
}

enum EvmFmt {
    static func amt(_ v: Double?, _ q: String?, _ native: String?) -> String {
        guard let v = v else { return "未知" }
        if q == "USD" { return String(format: "%.2f", v) + " USD" }
        return String(format: "%.4f", v) + " " + (native ?? "")
    }
    static func signed(_ v: Double?, _ unit: String) -> String {
        guard let v = v else { return "未知" }
        if unit == "USD" { return String(format: "%+.2f", v) + " USD" }
        return String(format: "%+.4f", v) + " " + unit
    }
    static func errorText(_ e: String, _ detail: String?) -> String {
        if e == "no_alchemy_key" { return "引擎还没有配置 Alchemy 密钥，EVM 交易记录暂时读不了（密钥配好后重试）" }
        if e == "chain_unsupported" { return "这条链引擎暂不支持" }
        return e + (detail.map { "：" + $0 } ?? "")
    }
}

// MARK: - 状态
@MainActor
final class EvmDetailVM: ObservableObject {
    static let supported = ["bsc", "eth", "base", "arbitrum", "optimism", "polygon"]
    @Published var chains: [String] = []
    @Published var skipped: [String] = []
    @Published var chain = ""
    @Published var w: EvmWallet?
    @Published var loading = false
    @Published var error: String?
    @Published var pages = 3
    @Published var ai: AIResult?
    @Published var aiLoading = false
    @Published var aiMsg: String?
    private var loadedKey = ""

    func setup(_ wallet: Wallet) {
        if !chains.isEmpty { return }
        let have = wallet.chains
        chains = EvmDetailVM.supported.filter { have.contains($0) }
        skipped = have.filter { !EvmDetailVM.supported.contains($0) && $0 != "solana" }
        chain = chains.first ?? ""
    }

    func ensure(_ wallet: Wallet) async {
        setup(wallet)
        if chain.isEmpty { return }
        if loadedKey == chain + wallet.address && w != nil { return }
        if loading { return }
        await load(wallet.address)
    }

    func select(_ c: String, wallet: Wallet) {
        chain = c
        w = nil
        error = nil
        ai = nil
        aiMsg = nil
        Task { await load(wallet.address) }
    }

    // 自己的钱包一律 fresh=1，不走缓存
    func load(_ address: String) async {
        if chain.isEmpty { return }
        loading = true
        error = nil
        ai = nil
        aiMsg = nil
        let ch = chain
        do {
            let r: EvmWallet = try await Engine.get("/e/evm/wallet", ["chain": ch, "address": address, "pages": String(pages), "fresh": "1"])
            if ch != chain { loading = false; return }
            if let e = r.error {
                error = EvmFmt.errorText(e, r.detail)
                w = nil
            } else {
                w = r
                loadedKey = ch + address
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
        if w != nil { await runAI(address) }
    }

    func runAI(_ address: String) async {
        guard let w = w else { return }
        aiLoading = true
        aiMsg = nil
        defer { aiLoading = false }
        let top = (w.positions ?? []).sorted { abs($0.realized ?? 0) > abs($1.realized ?? 0) }.prefix(8)
        let facts = EvmFacts(address: address, chain: chain, native: w.native, stats: w.stats, tags: w.tags ?? [], notes: w.notes ?? [], sample: w.sample, topPositions: Array(top))
        do {
            let r: AIResult = try await Engine.post("/e/ai", AIPayload(kind: "EVM 钱包交易记录分析", facts: facts))
            if let m = aiMessage(r) { aiMsg = m } else { ai = r }
        } catch {
            aiMsg = error.localizedDescription
        }
    }
}

// MARK: - 链选择条
struct EvmChainBar: View {
    @ObservedObject var vm: EvmDetailVM
    let wallet: Wallet
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if vm.chains.count > 1 {
                Picker("链", selection: Binding(get: { vm.chain }, set: { c in vm.select(c, wallet: wallet) })) {
                    ForEach(vm.chains, id: \.self) { c in
                        Text(Chain(rawValue: c)?.title ?? c).tag(c)
                    }
                }
                .pickerStyle(.segmented)
            } else if let c = vm.chains.first {
                Pill(text: Chain(rawValue: c)?.title ?? c, color: Color.blue)
            }
            if !vm.skipped.isEmpty {
                let names = vm.skipped.map { Chain(rawValue: $0)?.title ?? $0 }.joined(separator: "、")
                Text("暂不支持逐笔记录的链：" + names).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 交易记录
struct EvmTradesBody: View {
    let wallet: Wallet
    @ObservedObject var vm: EvmDetailVM

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("交易记录（swap）", systemImage: "arrow.left.arrow.right").font(.headline)
                    Spacer()
                    if vm.loading { ProgressView() }
                }
                EvmChainBar(vm: vm, wallet: wallet)
                if vm.chains.isEmpty {
                    Text("这个钱包没有勾选引擎支持的 EVM 链（支持 BSC、ETH、Base、Arbitrum、Optimism、Polygon）").font(.footnote).foregroundStyle(.secondary)
                } else if let e = vm.error {
                    Text(e).font(.footnote).foregroundStyle(Color.orange)
                    Button("重试") { Task { await vm.load(wallet.address) } }.font(.footnote.weight(.semibold))
                } else if let w = vm.w {
                    tradesList(w)
                } else if vm.loading {
                    Text("正在读取链上转账记录并配对买卖…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .task { await vm.ensure(wallet) }
    }

    private func tradesList(_ w: EvmWallet) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let s = w.stats {
                let done = s.complete == true ? "（已到最早记录）" : "（更早的未读取）"
                Text("窗口内 \(s.hashN ?? 0) 笔链上交易，其中 \(s.tradeN ?? 0) 笔能配对成该钱包的买卖" + done).font(.caption).foregroundStyle(.secondary)
            }
            if (w.trades ?? []).isEmpty {
                Text("窗口内没有能配对成买卖的记录").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(w.trades ?? []) { t in
                HStack(alignment: .top) {
                    Pill(text: t.side == "buy" ? "买" : "卖", color: t.side == "buy" ? Color.green : Color.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.sym ?? Addr.short(t.token)).font(.subheadline.weight(.semibold))
                        Text(Fmt2.time(t.t)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text((t.approx == true ? "≈ " : "") + EvmFmt.amt(t.amt, t.q, w.native)).font(.subheadline.monospacedDigit())
                        Text(Fmt2.qty(t.qty) + " 枚").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let u = EvmScan.tx(vm.chain, t.tx) { Link(destination: u) { Image(systemName: "arrow.up.right.square") } }
                }
                Divider()
            }
            Button {
                vm.pages = min(6, vm.pages + 1)
                Task { await vm.load(wallet.address) }
            } label: { Label("加载更早的记录（每个方向多读 1000 条转账）", systemImage: "clock.arrow.circlepath") }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(vm.loading || vm.pages >= 6 || w.stats?.complete == true)
            Text("带「≈」的卖出所得由区块前后余额变化反推，是近似值；每笔可点右侧图标到区块浏览器核对原始交易").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 分析
struct EvmStatsGrid: View {
    let s: EvmStats
    let native: String

    private var windowText: String {
        let n = s.hashN.map { "\($0) 笔交易" } ?? "未知"
        let d = s.spanDays.map { String(format: " / %.1f 天", $0) } ?? ""
        return n + d
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            StatTile(title: "分析窗口", value: windowText)
            StatTile(title: "涉及代币", value: s.tokensTraded.map { "\($0) 个" } ?? "未知")
            StatTile(title: "已兑现盈亏（\(native) 计价）", value: (s.realizedN ?? 0) > 0 ? EvmFmt.signed(s.realizedNative, native) : "样本不足", tint: (s.realizedNative ?? 0) >= 0 ? Color.green : Color.red)
            if (s.usdQuoteTrades ?? 0) > 0 {
                StatTile(title: "已兑现盈亏（稳定币计价）", value: EvmFmt.signed(s.realizedUsd, "USD"), tint: (s.realizedUsd ?? 0) >= 0 ? Color.green : Color.red)
            }
            StatTile(title: "胜率", value: s.winRate.map { String(format: "%.0f%%（%d/%d）", $0 * 100, s.winN ?? 0, s.realizedN ?? 0) } ?? "样本不足")
            StatTile(title: "持仓时间中位数", value: (s.closedN ?? 0) > 0 ? Fmt2.dur(s.medHoldSec) : "样本不足")
            StatTile(title: "单笔买入中位数", value: s.medBuyNative.map { String(format: "%.4f", $0) + " " + native } ?? "未知")
        }
    }
}

struct EvmAnalysisBody: View {
    let wallet: Wallet
    @ObservedObject var vm: EvmDetailVM

    var body: some View {
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    EvmChainBar(vm: vm, wallet: wallet)
                    if vm.chains.isEmpty { Text("这个钱包没有勾选引擎支持的 EVM 链").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            if let e = vm.error {
                ErrorCard(text: e) { Task { await vm.load(wallet.address) } }
            } else if let w = vm.w {
                content(w)
            } else if vm.loading {
                Card { HStack(spacing: 10) { ProgressView(); Text("正在读取并分析链上交易…").foregroundStyle(.secondary) } }
            }
        }
        .task { await vm.ensure(wallet) }
    }

    private func content(_ w: EvmWallet) -> some View {
        let native = w.native ?? ""
        return VStack(spacing: 14) {
            if let s = w.stats {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("交易统计", systemImage: "chart.bar.xaxis").font(.headline)
                        EvmStatsGrid(s: s, native: native)
                        if let sp = w.sample { Text(sp).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if let tags = w.tags, !tags.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("交易风格（规则判定，附依据）", systemImage: "tag").font(.headline)
                        ForEach(tags) { TagRow(t: $0) }
                    }
                }
            } else {
                Card { Text("按透明规则判定，当前样本没有触发任何风格标签。").font(.footnote).foregroundStyle(.secondary) }
            }
            AIResultCard(title: "AI 解读", result: vm.ai, loading: vm.aiLoading, message: vm.aiMsg, onRun: { Task { await vm.runAI(wallet.address) } })
            unitCard(w, q: "NATIVE", unit: native)
            unitCard(w, q: "USD", unit: "USD")
            if let n = w.notes, !n.isEmpty {
                Card { VStack(alignment: .leading, spacing: 4) { ForEach(Array(n.enumerated()), id: \.offset) { _, s in Text("· " + s).font(.caption2).foregroundStyle(.secondary) } } }
            }
        }
    }

    @ViewBuilder
    private func unitCard(_ w: EvmWallet, q: String, unit: String) -> some View {
        let ps = (w.positions ?? []).filter { $0.q == q }
        let realized = ps.filter { ($0.sells ?? 0) > 0 && ($0.realized ?? 0) != 0 }.sorted { ($0.realized ?? 0) > ($1.realized ?? 0) }
        let wins = Array(realized.filter { ($0.realized ?? 0) > 0 }.prefix(5))
        let losses = Array(realized.filter { ($0.realized ?? 0) < 0 }.reversed().prefix(5))
        let open = Array(ps.filter { ($0.remainingQty ?? 0) > 0 }.sorted { ($0.remainingCost ?? 0) > ($1.remainingCost ?? 0) }.prefix(8))
        if !ps.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("按币盈亏（\(unit) 计价，窗口内）", systemImage: "list.number").font(.headline)
                    if !wins.isEmpty { Text("盈利最多").font(.caption.weight(.semibold)).foregroundStyle(.secondary); ForEach(wins) { posRow($0, unit: unit) } }
                    if !losses.isEmpty { Text("亏损最多").font(.caption.weight(.semibold)).foregroundStyle(.secondary); ForEach(losses) { posRow($0, unit: unit) } }
                    if !open.isEmpty { Text("窗口内仍持有（按成本）").font(.caption.weight(.semibold)).foregroundStyle(.secondary); ForEach(open) { posRow($0, unit: unit) } }
                    if wins.isEmpty && losses.isEmpty && open.isEmpty { Text("窗口内没有可计算盈亏的币").font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func posRow(_ p: EvmPosition, unit: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.sym ?? Addr.short(p.token)).font(.subheadline.weight(.semibold))
                Text("买 \(p.buys ?? 0) 笔 " + EvmFmt.amt(p.boughtAmt, p.q, unit) + " · 卖 \(p.sells ?? 0) 笔 " + EvmFmt.amt(p.soldAmt, p.q, unit)).font(.caption2).foregroundStyle(.secondary)
                if (p.remainingQty ?? 0) > 0 {
                    let fl = p.unrealized != nil ? " · 浮动 " + EvmFmt.signed(p.unrealized, unit) : " · 无法估值"
                    Text("剩余成本 " + EvmFmt.amt(p.remainingCost, p.q, unit) + fl).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(EvmFmt.signed(p.realized, unit)).font(.subheadline.monospacedDigit()).foregroundStyle((p.realized ?? 0) >= 0 ? Color.green : Color.red)
                if let h = (p.realized ?? 0) >= 0 ? p.bestTx : p.worstTx, let u = EvmScan.tx(vm.chain, h) { Link("最大一笔", destination: u).font(.caption2) }
            }
        }
    }
}
