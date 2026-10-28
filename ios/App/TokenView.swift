import SwiftUI
import Charts
import UIKit

private struct DexSearch: Decodable {
    struct Pair: Decodable {
        var chainId: String?
        var baseToken: Tok?
        var liquidity: Liq?
    }
    struct Tok: Decodable { var address: String? }
    struct Liq: Decodable { var usd: Double? }
    var pairs: [Pair]?
}

@MainActor
final class TokenVM: ObservableObject {
    @Published var input = ""
    @Published var chain: Chain = .bsc
    @Published var autoChain = true
    @Published var token: TokenResponse?
    @Published var deep: DeepResponse?
    @Published var deepNote: String?
    @Published var analysis: AnalyzeResponse?
    @Published var aiMessage: String?
    @Published var loading = false
    @Published var aiLoading = false
    @Published var error: String?
    @Published var shareImage: UIImage?
    private var lastAddress = ""
    private var runID = 0

    func inputChanged() {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if (Addr.isEVM(t) || Addr.isSolana(t)) && t != lastAddress { start(t) }
    }

    func start(_ raw: String) {
        let addr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Addr.isEVM(addr) || Addr.isSolana(addr) else {
            error = "地址格式不对：EVM 是 0x 开头 42 位，Solana 是 32–44 位 Base58"
            return
        }
        runID += 1
        let id = runID
        lastAddress = addr
        token = nil; deep = nil; deepNote = nil; analysis = nil
        aiMessage = nil; error = nil; shareImage = nil
        loading = true
        Task { await run(addr, id) }
    }

    private func run(_ addr: String, _ id: Int) async {
        var c = chain
        if Addr.isSolana(addr) {
            c = .solana
        } else if autoChain {
            if let d = await Self.detect(addr) { c = d }
        }
        guard id == runID else { return }
        chain = c
        do {
            let t: TokenResponse = try await API.get("/api/token", ["chain": c.rawValue, "address": addr])
            guard id == runID else { return }
            if let e = t.error { error = e; loading = false; return }
            token = t
            loading = false
        } catch {
            guard id == runID else { return }
            self.error = error.localizedDescription
            loading = false
            return
        }
        async let d: Void = loadDeep(addr, c, id)
        async let a: Void = loadAI(addr, c, id)
        await d
        await a
        if id == runID { renderShare() }
    }

    private func loadDeep(_ addr: String, _ c: Chain, _ id: Int) async {
        if c == .solana { deepNote = "Solana 持有人钱包分析暂未接入"; return }
        guard c.tokenSupported else { deepNote = "该链暂不支持持有人钱包分析"; return }
        do {
            let r: DeepResponse = try await API.get("/api/token-deep", ["chain": c.rawValue, "address": addr])
            guard id == runID else { return }
            if let e = r.error { deepNote = e } else { deep = r }
        } catch {
            guard id == runID else { return }
            deepNote = error.localizedDescription
        }
    }

    func loadAI(_ addr: String, _ c: Chain, _ id: Int) async {
        guard c.tokenSupported else { return }
        aiLoading = true
        defer { aiLoading = false }
        do {
            let r: AnalyzeResponse = try await API.get("/v1/ai/analyze", ["chain": c.rawValue, "address": addr])
            guard id == runID else { return }
            if let e = r.error {
                if e == "no_groq_key" { aiMessage = "未绑定 Groq 密钥：设置 → API 密钥与额度" }
                else if e.hasPrefix("groq_429") { aiMessage = "Groq 已限额，恢复后再试（设置里有倒计时）" }
                else { aiMessage = "AI 研判失败：\(e)" }
            } else {
                analysis = r
            }
        } catch {
            guard id == runID else { return }
            aiMessage = error.localizedDescription
        }
    }

    func retryAI() {
        guard let t = token, let a = t.address else { return }
        let id = runID
        aiMessage = nil
        Task {
            await loadAI(a, chain, id)
            renderShare()
        }
    }

    // 合约在哪条链：向 Dexscreener 搜地址，按流动性取最大的一条链
    static func detect(_ addr: String) async -> Chain? {
        guard let url = URL(string: "https://api.dexscreener.com/latest/dex/search?q=" + addr) else { return nil }
        guard let result = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(DexSearch.self, from: result.0) else { return nil }
        var score: [Chain: Double] = [:]
        for p in r.pairs ?? [] {
            guard p.baseToken?.address?.lowercased() == addr.lowercased(),
                  let cid = p.chainId, let ch = Chain.fromDex(cid) else { continue }
            score[ch, default: 0] += (p.liquidity?.usd ?? 0) + 1
        }
        return score.max(by: { $0.value < $1.value })?.key
    }

