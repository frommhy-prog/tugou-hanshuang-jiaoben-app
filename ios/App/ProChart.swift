import SwiftUI
import UIKit
import WebKit

// MARK: - AI 触发方式：自动 / 手动（默认自动，和原来行为一致；各处 AI 都读这一个开关）
enum AIMode {
    static var auto: Bool {
        get { (Cfg.defaults.object(forKey: "aiAuto") as? Bool) ?? true }
        set { Cfg.defaults.set(newValue, forKey: "aiAuto") }
    }
}

func kNorm(_ a: String) -> String { a.hasPrefix("0x") ? a.lowercased() : a }

extension TF {
    var sec: Double {
        switch self {
        case .m1: return 60
        case .m5: return 300
        case .m15: return 900
        case .h1: return 3600
        case .h4: return 14400
        case .d1: return 86400
        case .w1: return 604800
        case .mo1: return 2592000
        }
    }
}

// GeckoTerminal OHLCV：一页最多 1000 根，用 before_timestamp 往前翻页，直到池子最早一根
extension MarketAPI {
    static func candlesPage(_ chain: Chain, _ pair: String, _ tf: TF, before: Double?, limit: Int) async throws -> [Candle] {
        var u = "https://api.geckoterminal.com/api/v2/networks/\(chain.geckoId)/pools/\(pair)/ohlcv/\(tf.unit)?aggregate=\(tf.aggregate)&limit=\(limit)&currency=usd&token=base"
        if let b = before { u += "&before_timestamp=\(Int(b))" }
        let o = try await json(u)
        guard let d = (o as? [String: Any])?["data"] as? [String: Any],
              let a = d["attributes"] as? [String: Any],
              let list = a["ohlcv_list"] as? [[Any]] else { return [] }
        var out: [Candle] = []
        for row in list where row.count >= 6 {
            guard let t = num(row[0]), let op = num(row[1]), let hi = num(row[2]), let lo = num(row[3]), let cl = num(row[4]) else { continue }
            out.append(Candle(t: t, o: op, h: hi, l: lo, c: cl, v: num(row[5]) ?? 0))
        }
        return out.sorted { $0.t < $1.t }
    }
}

// MARK: - 图表页（TradingView Lightweight Charts，Apache-2.0，构建时打包进 App，离线可用）
enum KLineHTML {
    private static func res(_ name: String, _ ext: String) -> String? {
        if let u = Bundle.main.url(forResource: name, withExtension: ext), let s = try? String(contentsOf: u, encoding: .utf8) { return s }
        if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Web"), let s = try? String(contentsOf: u, encoding: .utf8) { return s }
        return nil
    }

    static func page() -> String {
        guard let html = res("chart", "html") else {
            return "<html><body style='font:13px -apple-system;color:#999'>图表页面资源缺失</body></html>"
        }
        let js = res("lwc", "js") ?? ""
        return html.replacingOccurrences(of: "/*LWC_JS*/", with: js)
    }
}

struct KLineWeb: UIViewRepresentable {
    let payload: String
    let seq: Int
    let clearToken: Int
    let onWeb: (Double?) -> Void
    var onFail: (() -> Void)? = nil

    func makeCoordinator() -> Coord { Coord(onWeb, onFail) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "chart")
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.bounces = false
        wv.navigationDelegate = context.coordinator
        context.coordinator.web = wv
        context.coordinator.reloadPage()
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        let c = context.coordinator
        c.onWeb = onWeb
        c.onFail = onFail
        c.push(payload, seq: seq)
        if clearToken != c.lastClear {
            c.lastClear = clearToken
            if c.loaded { wv.evaluateJavaScript("window.clearSel && window.clearSel()", completionHandler: nil) }
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coord) {
        coordinator.stop()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "chart")
    }

    // 带自愈的网页桥：页面加载后推数据，3.5 秒内没收到「已渲染」就重载页面（最多 2 次），仍失败则通知上层退回基础图表
    final class Coord: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onWeb: (Double?) -> Void
        var onFail: (() -> Void)?
        weak var web: WKWebView?
        var loaded = false
        var lastPayload = ""
        var lastSeq = -1
        var lastClear = 0
        var gotOK = false
        var tries = 0
        var gen = 0

        init(_ onWeb: @escaping (Double?) -> Void, _ onFail: (() -> Void)?) {
            self.onWeb = onWeb
            self.onFail = onFail
        }

        func reloadPage() {
            loaded = false
            gotOK = false
            gen += 1
            web?.loadHTMLString(KLineHTML.page(), baseURL: nil)
        }

        func stop() { gen += 1 }

        func push(_ payload: String, seq: Int) {
            if payload.isEmpty || seq == lastSeq { return }
            lastSeq = seq
            lastPayload = payload
            if loaded { send() }
        }

        private func send() {
            guard let wv = web, !lastPayload.isEmpty else { return }
            let g = gen
            wv.evaluateJavaScript("window.pushData(" + lastPayload + ")") { [weak self] _, err in
                if err != nil { self?.failSoon(g) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
                guard let s = self, s.gen == g, !s.gotOK else { return }
                s.failSoon(g)
            }
        }

        private func failSoon(_ g: Int) {
            if g != gen || gotOK { return }
            if tries < 2 {
                tries += 1
                reloadPage()
            } else {
                onFail?()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            send()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            reloadPage()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let d = message.body as? [String: Any], let type = d["type"] as? String else { return }
            if type == "sel", let t = d["t"] as? Double { onWeb(t) }
            else if type == "clear" { onWeb(nil) }
            else if type == "more" { onWeb(-1) }
            else if type == "ok" { gotOK = true }
            else if type == "err" { failSoon(gen) }
        }
    }
}

// MARK: - K 线状态：全量历史（往前翻页）、20 秒增量刷新、选中哪根、按根缓存的 AI 与地址拆解
@MainActor
final class KLineVM: ObservableObject {
    @Published var tf: TF = .m15
    @Published var candles: [Candle] = []
    @Published var note: String?
    @Published var loadingHist = false
    @Published var histDone = false
    @Published var histCapped = false
    @Published var histPaused = false
    @Published var selT: Double?
    @Published var payload = ""
    @Published var seq = 0
    @Published var clearToken = 0
    @Published var candleAI: [String: AIResult] = [:]
    @Published var candleAIMsg: [String: String] = [:]
    @Published var aiLoading: Set<String> = []
    @Published var extra: [String: UHolderAnalysis] = [:]
    @Published var extraLoading: Set<String> = []
    @Published var extraErr: [String: String] = [:]

