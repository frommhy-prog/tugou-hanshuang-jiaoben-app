import SwiftUI
import Charts
import WidgetKit
import UIKit

struct WalletResult: Identifiable {
    var id: UUID { wallet.id }
    let wallet: Wallet
    let resp: PortfolioResponse?
    let error: String?
}

struct AggHolding: Identifiable {
    var id: String { symbol + "|" + chain }
    let symbol: String
    let chain: String
    var usd: Double
    var change: Double?
}

@MainActor
final class WalletsVM: ObservableObject {
    @Published var wallets: [Wallet] = Cfg.wallets {
        didSet { Cfg.wallets = wallets }
    }
    @Published var results: [WalletResult] = []
    @Published var loading = false
    @Published var updated: Date?

    var total: Double { results.reduce(0) { $0 + ($1.resp?.merged?.totalUsd ?? 0) } }

    var holdings: [AggHolding] {
        var m: [String: AggHolding] = [:]
        for r in results {
            for h in r.resp?.merged?.holdings ?? [] {
                if h.spamLikely == true { continue }
                guard let usd = h.usd, usd > 0 else { continue }
                let sym = h.symbol ?? "?"
                let ch = h.chain ?? ""
                let key = sym + "|" + ch
                if var e = m[key] { e.usd += usd; m[key] = e }
                else { m[key] = AggHolding(symbol: sym, chain: ch, usd: usd, change: h.priceChange24hPct) }
            }
        }
        return m.values.sorted { $0.usd > $1.usd }
    }

    func add(_ ws: [Wallet]) {
        let exist = Set(wallets.map { $0.address.lowercased() })
        let fresh = ws.filter { !exist.contains($0.address.lowercased()) }
        wallets.append(contentsOf: fresh)
        Task { await refresh() }
    }

    func remove(ids: Set<UUID>) {
        wallets.removeAll { ids.contains($0.id) }
        results.removeAll { ids.contains($0.wallet.id) }
        saveSnapshot()
    }

    // 我的钱包全量：mine=1 不走结果缓存，fresh=1 本次必取新数据，brain=1 带钱包大脑总结
    nonisolated static func fetch(_ w: Wallet) async -> WalletResult {
        let param = w.chains.map { $0 + ":" + w.address }.joined(separator: ",")
        do {
            let r: PortfolioResponse = try await API.get("/api/wallet-portfolio", ["wallets": param, "mode": "merged", "brain": "1", "mine": "1", "fresh": "1"])
            return WalletResult(wallet: w, resp: r, error: r.error)
        } catch {
            return WalletResult(wallet: w, resp: nil, error: error.localizedDescription)
        }
    }

    func refresh() async {
        let ws = wallets
        guard !ws.isEmpty else { results = []; return }
        loading = true
        var out: [WalletResult] = []
        await withTaskGroup(of: WalletResult.self) { group in
            for w in ws { group.addTask { await WalletsVM.fetch(w) } }
            for await r in group { out.append(r) }
        }
        results = ws.compactMap { w in out.first { $0.wallet.id == w.id } }
        updated = Date()
        loading = false
        saveSnapshot()
    }

