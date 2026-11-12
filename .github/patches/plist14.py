# 补丁清单（第十四批）：头像（代币/钱包）、搜索栏与记录条、周线月线、图表自愈、盯盘看板、清理寒霜字样
def register(rep, cut):
    # ---------- 查询记录带头像地址 ----------
    P = 'ios/App/Prefs.swift'
    rep('h14_hist_a', P, r'''    var at: Date
}

enum QueryHistory {
''', r'''    var at: Date
    var logo: String? = nil
}

enum QueryHistory {
''')
    rep('h14_hist_b', P, r'''    static func add(kind: String, chain: String, address: String, title: String) {
''', r'''    static func add(kind: String, chain: String, address: String, title: String, logo: String? = nil) {
''')
    rep('h14_hist_c', P, r'''        list.insert(HistoryItem(kind: kind, chain: chain, address: address, title: title, at: Date()), at: 0)
''', r'''        let keepLogo = logo ?? items.first(where: { $0.kind == kind && $0.address.lowercased() == address.lowercased() })?.logo
        list.insert(HistoryItem(kind: kind, chain: chain, address: address, title: title, at: Date(), logo: keepLogo), at: 0)
''')

    # ---------- 行情模型：记录头像、周期加周线月线 ----------
    M = 'ios/App/UnifiedTokenModel.swift'
    rep('h14_hist_d', M, r'''            QueryHistory.add(kind: "token", chain: c.rawValue, address: addr, title: ps[0].baseToken?.symbol ?? Addr.short(addr))
''', r'''            QueryHistory.add(kind: "token", chain: c.rawValue, address: addr, title: ps[0].baseToken?.symbol ?? Addr.short(addr), logo: ps[0].info?.imageUrl)
''')
    rep('h14_tf_a', M, r'''    case m1, m5, m15, h1, h4, d1
''', r'''    case m1, m5, m15, h1, h4, d1, w1, mo1
''')
    rep('h14_tf_b', M, r'''        case .d1: return "日"
''', r'''        case .d1: return "日"
        case .w1: return "周"
        case .mo1: return "月"
''')
    rep('h14_tf_c', M, r'''        case .d1: return "day"
''', r'''        case .d1, .w1, .mo1: return "day"
''')
    rep('h14_tf_d', M, r'''        case .m1, .h1, .d1: return 1
''', r'''        case .m1, .h1, .d1, .w1, .mo1: return 1
''')

    # ---------- K 线：周月线汇总、图表自愈、周期栏 ----------
    C = 'ios/App/ProChart.swift'
    rep('h14_sec', C, r'''        case .d1: return 86400
''', r'''        case .d1: return 86400
        case .w1: return 604800
        case .mo1: return 2592000
''')
    rep('h14_base', C, r'''    private var resumeBefore: Double?
''', r'''    private var resumeBefore: Double?
    private var base: [Candle] = []   // 拉到的原始 K 线（周线月线用日线汇总）
''')
    rep('h14_setc', C, r'''    private func merged(_ base: [Candle], _ over: [Candle]) -> [Candle] {
''', r'''    private func setCandles(_ raw: [Candle]) {
        base = raw
        candles = tf.rolled(raw)
        KLineShared.shared.update(chain: chain, pair: pair, tf: tf, candles: candles)
    }

    private func merged(_ base: [Candle], _ over: [Candle]) -> [Candle] {
''')
    rep('h14_reload', C, r'''        candles = KLineCache.load(chain.rawValue + ":" + pair + ":" + tf.rawValue)
''', r'''        setCandles(KLineCache.load(chain.rawValue + ":" + pair + ":" + tf.rawValue))
''')
    rep('h14_hist', C, r'''                candles = merged(page, candles)
''', r'''                setCandles(merged(page, base))
''')
    rep('h14_latest', C, r'''            candles = merged(candles, page)
''', r'''            setCandles(merged(base, page))
''')
    rep('h14_more', C, r'''        let b = (candles.first?.t ?? 0) - 1
''', r'''        let b = (base.first?.t ?? 0) - 1
''')
    rep('h14_bk1', C, r'''                let b = (t.t / sec).rounded(.down) * sec
''', r'''                let b = kBucket(t.t, tf)
''')
    rep('h14_bk2', C, r'''            let b = (m[0] / sec).rounded(.down) * sec
''', r'''            let b = kBucket(m[0], tf)
''')
    rep('h14_bk3', C, r'''            let b = ((cm / 1000) / sec).rounded(.down) * sec
''', r'''            let b = kBucket(cm / 1000, tf)
''')
    rep('h14_cache', C, r'''        KLineCache.save(key: chain.rawValue + ":" + pair + ":" + tf.rawValue, candles)
''', r'''        KLineCache.save(key: chain.rawValue + ":" + pair + ":" + tf.rawValue, base)
''')
    rep('h14_state', C, r'''    @AppStorage("kMcap", store: Cfg.defaults) private var mcap = false
''', r'''    @AppStorage("kMcap", store: Cfg.defaults) private var mcap = false
    @State private var webFailed = false
    @State private var fallbackSel: Date?
''')
    rep('h14_taskreset', C, r'''            cvm.dark = (scheme == .dark)
            applyCfg()
''', r'''            webFailed = false
            cvm.dark = (scheme == .dark)
            applyCfg()
''')
    rep('h14_webuse', C, r'''                    KLineWeb(payload: cvm.payload, seq: cvm.seq, clearToken: cvm.clearToken) { t in cvm.onWeb(t) }
                        .frame(height: 460)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
''', r'''                    chartArea
''')
    cut('h14_period', C, r'''    private var periodBar: some View {
''', r'''    private var indicatorBar: some View {
''', r'''    private var periodBar: some View {
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
                .frame(height: 460)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

''')
    cut('h14_web', C, r'''struct KLineWeb: UIViewRepresentable {
''', r'''// MARK: - K 线状态：''', r'''struct KLineWeb: UIViewRepresentable {
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

''')

    # ---------- 图表页：脚本错误可见、渲染成功回报、库缺失回报 ----------
    W = 'ios/App/Web/chart.html'
    rep('h14_web_a', W, r'''  var post=function(o){try{window.webkit.messageHandlers.chart.postMessage(o);}catch(e){}};
''', r'''  var post=function(o){try{window.webkit.messageHandlers.chart.postMessage(o);}catch(e){}};
  window.onerror=function(m,s,l){var t='图表脚本错误：'+m+' @'+l;try{document.getElementById('lg').textContent=t;}catch(e){}post({type:'err',m:t});};
''')
    rep('h14_web_b', W, r'''    if(d.key!==S.key){S.key=d.key;S.mode='init';}
    render();
  };
''', r'''    if(d.key!==S.key){S.key=d.key;S.mode='init';}
    try{render();post({type:'ok',n:S.C.length});}catch(e){var t='图表渲染错误：'+(e&&e.message?e.message:e);lg.textContent=t;post({type:'err',m:t});}
  };
''')
    rep('h14_web_c', W, r'''lg.textContent='图表库未打包（lwc.js 缺失）';return;}''', r'''lg.textContent='图表库未打包（lwc.js 缺失）';post({type:'err',m:'lwc'});return;}''')

    # ---------- 代币页：一行搜索栏 + 头像记录条 ----------
    U = 'ios/App/UnifiedToken.swift'
    cut('h14_input', U, r'''    private var inputCard: some View {
''', r'''    private var startCard: some View {
''', r'''    private var inputCard: some View {
        AvSearchBar(vm: vm, hist: $hist)
    }

''')
    cut('h14_start', U, r'''            if !hist.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("最近查询")''', r'''        .onAppear { hist = QueryHistory.items.filter { $0.kind == "token" } }
''', r'''            if !hist.isEmpty {
                Card {
                    AvRecentStrip(items: Array(hist.prefix(12)), showTitle: true) { h in vm.start(h.address) }
                }
            }
        }
''')

    # ---------- 仪表盘：原数据源诊断改名，新看板在 MarketBoard.swift ----------
    D = 'ios/App/Dashboard.swift'
    rep('h14_diag_a', D, r'''struct DashboardView: View {
''', r'''struct DiagnosticsView: View {
''')
    rep('h14_diag_b', D, r'''            .navigationTitle("仪表盘")
''', r'''            .navigationTitle("系统诊断")
''')

    # ---------- 清理寒霜字样（注释） ----------
    A = 'ios/App/TSTZMApp.swift'
    rep('h14_frost_c1', A, '// 全局路由：深链可切换标签页，并把兑换码交给寒霜页\n', '// 全局路由：深链可切换标签页\n')
    rep('h14_frost_c2', A, '// tstzm://setup?token=xxxx 一键写入令牌；tstzm://frost?code=XXXX 跳到寒霜页并带上兑换码\n', '// tstzm://setup?token=xxxx 一键写入令牌\n')

    # ---------- 钱包页：头像 + 紧凑查询记录 ----------
    X = 'ios/App/CexView.swift'
    rep('h14_ad_state', X, r'''    @State private var path: [AdHocTarget] = []
''', r'''    @State private var path: [AdHocTarget] = []
    @State private var showAllHist = false
''')
    cut('h14_ad_hist', X, r'''                Section {
                    if hist.isEmpty { Text("还没有查询记录").foregroundStyle(.secondary) }
''', r'''            .navigationTitle("查询地址")
''', r'''                if !hist.isEmpty {
                    Section {
                        AvRecentStrip(items: Array(hist.prefix(12)), showTitle: false) { h in open(h.address) }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    } header: {
                        HStack {
                            Text("最近查询")
                            Spacer()
                            Button("全部记录") { showAllHist = true }.font(.caption)
                        }
                    }
                }
            }
            .sheet(isPresented: $showAllHist) { AvHistorySheet(kind: "wallet") { h in open(h.address) } }
''')
    rep('h14_ad_row', X, r'''                                HStack {
                                    Text(w.label.isEmpty ? "钱包" : w.label).foregroundStyle(Color.primary)
''', r'''                                HStack(spacing: 10) {
                                    AvWalletIcon(address: w.address, chain: avWalletChain(w.address, w.chains), size: 30)
                                    Text(w.label.isEmpty ? "钱包" : w.label).foregroundStyle(Color.primary)
''')
    V = 'ios/App/WalletsView.swift'
    rep('h14_wv_row', V, r'''        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(w.label.isEmpty ? "钱包" : w.label).font(.headline)
''', r'''        return HStack(spacing: 12) {
            AvWalletIcon(address: w.address, chain: avWalletChain(w.address, w.chains), size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(w.label.isEmpty ? "钱包" : w.label).font(.headline)
''')
    rep('h14_wv_head', V, r'''                HStack {
                    Text(Addr.short(wallet.address)).font(.subheadline.monospaced())
''', r'''                HStack(spacing: 10) {
                    AvWalletIcon(address: wallet.address, chain: avWalletChain(wallet.address, wallet.chains), size: 36)
                    Text(Addr.short(wallet.address)).font(.subheadline.monospaced())
''')
