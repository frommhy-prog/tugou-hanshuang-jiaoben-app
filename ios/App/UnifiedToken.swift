import SwiftUI
import Charts
import UIKit

// MARK: - 统一代币页：一个入口自动识别 Solana / EVM
struct UnifiedTokenRoot: View {
    @ObservedObject private var vm = UTokenVM.shared
    @State private var selDate: Date?
    @State private var hist: [HistoryItem] = QueryHistory.items.filter { $0.kind == "token" }
    @State private var expanded: Set<String> = []
    @State private var shareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showAlert = false
    @State private var showDash = false
    @AppStorage("tokTab", store: Cfg.defaults) private var tokTab = 0

    private var navTitle: String {
        guard let m = vm.main else { return "代币" }
        let s: String = m.baseToken?.symbol ?? vm.symbol
        let p: String = m.price.map { Money.price($0) } ?? ""
        return s + " " + p
    }

    private var tabNames: [String] { ["总览", "成交", "筹码", "风险", "叙事", "更多"] }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabNames.indices, id: \.self) { i in
                    Button { tokTab = i } label: {
                        Text(tabNames[i])
                            .font(.subheadline.weight(tokTab == i ? .bold : .regular))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(tokTab == i ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: Capsule())
                            .foregroundStyle(tokTab == i ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        switch tokTab {
        case 0:
            VerdictCard(vm: vm)
            AIResultCard(title: "AI 研判（与规则并行）", result: vm.ai, loading: vm.aiLoading, message: vm.aiMsg, onRun: vm.reAI)
            LifecycleCard(vm: vm)
        case 1:
            flowCard
            poolsCard
        case 2:
            HoldersIntelButton(vm: vm)
            holdersCard
        case 3:
            ReportCard(vm: vm)
            securityCard
        case 4:
            NarrativeRulesCard(vm: vm)
            SocialCard(vm: vm)
            AIFoldCard(vm: vm)
        default:
            PromoCard(vm: vm)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    inputCard
                    if vm.loading { Card { HStack(spacing: 10) { ProgressView(); Text("正在识别链并读取行情…").foregroundStyle(.secondary) } } }
                    if let e = vm.error { ErrorCard(text: e) { vm.start(vm.input) } }
                    if vm.main != nil { content }
                    else if !vm.loading && vm.error == nil { startCard }
                }
                .padding(16)
            }
            .background(Color.page)
            .refreshable { vm.refreshAll(); try? await Task.sleep(nanoseconds: 800_000_000) }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if vm.main != nil {
                        Button { shareToken() } label: { Image(systemName: "square.and.arrow.up") }
                        Button { showAlert = true } label: { Image(systemName: "bell.badge") }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showDash = true } label: { Image(systemName: "gauge.with.dots.needle.67percent") }
                }
            }
            .sheet(isPresented: $showDash) { DashboardView() }
            .sheet(isPresented: $shareSheet) { ShareSheet(items: shareItems) }
            .sheet(isPresented: $showAlert) { AlertEditor(prefill: alertPrefill) { } }
            .task(id: vm.address) {
                if vm.address.isEmpty { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 20_000_000_000)
                    if Task.isCancelled { break }
                    await vm.tick()
                }
            }
        }
    }

    private var alertPrefill: AlertPrefill? {
        guard vm.main != nil else { return nil }
        return AlertPrefill(chain: vm.chain, address: vm.address, symbol: vm.symbol, price: vm.main?.price)
    }

    // MARK: 输入与记录
    private var inputCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("粘贴合约地址（Solana / EVM 自动识别）", text: $vm.input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: vm.input) { _, _ in vm.inputChanged() }
                    if !vm.input.isEmpty {
                        Button { vm.input = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    }
                }
                HStack {
                    Button {
                        if let s = UIPasteboard.general.string { vm.input = s }
                    } label: { Label("粘贴并分析", systemImage: "doc.on.clipboard") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Spacer()
                    Menu {
                        if hist.isEmpty { Text("还没有查询记录") }
                        ForEach(hist.prefix(15)) { h in
                            Button(h.title + " · " + (Chain(rawValue: h.chain)?.title ?? h.chain)) { vm.start(h.address) }
                        }
                        if !hist.isEmpty {
                            Divider()
                            Button("清空记录", role: .destructive) { QueryHistory.clear(kind: "token"); hist = [] }
                        }
                    } label: { Label("记录", systemImage: "clock.arrow.circlepath").font(.subheadline) }
                }
            }
        }
    }

    private var startCard: some View {
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("粘贴合约，自动出完整分析").font(.headline)
                    Text("K 线与资金流向、池子、持有人成本与盈亏、叙事、合约安全，每条结论附依据；查不到的项目显示「未知」，不编数。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if !hist.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最近查询").font(.headline)
                        ForEach(hist.prefix(12)) { h in
                            Button { vm.start(h.address) } label: {
                                HStack {
                                    Text(h.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                                    Pill(text: Chain(rawValue: h.chain)?.title ?? h.chain, color: Color.blue)
                                    Spacer()
                                    Text(TZ.short(h.at)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }
        .onAppear { hist = QueryHistory.items.filter { $0.kind == "token" } }
    }

    // MARK: 内容（SwiftUI 一个块最多 10 个子视图，所以分两组）
    @ViewBuilder
    private var content: some View {
        Group {
            KLineCard(vm: vm)
            FreshnessRow(vm: vm)
            tabBar
        }
        Group {
            tabBody
        }
    }

    private func changeChip(_ key: String, _ label: String) -> some View {
        let v = vm.main?.priceChange?[key]
        return VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(v.map { String(format: "%+.1f%%", $0) } ?? "—").font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle((v ?? 0) >= 0 ? Color.green : Color.red)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var headerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if let u = vm.main?.info?.imageUrl, let url = URL(string: u) {
                        AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
                            .frame(width: 44, height: 44).clipShape(Circle())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.symbol).font(.title2.bold())
                        Text(vm.main?.baseToken?.name ?? "").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Pill(text: vm.chain.title, color: Color.blue)
                }
                Text(Money.price(vm.main?.price)).font(.system(size: 32, weight: .bold, design: .rounded))
                HStack(spacing: 6) {
                    changeChip("m5", "5分")
                    changeChip("h1", "1时")
                    changeChip("h6", "6时")
                    changeChip("h24", "24时")
                }
                HStack {
                    Text(Addr.short(vm.address)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Button { UIPasteboard.general.string = vm.address } label: { Image(systemName: "doc.on.doc") }.font(.caption)
                    Spacer()
                    Text("每 20 秒自动刷新").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: K 线
    private var selectedCandle: Candle? {
        guard let d = selDate else { return nil }
        return vm.candles.min(by: { abs($0.t - d.timeIntervalSince1970) < abs($1.t - d.timeIntervalSince1970) })
    }

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("K 线", systemImage: "chart.xyaxis.line").font(.headline)
                    Spacer()
                    Text("来源 GeckoTerminal · 最深池子").font(.caption2).foregroundStyle(.secondary)
                }
                Picker("周期", selection: Binding(get: { vm.tf }, set: { vm.setTF($0) })) {
                    ForEach(TF.allCases) { t in Text(t.title).tag(t) }
                }
                .pickerStyle(.segmented)
                if let n = vm.chartNote {
                    Text(n).font(.footnote).foregroundStyle(.secondary)
                } else if vm.candles.isEmpty {
                    HStack(spacing: 8) { ProgressView(); Text("加载 K 线…").font(.footnote).foregroundStyle(.secondary) }
                } else {
                    readout
                    CandleChartView(candles: vm.candles, selected: $selDate)
                }
            }
        }
    }

    private var readout: some View {
        let c = selectedCandle ?? vm.candles.last
        return Group {
            if let c = c {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TZ.format(Date(timeIntervalSince1970: c.t))).font(.caption2).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Text("开 " + Money.price(c.o))
                        Text("高 " + Money.price(c.h))
                        Text("低 " + Money.price(c.l))
                        Text("收 " + Money.price(c.c)).foregroundStyle(c.up ? Color.green : Color.red)
                    }
                    .font(.system(size: 10, design: .monospaced))
                    Text("成交量 " + Fmt2.usd(c.v)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 关键数据
    private var statsGrid: some View {
        let m = vm.main
        let b = m?.txns?["h24"]?.buys
        let s = m?.txns?["h24"]?.sells
        var age = "未知"
        if let c = m?.pairCreatedAt {
            let h = (Date().timeIntervalSince1970 * 1000 - c) / 3_600_000
            age = h < 48 ? String(format: "%.1f 小时", h) : String(format: "%.1f 天", h / 24)
        }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(title: "流动性（最深池）", value: Money.format(m?.liquidity?.usd))
            StatTile(title: "市值 / FDV", value: Money.format(m?.marketCap ?? m?.fdv))
            StatTile(title: "24h 成交额", value: Money.format(m?.volume?["h24"]))
            StatTile(title: "24h 买 / 卖笔数", value: Fmt2.buySell(b, s))
            StatTile(title: "池龄", value: age)
            StatTile(title: "池子数量", value: "\(vm.pairs.count) 个")
        }
    }

    // MARK: 规则分析
    private var insightsCard: some View {
        let order: [String: Int] = ["risk": 0, "warn": 1, "info": 2, "ok": 3]
        let list = vm.insights.sorted { (order[$0.level] ?? 9) < (order[$1.level] ?? 9) }
        let nr = list.filter { $0.level == "risk" }.count
        let nw = list.filter { $0.level == "warn" }.count
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("分析结论（规则判定，附依据）", systemImage: "checklist").font(.headline)
                    Spacer()
                    if nr > 0 { Pill(text: "\(nr) 项风险", color: Color.red) }
                    if nw > 0 { Pill(text: "\(nw) 项注意", color: Color.orange) }
                }
                if list.isEmpty { Text("数据还在加载，或暂未触发任何规则。").font(.footnote).foregroundStyle(.secondary) }
                ForEach(list) { FindingRow(f: $0) }
            }
        }
    }

    // MARK: 代币成交分析
    private var flowCard: some View {
        let now = Date().timeIntervalSince1970
        let ws = FlowCalc.windows(vm.trades, now: now)
        let bks = FlowCalc.buckets(vm.trades)
        let ads = Array(FlowCalc.addrs(vm.trades).prefix(6))
        let big = Array(vm.trades.sorted { $0.usd > $1.usd }.prefix(5))
        let span: Double = {
            guard let lo = vm.trades.map({ $0.t }).min() else { return 0 }
            return now - lo
        }()
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("代币成交分析（买卖资金流）", systemImage: "arrow.left.arrow.right").font(.headline)
                if let n = vm.tradesNote, vm.trades.isEmpty {
                    Text(n).font(.footnote).foregroundStyle(.secondary)
                } else if vm.trades.isEmpty {
                    HStack(spacing: 8) { ProgressView(); Text("加载成交…").font(.footnote).foregroundStyle(.secondary) }
                } else {
                    Text("最近 \(vm.trades.count) 笔成交，覆盖约 " + Fmt2.dur(span) + "（GeckoTerminal，最深池子）").font(.caption2).foregroundStyle(.secondary)
                    ForEach(ws) { w in
                        HStack {
                            Text(w.label).font(.caption).frame(width: 56, alignment: .leading)
                            Text("买 " + Fmt2.usd(w.buy)).font(.caption.monospacedDigit()).foregroundStyle(Color.green)
                            Text("卖 " + Fmt2.usd(w.sell)).font(.caption.monospacedDigit()).foregroundStyle(Color.red)
                            Spacer()
                            Text("净 " + Fmt2.usd(w.net, signed: true)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(w.net >= 0 ? Color.green : Color.red)
                        }
                    }
                    if span < 86400 * 0.9 { Text("时间窗口长于覆盖范围的行只含已读到的成交，不是完整 24 小时").font(.caption2).foregroundStyle(.secondary) }
                    if !bks.isEmpty { FlowBarsView(buckets: bks) }
                    if !ads.isEmpty {
                        Divider()
                        Text("成交最活跃的地址（交易发起方，可能是机器人或聚合器）").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(ads) { a in
                            HStack {
                                Text(Addr.short(a.who)).font(.caption.monospaced())
                                Spacer()
                                Text("买 " + Fmt2.usd(a.buy) + "·" + "\(a.nb)").font(.caption2.monospacedDigit()).foregroundStyle(Color.green)
                                Text("卖 " + Fmt2.usd(a.sell) + "·" + "\(a.ns)").font(.caption2.monospacedDigit()).foregroundStyle(Color.red)
                            }
                        }
                    }
                    if !big.isEmpty {
                        Divider()
                        Text("最大几笔成交").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(big) { t in
                            HStack {
                                Pill(text: t.buy ? "买" : "卖", color: t.buy ? Color.green : Color.red)
                                Text(Fmt2.usd(t.usd)).font(.caption.monospacedDigit())
                                Text(TZ.short(Date(timeIntervalSince1970: t.t))).font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Text(Addr.short(t.who)).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 池子分析
    private var poolsCard: some View {
        let total = vm.pairs.reduce(0) { $0 + $1.liq }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("池子分析（流动性与成交分布）", systemImage: "drop.fill").font(.headline)
                Text("代币成交分析看的是买卖资金怎么流动；这里看的是承接这些交易的池子本身：流动性深浅、分布、各池成交。").font(.caption2).foregroundStyle(.secondary)
                ForEach(Array(vm.pairs.prefix(6).enumerated()), id: \.offset) { i, p in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text((p.dexId ?? "?") + " · " + (p.quoteToken?.symbol ?? "?")).font(.subheadline.weight(.semibold))
                            if i == 0 { Pill(text: "最深", color: Color.blue) }
                            Spacer()
                            Text(Fmt2.usd(p.liq)).font(.subheadline.monospacedDigit())
                        }
                        if total > 0 {
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.secondary.opacity(0.15))
                                    Capsule().fill(Color.blue.opacity(0.7)).frame(width: max(3, g.size.width * CGFloat(p.liq / total)))
                                }
                            }
                            .frame(height: 5)
                        }
                        HStack(spacing: 10) {
                            Text("24h 成交 " + Fmt2.usd(p.volume?["h24"]))
                            Text("买/卖 " + Fmt2.buySell(p.txns?["h24"]?.buys, p.txns?["h24"]?.sells))
                            Text("价格 " + Money.price(p.price))
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                        if let pa = p.pairAddress, let u = URL(string: "https://dexscreener.com/\(vm.chain.dexId)/\(pa)") {
                            Link("在 Dexscreener 打开", destination: u).font(.caption2)
                        }
                    }
                    if i < min(5, vm.pairs.count - 1) { Divider() }
                }
            }
        }
    }

    // MARK: 持有人与大户拆解
    private var holdersCard: some View {
        let a = vm.agg
        let wallets = vm.holders.filter { $0.kind == "wallet" }.prefix(10)
        let rows: [RoiRow] = wallets.compactMap { h in
            guard let r = vm.analyses[h.owner]?.position?.roi else { return nil }
            return RoiRow(label: "#\(h.rank) " + Addr.short(h.owner), roi: r * 100)
        }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("持有人与大户拆解", systemImage: "person.3.fill").font(.headline)
                    Spacer()
                    if vm.holderLoading || vm.analyzing { ProgressView() }
                }
                if let n = vm.holderNote, vm.holders.isEmpty {
                    Text(n).font(.footnote).foregroundStyle(.secondary)
                } else if vm.holders.isEmpty {
                    HStack(spacing: 8) { ProgressView(); Text("读取链上持有人…").font(.footnote).foregroundStyle(.secondary) }
                } else {
                    if let c = vm.conc { ConcBarView(conc: c) }
                    ForEach(vm.holderFindings) { FindingRow(f: $0) }
                    if !vm.holderComplete {
                        Button { vm.moreHolderPages() } label: { Label("多读 3000 笔转账再试", systemImage: "clock.arrow.circlepath") }
                            .buttonStyle(.bordered).controlSize(.small).disabled(vm.holderLoading || vm.holderPages >= 6)
                    }
                    Divider()
                    HStack {
                        Text("大户拆解（金额统一折算美元）").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("已拆解 \(a.analyzed)/\(wallets.count)").font(.caption).foregroundStyle(.secondary)
                    }
                    if a.withPos >= 1 {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            StatTile(title: "账面盈利", value: "\(a.profit)/\(a.withPos) 个")
                            StatTile(title: "合计盈亏", value: Fmt2.usd(a.pnl, signed: true), tint: a.pnl >= 0 ? Color.green : Color.red)
                            StatTile(title: "持仓价值", value: Fmt2.usd(a.valueNow))
                            StatTile(title: "10 分钟内入场", value: "\(a.early) 个（1 分钟内 \(a.snipers)）")
                        }
                    }
                    if rows.count >= 2 { RoiBarsView(rows: rows) }
                    ForEach(Array(wallets), id: \.owner) { h in holderRow(h) }
                    Text("大户 = 链上榜单里的普通钱包（已剔除池子、合约）。成本来自该钱包最近的真实买卖，卖出所得拿不准的币宁可不算；SOL/BNB/ETH 计价的成交按成交时刻小时价折算美元，是近似值。").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func holderRow(_ h: UHolder) -> some View {
        let isOpen = expanded.contains(h.owner)
        let r = vm.analyses[h.owner]
        let p = r?.position
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                if isOpen { expanded.remove(h.owner) } else { expanded.insert(h.owner) }
            } label: {
                HStack {
                    Text("#\(h.rank)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
                    Text(Addr.short(h.owner)).font(.caption.monospaced()).foregroundStyle(Color.primary)
                    Pill(text: h.kindText, color: Color.blue)
                    Spacer()
                    Text(h.pct.map { String(format: "%.2f%%", $0) } ?? "—").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Color.primary)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            if let p = p {
                HStack(spacing: 8) {
                    if let e = p.entry { Pill(text: e, color: (p.delayMin ?? 99) <= 10 ? Color.orange : Color.gray) }
                    if let s = p.state { Text(s).font(.caption2).foregroundStyle(.secondary) }
                    Spacer()
                    if let roi = p.roi { Text("综合 " + Fmt2.pct(roi)).font(.caption.weight(.semibold)).foregroundStyle(roi >= 0 ? Color.green : Color.red) }
                }
            } else if let e = vm.analysisErr[h.owner] {
                Text("拆解失败：" + e).font(.caption2).foregroundStyle(Color.orange)
            } else if let r = r, r.position == nil {
                Text((r.insights ?? []).first?.text ?? "窗口内没有该币的买卖记录").font(.caption2).foregroundStyle(.secondary)
            } else if vm.analyzing {
                Text("拆解中…").font(.caption2).foregroundStyle(.secondary)
            }
            if isOpen, let r = r { holderDetail(r, h) }
            Divider()
        }
    }

    private func txLink(_ tx: String) -> URL? { vm.chain == .solana ? Scan.tx(tx) : EvmScan.tx(vm.chain.rawValue, tx) }

    private func holderDetail(_ r: UHolderAnalysis, _ h: UHolder) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let p = r.position {
                VStack(alignment: .leading, spacing: 3) {
                    kv("累计投入", Fmt2.usd(p.boughtUsd) + "（\(p.buys ?? 0) 笔）")
                    kv("已卖出", Fmt2.usd(p.soldUsd) + "（\(p.sells ?? 0) 笔）")
                    kv("已兑现盈亏", Fmt2.usd(p.realizedUsd, signed: true))
                    kv("当前持仓价值", Fmt2.usd(p.valueNowUsd))
                    kv("浮动盈亏", Fmt2.usd(p.unrealizedUsd, signed: true))
                    kv("平均买入价", p.avgBuyUsd.map { Money.price($0) } ?? "未知")
                    kv("现价", p.priceNowUsd.map { Money.price($0) } ?? "未知")
                    if let d = p.delayMin { kv("入场时点", d < 0 ? "早于池子创建" : String(format: "池子创建后 %.1f 分钟", d)) }
                    if let f = p.firstBuy { kv("首次买入", TZ.format(Date(timeIntervalSince1970: f))) }
                }
            }
            ForEach(r.insights ?? []) { FindingRow(f: $0) }
            if let tags = r.tags, !tags.isEmpty {
                Text("该钱包整体风格").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(tags) { TagRow(t: $0) }
            }
            if let s = r.stats {
                let wr = s.winRate.map { String(format: "%.0f%%", $0 * 100) } ?? "样本不足"
                Text("整体：\(s.tokensTraded ?? 0) 个币 / \(s.tradeN ?? 0) 笔 · 胜率 " + wr + " · 持仓中位 " + Fmt2.dur(s.medHoldSec)).font(.caption2).foregroundStyle(.secondary)
            }
            if let ts = r.trades, !ts.isEmpty {
                Text("该币最近买卖").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(ts.prefix(8)) { t in
                    HStack {
                        Pill(text: t.side == "buy" ? "买" : "卖", color: t.side == "buy" ? Color.green : Color.red)
                        Text(TZ.short(Date(timeIntervalSince1970: t.t))).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text((t.approx == true ? "≈ " : "") + Fmt2.usd(t.usd)).font(.caption.monospacedDigit())
                        if let u = txLink(t.tx) { Link(destination: u) { Image(systemName: "arrow.up.right.square") }.font(.caption) }
                    }
                }
            }
            if let b = r.usdBasis { Text(b).font(.caption2).foregroundStyle(.secondary) }
            ForEach(Array((r.notes ?? []).prefix(3).enumerated()), id: \.offset) { _, n in Text("· " + n).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.caption.monospacedDigit())
        }
    }

    // MARK: 合约安全
    private var securityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("合约安全", systemImage: "shield.lefthalf.filled").font(.headline)
                if vm.chain == .solana {
                    let mintOK = (vm.authorities?.mint ?? "").isEmpty
                    let frzOK = (vm.authorities?.freeze ?? "").isEmpty
                    if vm.authorities == nil { Text("读取中或暂无数据").font(.footnote).foregroundStyle(.secondary) }
                    else {
                        RiskRow(label: "已放弃增发权限", text: mintOK ? "是" : "否", state: mintOK ? .good : .bad)
                        RiskRow(label: "已放弃冻结权限", text: frzOK ? "是" : "否", state: frzOK ? .good : .bad)
                    }
                } else if let s = vm.security {
                    RiskRow(label: "蜜罐", text: yn(s.honeypot), state: s.honeypot == nil ? .unknown : (s.honeypot == true ? .bad : .good))
                    RiskRow(label: "买入税", text: s.buyTax.map { String(format: "%.1f%%", $0) } ?? "未知", state: taxState(s.buyTax))
                    RiskRow(label: "卖出税", text: s.sellTax.map { String(format: "%.1f%%", $0) } ?? "未知", state: taxState(s.sellTax))
                    RiskRow(label: "可增发", text: yn(s.mintable), state: s.mintable == nil ? .unknown : (s.mintable == true ? .warn : .good))
                    RiskRow(label: "有黑名单", text: yn(s.blacklist), state: s.blacklist == nil ? .unknown : (s.blacklist == true ? .warn : .good))
                    RiskRow(label: "已放弃所有权", text: yn(s.renounced), state: s.renounced == nil ? .unknown : (s.renounced == true ? .good : .warn))
                    RiskRow(label: "LP 已锁定", text: yn(s.lpLocked), state: s.lpLocked == nil ? .unknown : (s.lpLocked == true ? .good : .warn))
                    if let src = s.riskSource { Text("来源：" + src).font(.caption2).foregroundStyle(.secondary) }
                } else {
                    Text("读取中或该链暂无合约扫描数据").font(.footnote).foregroundStyle(.secondary)
                }
                Text("扫描信号不是安全保证").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func yn(_ v: Bool?) -> String { v == nil ? "未知" : (v == true ? "是" : "否") }
    private func taxState(_ v: Double?) -> RiskState {
        guard let v = v else { return .unknown }
        return v >= 50 ? .bad : (v >= 10 ? .warn : .good)
    }

    // MARK: 跳转
    private var linksCard: some View {
        var items: [(String, String)] = []
        if let pa = vm.main?.pairAddress { items.append(("Dexscreener", "https://dexscreener.com/\(vm.chain.dexId)/\(pa)")) }
        let gm = vm.chain == .solana ? "sol" : (vm.chain == .eth ? "eth" : vm.chain.rawValue)
        items.append(("GMGN", "https://gmgn.ai/\(gm)/token/\(vm.address)"))
        items.append(("Ave", "https://ave.ai/token/\(vm.address)-\(vm.chain == .eth ? "eth" : vm.chain.rawValue)"))
        items.append(("X 搜索", "https://x.com/search?q=\(vm.address)"))
        for w in vm.main?.info?.websites ?? [] { if let u = w.url { items.append((w.label ?? "官网", u)) } }
        for s in vm.main?.info?.socials ?? [] { if let u = s.url { items.append((s.type ?? "社交", u)) } }
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("跳转与项目信息", systemImage: "arrow.up.right.square").font(.headline)
                FlowLayoutLinks(items: items)
            }
        }
    }

    // MARK: 分享
    private func shareToken() {
        shareItems = ShareKit.tokenItems(vm)
        shareSheet = true
    }
}