    var dark = true
    static let autoPages = 1
    @Published var histMore = false
    @Published var liveNote = ""
    var extraMarks: [[Double]] = []
    var cfgMain = "MA,SUPER"
    var cfgSub = "MACD"
    var cfgMcap = false
    var cfgMult = 1.0
    private var trades: [UTrade] = []
    private var createdMs: Double?
    private var chain: Chain = .solana
    private var pair = ""
    private var token = ""
    private var key = ""
    private var gen = 0
    private var resumeBefore: Double?
    private var base: [Candle] = []   // 拉到的原始 K 线（周线月线用日线汇总）
    private var liveC: Candle?
    private var liveTF: TF = .m15

    var tzOff: Double { Double(TZ.current.secondsFromGMT()) }

    var statusText: String {
        if candles.isEmpty { return "" }
        let tail = loadingHist ? "，历史加载中…" : (histDone ? "，已到池子最早一根" : (histCapped ? "，已达加载上限" : ""))
        return "共 \(candles.count) 根" + tail + liveNote
    }

    func aiKey(_ t: Double) -> String { tf.rawValue + ":" + String(Int(t)) }

    func begin(chain: Chain, pair: String?, token: String) {
        guard let pair = pair, !pair.isEmpty else { return }
        let k = chain.rawValue + ":" + pair
        if k == key { return }
        key = k
        self.chain = chain
        self.pair = pair
        self.token = token
        extra = [:]
        extraErr = [:]
        extraLoading = []
        reload()
    }

    func setTF(_ t: TF) {
        if t == tf { return }
        tf = t
        reload()
    }

    func loadMore() {
        if loadingHist || histDone || candles.isEmpty { return }
        let g = gen
        let b = (base.first?.t ?? 0) - 1
        histMore = false
        Task { await loadHistory(g, startBefore: b) }
    }

    func retry() { reload() }

    func resume() {
        histPaused = false
        let g = gen
        let b = resumeBefore
        Task { await loadHistory(g, startBefore: b) }
    }

    func sync(trades: [UTrade], createdMs: Double?) {
        self.trades = trades
        self.createdMs = createdMs
        rebuild()
    }

    func onWeb(_ t: Double?) {
        if let t = t, t < 0 { loadMore(); return } // 网页向左滚到头 → 补历史
        if let t = t { selT = t - tzOff } else { selT = nil }
    }

    func clearSelection() {
        selT = nil
        clearToken += 1
    }

    private func reload() {
        gen += 1
        let g = gen
        var own = KLineCache.load(chain.rawValue + ":" + pair + ":" + tf.rawValue)
        if own.count < 30, let d = deriveFromFiner() { own = merged(d, own) }
        setCandles(own)
        if !candles.isEmpty { rebuild() }
        note = nil
        histDone = false
        histCapped = false
        histPaused = false
        selT = nil
        candleAI = [:]
        candleAIMsg = [:]
        aiLoading = []
        loadingHist = false
        Task { await loadHistory(g, startBefore: nil) }
    }

    private func setCandles(_ raw: [Candle]) {
        base = raw
        candles = withLive(tf.rolled(raw))
        KLineShared.shared.update(chain: chain, pair: pair, tf: tf, candles: candles)
    }

    private func merged(_ base: [Candle], _ over: [Candle]) -> [Candle] {
        var m: [Double: Candle] = [:]
        for c in base { m[c.t] = c }
        for c in over { m[c.t] = c }
        return m.values.sorted { $0.t < $1.t }
    }

    private func fetchPage(_ before: Double?, _ g: Int) async throws -> [Candle] {
        var lastErr: Error = APIError.network("K 线读取失败")
        for i in 0..<3 {
            do {
                return try await MarketAPI.candlesPage(chain, pair, tf, before: before, limit: 1000)
            } catch {
                lastErr = error
                if g != gen { throw error }
                try? await Task.sleep(nanoseconds: UInt64(4 + i * 4) * 1_000_000_000)
            }
        }
        throw lastErr
    }

    // 往前翻页读到池子最早一根（一页 1000 根，页间隔 2.3 秒，守住 GeckoTerminal 免费 30 次/分钟）
    private func loadHistory(_ g: Int, startBefore: Double?) async {
        if pair.isEmpty { return }
        loadingHist = true
        var before = startBefore
        var pages = 0
        while g == gen && pages < KLineVM.autoPages {
            do {
                let page = try await fetchPage(before, g)
                if g != gen { return }
                if page.isEmpty { histDone = true; break }
                setCandles(merged(page, base))
                rebuild()
                pages += 1
                if page.count < 1000 { histDone = true; break }
                before = (page.first?.t ?? 0) - 1
                if pages < KLineVM.autoPages { try? await Task.sleep(nanoseconds: 2_300_000_000) }
            } catch {
                if g != gen { return }
                if candles.isEmpty { note = error.localizedDescription } else { histPaused = true; resumeBefore = before }
                loadingHist = false
                return
            }
        }
        if g != gen { return }
        if !histDone && pages >= KLineVM.autoPages { histMore = true }
        if candles.isEmpty && note == nil { note = "该池子暂无 K 线数据" }
        loadingHist = false
    }

    func refreshLatest() async {
        if pair.isEmpty || candles.isEmpty { return }
        let g = gen
        if let page = try? await MarketAPI.candlesPage(chain, pair, tf, before: nil, limit: 60), g == gen, !page.isEmpty {
            setCandles(merged(base, page))
            rebuild()
        }
    }