    func renderShare() {
        guard let t = token else { return }
        let a = analysis?.analysis
        let card = ShareCard(symbol: t.price?.symbol ?? "未知代币", chain: chain.title,
                             price: Money.price(t.price?.priceUsd), change: t.price?.priceChange24hPct,
                             liq: Money.format(t.price?.liquidityUsd), holders: t.holders ?? t.realHolders,
                             verdict: a?.verdict, score: a?.score, headline: a?.headline)
        let r = ImageRenderer(content: card)
        r.scale = 3
        shareImage = r.uiImage
    }
}

struct AlertPrefill {
    var chain: Chain
    var address: String
    var symbol: String
    var price: Double?
}

struct TokenView: View {
    @StateObject private var vm = TokenVM()
    @ObservedObject private var live = LiveWatch.shared
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    inputCard
                    if vm.loading {
                        Card { HStack(spacing: 10) { ProgressView(); Text("正在查询…").foregroundStyle(.secondary) } }
                    }
                    if let e = vm.error { ErrorCard(text: e) { vm.start(vm.input) } }
                    if let t = vm.token { content(t) }
                    if vm.token == nil && !vm.loading && vm.error == nil { hint }
                }
                .padding(16)
            }
            .background(Color.page)
            .navigationTitle("体检")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let img = vm.shareImage {
                        ShareLink(item: Image(uiImage: img), preview: SharePreview("TSTZ-M 体检", image: Image(uiImage: img))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    if vm.token != nil {
                        Button { showAlert = true } label: { Image(systemName: "bell.badge") }
                    }
                }
            }
            .sheet(isPresented: $showAlert) {
                AlertEditor(prefill: prefill) { }
            }
        }
    }

    private var prefill: AlertPrefill? {
        guard let t = vm.token, let a = t.address else { return nil }
        return AlertPrefill(chain: vm.chain, address: a, symbol: t.price?.symbol ?? "", price: t.price?.priceUsd)
    }

    private var inputCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("粘贴合约地址，自动体检", text: $vm.input)
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
                    } label: { Label("粘贴", systemImage: "doc.on.clipboard") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Spacer()
                    Menu {
                        Button("自动识别链") { vm.autoChain = true }
                        ForEach(Chain.allCases.filter { $0.tokenSupported }) { c in
                            Button(c.title) { vm.autoChain = false; vm.chain = c }
                        }
                    } label: {
                        Label(vm.autoChain ? "自动识别链" : vm.chain.title, systemImage: "link")
                            .font(.subheadline)
                    }
                }
            }
        }
    }

    private var hint: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("粘贴合约即自动体检").font(.headline)
                Text("价格、流动性、持仓人数与分布、合约风险、安全字段，再由 AI 结合数据给出结论。查不到的项目显示「未知」，不会编数。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func content(_ t: TokenResponse) -> some View {
        header(t)
        metrics(t)
        aiCard
        riskCard(t)
        flowCard(t)
        holdersChart(t)
        deepCard
        linksCard(t)
    }

    private func header(_ t: TokenResponse) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.price?.symbol ?? "未知代币").font(.title2.bold())
                        Text(t.price?.name ?? "").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Pill(text: vm.chain.title, color: Color.blue)
                    if let r = t.risk { Pill(text: Verdict.label(r), color: Verdict.color(r)) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Money.price(t.price?.priceUsd)).font(.system(size: 30, weight: .bold, design: .rounded))
                    if let c = t.price?.priceChange24hPct {
                        Text(String(format: "%+.2f%%", c)).font(.subheadline.weight(.semibold))
                            .foregroundStyle(c >= 0 ? Color.green : Color.red)
                    } else {
                        Text("24h 未知").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text(Addr.short(t.address ?? vm.input)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Button { UIPasteboard.general.string = t.address ?? vm.input } label: { Image(systemName: "doc.on.doc") }
                        .font(.caption)
                    Spacer()
                    if let p = t.price?.priceUsd {
                        Button {
                            if live.running { live.stop() }
                            else { live.start(chain: vm.chain, address: t.address ?? vm.input, symbol: t.price?.symbol ?? "?", price: p, change: t.price?.priceChange24hPct, liq: t.price?.liquidityUsd) }
                        } label: {
                            Label(live.running ? "停止盯盘" : "灵动岛盯盘", systemImage: live.running ? "stop.circle" : "dot.radiowaves.left.and.right")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            }
        }
    }

    private func metrics(_ t: TokenResponse) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(title: "流动性", value: Money.format(t.price?.liquidityUsd))
            StatTile(title: "24h 成交", value: Money.format(t.price?.volume24hUsd))
            StatTile(title: "市值", value: Money.format(t.marketCapUsd))
            StatTile(title: "持仓人数", value: (t.holders ?? t.realHolders).map { "\($0)" } ?? "未知")
            StatTile(title: "Top10 占比", value: pctText(t.topHoldersPct), tint: (t.topHoldersPct ?? 0) >= 50 ? Color.red : Color.primary)
            StatTile(title: "池龄", value: t.poolAge.map { String(format: "%.1f 天", $0) } ?? "未知")
        }
    }

    // MARK: AI 研判
    private var aiCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("AI 研判", systemImage: "sparkles").font(.headline)
                    Spacer()
                    if vm.aiLoading { ProgressView() }
                }
                if let a = vm.analysis?.analysis {
                    HStack(spacing: 16) {
                        ScoreGauge(score: a.score ?? 0, color: Verdict.color(a.verdict))
                        VStack(alignment: .leading, spacing: 6) {
                            Pill(text: Verdict.label(a.verdict), color: Verdict.color(a.verdict))
                            Text(a.headline ?? "").font(.subheadline.weight(.semibold))
                        }
                    }
                    ForEach(Array((a.bullets ?? []).enumerated()), id: \.offset) { _, b in
                        HStack(alignment: .top, spacing: 8) {
                            Pill(text: b.tag ?? "—", color: tagColor(b.tag))
                            Text(b.text ?? "").font(.footnote)
                        }
                    }
                    if let w = a.watch, !w.isEmpty {
                        Divider()
                        Text("后续观察").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(w.enumerated()), id: \.offset) { _, s in
                            Text("• " + s).font(.footnote)
                        }
                    }
                    Text("仅依据上方已查到的数据生成，未查到的项目标未知，不构成投资建议").font(.caption2).foregroundStyle(.secondary)
                } else if let m = vm.aiMessage {
                    Text(m).font(.footnote).foregroundStyle(.secondary)
                    Button("重试", action: vm.retryAI).font(.footnote.weight(.semibold))
                } else if !vm.aiLoading {
                    Text("等待数据").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func tagColor(_ s: String?) -> Color {
        switch s ?? "" {
        case "风险": return Color.red
        case "亮点": return Color.green
        default: return Color.gray
        }
    }

    // MARK: 合约风险与安全字段
    private func yn(_ v: Bool?, riskWhenTrue: Bool, level: RiskState) -> (String, RiskState) {
        guard let v = v else { return ("未知", .unknown) }
        let risky = (v == riskWhenTrue)
        return (v ? "是" : "否", risky ? level : .good)
    }

    private func taxRow(_ label: String, _ v: Double?) -> some View {
        let state: RiskState
        if let v = v { state = v >= 50 ? .bad : (v >= 10 ? .warn : .good) } else { state = .unknown }
        return RiskRow(label: label, text: v.map { String(format: "%.1f%%", $0) } ?? "未知", state: state)
    }

    private func riskCard(_ t: TokenResponse) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("合约风险", systemImage: "shield.lefthalf.filled").font(.headline)
                    Spacer()
                    if let src = t.riskSource { Text(src).font(.caption2).foregroundStyle(.secondary) }
                }
                if vm.chain == .solana {
                    let mint = yn(t.solanaAuthorities?.mintRenounced, riskWhenTrue: false, level: .warn)
                    let freeze = yn(t.solanaAuthorities?.freezeRenounced, riskWhenTrue: false, level: .warn)
                    RiskRow(label: "已放弃增发权限", text: mint.0, state: mint.1)
                    RiskRow(label: "已放弃冻结权限", text: freeze.0, state: freeze.1)
                } else {
                    let hp = yn(t.honeypot, riskWhenTrue: true, level: .bad)
                    let mt = yn(t.mintable, riskWhenTrue: true, level: .warn)
                    let bl = yn(t.blacklist, riskWhenTrue: true, level: .warn)
                    let rn = yn(t.renounced, riskWhenTrue: false, level: .warn)
                    RiskRow(label: "蜜罐", text: hp.0, state: hp.1)
                    taxRow("买入税", t.buyTax)
                    taxRow("卖出税", t.sellTax)
                    RiskRow(label: "可增发", text: mt.0, state: mt.1)
                    RiskRow(label: "有黑名单", text: bl.0, state: bl.1)
                    RiskRow(label: "已放弃所有权", text: rn.0, state: rn.1)
                }
                let lp = yn(t.lpLocked, riskWhenTrue: false, level: .warn)
                RiskRow(label: "LP 已锁定", text: lp.0, state: lp.1)
                if let b = t.lpBurnPct { RiskRow(label: "LP 销毁占比", text: pctText(b), state: b >= 90 ? .good : .warn) }
                Text("风险灯来自扫描信号，不是安全保证").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 图表
    private func flowCard(_ t: TokenResponse) -> some View {
        var pts: [FlowPoint] = []
        func add(_ name: String, _ p: TradeFlowPeriod?) {
            guard let p = p, let b = p.buys, let s = p.sells, b + s > 0 else { return }
            pts.append(FlowPoint(period: name, side: "买", n: b))
            pts.append(FlowPoint(period: name, side: "卖", n: s))
        }
        add("5 分钟", t.tradeFlow?.m5)
        add("1 小时", t.tradeFlow?.h1)
        add("24 小时", t.tradeFlow?.h24)
        if pts.isEmpty, let b = t.txns24h?.buys, let s = t.txns24h?.sells, b + s > 0 {
            pts.append(FlowPoint(period: "24 小时", side: "买", n: b))
            pts.append(FlowPoint(period: "24 小时", side: "卖", n: s))
        }
        return Group {
            if pts.isEmpty { EmptyView() } else {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("买卖笔数", systemImage: "arrow.left.arrow.right").font(.headline)
                        Chart(pts) { p in
                            BarMark(x: .value("笔数", p.n), y: .value("周期", p.period), stacking: .normalized)
                                .foregroundStyle(by: .value("方向", p.side))
                        }
                        .chartForegroundStyleScale(["买": Color.green, "卖": Color.red])
                        .chartXAxis(.hidden)
                        .frame(height: CGFloat(pts.count / 2) * 44 + 24)
                    }
                }
            }
        }
    }

    private func holdersChart(_ t: TokenResponse) -> some View {
        let hs = (t.topHolders ?? []).compactMap { h -> HoldSlice? in
            guard let p = h.sharePct, p > 0 else { return nil }
            return HoldSlice(name: Addr.short(h.address ?? "?") + (h.isContract == true ? "（合约）" : ""), pct: p)
        }
        let top = Array(hs.prefix(10))
        let sum = top.reduce(0) { $0 + $1.pct }
        var slices = top
        if sum < 99.5 && !top.isEmpty { slices.append(HoldSlice(name: "其他", pct: max(0, 100 - sum))) }
        return Group {
            if top.isEmpty { EmptyView() } else {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("持仓分布", systemImage: "chart.pie").font(.headline)
                        HoldersDonut(slices: slices)
                        ForEach(Array(top.prefix(5).enumerated()), id: \.offset) { _, s in
                            HStack {
                                Text(s.name).font(.caption.monospaced())
                                Spacer()
                                Text(String(format: "%.2f%%", s.pct)).font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
            }
        }
    }

    private var deepCard: some View {
        Group {
            if let rows = vm.deep?.holderAnalyses, !rows.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("持有人钱包风格", systemImage: "person.crop.rectangle.stack").font(.headline)
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Addr.short(r.wallet ?? "?")).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(r.style ?? "未知").font(.footnote)
                            }
                        }
                    }
                }
            } else if let n = vm.deepNote {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("持有人钱包风格", systemImage: "person.crop.rectangle.stack").font(.headline)
                        Text(n).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func linksCard(_ t: TokenResponse) -> some View {
        let items: [(String, String?)] = [("Ave", t.tradeLinks?.ave), ("GMGN", t.tradeLinks?.gmgn), ("Dexscreener", t.tradeLinks?.dexscreener), ("X 搜索", t.tradeLinks?.xSearch)]
        return Group {
            if items.contains(where: { $0.1 != nil }) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("跳转", systemImage: "arrow.up.right.square").font(.headline)
                        HStack {
                            ForEach(items, id: \.0) { item in
                                if let s = item.1, let u = URL(string: s) {
                                    Link(item.0, destination: u).font(.footnote.weight(.semibold))
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

struct FlowPoint: Identifiable {
    let id = UUID()
    let period: String
    let side: String
    let n: Int
}

struct HoldSlice: Identifiable {
    let id = UUID()
    let name: String
    let pct: Double
}

struct HoldersDonut: View {
    let slices: [HoldSlice]
    @State private var appear = false
    var body: some View {
        Chart(slices) { s in
            SectorMark(angle: .value("占比", appear ? s.pct : 0.001), innerRadius: .ratio(0.6), angularInset: 1.5)
                .cornerRadius(3)
                .foregroundStyle(by: .value("持有人", s.name))
        }
        .chartLegend(.hidden)
        .frame(height: 190)
        .onAppear { withAnimation(.easeOut(duration: 1.0)) { appear = true } }
    }
}

struct ScoreGauge: View {
    let score: Double
    let color: Color
    @State private var shown = 0.0
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 9)
            Circle().trim(from: 0, to: shown / 100)
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(String(format: "%.0f", shown)).font(.system(size: 22, weight: .bold, design: .rounded))
                Text("安全分").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 72, height: 72)
        .onAppear { withAnimation(.easeOut(duration: 1.0)) { shown = min(100, max(0, score)) } }
    }
}