struct FlowLayoutLinks: View {
    let items: [(String, String)]
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 92), spacing: 8)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                if let u = URL(string: it.1) {
                    Link(it.0, destination: u).font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
            }
        }
    }
}

struct RoiRow: Identifiable {
    let label: String
    let roi: Double
    var id: String { label }
}

// MARK: - 图表：K 线 + 成交量（交易所风格）
struct CandleChartView: View {
    let candles: [Candle]
    @Binding var selected: Date?

    var body: some View {
        let lo = candles.map { $0.l }.min() ?? 0
        let hi = candles.map { $0.h }.max() ?? 1
        let pad = max((hi - lo) * 0.06, hi * 0.001)
        let w = CGFloat(max(1.5, min(8, 300.0 / Double(max(1, candles.count)))))
        let sel = selected.flatMap { d in candles.min(by: { abs($0.t - d.timeIntervalSince1970) < abs($1.t - d.timeIntervalSince1970) }) }
        return VStack(spacing: 4) {
            Chart {
                ForEach(candles) { c in
                    RuleMark(x: .value("时间", c.date), yStart: .value("最低", c.l), yEnd: .value("最高", c.h))
                        .foregroundStyle(c.color)
                    RectangleMark(x: .value("时间", c.date), yStart: .value("开", c.o), yEnd: .value("收", c.c), width: .fixed(w))
                        .foregroundStyle(c.color)
                }
                if let s = sel {
                    RuleMark(x: .value("选中", s.date)).foregroundStyle(Color.gray.opacity(0.5))
                }
            }
            .chartYScale(domain: (lo - pad)...(hi + pad))
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .trailing) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = v.as(Double.self) { Text(Money.price(d)).font(.system(size: 9)) }
                    }
                }
            }
            .frame(height: 230)
            Chart(candles) { c in
                BarMark(x: .value("时间", c.date), y: .value("成交量", c.v), width: .fixed(w))
                    .foregroundStyle(c.color.opacity(0.65))
            }
            .chartYAxis(.hidden)
            .chartXAxis(.hidden)
            .chartXSelection(value: $selected)
            .frame(height: 56)
        }
    }
}

