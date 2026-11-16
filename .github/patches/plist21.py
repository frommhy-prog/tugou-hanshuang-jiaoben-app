# 2026-11-16：计价货币、刷新图标位置与外圈、顶栏并进头部、数据条缩小、免 GMGN Key 数据源回落
def register(rep, cut):
    H = 'ios/App/GMHeader.swift'
    M = 'ios/App/GMMetrics.swift'
    G = 'ios/App/GMMore.swift'
    U = 'ios/App/UnifiedToken.swift'
    P = 'ios/App/ProChart.swift'
    W = 'ios/App/Web/chart.html'

    # ---------- 头部：搜索图标 + ⋯ 菜单带上原顶栏的功能 + 金额跟随货币 + 缩小 ----------
    rep('g21_h1', H, r'''FavButton(vm: vm)''', r'''Button { NotificationCenter.default.post(name: .gmOpenSearch, object: nil) } label: {
                Image(systemName: "magnifyingglass").font(.body)
            }
            .buttonStyle(.plain)
            FavButton(vm: vm)''')
    rep('g21_h2', H, r'''ForEach(ls.indices, id: \.self) { i in''', r'''Button { NotificationCenter.default.post(name: .gmOpenTools, object: nil) } label: { Label("工具箱 · 全部数据源", systemImage: "wrench.and.screwdriver") }
                Button { NotificationCenter.default.post(name: .gmOpenDash, object: nil) } label: { Label("盯盘看板", systemImage: "gauge.with.dots.needle.67percent") }
                Button { NotificationCenter.default.post(name: .gmShare, object: nil) } label: { Label("分享", systemImage: "square.and.arrow.up") }
                Button { NotificationCenter.default.post(name: .gmAlert, object: nil) } label: { Label("设提醒", systemImage: "bell.badge") }
                Divider()
                ForEach(ls.indices, id: \.self) { i in''')
    rep('g21_h3', H, r'''if mcapMode { kvRow("价格", other) } else { kvRow("市值", Fmt2.usd(m.marketCap ?? m.fdv)) }''', r'''if mcapMode { kvRow("价格", other) } else { kvRow("市值", GMPx.cap(m.marketCap ?? m.fdv)) }''')
    rep('g21_h4', H, r'''kvRow("流动性", Fmt2.usd(m.liq))''', r'''kvRow("流动性", GMPx.cap(m.liq))''')
    rep('g21_h5', H, r'''kvRow("24h成交", Fmt2.usd(m.volume?["h24"]))''', r'''kvRow("24h成交", GMPx.cap(m.volume?["h24"]))''')
    rep('g21_h6', H, r'''.padding(.vertical, 4)''', r'''.padding(.vertical, 2)''')
    rep('g21_h7', H, r'''.font(.system(size: 30, weight: .bold, design: .rounded))''', r'''.font(.system(size: 27, weight: .bold, design: .rounded))''')

    # ---------- 数据条：框缩小；GMGN 没有时回落免费数据源 ----------
    rep('g21_m1', M, r'''Text(title).underline(true, pattern: .dot, color: Color.secondary).font(.caption2).foregroundStyle(Color.secondary)''', r'''Text(title).underline(true, pattern: .dot, color: Color.secondary).font(.system(size: 9.5)).foregroundStyle(Color.secondary)''')
    rep('g21_m2', M, r'''Text(v.text).font(.footnote.weight(.bold)).foregroundStyle(v.color).lineLimit(1)''', r'''Text(v.text).font(.system(size: 11.5, weight: .bold)).foregroundStyle(v.color).lineLimit(1)''')
    rep('g21_m3', M, r'''.padding(.horizontal, 9)''', r'''.padding(.horizontal, 7).padding(.vertical, -2.5)''')
    rep('g21_m4', M, r'''@State private var sheet: GMSheetID?''', r'''@State private var sheet: GMSheetID?
    @ObservedObject private var fr = GMFreeStore.shared''')
    rep('g21_m5', M, r'''paid = nil''', r'''paid = nil
            Task { await fr.load(chain: vm.chain, address: vm.address) }''')
    rep('g21_m6', M, r'''.onChange(of: vm.refreshToken) { _, _ in''', r'''.onChange(of: vm.refreshToken) { _, _ in
            Task { await fr.load(chain: vm.chain, address: vm.address, force: true) }''')
    rep('g21_m7', M, r'''@State private var showBuyers = false''', r'''@State private var showBuyers = false
    @ObservedObject private var fr = GMFreeStore.shared''')
    rep('g21_m8', M, r'''if !ws.isEmpty { walletsCard(ws) }''', r'''if !ws.isEmpty { walletsCard(ws) }
                    if ws.isEmpty { GMFreeWalletsCard(chain: vm.chain, id: id) }''')
    rep('g21_m9', M, r'''let hint: String = gm.hasKey ? "GMGN 暂未返回这一项" : "没填 GMGN API Key，这一项暂时读不到（设置 → GMGN 数据）"''', r'''let hint: String = gm.hasKey ? "GMGN 暂未返回这一项" : "免费来源（币安 Web3、Blockscout、GoPlus、RugCheck 等）暂时没有这一项；填 GMGN 或 OKX Web3 Key 可补全（设置）"''')
    rep('g21_m10', M, r'''guard let x = v else { return none }''', r'''if v == nil, let fx = GMFreeStore.shared.v["top10"] {
                v = fx
                src = (GMFreeStore.shared.src["top10"] ?? "免费数据源") + (GMFreeStore.shared.t["top10note"].map { "（" + $0 + "）" } ?? "")
            }
            guard let x = v else { return none }''')
    rep('g21_m11', M, r'''guard let n = gm.num("holder_count", "stat.holder_count") else { return none }''', r'''let gmN: Double? = gm.num("holder_count", "stat.holder_count")
            guard let n = gmN ?? GMFreeStore.shared.v["holders"] else { return none }''')
    rep('g21_m12', M, r'''rows: [("持有钱包数", String(Int(n))), ("数据来源", "GMGN")])''', r'''rows: [("持有钱包数", String(Int(n))), ("数据来源", gmN != nil ? "GMGN" : (GMFreeStore.shared.src["holders"] ?? "免费数据源"))])''')
    cut('g21_m13', M, r'''case "devhold":''', r'''case "tax":''', r'''case "devhold":
            let fs = GMFreeStore.shared
            let gmDev: Double? = gm.num("creator_balance_rate", "stat.creator_hold_rate").map { $0 * 100 }
            let r: Double? = gmDev ?? fs.v["dev"]
            let st: String? = gm.str("creator_token_status")
            if r == nil && st == nil { return none }
            let stText: String = st == "creator_hold" ? "仍持有" : (st == "creator_close" ? "已清仓" : "未知")
            var rows: [(String, String)] = []
            if st != nil { rows.append(("创建者状态", stText)) }
            if let x = r { rows.append(("创建者持仓占比", String(format: "%.2f%%", x))) }
            if let t = gm.num("dev_team_hold_rate", "stat.dev_team_hold_rate") { rows.append(("Dev 团队持仓", String(format: "%.2f%%", t * 100))) }
            let devFromGM: Bool = gmDev != nil || st != nil
            rows.append(("数据来源", devFromGM ? "GMGN" : (fs.src["dev"] ?? "免费数据源")))
            let col: Color = st == "creator_close" ? Color.green : ((r ?? 0) > 5 ? Color.red : Color.orange)
            return GMVal(text: r.map { String(format: "%.1f%%", $0) } ?? stText, color: col, rows: rows)
        case "sniper":
            let fs = GMFreeStore.shared
            let cnt: Double? = gm.num("sniper_count", "wallet_tags_stat.sniper_wallets") ?? fs.v["sniperN"]
            let gmHold: Double? = gm.sniperHold()
            let hold: Double? = gmHold ?? fs.v["sniper"]
            if cnt == nil && hold == nil { return none }
            var rows: [(String, String)] = []
            if let c = cnt { rows.append(("狙击钱包数", String(Int(c)))) }
            if let h = hold { rows.append(("狙击者当前持仓", String(format: "%.2f%%", h))) }
            let fromFree: Bool = gmHold == nil && fs.v["sniper"] != nil
            rows.append(("数据来源", fromFree ? (fs.src["sniper"] ?? "免费数据源") : "GMGN"))
            if let h = hold { return GMVal(text: String(format: "%.2f%%", h), color: pctColor(h, 3, 10), rows: rows) }
            let c = cnt ?? 0
            return GMVal(text: String(Int(c)) + " 个", color: c < 5 ? Color.green : (c <= 20 ? Color.orange : Color.red), rows: rows)
        case "bundler":
            return GMFreeStore.pctVal(gm.num("bundler_trader_amount_rate", "stat.top_bundler_trader_percentage").map { $0 * 100 }, "bundle", 5, 15, none)
        case "rat":
            return GMFreeStore.pctVal(gm.num("suspected_insider_hold_rate", "rat_trader_amount_rate", "stat.top_rat_trader_percentage").map { $0 * 100 }, "insider", 5, 15, none)
        case "phishing":
            return pct(gm.num("stat.top_entrapment_trader_percentage").map { $0 * 100 }, 3, 10, [])
        case "fresh":
            return pct(gm.num("stat.fresh_wallet_rate").map { $0 * 100 }, 20, 50, [])
        ''')
    rep('g21_m14', M, r'''if b == nil && s == nil { return none }''', r'''if b == nil && s == nil, let fb = GMFreeStore.shared.v["buyTax"] ?? GMFreeStore.shared.v["sellTax"] {
                _ = fb
                b = GMFreeStore.shared.v["buyTax"]
                s = GMFreeStore.shared.v["sellTax"]
                src = GMFreeStore.shared.src["buyTax"] ?? GMFreeStore.shared.src["sellTax"] ?? "免费数据源"
            }
            if b == nil && s == nil { return none }''')
    rep('g21_m15', M, r'''case "honeypot":''', r'''case "honeypot":
            if vm.chain != .solana, gm.str("is_honeypot") == nil, vm.security?.honeypot == nil, let hv = GMFreeStore.shared.v["honeypot"] {
                let yes: Bool = hv > 0
                return GMVal(text: yes ? "是" : "否", color: yes ? Color.red : Color.green, rows: [("数据来源", GMFreeStore.shared.src["honeypot"] ?? "免费数据源")])
            }''')
    rep('g21_m16', M, r'''case "lp":''', r'''case "lp":
            if gm.str("burn_status") == nil, gmPath(gm.sec, "burn_status") == nil, vm.security?.lpLocked == nil, let lv = GMFreeStore.shared.v["lpSafe"] {
                return GMVal(text: String(format: "%.0f%%", lv), color: lv >= 90 ? Color.green : (lv >= 50 ? Color.orange : Color.red), rows: [("LP 已锁定/烧毁占比", String(format: "%.1f%%", lv)), ("数据来源", GMFreeStore.shared.src["lpSafe"] ?? "免费数据源")])
            }''')

    # ---------- 刷新图标：去掉外圈圆盘；刷新时内容下移，图标放进空出来的位置 ----------
    rep('g21_g1', G, r'''.fill(Color.card.opacity(0.94))''', r'''.fill(Color.clear)''')
    rep('g21_g2', G, r'''.shadow(color: Color.black.opacity(0.18), radius: 8, y: 2)''', r'''.shadow(color: Color.clear, radius: 0)''')
    rep('g21_g3', G, r'''init(_ action: @escaping @MainActor () async -> Void) { self.action = action }''', r'''init(_ action: @escaping @MainActor () async -> Void) { self.action = action }
    var bind: Binding<Bool>? = nil
    init(refreshing: Binding<Bool>, _ action: @escaping @MainActor () async -> Void) {
        self.action = action
        self.bind = refreshing
    }''')
    rep('g21_g4', G, r'''context.coordinator.action = action''', r'''context.coordinator.action = action
        context.coordinator.bind = bind''')
    rep('g21_g5', G, r'''private weak var scroll: UIScrollView?''', r'''var bind: Binding<Bool>?
        private weak var scroll: UIScrollView?''')
    rep('g21_g6', G, r'''await self.action?()''', r'''if let b = self.bind { withAnimation(.easeInOut(duration: 0.25)) { b.wrappedValue = true } }
                await self.action?()''')
    rep('g21_g7', G, r'''self.st.pull = 0''', r'''self.st.pull = 0
                if let b = self.bind { withAnimation(.easeInOut(duration: 0.25)) { b.wrappedValue = false } }''')
    rep('g21_g8', G, r'''let y: CGFloat = refreshing ? 38 : min(pull, 110) * 0.5 + 4''', r'''let y: CGFloat = refreshing ? 27 : min(pull, 96) * 0.5 + 10''')
    rep('g21_g9', G, r'''h.view.center = CGPoint(x: sv.frame.midX, y: sv.frame.minY + top + y + 12)''', r'''h.view.center = CGPoint(x: sv.frame.midX, y: sv.frame.minY + top + y)''')
    rep('g21_g10', G, r'''Section("提醒") {''', r'''GMFreeSettings()
            Section("提醒") {''')
    rep('g21_g11', G, r'''return max(240, min(560, h - 548))''', r'''return max(240, min(560, h - 492))''')

    # ---------- 代币页：隐藏导航栏（按钮并进头部）、货币变化强制重绘、刷新时内容下移 ----------
    rep('g21_u1', U, r'''@State private var showSearch = false''', r'''@State private var showSearch = false
    @State private var showTools = false
    @State private var isRefreshing = false
    @AppStorage("currency", store: Cfg.defaults) private var curCode = "USD"
    @ObservedObject private var fxs = GMFXState.shared''')
    rep('g21_u2', U, r'''.background(LogoRefreshHook { vm.refreshAll(); try? await Task.sleep(nanoseconds: 800_000_000) })''', r'''.background(LogoRefreshHook(refreshing: $isRefreshing) { vm.refreshAll(); try? await Task.sleep(nanoseconds: 800_000_000) })''')
    rep('g21_u3', U, r'''.padding(.top, 2)''', r'''.padding(.top, isRefreshing ? 52 : 2)''')
    rep('g21_u4', U, r'''if vm.main != nil { content }''', r'''if vm.main != nil { content.id(curCode + "|" + String(fxs.tick)) }''')
    rep('g21_u5', U, r'''.onAppear { GMPx.sync(vm.main) }''', r'''.onAppear { GMPx.sync(vm.main); Task { await GMPx.ensureFX() } }''')
    rep('g21_u6', U, r'''.sheet(isPresented: $showDash) { DashboardView() }''', r'''.toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showDash) { DashboardView() }
            .sheet(isPresented: $showTools) { GMToolbox(vm: vm) }
            .onReceive(NotificationCenter.default.publisher(for: .gmOpenSearch)) { _ in showSearch = true }
            .onReceive(NotificationCenter.default.publisher(for: .gmOpenDash)) { _ in showDash = true }
            .onReceive(NotificationCenter.default.publisher(for: .gmOpenTools)) { _ in showTools = true }
            .onReceive(NotificationCenter.default.publisher(for: .gmShare)) { _ in shareToken() }
            .onReceive(NotificationCenter.default.publisher(for: .gmAlert)) { _ in showAlert = true }''')
    rep('g21_u7', U, r'''Text("粘贴合约，自动出完整分析").font(.headline)''', r'''HStack {
                        Text("粘贴合约，自动出完整分析").font(.headline)
                        Spacer()
                        Button { showDash = true } label: { Label("盯盘看板", systemImage: "gauge.with.dots.needle.67percent").font(.footnote) }
                    }''')

    # ---------- K 线：价格、成交额乘汇率，符号跟随货币 ----------
    rep('g21_p1', P, r'''"mult": (cfgMult.isFinite && cfgMult > 0) ? cfgMult : 1.0,''', r'''"mult": (cfgMult.isFinite && cfgMult > 0) ? cfgMult : 1.0,
            "rate": GMPx.rate,
            "cur": GMPx.sym,''')
    rep('g21_w1', W, r'''var S={raw:[],C:[],idx:{},prec:6,F:1,key:'',mode:'init\'''', r'''var S={raw:[],C:[],idx:{},prec:6,F:1,R:1,cur:'$',key:'',mode:'init\'''')
    rep('g21_w2', W, r'''function fu(v){return '$'+fCN(v);}''', r'''function fu(v){return (S.cur||'$')+fCN(v);}''')
    rep('g21_w3', W, r'''o.text=fu(m[2]);''', r'''o.text=fu(m[2]*(S.R||1));''')
    rep('g21_w4', W, r'''var m=S.cfg.mcap?S.cfg.mult:1,ts=chart.timeScale(),vr=null;var F=1;if(!S.cfg.mcap){var lo0=Infinity;S.raw.forEach(function(r){if(r[3]>0&&r[3]<lo0)lo0=r[3];});''', r'''var R=S.R||1;var m=(S.cfg.mcap?S.cfg.mult:1)*R,ts=chart.timeScale(),vr=null;var F=1;if(!S.cfg.mcap){var lo0=Infinity;S.raw.forEach(function(r){var lw=r[3]*R;if(lw>0&&lw<lo0)lo0=lw;});''')
    rep('g21_w5', W, r'''l:r[3]*m,c:r[4]*m,v:r[5]};''', r'''l:r[3]*m,c:r[4]*m,v:r[5]*(S.R||1)};''')
    rep('g21_w6', W, r'''S.raw=d.candles||[];S.prec=d.prec||6;''', r'''S.R=(d.rate>0?d.rate:1);S.cur=d.cur||'$';S.raw=d.candles||[];S.prec=d.prec||6;''')
