import SwiftUI

// MARK: - EVM 代币持有人（引擎 /e/evm/token、/e/evm/holder）。字段全部可选，缺失显示「未知」
struct EvmHolder: Codable, Identifiable {
    var rank: Int?
    var owner: String
    var kind: String?
    var amount: Double?
    var pct: Double?
    var id: String { owner }
}

struct EvmFinding: Codable, Identifiable {
    var level: String?
    var text: String?
    var basis: String?
    var id: String { (text ?? "") + (basis ?? "") }
}

struct EvmConc: Codable {
    var top1: Double?
    var top5: Double?
    var top10: Double?
    var top20: Double?
    var wallets10: Double?
    var nonWallet: Double?
    var listed: Int?
}

struct EvmTokenResp: Codable {
    var chain: String?
    var token: String?
    var complete: Bool?
    var transferN: Int?
    var holderCount: Int?
    var burnedPct: Double?
    var supply: Double?
    var holders: [EvmHolder]?
    var concentration: EvmConc?
    var findings: [EvmFinding]?
    var notes: [String]?
    var error: String?
    var detail: String?
}

struct EvmHolderResp: Codable {
    struct Pos: Codable {
        var q: String?
        var buys: Int?
        var sells: Int?
        var boughtAmt: Double?
        var soldAmt: Double?
        var realized: Double?
        var remainingQty: Double?
        var remainingCost: Double?
        var firstBuy: Double?
        var lastSell: Double?
        var uncovQty: Double?
        var avgBuyPrice: Double?
    }
    var owner: String?
    var native: String?
    var tokenPositions: [Pos]?
    var tradesThis: [EvmTrade]?
    var finding: String?
    var stats: EvmStats?
    var tags: [SolTag]?
    var notes: [String]?
    var sample: String?
    var error: String?
    var detail: String?
}

enum EvmLook {
    static func levelColor(_ l: String?) -> Color {
        switch l ?? "" {
        case "risk": return Color.red
        case "warn": return Color.orange
        case "ok": return Color.green
        default: return Color.gray
        }
    }
    static func levelText(_ l: String?) -> String {
        switch l ?? "" {
        case "risk": return "风险"
        case "warn": return "注意"
        case "ok": return "正常"
        default: return "信息"
        }
    }
    static func kindText(_ k: String?) -> String {
        switch k ?? "" {
        case "wallet": return "钱包"
        case "contract": return "合约"
        case "pool": return "池子"
        default: return "未知"
        }
    }
    static func pct(_ v: Double?) -> String {
        guard let v = v else { return "未知" }
        return String(format: "%.2f%%", v)
    }
    static func addressURL(_ chain: String, _ a: String) -> URL? {
        URL(string: "https://" + EvmScan.host(chain) + "/address/" + a)
    }
}

@MainActor
final class EvmTokenVM: ObservableObject {
    @Published var r: EvmTokenResp?
    @Published var loading = false
    @Published var error: String?
    @Published var pages = 3