    // 把全部 K 线 + 大额成交标记打成 JSON 交给网页图表（时间按设置里的时区平移）
    func rebuild(live: Bool = false) {
        if candles.isEmpty { return }
        let off = tzOff
        let sec = tf.sec
        var rows: [[Double]] = []
        rows.reserveCapacity(candles.count)
        var lo = Double.greatestFiniteMagnitude
        for c in candles {
            if !(c.o.isFinite && c.h.isFinite && c.l.isFinite && c.c.isFinite && c.v.isFinite) { continue }
            rows.append([c.t + off, c.o, c.h, c.l, c.c, c.v])
            if c.l > 0 && c.l < lo { lo = c.l }
        }
        var prec = 4
        if lo > 0 && lo < Double.greatestFiniteMagnitude { prec = max(2, min(12, Int(ceil(-log10(lo))) + 3)) }

        var mk: [[Double]] = []
        if !trades.isEmpty, let first = candles.first?.t, let last = candles.last?.t {
            var buckets: [Double: [Double]] = [:]
            for t in trades {
                let b = kBucket(t.t, tf)
                if b < first || b > last { continue }
                var e = buckets[b] ?? [0, 0]
                if t.buy { e[0] += t.usd } else { e[1] += t.usd }
                buckets[b] = e
            }
            var items: [[Double]] = []
            for (b, e) in buckets {
                if e[0] > 0 { items.append([b, 1, e[0]]) }
                if e[1] > 0 { items.append([b, -1, e[1]]) }
            }
            items.sort { $0[2] > $1[2] }
            for it in items.prefix(14) { mk.append([it[0] + off, it[1], it[2]]) }
        }

        for m in extraMarks where m.count >= 4 {
            let b = kBucket(m[0], tf)
            if let f = candles.first?.t, let l = candles.last?.t, b >= f, b <= l { mk.append([b + off, m[1], m[2], m[3]]) }
        }
        var created: Any = NSNull()
        if let cm = createdMs {
            let b = kBucket(cm / 1000, tf)
            created = b + off
        }
        var sel: Any = NSNull()
        if let s = selT { sel = s + off }

        let obj: [String: Any] = [
            "key": chain.rawValue + pair + tf.rawValue,
            "candles": rows,
            "markers": mk,
            "created": created,
            "sel": sel,
            "prec": prec,
            "dark": dark,
            "main": cfgMain,
            "sub": cfgSub,
            "mcap": cfgMcap,
            "mult": (cfgMult.isFinite && cfgMult > 0) ? cfgMult : 1.0,
        ]
        if let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) {
            payload = s
            seq += 1
        }
        if !live { KLineCache.save(key: chain.rawValue + ":" + pair + ":" + tf.rawValue, base) }
    }

    // MARK: 实时尾巴：Dexscreener 实时价每 3 秒把最新一根 K 线补到「现在」，不再等 GeckoTerminal 的延迟 K 线
    private func withLive(_ cs: [Candle]) -> [Candle] {
        guard let lc = liveC, liveTF == tf, let last = cs.last else { return cs }
        var out = cs
        if lc.t == last.t {
            out[out.count - 1] = Candle(t: last.t, o: last.o, h: max(last.h, lc.h), l: min(last.l, lc.l), c: lc.c, v: max(last.v, lc.v))
        } else if lc.t > last.t {
            if tf.sec <= 86400 {
                var t = last.t + tf.sec
                var n = 0
                while t < lc.t && n < 300 {
                    out.append(Candle(t: t, o: last.c, h: last.c, l: last.c, c: last.c, v: 0))
                    t += tf.sec
                    n += 1
                }
            }
            out.append(lc)
        }
        return out
    }

    func applyLive(_ price: Double) {
        guard price > 0, price.isFinite, let last = candles.last else { return }
        let b = kBucket(Date().timeIntervalSince1970, tf)
        if b < last.t { return }
        let lc: Candle
        if let ex = liveC, liveTF == tf, ex.t == b {
            lc = Candle(t: b, o: ex.o, h: max(ex.h, price), l: min(ex.l, price), c: price, v: ex.v)
        } else if b == last.t {
            lc = Candle(t: b, o: last.o, h: max(last.h, price), l: min(last.l, price), c: price, v: last.v)
        } else {
            lc = Candle(t: b, o: last.c, h: max(last.c, price), l: min(last.c, price), c: price, v: 0)
        }
        liveC = lc
        liveTF = tf
        candles = withLive(tf.rolled(base))
        rebuild(live: true)
    }

    func liveLoop() async {
        while !Task.isCancelled {
            let g = gen
            if !pair.isEmpty, !candles.isEmpty, let p = try? await MarketAPI.livePrice(chain, pair), g == gen {
                applyLive(p)
                let f = DateFormatter()
                f.dateFormat = "HH:mm:ss"
                f.timeZone = TZ.current
                liveNote = "，实时价 " + f.string(from: Date())
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    // MARK: 秒切周期：本地缓存里有更细的周期时，直接汇总出当前周期先显示，网络数据回来再覆盖
    private func deriveFromFiner() -> [Candle]? {
        if tf == .w1 || tf == .mo1 || tf == .m1 { return nil }
        let order: [TF] = [.m1, .m5, .m15, .h1, .h4]
        for f in order where f.sec < tf.sec && Int(tf.sec) % Int(f.sec) == 0 {
            let cs = KLineCache.load(chain.rawValue + ":" + pair + ":" + f.rawValue)
            if cs.count < 5 { continue }
            var out: [Candle] = []
            var cur: Candle?
            for c in cs.sorted(by: { $0.t < $1.t }) {
                let b = kBucket(c.t, tf)
                if let x = cur, x.t == b {
                    cur = Candle(t: b, o: x.o, h: max(x.h, c.h), l: min(x.l, c.l), c: c.c, v: x.v + c.v)
                } else {
                    if let x = cur { out.append(x) }
                    cur = Candle(t: b, o: c.o, h: c.h, l: c.l, c: c.c, v: c.v)
                }
            }
            if let x = cur { out.append(x) }
            if out.count >= 3 { return out }
        }
        return nil
    }

    // 后台把其它周期预取进缓存（受限流网关排队，不会触发 429）
    func prefetchOthers() async {
        let g = gen
        try? await Task.sleep(nanoseconds: 7_000_000_000)
        for t in [TF.m1, .m5, .m15, .h1, .h4, .d1] {
            if g != gen || Task.isCancelled { return }
            if t == tf { continue }
            let k = chain.rawValue + ":" + pair + ":" + t.rawValue
            if KLineCache.load(k).count >= 200 { continue }
            if let page = try? await MarketAPI.candlesPage(chain, pair, t, before: nil, limit: 1000), !page.isEmpty {
                KLineCache.save(key: k, page)
            }
        }
    }

    // 任意地址的拆解（成本、盈亏、入场时点、状态），同一地址只拆一次
    func analyze(owner: String) async {
        let k = kNorm(owner)
        if extra[k] != nil || extraLoading.contains(k) { return }
        extraLoading.insert(k)
        extraErr[k] = nil
        defer { extraLoading.remove(k) }
        do {
            let r: UHolderAnalysis = try await Engine.get("/e/v2/holder", ["chain": chain.rawValue, "token": token, "owner": owner, "pages": "2"])
            if let e = r.error { extraErr[k] = e + (r.detail.map { "：" + $0 } ?? "") } else { extra[k] = r }
        } catch {
            extraErr[k] = error.localizedDescription
        }
    }
}

// MARK: - 图表卡片：全量 K 线 + 下方随光标变化的分析面板
struct KLineCard: View {
    @ObservedObject var vm: UTokenVM
    @StateObject private var cvm = KLineVM()
    @Environment(\.colorScheme) private var scheme
    @AppStorage("kMain", store: Cfg.defaults) private var mainSet = "MA,SUPER"
    @AppStorage("kSub", store: Cfg.defaults) private var subInd = "MACD"
    @AppStorage("kMcap", store: Cfg.defaults) private var mcap = false
    @State private var webFailed = false
    @State private var fallbackSel: Date?
    @State private var showFull = false

    private var key: String { vm.chain.rawValue + ":" + (vm.main?.pairAddress ?? "") + ":" + vm.address }

    var body: some View {
        VStack(spacing: 14) {
            chartBlock
            KLineDetailCard(vm: vm, cvm: cvm).padding(.horizontal, 16)
        }
        .task(id: key) { await cvm.liveLoop() }
        .task(id: key) {
            webFailed = false
            cvm.dark = (scheme == .dark)
            applyCfg()
            cvm.sync(trades: vm.trades, createdMs: vm.main?.pairCreatedAt)
            cvm.begin(chain: vm.chain, pair: vm.main?.pairAddress, token: vm.address)
            Task { await cvm.prefetchOthers() }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                if Task.isCancelled { break }
                applyCfg()
                await cvm.refreshLatest()
            }
        }
        .onChange(of: vm.trades.first?.id) { _, _ in cvm.sync(trades: vm.trades, createdMs: vm.main?.pairCreatedAt) }
        .onChange(of: scheme) { _, s in
            cvm.dark = (s == .dark)
            cvm.rebuild()
        }
    }

    private var mainList: [String] { mainSet.split(separator: ",").map { String($0) } }

    private func toggleMain(_ n: String) {
        var s = Set(mainList)
        if s.contains(n) { s.remove(n) } else { s.insert(n) }
        mainSet = ["MA", "EMA", "BOLL", "SAR", "SUPER"].filter { s.contains($0) }.joined(separator: ",")
    }

    private func applyCfg() {
        cvm.cfgMain = mainSet
        cvm.cfgSub = subInd
        cvm.cfgMcap = mcap
        var mult = 1.0
        if let m = vm.main, let p = m.price, p > 0, let mc = m.marketCap ?? m.fdv, mc > 0 { mult = mc / p }
        cvm.cfgMult = mult
        var marks: [[Double]] = []
        for (owner, an) in vm.analyses {
            let rank = vm.holders.first(where: { kNorm($0.owner) == kNorm(owner) })?.rank ?? 0
            for t in an.trades ?? [] {
                guard let u = t.usd, u > 0 else { continue }
                marks.append([t.t, t.side == "buy" ? 1 : -1, u, Double(rank)])
            }
        }
        marks.sort { $0[2] > $1[2] }
        cvm.extraMarks = Array(marks.prefix(16))
    }

    private var periodBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(TF.allCases) { t in
                        Button { cvm.setTF(t) } label: {
                            Text(t.title)
                                .font(.footnote.weight(cvm.tf == t ? .bold : .regular))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(cvm.tf == t ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                                .foregroundStyle(cvm.tf == t ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button { mcap.toggle() } label: {
                Text(mcap ? "市值 ⇄" : "价格 ⇄").font(.footnote.weight(.semibold))
            }
        }
    }

    // 高级图表（TradingView Lightweight Charts）渲染失败时自动退回系统自带的基础 K 线图，不再出现空白
    @ViewBuilder
    private var chartArea: some View {
        if webFailed {
            VStack(alignment: .leading, spacing: 6) {
                CandleChartView(candles: cvm.candles, selected: $fallbackSel)
                HStack {
                    Text("高级图表没能加载，已切换为基础图表").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("重试高级图表") { webFailed = false }.font(.caption2.weight(.semibold))
                }
            }
        } else {
            KLineWeb(payload: cvm.payload, seq: cvm.seq, clearToken: cvm.clearToken, onWeb: { t in cvm.onWeb(t) }, onFail: { webFailed = true })
                .frame(height: KHero.chartHeight)
        }
    }

    private var indicatorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(["MA", "EMA", "BOLL", "SAR", "SUPER"], id: \.self) { n in
                    Button { toggleMain(n) } label: {
                        Text(n).font(.footnote.weight(mainList.contains(n) ? .bold : .regular)).foregroundStyle(mainList.contains(n) ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Divider().frame(height: 14)
                ForEach(["VOL", "MACD", "KDJ", "RSI", "ROC"], id: \.self) { n in
                    Button { subInd = (subInd == n ? "" : n) } label: {
                        Text(n).font(.footnote.weight(subInd == n ? .bold : .regular)).foregroundStyle(subInd == n ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var chartBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            CompactHeader(vm: vm, embedded: true).padding(.horizontal, 14)
            periodBar.padding(.horizontal, 14)
            Text(cvm.statusText).font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 14)
            if cvm.payload.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if let n = cvm.note {
                        Text(n).font(.footnote).foregroundStyle(.secondary)
                        Button("重试") { cvm.retry() }.font(.footnote.weight(.semibold))
                    } else {
                        HStack(spacing: 8) { ProgressView(); Text("加载 K 线…").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: KHero.chartHeight / 2, alignment: .top)
            } else {
                chartArea
                indicatorBar.padding(.horizontal, 14)
                if cvm.histPaused {
                    Button("历史加载被限速打断，点这里继续补全") { cvm.resume() }.font(.footnote.weight(.semibold)).padding(.horizontal, 14)
                }
                Text("K 线 GeckoTerminal + 最新一根用 Dexscreener 实时价每 3 秒补齐 · 箭头 = 大额买卖，圆点 #n = 第 n 大持有人 · 点 K 线选中，再点取消 · 右上角 ⤢ 全屏图表 · TradingView Lightweight Charts™").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 10)
        .background(Color.card)
        .onChange(of: mainSet) { _, _ in applyCfg(); cvm.rebuild() }
        .onChange(of: subInd) { _, _ in applyCfg(); cvm.rebuild() }
        .onChange(of: mcap) { _, _ in applyCfg(); cvm.rebuild() }
        .onChange(of: vm.stamps.analyses) { _, _ in applyCfg(); cvm.rebuild() }
        .onReceive(NotificationCenter.default.publisher(for: .tstzmFullChart)) { _ in showFull = true }
        .fullScreenCover(isPresented: $showFull) { fullCover }
    }

    // 全屏图表：顶部价格条 + 周期栏 + 整屏 K 线 + 指标栏
    private var fullCover: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(vm.symbol).font(.headline)
                Text(Money.price(vm.main?.price)).font(.headline.monospacedDigit())
                Spacer()
                Button { showFull = false } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            periodBar.padding(.horizontal, 14)
            if cvm.payload.isEmpty {
                Spacer()
            } else {
                KLineWeb(payload: cvm.payload, seq: cvm.seq, clearToken: cvm.clearToken, onWeb: { t in cvm.onWeb(t) }, onFail: { webFailed = true })
            }
            indicatorBar.padding(.horizontal, 14).padding(.vertical, 8)
        }
        .background(Color.page.ignoresSafeArea())
    }
}

// MARK: - 单根 K 线的切片计算
struct KSlice {
    var c: Candle
    var inWin: [UTrade] = []
    var coverage = 0   // 0 不在成交明细覆盖范围，1 部分覆盖，2 完整覆盖
    var buy = 0.0
    var sell = 0.0
    var nb = 0
    var ns = 0
    var net: Double { buy - sell }
}

struct KWallet: Identifiable {
    var owner: String
    var buy: Double
    var sell: Double
    var nb: Int
    var ns: Int
    var precise: Bool
    var id: String { owner }
}

enum KCalc {
    static func slice(_ c: Candle, sec: Double, trades: [UTrade]) -> KSlice {
        var s = KSlice(c: c)
        let lo = c.t
        let hi = c.t + sec
        if let minT = trades.map({ $0.t }).min() {
            if minT <= lo { s.coverage = 2 } else if minT < hi { s.coverage = 1 } else { s.coverage = 0 }
        }
        for t in trades where t.t >= lo && t.t < hi {
            s.inWin.append(t)
            if t.buy { s.buy += t.usd; s.nb += 1 } else { s.sell += t.usd; s.ns += 1 }
        }
        return s
    }

    static func volRatio(_ cs: [Candle], _ idx: Int) -> Double? {
        if idx <= 0 || idx >= cs.count { return nil }
        let lo = max(0, idx - 20)
        let prev = cs[lo..<idx].map { $0.v }
        let avg = prev.reduce(0, +) / Double(prev.count)
        return avg > 0 ? cs[idx].v / avg : nil
    }

    static func gain(_ c: Candle) -> Double { c.o > 0 ? c.c / c.o - 1 : 0 }
}

struct KFacts: Encodable {
    var token: String
    var chain: String
    var candle: [String: String]
    var context: [String]
    var flow: [String]
    var wallets: [String]
    var pool: [String]
}

// MARK: - 分析面板：选中一根 K 线 → 价格 / 池子变化 / 交易 / 钱包 / AI；没选中 → 全量概览
struct KLineDetailCard: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject var cvm: KLineVM
    @AppStorage("aiAuto", store: Cfg.defaults) private var aiAuto: Bool = true

    var body: some View {
        VStack(spacing: 14) {
            if let t = cvm.selT {
                if let idx = cvm.candles.firstIndex(where: { $0.t == t }) {
                    candleBody(idx)
                } else {
                    Card { Text("选中的 K 线不在已加载范围内").font(.footnote).foregroundStyle(.secondary) }
                }
            } else {
                overviewBody
            }
        }
        .task(id: cvm.selT) { await autoWork() }
    }

    // 光标在一根 K 线上停约 1 秒后：本根成交额最大的 3 个地址自动拆解；AI 为自动时同时请求 AI
    private func autoWork() async {
        guard let t = cvm.selT else { return }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        if Task.isCancelled || cvm.selT != t { return }
        guard let idx = cvm.candles.firstIndex(where: { $0.t == t }) else { return }
        let s = KCalc.slice(cvm.candles[idx], sec: cvm.tf.sec, trades: vm.trades)
        let known = Set(vm.analyses.keys.map { kNorm($0) })
        for a in FlowCalc.addrs(s.inWin).prefix(3) where !known.contains(kNorm(a.who)) {
            let who = a.who
            Task { await cvm.analyze(owner: who) }
        }
        if aiAuto { await runCandleAI(t, fresh: false) }
    }

    // MARK: 选中一根
    @ViewBuilder
    private func candleBody(_ idx: Int) -> some View {
        let c = cvm.candles[idx]
        let s = KCalc.slice(c, sec: cvm.tf.sec, trades: vm.trades)
        priceCard(c, idx)
        poolCard(c)
        tradeCard(s)
        walletCard(s)
        aiModeRow
        aiCard(c)
    }

    private func priceCard(_ c: Candle, _ idx: Int) -> some View {
        let sec = cvm.tf.sec
        let chg = c.o > 0 ? (c.c / c.o - 1) * 100 : 0
        let amp = c.l > 0 ? (c.h / c.l - 1) * 100 : 0
        let rng = c.h - c.l
        let upper = rng > 0 ? (c.h - max(c.o, c.c)) / rng * 100 : 0
        let lower = rng > 0 ? (min(c.o, c.c) - c.l) / rng * 100 : 0
        let ratio = KCalc.volRatio(cvm.candles, idx)
        let col: Color = c.up ? Color.green : Color.red
        let span = TZ.short(c.date) + " ~ " + TZ.short(Date(timeIntervalSince1970: c.t + sec)) + "（" + cvm.tf.title + "）"
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("选中的这根 K 线", systemImage: "scope").font(.headline)
                    Spacer()
                    Button("回到全量") { cvm.clearSelection() }.font(.caption.weight(.semibold))
                }
                Text(span).font(.caption).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    StatTile(title: "开盘 → 收盘", value: Money.price(c.o) + " → " + Money.price(c.c), tint: col)
                    StatTile(title: "涨跌 / 振幅", value: String(format: "%+.1f%% / %.1f%%", chg, amp), tint: col)
                    StatTile(title: "最高 / 最低", value: Money.price(c.h) + " / " + Money.price(c.l))
                    StatTile(title: "K 线成交额", value: Fmt2.usd(c.v))
                }
                if let r = ratio {
                    let tag = r >= 3 ? "，明显放量" : (r <= 0.3 ? "，明显缩量" : "")
                    Text(String(format: "成交额是前 20 根均值的 %.1f 倍", r) + tag).font(.footnote)
                }
                if upper >= 50 { Text(String(format: "长上影线（占 %.0f%%）：冲高后被砸回，上方有抛压", upper)).font(.footnote) }
                if lower >= 50 { Text(String(format: "长下影线（占 %.0f%%）：探底后被拉回，下方有承接", lower)).font(.footnote) }
            }
        }
    }

    private func poolRows(_ c: Candle) -> [String] {
        let sec = cvm.tf.sec
        var rows: [String] = []
        if let cr = vm.main?.pairCreatedAt {
            let created = cr / 1000
            if created >= c.t && created < c.t + sec { rows.append("本根包含最深池子的创建（建池时刻 " + TZ.format(ts: created) + "）") }
            else if created < c.t { rows.append("距最深池子创建 " + Fmt2.dur(c.t - created)) }
            else { rows.append("早于最深池子创建时间，数据源可能把旧池合并进来了") }
        }
        let liq = vm.main?.liq ?? 0
        rows.append("当时流动性：公开接口不提供历史流动性，未知（现在 " + Fmt2.usd(liq) + "）")
        if liq > 0 { rows.append(String(format: "本根成交额相当于现流动性的 %.0f%%（按现在的流动性估算，只作量级参考）", c.v / liq * 100)) }
        for p in vm.pairs {
            if p.pairAddress == vm.main?.pairAddress { continue }
            if let cr = p.pairCreatedAt {
                let sc = cr / 1000
                if sc >= c.t && sc < c.t + sec { rows.append("本根新增池子：" + (p.dexId ?? "?") + " · " + (p.quoteToken?.symbol ?? "?") + "，现流动性 " + Fmt2.usd(p.liq)) }
            }
        }
        return rows
    }

    private func poolCard(_ c: Candle) -> some View {
        let rows = poolRows(c)
        return Card {
            VStack(alignment: .leading, spacing: 6) {
                Label("池子变化", systemImage: "drop.fill").font(.headline)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, r in Text("· " + r).font(.footnote) }
            }
        }
    }

    private func tradeCard(_ s: KSlice) -> some View {
        let n = vm.trades.count
        let minT = vm.trades.map { $0.t }.min() ?? s.c.t
        var cover = "成交明细覆盖整根（最近 \(n) 笔成交）"
        if s.coverage == 1 { cover = "成交明细只覆盖本根后半段（最早一笔在 " + TZ.short(Date(timeIntervalSince1970: minT)) + "），下面数字偏小" }
        if s.coverage == 0 { cover = "本根不在最近 \(n) 笔成交的覆盖范围内，买卖明细未知（GeckoTerminal 只提供最近约 300 笔）" }
        let big = s.inWin.max(by: { $0.usd < $1.usd })
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("交易分析（本根内的成交）", systemImage: "arrow.left.arrow.right").font(.headline)
                Text(cover).font(.caption2).foregroundStyle(.secondary)
                if s.coverage > 0 {
                    if s.inWin.isEmpty {
                        Text("覆盖范围内本根没有成交记录").font(.footnote)
                    } else {
                        HStack {
                            Text("买 " + Fmt2.usd(s.buy) + "·\(s.nb)").foregroundStyle(Color.green)
                            Text("卖 " + Fmt2.usd(s.sell) + "·\(s.ns)").foregroundStyle(Color.red)
                            Spacer()
                            Text("净 " + Fmt2.usd(s.net, signed: true)).foregroundStyle(s.net >= 0 ? Color.green : Color.red)
                        }
                        .font(.subheadline.monospacedDigit())
                        if s.buy + s.sell > 0 { Text(String(format: "买盘占本根成交额 %.0f%%", s.buy / (s.buy + s.sell) * 100)).font(.footnote) }
                        if let b = big { Text("最大一笔：" + (b.buy ? "买入 " : "卖出 ") + Fmt2.usd(b.usd) + " · " + Addr.short(b.who)).font(.footnote) }
                        Text(KDeep.sliceExtra(s.inWin)).font(.footnote)
                    }
                }
            }
        }
    }

    private func ownersMap() -> [String: UHolderAnalysis] {
        var m: [String: UHolderAnalysis] = [:]
        for (k, v) in vm.analyses { m[kNorm(k)] = v }
        for (k, v) in cvm.extra { m[k] = v }
        return m
    }

    private func walletHits(_ s: KSlice, _ owners: [String: UHolderAnalysis]) -> [KWallet] {
        let lo = s.c.t
        let hi = s.c.t + cvm.tf.sec
        var map: [String: KWallet] = [:]
        for a in FlowCalc.addrs(s.inWin) {
            map[kNorm(a.who)] = KWallet(owner: a.who, buy: a.buy, sell: a.sell, nb: a.nb, ns: a.ns, precise: false)
        }
        for (k, an) in owners {
            var b = 0.0
            var sl = 0.0
            var nb = 0
            var ns = 0
            for t in an.trades ?? [] where t.t >= lo && t.t < hi {
                let u = t.usd ?? 0
                if t.side == "buy" { b += u; nb += 1 } else { sl += u; ns += 1 }
            }
            if nb + ns > 0 { map[k] = KWallet(owner: an.owner ?? k, buy: b, sell: sl, nb: nb, ns: ns, precise: true) }
        }
        return map.values.sorted { ($0.buy + $0.sell) > ($1.buy + $1.sell) }
    }

    private func walletCard(_ s: KSlice) -> some View {
        let owners = ownersMap()
        let hits = walletHits(s, owners)
        let empty = s.coverage == 0 ? "本根不在成交明细覆盖范围内，也没有已拆解大户在本根成交，出手的钱包未知" : "覆盖范围内没有查到本根出手的地址"
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("钱包分析（本根内出手的地址）", systemImage: "person.3.fill").font(.headline)
                if hits.isEmpty {
                    Text(empty).font(.footnote).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(hits.prefix(8))) { w in walletRow(w, owners) }
                }
                Text("成交地址是交易发起方，可能是机器人或聚合器；拆解 = 该地址在这个币上的成本、盈亏、入场时点（同上方大户拆解口径）。本根成交额最大的 3 个地址会自动拆解，其余点按钮拆。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func walletRow(_ w: KWallet, _ owners: [String: UHolderAnalysis]) -> some View {
        let k = kNorm(w.owner)
        let an = owners[k]
        let rank = vm.holders.first(where: { kNorm($0.owner) == k })?.rank
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let r = rank { Pill(text: "大户 #\(r)", color: Color.orange) }
                Text(Addr.short(w.owner)).font(.caption.monospaced())
                if vm.chain == .solana, let u = Scan.account(w.owner) { Link(destination: u) { Image(systemName: "arrow.up.right.square") }.font(.caption) }
                Spacer()
                Text("买 " + Fmt2.usd(w.buy) + "·\(w.nb)").font(.caption.monospacedDigit()).foregroundStyle(Color.green)
                Text("卖 " + Fmt2.usd(w.sell) + "·\(w.ns)").font(.caption.monospacedDigit()).foregroundStyle(Color.red)
            }
            if let p = an?.position {
                HStack(spacing: 8) {
                    if let e = p.entry { Pill(text: e, color: (p.delayMin ?? 99) <= 10 ? Color.orange : Color.gray) }
                    if let st = p.state { Text(st).font(.caption2).foregroundStyle(.secondary) }
                    Spacer()
                    if let roi = p.roi { Text("综合 " + Fmt2.pct(roi)).font(.caption.weight(.semibold)).foregroundStyle(roi >= 0 ? Color.green : Color.red) }
                }
                Text("累计投入 " + Fmt2.usd(p.boughtUsd) + " · 已兑现 " + Fmt2.usd(p.realizedUsd, signed: true) + " · 浮动 " + Fmt2.usd(p.unrealizedUsd, signed: true)).font(.caption2).foregroundStyle(.secondary)
            } else if cvm.extraLoading.contains(k) {
                Text("拆解中…").font(.caption2).foregroundStyle(.secondary)
            } else if let e = cvm.extraErr[k] {
                Text("拆解失败：" + e).font(.caption2).foregroundStyle(Color.orange)
            } else if let a = an {
                Text((a.insights ?? []).first?.text ?? "窗口内没有这个地址在该币上的买卖记录，成本无法确认").font(.caption2).foregroundStyle(.secondary)
            } else {
                Button("拆解这个地址") { Task { await cvm.analyze(owner: w.owner) } }.font(.caption.weight(.semibold))
            }
            Divider()
        }
    }

    private var aiModeRow: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Picker("AI 触发", selection: $aiAuto) {
                    Text("AI 自动").tag(true)
                    Text("AI 手动").tag(false)
                }
                .pickerStyle(.segmented)
                Text(aiAuto ? "自动：光标停在一根 K 线约 1 秒后请求 AI，结果按 K 线缓存；全 App 的 AI 都跟这个开关。" : "手动：只在点「让 AI 解读这份数据」时才请求，不自动消耗额度；全 App 的 AI 都跟这个开关。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func aiCard(_ c: Candle) -> some View {
        let k = cvm.aiKey(c.t)
        return AIResultCard(title: "这根 K 线的 AI 解读", result: cvm.candleAI[k], loading: cvm.aiLoading.contains(k), message: cvm.candleAIMsg[k], onRun: { Task { await runCandleAI(c.t, fresh: true) } })
    }

    private func makeFacts(_ t: Double) -> KFacts? {
        guard let idx = cvm.candles.firstIndex(where: { $0.t == t }) else { return nil }
        let c = cvm.candles[idx]
        let sec = cvm.tf.sec
        let s = KCalc.slice(c, sec: sec, trades: vm.trades)
        let owners = ownersMap()
        let hits = walletHits(s, owners)
        var cd: [String: String] = [:]
        cd["周期"] = cvm.tf.title
        cd["时间"] = TZ.format(ts: c.t)
        cd["开盘美元"] = String(format: "%.6g", c.o)
        cd["最高美元"] = String(format: "%.6g", c.h)
        cd["最低美元"] = String(format: "%.6g", c.l)
        cd["收盘美元"] = String(format: "%.6g", c.c)
        cd["涨跌"] = String(format: "%+.1f%%", KCalc.gain(c) * 100)
        cd["成交额美元"] = String(format: "%.0f", c.v)
        if let r = KCalc.volRatio(cvm.candles, idx) { cd["相对前20根均量"] = String(format: "%.1f倍", r) }
        var ctx: [String] = []
        if idx > 0 {
            let p = cvm.candles[idx - 1]
            ctx.append(String(format: "前一根：涨跌%+.1f%%，成交额", KCalc.gain(p) * 100) + Fmt2.usd(p.v))
        }
        if idx + 1 < cvm.candles.count {
            let n = cvm.candles[idx + 1]
            ctx.append(String(format: "后一根：涨跌%+.1f%%，成交额", KCalc.gain(n) * 100) + Fmt2.usd(n.v))
        }
        if let hi = cvm.candles.max(by: { $0.h < $1.h }) { ctx.append("已加载范围内最高价 " + String(format: "%.6g", hi.h) + " 美元，出现在 " + TZ.short(hi.date)) }
        ctx.append("已加载 \(cvm.candles.count) 根" + cvm.tf.title + "K线")
        var flow: [String] = []
        if s.coverage == 0 { flow.append("本根不在成交明细覆盖范围内，买卖明细未知") }
        else {
            flow.append("买 " + Fmt2.usd(s.buy) + "(\(s.nb)笔) 卖 " + Fmt2.usd(s.sell) + "(\(s.ns)笔)" + (s.coverage == 1 ? "（只覆盖本根后半段）" : ""))
        }
        var ws: [String] = []
        for w in hits.prefix(5) {
            var line = Addr.short(w.owner) + " 买" + Fmt2.usd(w.buy) + " 卖" + Fmt2.usd(w.sell)
            if let p = owners[kNorm(w.owner)]?.position {
                line += "；入场：" + (p.entry ?? "未知") + "；" + (p.state ?? "")
                if let roi = p.roi { line += "；综合回报" + Fmt2.pct(roi) }
            }
            if let r = vm.holders.first(where: { kNorm($0.owner) == kNorm(w.owner) })?.rank { line += "；榜单第\(r)大" }
            ws.append(line)
        }
        return KFacts(token: vm.symbol, chain: vm.chain.title, candle: cd, context: ctx, flow: flow, wallets: ws, pool: poolRows(c))
    }

    private func runCandleAI(_ t: Double, fresh: Bool) async {
        let k = cvm.aiKey(t)
        if !fresh && cvm.candleAI[k] != nil { return }
        guard let facts = makeFacts(t) else { return }
        cvm.aiLoading.insert(k)
        cvm.candleAIMsg[k] = nil
        defer { cvm.aiLoading.remove(k) }
        do {
            let r: AIResult = try await Engine.post("/e/v2/ai", AIPayload(kind: "单根K线复盘（这一根K线内的价格、成交、出手钱包、池子变化）", facts: facts, fresh: fresh ? true : nil))
            if let m = aiMessage(r) { cvm.candleAIMsg[k] = m; cvm.candleAI[k] = nil } else { cvm.candleAI[k] = r }
        } catch {
            cvm.candleAIMsg[k] = "AI 暂时不可用（" + Net.message(error) + "），规则分析不受影响"
        }
    }

    // MARK: 没选中：全量概览
    private var overviewBody: some View {
        let cs = cvm.candles
        return VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("全量概览（没有选中 K 线）", systemImage: "chart.bar.doc.horizontal").font(.headline)
                    if let first = cs.first, let last = cs.last, let hi = cs.max(by: { $0.h < $1.h }), let lo = cs.min(by: { $0.l < $1.l }) {
                        overviewRows(cs, first, last, hi, lo)
                    } else {
                        Text("K 线加载中…").font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("长按（或点一下）图上某根 K 线，这里切换成那一根的价格、池子变化、成交、钱包拆解与 AI 解读；光标离开后自动回到这个全量视图。").font(.caption2).foregroundStyle(.secondary)
                }
            }
            aiModeRow
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.caption).foregroundStyle(.secondary).frame(width: 66, alignment: .leading)
            Text(v).font(.footnote)
            Spacer(minLength: 0)
        }
    }

    private func overviewRows(_ cs: [Candle], _ first: Candle, _ last: Candle, _ hi: Candle, _ lo: Candle) -> some View {
        let total = cs.reduce(0.0) { $0 + $1.v }
        let run = first.o > 0 ? (last.c / first.o - 1) * 100 : 0
        let dd = hi.h > 0 ? (last.c / hi.h - 1) * 100 : 0
        let topVol = Array(cs.sorted { $0.v > $1.v }.prefix(3))
        let up = cs.max(by: { KCalc.gain($0) < KCalc.gain($1) })
        let down = cs.min(by: { KCalc.gain($0) < KCalc.gain($1) })
        let a = vm.agg
        let range = TZ.short(first.date) + " ~ " + TZ.short(last.date) + " · \(cs.count) 根（" + cvm.tf.title + "）"
        let path = Money.price(first.o) + " → " + Money.price(last.c) + String(format: "（%+.1f%%）", run)
        let hl = "最高 " + Money.price(hi.h) + "（" + TZ.short(hi.date) + "）· 最低 " + Money.price(lo.l) + "（" + TZ.short(lo.date) + "）"
        let tv = topVol.map { TZ.short($0.date) + " " + Fmt2.usd($0.v) }.joined(separator: "；")
        let now = Date().timeIntervalSince1970
        let w24 = FlowCalc.windows(vm.trades, now: now).first(where: { $0.id == "24h" })
        return VStack(alignment: .leading, spacing: 6) {
            row("范围", range)
            row("全程", path)
            row("高低", hl)
            row("距最高", String(format: "%+.1f%%", dd))
            row("累计成交", Fmt2.usd(total) + "（已加载 K 线汇总）")
            row("成交最大", tv)
            if let u = up { row("最大单根涨", String(format: "%+.1f%% · ", KCalc.gain(u) * 100) + TZ.short(u.date)) }
            if let d = down { row("最大单根跌", String(format: "%+.1f%% · ", KCalc.gain(d) * 100) + TZ.short(d.date)) }
            if let w = w24, w.total > 0 { row("资金流", "最近成交窗口 买 " + Fmt2.usd(w.buy) + " 卖 " + Fmt2.usd(w.sell) + " 净 " + Fmt2.usd(w.net, signed: true)) }
            if a.withPos >= 1 { row("大户", "已拆解 \(a.withPos) 个，账面盈利 \(a.profit) 个，合计盈亏 " + Fmt2.usd(a.pnl, signed: true) + "，持仓价值 " + Fmt2.usd(a.valueNow)) }
            if let c = vm.conc, let t10 = c.top10 { row("集中度", String(format: "前 10 大持有 %.1f%%", t10) + (c.wallets10.map { String(format: "，其中普通钱包 %.1f%%", $0) } ?? "")) }
        }
    }
}

// MARK: - AI 区（放到页面最底部；触发方式在这里和 K 线分析面板里都能切）
struct AIFoldCard: View {
    @ObservedObject var vm: UTokenVM
    @AppStorage("aiAuto", store: Cfg.defaults) private var aiAuto: Bool = true

    var body: some View {
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Label("AI 触发方式", systemImage: "sparkles").font(.headline)
                    Picker("AI 触发", selection: $aiAuto) {
                        Text("自动").tag(true)
                        Text("手动").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Text(aiAuto ? "自动：查一个币后自动出 AI 研判与叙事。" : "手动：不自动请求，点下面卡片里的按钮才请求，省 Groq 额度。").font(.caption2).foregroundStyle(.secondary)
                }
            }
            NarrativeCard(chain: vm.chain, address: vm.address, main: vm.main)
        }
    }
}
