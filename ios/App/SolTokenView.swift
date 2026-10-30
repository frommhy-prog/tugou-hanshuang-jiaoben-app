import SwiftUI
import Charts
import UIKit

@MainActor
final class SolTokenVM: ObservableObject {
    @Published var input = ""
    @Published var token: SolToken?
    @Published var loading = false
    @Published var error: String?
    @Published var holderResults: [String: SolHolder] = [:]
    @Published var holderErrors: [String: String] = [:]
    @Published var holderBusy: Set<String> = []
    @Published var holderDone = 0
    @Published var holderTotal = 0
    @Published var pool: SolPool?
    @Published var poolError: String?
    @Published var poolLoading = false
    @Published var ai: AIResult?
    @Published var aiLoading = false
    @Published var aiMsg: String?
    private var runID = 0
    private var last = ""

    func inputChanged() {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if Addr.isSolana(t) && t != last { start(t) }
    }

    func start(_ raw: String) {
        let mint = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Addr.isSolana(mint) else {
            error = Addr.isEVM(mint) ? "这是 EVM 地址，请切到「EVM」标签查询" : "Solana 合约地址是 32–44 位 Base58"
            return
        }
        runID += 1
        let id = runID
        last = mint
        token = nil; error = nil; holderResults = [:]; holderErrors = [:]; holderBusy = []
        holderDone = 0; holderTotal = 0; pool = nil; poolError = nil; ai = nil; aiMsg = nil
        loading = true
        Task { await run(mint, id) }
    }

    func refreshFresh() {
        guard let m = token?.mint else { return }
        last = ""
        start(m)
    }

    private func run(_ mint: String, _ id: Int) async {
        do {
            let t: SolToken = try await Engine.get("/e/sol/token", ["mint": mint])
            guard id == runID else { return }
            if let e = t.error { error = e + (t.detail.map { "：" + $0 } ?? ""); loading = false; return }
            token = t
            loading = false
        } catch {
            guard id == runID else { return }
            self.error = error.localizedDescription
            loading = false
            return
        }
        // 池子交易分析
        if let pair = token?.market?.pair {
            poolLoading = true
            do {
                let p: SolPool = try await Engine.get("/e/sol/pool", ["pair": pair, "mint": mint, "pages": "3"])
                if id == runID { if let e = p.error { poolError = e + (p.detail.map { "：" + $0 } ?? "") } else { pool = p } }
            } catch { if id == runID { poolError = error.localizedDescription } }
            poolLoading = false
        } else {
            poolError = "没有找到该代币的交易池，无法分析池子交易"
        }
        // 前十大普通钱包逐个拆解（串行，避免触发数据源限速）
        let wallets = (token?.holders ?? []).filter { $0.kind == "wallet" }.prefix(10)
        holderTotal = wallets.count
        for h in wallets {
            guard id == runID else { return }
            await loadHolder(mint: mint, owner: h.owner, id: id)
            holderDone += 1
        }
        guard id == runID else { return }
        await runAI(id: id)
    }

    func loadHolder(mint: String, owner: String, id: Int) async {
        holderBusy.insert(owner)
        defer { holderBusy.remove(owner) }
        do {
            let r: SolHolder = try await Engine.get("/e/sol/holder", ["mint": mint, "owner": owner, "pages": "3"])
            guard id == runID else { return }
            if let e = r.error { holderErrors[owner] = e + (r.detail.map { "：" + $0 } ?? "") } else { holderResults[owner] = r }
        } catch {
            guard id == runID else { return }
            holderErrors[owner] = error.localizedDescription
        }
    }

    func retryHolder(_ owner: String) {
        guard let m = token?.mint else { return }
        let id = runID
        holderErrors[owner] = nil
        Task { await loadHolder(mint: m, owner: owner, id: id) }
    }

    func runAIManual() { Task { await runAI(id: runID) } }