    func load(chain: String, token: String) async {
        loading = true
        error = nil
        do {
            let x: EvmTokenResp = try await Engine.get("/e/evm/token", ["chain": chain, "token": token, "pages": String(pages), "fresh": "1"])
            if let e = x.error { error = EvmFmt.errorText(e, x.detail); r = nil } else { r = x }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - 代币页里的「链上持有人榜单」卡片
struct EvmHoldersCard: View {
    let chain: Chain
    let address: String
    @StateObject private var vm = EvmTokenVM()
    @State private var picked: EvmHolder?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("链上持有人榜单", systemImage: "person.3").font(.headline)
                    Spacer()
                    if vm.loading { ProgressView() }
                }
                if let e = vm.error {
                    Text(e).font(.footnote).foregroundStyle(Color.orange)
                    Button("重试") { Task { await vm.load(chain: chain.rawValue, token: address) } }.font(.footnote.weight(.semibold))
                } else if let r = vm.r {
                    content(r)
                } else if vm.loading {
                    Text("正在读取该代币的全部转账记录并还原持有人…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: chain.rawValue + address) { await vm.load(chain: chain.rawValue, token: address) }
        .sheet(item: $picked) { h in EvmHolderSheet(chain: chain, token: address, holder: h) }
    }

    @ViewBuilder
    private func content(_ r: EvmTokenResp) -> some View {
        if r.complete == true {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                StatTile(title: "持有人数", value: r.holderCount.map { "\($0)" } ?? "未知")
                StatTile(title: "第 1 大占比", value: EvmLook.pct(r.concentration?.top1), tint: (r.concentration?.top1 ?? 0) >= 20 ? Color.red : Color.primary)
                StatTile(title: "前 10 大占比", value: EvmLook.pct(r.concentration?.top10), tint: (r.concentration?.top10 ?? 0) >= 50 ? Color.red : Color.primary)
                StatTile(title: "前 10 大普通钱包", value: EvmLook.pct(r.concentration?.wallets10), tint: (r.concentration?.wallets10 ?? 0) >= 30 ? Color.red : Color.primary)
            }
        }
        ForEach(r.findings ?? []) { f in
            HStack(alignment: .top, spacing: 8) {
                Pill(text: EvmLook.levelText(f.level), color: EvmLook.levelColor(f.level))
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.text ?? "").font(.footnote)
                    if let b = f.basis { Text("依据：" + b).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
        if r.complete != true {
            Button {
                vm.pages = min(6, vm.pages + 3)
                Task { await vm.load(chain: chain.rawValue, token: address) }
            } label: { Label("多读 3000 笔转账再试", systemImage: "clock.arrow.circlepath") }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(vm.loading || vm.pages >= 6)
        }
        if let hs = r.holders, !hs.isEmpty {
            Divider()
            Text("前 \(hs.count) 大持有人（点普通钱包看他在这个币上的盈亏和整体风格）").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(hs) { h in
                Button {
                    if h.kind == "wallet" { picked = h }
                } label: {
                    HStack {
                        Text("#\(h.rank ?? 0)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                        Text(Addr.short(h.owner)).font(.caption.monospaced()).foregroundStyle(Color.primary)
                        Pill(text: EvmLook.kindText(h.kind), color: h.kind == "wallet" ? Color.blue : Color.gray)
                        Spacer()
                        Text(EvmLook.pct(h.pct)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Color.primary)
                        if h.kind == "wallet" { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        if let n = r.notes, !n.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(n.enumerated()), id: \.offset) { _, s in Text("· " + s).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - 单个持有人分析
struct EvmHolderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let chain: Chain
    let token: String
    let holder: EvmHolder
    @State private var r: EvmHolderResp?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    if let e = error {
                        ErrorCard(text: e) { Task { await load() } }
                    } else if let x = r {
                        positionCard(x)
                        if let s = x.stats {
                            Card {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("该钱包整体交易统计", systemImage: "chart.bar.xaxis").font(.headline)
                                    EvmStatsGrid(s: s, native: x.native ?? "")
                                    if let sp = x.sample { Text(sp).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                        if let tags = x.tags, !tags.isEmpty {
                            Card {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("交易风格（规则判定，附依据）", systemImage: "tag").font(.headline)
                                    ForEach(tags) { TagRow(t: $0) }
                                }
                            }
                        }
                        if let n = x.notes, !n.isEmpty {
                            Card { VStack(alignment: .leading, spacing: 4) { ForEach(Array(n.enumerated()), id: \.offset) { _, s in Text("· " + s).font(.caption2).foregroundStyle(.secondary) } } }
                        }
                    } else if loading {
                        Card { HStack(spacing: 10) { ProgressView(); Text("正在读取该钱包的链上交易并分析…").foregroundStyle(.secondary) } }
                    }
                }
                .padding(16)
            }
            .background(Color.page)
            .navigationTitle("持有人分析")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .task { await load() }
    }

    private var headerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Addr.short(holder.owner)).font(.subheadline.monospaced())
                    Button { UIPasteboard.general.string = holder.owner } label: { Image(systemName: "doc.on.doc") }.font(.caption)
                    Spacer()
                    if let u = EvmLook.addressURL(chain.rawValue, holder.owner) { Link("浏览器", destination: u).font(.caption.weight(.semibold)) }
                }
                Text("持有该代币 " + EvmLook.pct(holder.pct) + "（占总供应量）").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.footnote.monospacedDigit())
        }
    }

    private func positionCard(_ x: EvmHolderResp) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("在这个币上的盈亏", systemImage: "dollarsign.circle").font(.headline)
                if let f = x.finding { Text(f).font(.footnote).foregroundStyle(.secondary) }
                ForEach(Array((x.tokenPositions ?? []).enumerated()), id: \.offset) { _, p in
                    posBlock(p, native: x.native)
                }
                if !(x.tradesThis ?? []).isEmpty {
                    Divider()
                    Text("该币的买卖记录").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(x.tradesThis ?? []) { t in
                        HStack(alignment: .top) {
                            Pill(text: t.side == "buy" ? "买" : "卖", color: t.side == "buy" ? Color.green : Color.red)
                            Text(Fmt2.time(t.t)).font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text((t.approx == true ? "≈ " : "") + EvmFmt.amt(t.amt, t.q, x.native)).font(.caption.monospacedDigit())
                            if let u = EvmScan.tx(chain.rawValue, t.tx) { Link(destination: u) { Image(systemName: "arrow.up.right.square") }.font(.caption) }
                        }
                    }
                }
            }
        }
    }

    private func posBlock(_ p: EvmHolderResp.Pos, native: String?) -> some View {
        let unit = p.q == "USD" ? "USD" : (native ?? "")
        return VStack(alignment: .leading, spacing: 4) {
            Text(p.q == "USD" ? "稳定币计价" : (unit + " 计价")).font(.caption.weight(.semibold))
            row("买入", "\(p.buys ?? 0) 笔 · " + EvmFmt.amt(p.boughtAmt, p.q, native))
            row("卖出", "\(p.sells ?? 0) 笔 · " + EvmFmt.amt(p.soldAmt, p.q, native))
            row("已兑现盈亏", EvmFmt.signed(p.realized, unit))
            if (p.remainingQty ?? 0) > 0 { row("剩余成本", EvmFmt.amt(p.remainingCost, p.q, native)) }
            if let a = p.avgBuyPrice { row("平均买入价", String(format: "%.8g", a) + " " + unit + "/枚") }
            if (p.uncovQty ?? 0) > 0 { Text("有一部分卖出找不到对应买入（窗口之前买入或转入），那部分不计盈亏").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            let x: EvmHolderResp = try await Engine.get("/e/evm/holder", ["chain": chain.rawValue, "token": token, "owner": holder.owner, "pages": "3", "fresh": "1"])
            if let e = x.error { error = EvmFmt.errorText(e, x.detail) } else { r = x }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
