# 补丁清单（第十七批）：Logo 品牌图/转圈/下拉刷新、交易所风格头部 + 全屏图表、K 线价格轴修复 + 实时尾巴 + 秒切周期、限流网关、持有人兜底、收藏、情报页
def register(rep, cut):
    # ---------- 品牌图：令牌页等处统一用应用 Logo ----------
    C = 'ios/App/Components.swift'
    cut('h17_brand', C, 'struct BrandMark: View {', 'enum Verdict {', r'''struct BrandMark: View {
    var size: CGFloat = 44
    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
    }
}

''')

    # ---------- 收藏监控随 App 启动 ----------
    A = 'ios/App/TSTZMApp.swift'
    rep('h17_monitor', A, '        .task { await FX.refresh() }\n', '        .task { await FX.refresh() }\n        .task { WatchMonitor.shared.start() }\n')

    # ---------- 行情请求：限流网关 + 429 退避 + 查空兜底；持有人兜底 ----------
    M = 'ios/App/UnifiedTokenModel.swift'
    cut('h17_json', M, '    static func json(_ urlStr: String) async throws -> Any {', '    static func num(_ x: Any?) -> Double? {', r'''    static func json(_ urlStr: String, ttl: Double = 0) async throws -> Any {
        guard let url = URL(string: urlStr) else { throw APIError.network("地址无效") }
        let host = url.host ?? ""
        if ttl > 0, let d = await DataGate.shared.cached(urlStr, ttl: ttl), let o = try? JSONSerialization.jsonObject(with: d) { return o }
        var attempt = 0
        while true {
            await DataGate.shared.wait(host)
            var req = URLRequest(url: url, timeoutInterval: 25)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let r: (Data, URLResponse)
            do { r = try await Net.fetch(req) } catch { throw APIError.network(Net.message(error)) }
            let resp = r.1 as? HTTPURLResponse
            let code = resp?.statusCode ?? 0
            if code == 429 {
                let ra = Double(resp?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 8
                await DataGate.shared.penalize(host, min(max(ra, 3), 20))
                attempt += 1
                if attempt >= 2 { throw APIError.network("行情接口限速（429），稍后自动重试") }
                continue
            }
            if !(200..<300).contains(code) { throw APIError.http(code, String((String(data: r.0, encoding: .utf8) ?? "").prefix(80))) }
            guard let o = try? JSONSerialization.jsonObject(with: r.0) else { throw APIError.decode("行情数据不是 JSON") }
            if ttl > 0 { await DataGate.shared.put(urlStr, r.0) }
            return o
        }
    }

''')
    rep('h17_pairs', M, '        return all.filter { ($0.baseToken?.address ?? "").lowercased() == key }.sorted { $0.liq > $1.liq }\n', r'''        let hit = all.filter { ($0.baseToken?.address ?? "").lowercased() == key }.sorted { $0.liq > $1.liq }
        if !hit.isEmpty { return hit }
        return await legacyPairs(chain, addr)
''')
    cut('h17_holders', M, r'''let r: EvmTokenResp = try await Engine.get("/e/evm/token", ["chain": chain.rawValue, "token": address, "pages": String(holderPages)])''', '            } else {\n                holderNote = "该链暂不支持持有人榜单"', r'''let r: EvmTokenResp? = try? await Engine.get("/e/v2/holders2", ["chain": chain.rawValue, "token": address, "pages": String(max(holderPages, 12))])
                guard id == runID else { return }
                var got = false
                if let r = r, r.error == nil, !(r.holders ?? []).isEmpty {
                    holders = (r.holders ?? []).enumerated().map { UHolder(rank: $0.element.rank ?? ($0.offset + 1), owner: $0.element.owner, kind: $0.element.kind ?? "unknown", pct: $0.element.pct) }
                    conc = r.concentration.map { Conc(top1: $0.top1, top5: $0.top5, top10: $0.top10, top20: $0.top20, wallets10: $0.wallets10, nonWallet: $0.nonWallet, listed: $0.listed) }
                    holderFindings = (r.findings ?? []).compactMap { f in
                        guard let t = f.text else { return nil }
                        return Finding(level: f.level ?? "info", text: t, basis: f.basis)
                    }
                    holderComplete = r.complete == true
                    holderNote = nil
                    got = true
                }
                if !got {
                    if let fb = await HolderFallback.load(chain: chain, address: address, pair: main?.pairAddress) {
                        guard id == runID else { return }
                        holders = fb.holders
                        conc = fb.conc
                        holderFindings = fb.findings
                        holderComplete = false
                        holderNote = fb.note
                    } else {
                        holderNote = (r?.findings ?? []).first?.text ?? "云端与备用数据源都没有返回持有人，稍后下拉刷新重试"
                    }
                }
''')

    # ---------- 代币页：整页布局（头部 + K 线通栏）、Logo 下拉刷新、收藏条、情报页 ----------
    U = 'ios/App/UnifiedToken.swift'
    rep('h17_tabnames', U, '    private var tabNames: [String] { ["总览", "成交", "筹码", "风险", "叙事", "更多"] }', '    private var tabNames: [String] { ["总览", "成交", "筹码", "风险", "叙事", "情报", "更多"] }')
    rep('h17_tabbody', U, '        default:\n            PromoCard(vm: vm)\n', '        case 5:\n            IntelTab(vm: vm)\n        default:\n            PromoCard(vm: vm)\n')
    cut('h17_body', U, '                    inputCard\n', '            .navigationTitle(navTitle)\n', r'''                    VStack(spacing: 10) {
                        inputCard
                        FavBar(vm: vm)
                    }
                    .padding(.horizontal, 16)
                    if vm.loading { Card { HStack(spacing: 10) { ProgressView(); Text("正在识别链并读取行情…").foregroundStyle(.secondary) } }.padding(.horizontal, 16) }
                    if let e = vm.error { ErrorCard(text: e) { vm.start(vm.input) }.padding(.horizontal, 16) }
                    if vm.main != nil { content }
                    else if !vm.loading && vm.error == nil { startCard.padding(.horizontal, 16) }
                }
                .padding(.vertical, 12)
                .background(LogoRefreshHook { vm.refreshAll(); try? await Task.sleep(nanoseconds: 800_000_000) })
            }
            .background(Color.page)
''')
    rep('h17_content', U, '            KLineCard(vm: vm)\n            FreshnessRow(vm: vm)\n            tabBar\n        }\n        Group {\n            tabBody\n        }\n', '            KLineCard(vm: vm)\n            FreshnessRow(vm: vm).padding(.horizontal, 16)\n            tabBar.padding(.horizontal, 16)\n        }\n        Group {\n            tabBody.padding(.horizontal, 16)\n        }\n')

    # ---------- 交易所风格头部 ----------
    H = 'ios/App/CompactHeader.swift'
    rep('h17_title_btns', H, '            Spacer(minLength: 4)\n            Menu {', r'''            Spacer(minLength: 4)
            FavButton(vm: vm)
            Button { NotificationCenter.default.post(name: .tstzmFullChart, object: nil) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.body)
            }
            .buttonStyle(.plain)
            Menu {''')
    cut('h17_header', H, '    @ViewBuilder\n    private func content(_ m: DexPair) -> some View {', '    var body: some View {\n        Group {\n            if let m = vm.main { content(m) }', r'''    @ViewBuilder
    private func content(_ m: DexPair) -> some View {
        let h24 = m.priceChange?["h24"]
        let tx = m.txns?["h24"]
        let ls = links(m) + externals(m)
        wrap {
            VStack(alignment: .leading, spacing: 10) {
                titleRow(m, ls)
                exchangeRow(m, h24)
                changeRow(m)
                if expanded { moreBlock(m, tx) }
                toggleButton
            }
        }
    }

    // 交易所样式：左边大价格 + 24h 涨跌，右边 4 项关键数据
    private func exchangeRow(_ m: DexPair, _ h24: Double?) -> some View {
        let age: String = m.pairCreatedAt.map { Fmt2.dur(Date().timeIntervalSince1970 - $0 / 1000) } ?? "—"
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(m.price.map { Money.price($0) } ?? "—")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(col(h24))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(pct(h24)).font(.subheadline.weight(.semibold)).foregroundStyle(col(h24))
                    Text("24h").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                kvRow("市值", Fmt2.usd(m.marketCap))
                kvRow("流动性", Fmt2.usd(m.liq))
                kvRow("24h成交", Fmt2.usd(m.volume?["h24"]))
                kvRow("池龄", age)
            }
        }
    }

    private func kvRow(_ k: String, _ v: String) -> some View {
        HStack(spacing: 6) {
            Text(k).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.caption.weight(.semibold).monospacedDigit())
        }
    }

''')

    # ---------- K 线：状态 / 实时尾巴 / 秒切周期 / 通栏 + 全屏 ----------
    P = 'ios/App/ProChart.swift'
    rep('h17_k_props', P, '    @Published var histMore = false\n', '    @Published var histMore = false\n    @Published var liveNote = ""\n')
    rep('h17_k_live_vars', P, '    private var base: [Candle] = []   // 拉到的原始 K 线（周线月线用日线汇总）\n', '    private var base: [Candle] = []   // 拉到的原始 K 线（周线月线用日线汇总）\n    private var liveC: Candle?\n    private var liveTF: TF = .m15\n')
    rep('h17_k_status', P, r'''        return "共 \(candles.count) 根" + tail
''', r'''        return "共 \(candles.count) 根" + tail + liveNote
''')
    rep('h17_k_setc', P, '        candles = tf.rolled(raw)\n', '        candles = withLive(tf.rolled(raw))\n')
    rep('h17_k_reload', P, '        setCandles(KLineCache.load(chain.rawValue + ":" + pair + ":" + tf.rawValue))\n', r'''        var own = KLineCache.load(chain.rawValue + ":" + pair + ":" + tf.rawValue)
        if own.count < 30, let d = deriveFromFiner() { own = merged(d, own) }
        setCandles(own)
''')
    rep('h17_k_rebuild_sig', P, '    func rebuild() {\n        if candles.isEmpty { return }\n', '    func rebuild(live: Bool = false) {\n        if candles.isEmpty { return }\n')
    rep('h17_k_save', P, '        KLineCache.save(key: chain.rawValue + ":" + pair + ":" + tf.rawValue, base)\n    }\n\n    // 任意地址的拆解', '        if !live { KLineCache.save(key: chain.rawValue + ":" + pair + ":" + tf.rawValue, base) }\n    }\n\n    // 任意地址的拆解')
    rep('h17_k_methods', P, '    // 任意地址的拆解（成本、盈亏、入场时点、状态），同一地址只拆一次\n', r'''    // MARK: 实时尾巴：Dexscreener 实时价每 3 秒把最新一根 K 线补到「现在」，不再等 GeckoTerminal 的延迟 K 线
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
''')
    rep('h17_k_state', P, '    @State private var fallbackSel: Date?\n', '    @State private var fallbackSel: Date?\n    @State private var showFull = false\n')
    rep('h17_k_body', P, '            KLineDetailCard(vm: vm, cvm: cvm)\n        }\n        .task(id: key) {\n            webFailed = false\n', '            KLineDetailCard(vm: vm, cvm: cvm).padding(.horizontal, 16)\n        }\n        .task(id: key) { await cvm.liveLoop() }\n        .task(id: key) {\n            webFailed = false\n')
    rep('h17_k_begin', P, '            cvm.begin(chain: vm.chain, pair: vm.main?.pairAddress, token: vm.address)\n', '            cvm.begin(chain: vm.chain, pair: vm.main?.pairAddress, token: vm.address)\n            Task { await cvm.prefetchOthers() }\n')
    rep('h17_k_height', P, '                .frame(height: 460)\n                .clipShape(RoundedRectangle(cornerRadius: 10))\n', '                .frame(height: KHero.chartHeight)\n')
    cut('h17_k_block', P, '    @ViewBuilder\n    private var chartBlock: some View {', '// MARK: - 单根 K 线的切片计算', r'''    @ViewBuilder
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

''')

    # ---------- 图表页：价格轴（极小价格用「0.0₆1587」写法）+ 副图数值格式 ----------
    W = 'ios/App/Web/chart.html'
    rep('h17_w_state', W, "prec:6,key:'',mode:'init'", "prec:6,F:1,key:'',mode:'init'")
    cut('h17_w_fp', W, '  function fp(v){', '  function fu(v){', r'''  function fSub(a){var s=a<0?'-':'';a=Math.abs(a);if(a===0)return '0';if(a>=1000)return s+a.toFixed(2);if(a>=1)return s+a.toFixed(4);if(a>=0.0001)return s+a.toFixed(Math.min(8,Math.max(4,Math.ceil(-Math.log10(a))+3)));var e=a.toExponential(3).split('e'),m=e[0].replace('.',''),z=-parseInt(e[1],10)-1,sb='₀₁₂₃₄₅₆₇₈₉',zs=String(z).split('').map(function(d){return sb.charAt(+d);}).join('');return s+'0.0'+zs+m;}
  function fp(v){if(v==null)return '--';if(S.cfg.mcap)return fCN(v);return fSub(v/(S.F||1));}
''')
    cut('h17_w_pf', W, '  function pf(){', '  function mkd(arr,t){', r'''  function pf(){if(S.cfg.mcap)return {type:'custom',formatter:fCN,minMove:0.01};return {type:'custom',formatter:fp,minMove:(S.F>1?0.001:0.00001)};}
''')
    rep('h17_w_scale', W, 'var m=S.cfg.mcap?S.cfg.mult:1,ts=chart.timeScale(),vr=null;', "var m=S.cfg.mcap?S.cfg.mult:1,ts=chart.timeScale(),vr=null;var F=1;if(!S.cfg.mcap){var lo0=Infinity;S.raw.forEach(function(r){if(r[3]>0&&r[3]<lo0)lo0=r[3];});if(lo0<0.1&&lo0>0)F=Math.pow(10,Math.ceil(-Math.log10(lo0)));}S.F=F;m=m*F;")
    rep('h17_w_sp', W, "(v==null?'--':fp(v))", "(v==null?'--':(/^(K|D|J|RSI|ROC|MAROC)[:(]/.test(txt)?v.toFixed(2):fp(v)))")
    rep('h17_w_vma', W, "+sp('#fbbf24','MA(5): ',g(I.vma));", "+'<span style=\"color:#fbbf24\">MA(5): '+(g(I.vma)==null?'--':fCN(g(I.vma)))+'</span> ';")