// 买卖资金流：买入向上、卖出向下
struct FlowBarsView: View {
    let buckets: [FlowBucket]
    var body: some View {
        Chart {
            ForEach(buckets) { b in
                RectangleMark(xStart: .value("起", Date(timeIntervalSince1970: b.t)), xEnd: .value("止", Date(timeIntervalSince1970: b.t + b.width * 0.85)), yStart: .value("零", 0), yEnd: .value("买", b.buy))
                    .foregroundStyle(Color.green.opacity(0.85))
                RectangleMark(xStart: .value("起", Date(timeIntervalSince1970: b.t)), xEnd: .value("止", Date(timeIntervalSince1970: b.t + b.width * 0.85)), yStart: .value("零", 0), yEnd: .value("卖", -b.sell))
                    .foregroundStyle(Color.red.opacity(0.85))
            }
            RuleMark(y: .value("零线", 0)).foregroundStyle(Color.gray.opacity(0.5))
        }
        .chartYAxis {
            AxisMarks { v in
                AxisGridLine()
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(Fmt2.usd(abs(d))).font(.system(size: 9)) }
                }
            }
        }
        .frame(height: 150)
    }
}

// 大户盈亏分布：每个大户的综合回报
struct RoiBarsView: View {
    let rows: [RoiRow]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("大户综合回报（已兑现 + 浮动，相对投入）").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Chart(rows) { r in
                BarMark(x: .value("回报%", max(-100, min(r.roi, 500))), y: .value("大户", r.label))
                    .foregroundStyle(r.roi >= 0 ? Color.green : Color.red)
                    .annotation(position: r.roi >= 0 ? .trailing : .leading) {
                        Text(String(format: "%+.0f%%", r.roi)).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
            }
            .chartXAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "%.0f%%", d)).font(.system(size: 9)) } } } }
            .frame(height: CGFloat(rows.count) * 26 + 24)
        }
    }
}