    private func saveSnapshot() {
        let rs = results.compactMap { $0.resp }
        if rs.isEmpty { return }
        Cfg.snapshot = Snapshot.build(rs)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

struct WalletsView: View {
    @StateObject private var vm = WalletsVM()
    @State private var showAdd = false
    @State private var editMode: EditMode = .inactive
    @State private var selected = Set<UUID>()
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List(selection: $selected) {
                if vm.wallets.isEmpty {
                    ContentUnavailableView("还没有钱包", systemImage: "wallet.pass", description: Text("点右上角 + 粘贴地址，可一次粘贴多个，EVM 和 Solana 可以混着加"))
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        totalCard
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Section("我的钱包（\(vm.wallets.count)）") {
                        ForEach(vm.wallets) { w in
                            NavigationLink(value: w) { row(w) }
                        }
                        .onDelete { idx in
                            let ids = Set(idx.map { vm.wallets[$0].id })
                            vm.remove(ids: ids)
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle("钱包")
            .navigationDestination(for: Wallet.self) { w in
                WalletDetailView(wallet: w, result: vm.results.first { $0.wallet.id == w.id })
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if vm.loading { ProgressView() }
                    else if !vm.wallets.isEmpty && !editMode.isEditing {
                        Button { Task { await vm.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                    if !vm.wallets.isEmpty { EditButton() }
                    if !editMode.isEditing { Button { showAdd = true } label: { Image(systemName: "plus") } }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    if editMode.isEditing {
                        Button("全选") { selected = Set(vm.wallets.map { $0.id }) }
                        Spacer()
                        Button("删除所选（\(selected.count)）", role: .destructive) { confirmDelete = true }
                            .disabled(selected.isEmpty)
                    }
                }
            }
            .confirmationDialog("删除 \(selected.count) 个钱包？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    vm.remove(ids: selected)
                    selected = []
                    editMode = .inactive
                }
            }
            .refreshable { await vm.refresh() }
            .sheet(isPresented: $showAdd) { AddWalletsSheet { vm.add($0) } }
            .task { if vm.results.isEmpty && !vm.wallets.isEmpty { await vm.refresh() } }
        }
    }

    private func row(_ w: Wallet) -> some View {
        let r = vm.results.first { $0.wallet.id == w.id }
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(w.label.isEmpty ? "钱包" : w.label).font(.headline)
                Text(Addr.short(w.address)).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(Addr.isSolana(w.address) ? "Solana" : "EVM · \(w.chains.count) 条链").font(.caption2).foregroundStyle(.secondary)
                if let e = r?.error { Text(e).font(.caption2).foregroundStyle(Color.orange).lineLimit(1) }
            }
            Spacer()
            Text(Money.format(r?.resp?.merged?.totalUsd)).font(.subheadline.monospacedDigit())
        }
    }

    private var totalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("总资产").font(.footnote).foregroundStyle(.secondary)
                Text(Money.format(vm.total)).font(.system(size: 34, weight: .bold, design: .rounded))
                if let u = vm.updated {
                    Text("更新于 " + u.formatted(date: .omitted, time: .standard) + " · 全量实时，不走缓存").font(.caption2).foregroundStyle(.secondary)
                }
                let hs = vm.holdings
                if !hs.isEmpty {
                    AllocationDonut(items: Array(hs.prefix(8)), rest: hs.dropFirst(8).reduce(0) { $0 + $1.usd })
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AllocationDonut: View {
    let items: [AggHolding]
    let rest: Double
    @State private var appear = false
    var body: some View {
        Chart {
            ForEach(items) { h in
                SectorMark(angle: .value("价值", appear ? h.usd : 0.001), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(by: .value("代币", h.symbol))
            }
            if rest > 0 {
                SectorMark(angle: .value("价值", appear ? rest : 0.001), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(by: .value("代币", "其他"))
            }
        }
        .chartLegend(.hidden)
        .frame(height: 180)
        .onAppear { withAnimation(.easeOut(duration: 1.0)) { appear = true } }
    }
}

// 一次粘贴多个地址：空格、逗号、换行分隔都行
struct AddWalletsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: ([Wallet]) -> Void
    @State private var text = ""
    @State private var label = ""
    @State private var chains: Set<String> = Set(Chain.evmDefault.map { $0.rawValue })

    private var addrs: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for p in text.components(separatedBy: CharacterSet(charactersIn: " ,;\n\t，；")) {
            let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if (Addr.isEVM(t) || Addr.isSolana(t)) && !seen.contains(t.lowercased()) { seen.insert(t.lowercased()); out.append(t) }
        }
        return out
    }
    private var hasEVM: Bool { addrs.contains { Addr.isEVM($0) } }

    var body: some View {
        NavigationStack {
            Form {
                Section("钱包地址（可多个）") {
                    TextEditor(text: $text)
                        .frame(minHeight: 110)
                        .font(.system(.footnote, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("从剪贴板粘贴") { text = (text.isEmpty ? "" : text + "\n") + (UIPasteboard.general.string ?? "") }
                    Text("识别到 \(addrs.count) 个有效地址（EVM \(addrs.filter { Addr.isEVM($0) }.count) · Solana \(addrs.filter { Addr.isSolana($0) }.count)）").font(.footnote).foregroundStyle(.secondary)
                }
                Section("备注（可选，多个时自动加序号）") { TextField("例如：主钱包", text: $label) }
                if hasEVM {
                    Section("EVM 地址要查询的链") {
                        ForEach(Chain.allCases.filter { $0.isEVM }) { c in
                            Toggle(c.title, isOn: Binding(
                                get: { chains.contains(c.rawValue) },
                                set: { on in if on { chains.insert(c.rawValue) } else { chains.remove(c.rawValue) } }
                            ))
                        }
                    }
                }
            }
            .navigationTitle("添加钱包")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let list = addrs
                        let evmChains = Chain.evmDefault.map { $0.rawValue }.filter { chains.contains($0) }
                        var ws: [Wallet] = []
                        for (i, a) in list.enumerated() {
                            let lb = label.isEmpty ? "" : (list.count > 1 ? "\(label) \(i + 1)" : label)
                            ws.append(Wallet(address: a, label: lb, chains: Addr.isSolana(a) && !Addr.isEVM(a) ? [Chain.solana.rawValue] : evmChains))
                        }
                        onAdd(ws)
                        dismiss()
                    }
                    .disabled(addrs.isEmpty || (hasEVM && chains.isEmpty))
                }
            }
        }
    }
}

// MARK: - 钱包详情：持仓 / 交易记录 / 分析
@MainActor
final class WalletDetailVM: ObservableObject {
    @Published var w: SolWallet?
    @Published var loading = false
    @Published var error: String?
    @Published var pages = 3
    @Published var ai: AIResult?
    @Published var aiLoading = false
    @Published var aiMsg: String?

    // 自己的钱包一律取最新（fresh=1），不走缓存
    func load(_ address: String) async {
        loading = true; error = nil; ai = nil; aiMsg = nil
        do {
            let r: SolWallet = try await Engine.get("/e/sol/wallet", ["address": address, "pages": String(pages), "fresh": "1"])
            if let e = r.error { error = e + (r.detail.map { "：" + $0 } ?? "") } else { w = r }
        } catch { self.error = error.localizedDescription }
        loading = false
        if w != nil { await runAI(address) }
    }

    func runAI(_ address: String) async {
        guard let w = w else { return }
        aiLoading = true; aiMsg = nil
        defer { aiLoading = false }
        let top = (w.positions ?? []).sorted { abs($0.realized ?? 0) > abs($1.realized ?? 0) }.prefix(10)
        let facts = WalletFacts(address: address, stats: w.stats, tags: w.tags ?? [], notes: w.notes ?? [], sample: w.sample, topPositions: Array(top))
        do {
            let r: AIResult = try await Engine.post("/e/ai", AIPayload(kind: "钱包交易记录分析", facts: facts))
            if let m = aiMessage(r) { aiMsg = m } else { ai = r }
        } catch { aiMsg = error.localizedDescription }
    }
}

struct WalletDetailView: View {
    let wallet: Wallet
    let result: WalletResult?
    @StateObject private var vm = WalletDetailVM()
    @StateObject private var evm = EvmDetailVM() // 新增：EVM 钱包交易记录与分析
    @State private var seg = 0

    private var isSol: Bool { Addr.isSolana(wallet.address) && !Addr.isEVM(wallet.address) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                Picker("", selection: $seg) {
                    Text("持仓").tag(0)
                    Text("交易记录").tag(1)
                    Text("分析").tag(2)
                }
                .pickerStyle(.segmented)
                if seg == 0 { holdingsSection }
                else if seg == 1 { tradesSection }
                else { analysisSection }
            }
            .padding(16)
        }
        .background(Color.page)
        .navigationTitle(wallet.label.isEmpty ? "钱包" : wallet.label)
        .navigationBarTitleDisplayMode(.inline)
        .task { if isSol && vm.w == nil { await vm.load(wallet.address) } }
    }

    private var headerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Addr.short(wallet.address)).font(.subheadline.monospaced())
                    Button { UIPasteboard.general.string = wallet.address } label: { Image(systemName: "doc.on.doc") }.font(.caption)
                    Spacer()
                    if isSol, let u = Scan.account(wallet.address) { Link("Solscan", destination: u).font(.caption.weight(.semibold)) }
                }
                Text(Money.format(result?.resp?.merged?.totalUsd)).font(.system(size: 30, weight: .bold, design: .rounded))
                if let r = result?.resp?.merged {
                    Text("已估值 \(r.pricedCount ?? 0) 个 · 未估值 \(r.unpricedCount ?? 0) 个（未估值的不计入总值）").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 持仓
    private var holdingsSection: some View {
        let hs = (result?.resp?.merged?.holdings ?? []).filter { $0.spamLikely != true }.sorted { ($0.usd ?? -1) > ($1.usd ?? -1) }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("当前持仓", systemImage: "square.stack.3d.up").font(.headline)
                if let e = result?.error { Text(e).font(.footnote).foregroundStyle(Color.orange) }
                if hs.isEmpty { Text("没有读到持仓（或还在加载，回到上一页下拉刷新）").font(.footnote).foregroundStyle(.secondary) }
                ForEach(Array(hs.enumerated()), id: \.offset) { _, h in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(h.symbol ?? "?").font(.subheadline.weight(.semibold))
                                Pill(text: Chain(rawValue: h.chain ?? "")?.title ?? (h.chain ?? ""), color: Color.blue)
                            }
                            Text("数量 " + Fmt2.qty(h.amount)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(h.usd != nil ? Money.format(h.usd) : "无报价").font(.subheadline.monospacedDigit())
                            if let c = h.priceChange24hPct { Text(String(format: "%+.1f%%", c)).font(.caption).foregroundStyle(c >= 0 ? Color.green : Color.red) }
                        }
                    }
                    Divider()
                }
                if let b = result?.resp?.brain, let c = b.conclusion, !c.isEmpty {
                    Label("钱包大脑", systemImage: "brain.head.profile").font(.subheadline.weight(.semibold))
                    Text(c).font(.footnote)
                    ForEach(Array((b.watch ?? []).enumerated()), id: \.offset) { _, s in Text("• " + s).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
    }

    // MARK: 交易记录
    private var tradesSection: some View {
        Group {
            if isSol { solTradesSection }
            else { EvmTradesBody(wallet: wallet, vm: evm) } // 新增：EVM 逐笔交易记录
        }
    }

    private var solTradesSection: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("交易记录（swap）", systemImage: "arrow.left.arrow.right").font(.headline)
                    Spacer()
                    if vm.loading { ProgressView() }
                }
                if let e = vm.error {
                    Text(e).font(.footnote).foregroundStyle(Color.orange)
                    Button("重试") { Task { await vm.load(wallet.address) } }.font(.footnote.weight(.semibold))
                } else if let w = vm.w {
                    if let s = w.stats {
                        Text("读取了最近 \(s.swapTx ?? 0) 笔 swap，其中 \(s.tradeN ?? 0) 笔能归属为该钱包的买卖" + (s.complete == true ? "（已到最早记录）" : "（更早的未读取）")).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(w.trades ?? []) { t in
                        HStack(alignment: .top) {
                            Pill(text: t.side == "buy" ? "买" : "卖", color: t.side == "buy" ? Color.green : Color.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.sym ?? Addr.short(t.mint)).font(.subheadline.weight(.semibold))
                                Text(Fmt2.time(t.t)).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text((t.q == "USD" ? String(format: "%.2f USD", t.amt ?? 0) : Fmt2.solPlain(t.amt))).font(.subheadline.monospacedDigit())
                                Text(Fmt2.qty(t.qty) + " 枚").font(.caption2).foregroundStyle(.secondary)
                            }
                            if let u = Scan.tx(t.sig) { Link(destination: u) { Image(systemName: "arrow.up.right.square") } }
                        }
                        Divider()
                    }
                    Button {
                        vm.pages = min(8, vm.pages + 2)
                        Task { await vm.load(wallet.address) }
                    } label: { Label("加载更早的记录（再读 200 笔）", systemImage: "clock.arrow.circlepath") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .disabled(vm.loading || vm.pages >= 8 || w.stats?.complete == true)
                    Text("每笔都可点右侧图标到 Solscan 核对原始交易").font(.caption2).foregroundStyle(.secondary)
                } else if vm.loading {
                    Text("正在读取链上交易记录…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 分析
    private var analysisSection: some View {
        Group {
            if !isSol {
                EvmAnalysisBody(wallet: wallet, vm: evm) // 新增：EVM 钱包分析
            } else if let w = vm.w {
                VStack(spacing: 14) {
                    if let s = w.stats {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("交易统计", systemImage: "chart.bar.xaxis").font(.headline)
                                StatsGrid(s: s)
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
                    positionsCard(w)
                    if let n = w.notes, !n.isEmpty {
                        Card { VStack(alignment: .leading, spacing: 4) { ForEach(Array(n.enumerated()), id: \.offset) { _, s in Text("· " + s).font(.caption2).foregroundStyle(.secondary) } } }
                    }
                }
            } else if vm.loading {
                Card { HStack(spacing: 10) { ProgressView(); Text("正在读取并分析链上交易…").foregroundStyle(.secondary) } }
            } else if let e = vm.error {
                ErrorCard(text: e) { Task { await vm.load(wallet.address) } }
            }
        }
    }

    private func positionsCard(_ w: SolWallet) -> some View {
        let ps = (w.positions ?? []).filter { $0.q == "SOL" }
        let realized = ps.filter { ($0.sells ?? 0) > 0 && ($0.realized ?? 0) != 0 }.sorted { ($0.realized ?? 0) > ($1.realized ?? 0) }
        let wins = Array(realized.filter { ($0.realized ?? 0) > 0 }.prefix(5))
        let losses = Array(realized.filter { ($0.realized ?? 0) < 0 }.reversed().prefix(5))
        let open = ps.filter { ($0.remainingQty ?? 0) > 0 }.sorted { ($0.remainingCost ?? 0) > ($1.remainingCost ?? 0) }.prefix(8)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("按币盈亏（SOL 计价，窗口内）", systemImage: "list.number").font(.headline)
                if !wins.isEmpty { Text("盈利最多").font(.caption.weight(.semibold)).foregroundStyle(.secondary); ForEach(wins) { posRow($0) } }
                if !losses.isEmpty { Text("亏损最多").font(.caption.weight(.semibold)).foregroundStyle(.secondary); ForEach(losses) { posRow($0) } }
                if !open.isEmpty { Text("窗口内仍持有（按成本）").font(.caption.weight(.semibold)).foregroundStyle(.secondary); ForEach(Array(open)) { posRow($0) } }
                if wins.isEmpty && losses.isEmpty && open.isEmpty { Text("窗口内没有可计算盈亏的币").font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    private func posRow(_ p: SolPosition) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(p.sym ?? Addr.short(p.mint)).font(.subheadline.weight(.semibold))
                Text("买 \(p.buys ?? 0) 笔 \(Fmt2.solPlain(p.boughtAmt)) · 卖 \(p.sells ?? 0) 笔 \(Fmt2.solPlain(p.soldAmt))").font(.caption2).foregroundStyle(.secondary)
                if (p.remainingQty ?? 0) > 0 { Text("剩余成本 " + Fmt2.solPlain(p.remainingCost) + (p.unrealized != nil ? " · 浮动 " + Fmt2.sol(p.unrealized) : " · 无法估值")).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt2.sol(p.realized)).font(.subheadline.monospacedDigit()).foregroundStyle((p.realized ?? 0) >= 0 ? Color.green : Color.red)
                if let sig = (p.realized ?? 0) >= 0 ? p.bestSig : p.worstSig, let u = Scan.tx(sig) { Link("最大一笔", destination: u).font(.caption2) }
            }
        }
    }
}
