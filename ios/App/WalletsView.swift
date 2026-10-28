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

    func add(_ w: Wallet) {
        wallets.append(w)
        Task { await refresh() }
    }

    func remove(_ w: Wallet) {
        wallets.removeAll { $0.id == w.id }
        results.removeAll { $0.wallet.id == w.id }
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if vm.wallets.isEmpty {
                        ContentUnavailableView("还没有钱包", systemImage: "wallet.pass", description: Text("点右上角 + 粘贴地址，EVM 和 Solana 可以混着加"))
                            .padding(.top, 60)
                    } else {
                        totalCard
                        ForEach(vm.wallets) { w in walletCard(w) }
                    }
                }
                .padding(16)
            }
            .background(Color.page)
            .navigationTitle("钱包")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if vm.loading { ProgressView() }
                    else if !vm.wallets.isEmpty {
                        Button { Task { await vm.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await vm.refresh() }
            .sheet(isPresented: $showAdd) { AddWalletSheet { vm.add($0) } }
            .task { if vm.results.isEmpty && !vm.wallets.isEmpty { await vm.refresh() } }
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
                    ForEach(Array(hs.prefix(6))) { h in
                        HStack {
                            Text(h.symbol).font(.subheadline.weight(.semibold))
                            Pill(text: h.chain, color: Color.blue)
                            Spacer()
                            if let c = h.change {
                                Text(String(format: "%+.1f%%", c)).font(.caption).foregroundStyle(c >= 0 ? Color.green : Color.red)
                            }
                            Text(Money.format(h.usd)).font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
        }
    }

    private func walletCard(_ w: Wallet) -> some View {
        let r = vm.results.first { $0.wallet.id == w.id }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.label.isEmpty ? "钱包" : w.label).font(.headline)
                        Text(Addr.short(w.address)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Money.format(r?.resp?.merged?.totalUsd)).font(.headline.monospacedDigit())
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(w.chains, id: \.self) { Pill(text: Chain(rawValue: $0)?.title ?? $0, color: Color.gray) } }
                }
                if let e = r?.error { Text(e).font(.footnote).foregroundStyle(Color.orange) }
                if let inv = r?.resp?.invalid, !inv.isEmpty {
                    Text("未能识别：" + inv.map { ($0.chain ?? "?") + " " + ($0.reason ?? "") }.joined(separator: "；")).font(.caption).foregroundStyle(.secondary)
                }
                if let b = r?.resp?.brain, let c = b.conclusion, !c.isEmpty {
                    Divider()
                    Label("钱包大脑", systemImage: "brain.head.profile").font(.subheadline.weight(.semibold))
                    Text(c).font(.footnote)
                    if let ws = b.watch, !ws.isEmpty {
                        ForEach(Array(ws.enumerated()), id: \.offset) { _, s in Text("• " + s).font(.footnote).foregroundStyle(.secondary) }
                    }
                    if let a = b.analyzedCount, let t = b.totalNonNative {
                        Text("已分析 \(a) / \(t) 个非原生代币").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) { vm.remove(w) } label: { Label("删除钱包", systemImage: "trash") }
        }
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

struct AddWalletSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (Wallet) -> Void
    @State private var address = ""
    @State private var label = ""
    @State private var chains: Set<String> = Set(Chain.evmDefault.map { $0.rawValue })

    private var trimmed: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isEVM: Bool { Addr.isEVM(trimmed) }
    private var isSol: Bool { Addr.isSolana(trimmed) }

    var body: some View {
        NavigationStack {
            Form {
                Section("地址") {
                    TextField("粘贴钱包地址", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Button("从剪贴板粘贴") { address = UIPasteboard.general.string ?? address }
                    if !trimmed.isEmpty {
                        Text(isEVM ? "识别为 EVM 地址" : (isSol ? "识别为 Solana 地址" : "地址格式不对")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("备注（可选）") { TextField("例如：主钱包", text: $label) }
                if isEVM {
                    Section("要查询的链") {
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
                        let cs = isSol ? [Chain.solana.rawValue] : Chain.evmDefault.map { $0.rawValue }.filter { chains.contains($0) }
                        onAdd(Wallet(address: trimmed, label: label, chains: cs))
                        dismiss()
                    }
                    .disabled(!(isEVM || isSol) || (isEVM && chains.isEmpty))
                }
            }
        }
    }
}