// 持仓集中度：一根横向堆叠条
struct ConcBarView: View {
    let conc: Conc
    var body: some View {
        let t1 = conc.top1 ?? 0
        let t5 = max(0, (conc.top5 ?? 0) - t1)
        let t10 = max(0, (conc.top10 ?? 0) - (conc.top5 ?? 0))
        let rest = max(0, 100 - (conc.top10 ?? 0))
        let parts: [(String, Double, Color)] = [("第1大", t1, Color.red), ("第2-5大", t5, Color.orange), ("第6-10大", t10, Color.yellow), ("其他", rest, Color.gray.opacity(0.4))]
        return VStack(alignment: .leading, spacing: 6) {
            Text("持仓集中度").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            GeometryReader { g in
                HStack(spacing: 1) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                        Rectangle().fill(p.2).frame(width: max(0, g.size.width * CGFloat(p.1 / 100)))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 14)
            HStack(spacing: 10) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    HStack(spacing: 3) {
                        Circle().fill(p.2).frame(width: 7, height: 7)
                        Text(p.0 + String(format: " %.1f%%", p.1)).font(.system(size: 10))
                    }
                }
            }
            if let w = conc.wallets10 {
                Text(String(format: "前 10 大普通钱包合计 %.1f%%（已剔除池子、合约、金库）", w)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