    private func runAI(id: Int) async {
        guard let t = token, let mint = t.mint else { return }
        aiLoading = true; aiMsg = nil
        defer { aiLoading = false }
        let hs: [HolderFact] = (t.holders ?? []).filter { $0.kind == "wallet" }.prefix(10).map { h in
            let r = holderResults[h.owner]
            return HolderFact(rank: h.rank, owner: h.owner, kind: h.kind, pct: h.pct, finding: r?.finding, stats: r?.stats, tags: r?.tags, thisToken: r?.tokenPositions)
        }
        let facts = TokenFacts(mint: mint, symbol: t.market?.sym, liquidityUsd: t.market?.liq, priceUsd: t.market?.priceUsd,
                               poolCreatedAtMs: t.market?.createdAt, authorities: t.authorities, concentration: t.concentration,
                               findings: t.findings ?? [], holders: hs, pool: PoolFact(totals: pool?.totals, findings: pool?.findings))
        do {
            let r: AIResult = try await Engine.post("/e/ai", AIPayload(kind: "代币+持有人分析", facts: facts))
            guard id == runID else { return }
            if let m = aiMessage(r) { aiMsg = m } else { ai = r }
        } catch { if id == runID { aiMsg = error.localizedDescription } }
    }
}

struct SolTokenView: View {
    @StateObject private var vm = SolTokenVM()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    inputCard
                    if vm.loading { Card { HStack(spacing: 10) { ProgressView(); Text("正在读取链上数据…").foregroundStyle(.secondary) } } }
                    if let e = vm.error { ErrorCard(text: e) { vm.start(vm.input) } }
                    if let t = vm.token { content(t) }
                    if vm.token == nil && !vm.loading && vm.error == nil { hint }
                }
                .padding(16)
            }
            .background(Color.page)
            .navigationTitle("代币分析")
            .toolbar {
                if vm.token != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { vm.refreshFresh() } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
        }
    }

    private var inputCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("粘贴 Solana 代币合约，自动分析", text: $vm.input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: vm.input) { _, _ in vm.inputChanged() }
                    if !vm.input.isEmpty {
                        Button { vm.input = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    }
                }
                Button {
                    if let s = UIPasteboard.general.string { vm.input = s }
                } label: { Label("粘贴", systemImage: "doc.on.clipboard") }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var hint: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("读链上原始记录，不是转述别人的榜单").font(.headline)
                Text("持仓分布和权限直接读链上账户；前十大钱包逐个拆解它们的真实买卖记录与盈亏；池子交易看是否集中或对敲。每条结论都写出依据，数据读不到的写「未知」。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func content(_ t: SolToken) -> some View {
        header(t)
        concentration(t)
        findingsCard(t)
        AIResultCard(title: "AI 解读", result: vm.ai, loading: vm.aiLoading, message: vm.aiMsg, onRun: vm.runAIManual)
        holdersCard(t)
        poolCard
        if let n = t.notes, !n.isEmpty {
            Card { VStack(alignment: .leading, spacing: 4) { ForEach(Array(n.enumerated()), id: \.offset) { _, s in Text("· " + s).font(.caption2).foregroundStyle(.secondary) } } }
        }
    }

    private func header(_ t: SolToken) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.market?.sym ?? "未知代币").font(.title2.bold())
                        Text(t.market?.name ?? "").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Pill(text: "Solana", color: Color.purple)
                }
                HStack(spacing: 10) {
                    StatTile(title: "价格", value: Money.price(t.market?.priceUsd))
                    StatTile(title: "流动性", value: Money.format(t.market?.liq))
                }
                HStack(spacing: 10) {
                    StatTile(title: "24h 成交", value: Money.format(t.market?.vol24))
                    StatTile(title: "24h 买/卖笔数", value: (t.market?.b24).map { "\($0)" } ?? "?" + " / " + ((t.market?.s24).map { "\($0)" } ?? "?"))
                }
                if let c = t.market?.createdAt {
                    Text("最深池子创建于 " + Fmt2.time(c / 1000)).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    if let m = t.mint, let u = Scan.token(m) { Link("Solscan", destination: u).font(.caption.weight(.semibold)) }
                    if let m = t.mint, let u = URL(string: "https://dexscreener.com/solana/" + m) { Link("Dexscreener", destination: u).font(.caption.weight(.semibold)) }
                    Spacer()
                    if let m = t.mint { Button { UIPasteboard.general.string = m } label: { Label("复制合约", systemImage: "doc.on.doc").font(.caption) } }
                }
            }
        }
    }

    private func concentration(_ t: SolToken) -> some View {
        let top = Array((t.holders ?? []).prefix(10))
        let sum = top.reduce(0.0) { $0 + ($1.pct ?? 0) }
        var slices = top.map { HoldSlice(name: "#\($0.rank) " + Addr.short($0.owner), pct: $0.pct ?? 0) }
        if sum < 99.5 && !top.isEmpty { slices.append(HoldSlice(name: "其他", pct: max(0, 100 - sum))) }
        let c = t.concentration
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("持仓分布（链上最大 20 个账户）", systemImage: "chart.pie").font(.headline)
                if !slices.isEmpty { HoldersDonut(slices: slices) }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    StatTile(title: "第 1 名", value: pctText(c?.top1))
                    StatTile(title: "前 5 名", value: pctText(c?.top5))
                    StatTile(title: "前 10 名", value: pctText(c?.top10))
                    StatTile(title: "前 20 名", value: pctText(c?.top20))
                    StatTile(title: "前十大钱包合计", value: pctText(c?.wallets10))
                    StatTile(title: "池子/合约占比", value: pctText(c?.nonWallet))
                }
                Text("权限：增发 " + (t.authorities?.mint == nil ? "已放弃" : "仍存在") + " · 冻结 " + (t.authorities?.freeze == nil ? "已放弃" : "仍存在")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func findingsCard(_ t: SolToken) -> some View {
        Group {
            if let f = t.findings, !f.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("结论与依据", systemImage: "checklist").font(.headline)
                        ForEach(f) { x in FindingRow(f: x) }
                    }
                }
            }
        }
    }

    // MARK: 前十大持有人拆解
    private func holdersCard(_ t: SolToken) -> some View {
        let hs = Array((t.holders ?? []).prefix(12))
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("大户拆解", systemImage: "person.3.sequence").font(.headline)
                    Spacer()
                    if vm.holderTotal > 0 { Text("已分析 \(vm.holderDone)/\(vm.holderTotal)").font(.caption).foregroundStyle(.secondary) }
                }
                Text("逐个读取大户钱包最近的真实 swap 记录，算出他们在这个币上的成本、盈亏、持仓时间和交易风格。").font(.caption).foregroundStyle(.secondary)
                ForEach(hs) { h in
                    Divider()
                    holderRow(h, mint: t.mint ?? "")
                }
            }
        }
    }

    private func holderRow(_ h: TokHolder, mint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("#\(h.rank)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                if let u = Scan.account(h.owner) { Link(Addr.short(h.owner), destination: u).font(.caption.monospaced()) }
                Pill(text: h.kindText, color: h.kind == "wallet" ? Color.blue : Color.gray)
                Spacer()
                Text(pctText(h.pct)).font(.subheadline.weight(.semibold))
            }
            if h.kind == "wallet" {
                if vm.holderBusy.contains(h.owner) {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("读取交易记录…").font(.caption).foregroundStyle(.secondary) }
                } else if let e = vm.holderErrors[h.owner] {
                    HStack { Text(e).font(.caption).foregroundStyle(Color.orange); Button("重试") { vm.retryHolder(h.owner) }.font(.caption.weight(.semibold)) }
                } else if let r = vm.holderResults[h.owner] {
                    HolderDetail(r: r)
                } else {
                    Text("排队中").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 池子交易
    private var poolCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("池子交易分析", systemImage: "arrow.left.arrow.right").font(.headline)
                    Spacer()
                    if vm.poolLoading { ProgressView() }
                }
                if let e = vm.poolError { Text(e).font(.footnote).foregroundStyle(Color.orange) }
                if let p = vm.pool {
                    if let w = p.window {
                        Text("窗口：最近 \(w.swapTx ?? 0) 笔 swap" + (w.from != nil && w.to != nil ? "，跨度 " + Fmt2.dur((w.to ?? 0) - (w.from ?? 0)) : "")).font(.caption).foregroundStyle(.secondary)
                    }
                    if let tt = p.totals {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            StatTile(title: "买入", value: Fmt2.solPlain(tt.buySol) + " · \(tt.nb ?? 0) 笔")
                            StatTile(title: "卖出", value: Fmt2.solPlain(tt.sellSol) + " · \(tt.ns ?? 0) 笔")
                            StatTile(title: "净流入", value: Fmt2.sol(tt.netInSol), tint: (tt.netInSol ?? 0) >= 0 ? Color.green : Color.red)
                            StatTile(title: "成交地址数", value: tt.traders.map { "\($0)" } ?? "未知")
                        }
                    }
                    ForEach(p.findings ?? []) { f in FindingRow(f: f) }
                    if let b = p.topBuyers, !b.isEmpty {
                        Text("买入最多的地址").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(b.prefix(5)) { x in traderRow(x, buy: true) }
                    }
                    if let s = p.topSellers, !s.isEmpty {
                        Text("卖出最多的地址").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(s.prefix(5)) { x in traderRow(x, buy: false) }
                    }
                    ForEach(Array((p.notes ?? []).enumerated()), id: \.offset) { _, n in Text("· " + n).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func traderRow(_ x: PoolTrader, buy: Bool) -> some View {
        HStack {
            if let u = Scan.account(x.w) { Link(Addr.short(x.w), destination: u).font(.caption.monospaced()) }
            Spacer()
            Text(buy ? Fmt2.solPlain(x.buySol) + " · \(x.nb ?? 0) 笔" : Fmt2.solPlain(x.sellSol) + " · \(x.ns ?? 0) 笔").font(.caption)
        }
    }
}

// 单个大户的拆解结果
struct HolderDetail: View {
    let r: SolHolder
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let f = r.finding { Text(f).font(.caption).foregroundStyle(.secondary) }
            ForEach(Array((r.tokenPositions ?? []).enumerated()), id: \.offset) { _, p in
                VStack(alignment: .leading, spacing: 2) {
                    Text("在这个币上（\(p.q ?? "SOL") 计价）").font(.caption.weight(.semibold))
                    Text("买入 \(p.buys ?? 0) 笔 / \(Fmt2.solPlain(p.boughtAmt))，卖出 \(p.sells ?? 0) 笔 / \(Fmt2.solPlain(p.soldAmt))").font(.caption)
                    Text("已兑现 " + Fmt2.sol(p.realized) + "，首次买入 " + Fmt2.time(p.firstBuy)).font(.caption)
                    if let a = p.avgBuyPrice { Text(String(format: "平均买入价 %.10f SOL", a)).font(.caption2).foregroundStyle(.secondary) }
                    if (p.uncovQty ?? 0) > 0 { Text("有一部分卖出找不到对应买入，不计入盈亏").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            if let s = r.stats, (s.tradeN ?? 0) > 0 {
                Text("整体风格（窗口 \(s.swapTx ?? 0) 笔 swap，\(s.tokensTraded ?? 0) 个币）：已兑现 " + (s.realizedN ?? 0 > 0 ? Fmt2.sol(s.realizedSol) : "样本不足") + "，胜率 " + (s.winRate.map { String(format: "%.0f%%", $0 * 100) } ?? "样本不足")).font(.caption)
            } else if let s = r.stats, (s.swapTx ?? 0) > 0 {
                Text("读到 \(s.swapTx ?? 0) 笔涉及该地址的 swap，但按链上余额变化无法归属为它自己的买卖（可能是做市商/路由/中转账户）").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(r.tags ?? []) { t in TagRow(t: t) }
            ForEach(Array((r.tradesThis ?? []).prefix(5).enumerated()), id: \.offset) { _, tr in
                HStack {
                    Pill(text: tr.side == "buy" ? "买" : "卖", color: tr.side == "buy" ? Color.green : Color.red)
                    Text(Fmt2.solPlain(tr.amt)).font(.caption)
                    Text(Fmt2.time(tr.t)).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if let u = Scan.tx(tr.sig) { Link(destination: u) { Image(systemName: "arrow.up.right.square") } }
                }
            }
        }
    }
}

// 顶部切换：Solana 用新分析引擎，EVM 沿用原有查询
struct AnalyzeRoot: View {
    @State private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("链", selection: $tab) {
                Text("Solana").tag(0)
                Text("EVM（BSC/ETH/Base 等）").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if tab == 0 { SolTokenView() } else { TokenView() }
        }
        .background(Color.page)
    }
}
