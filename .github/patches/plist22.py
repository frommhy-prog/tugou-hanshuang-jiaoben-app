# 2026-11-16 第二批：全 App 金额跟随计价货币、头部标签一行放下、数据条单行紧凑、K 线下分析分页（GMGN 风格）、分析工具修正
def register(rep, cut):
    g = rep.__globals__

    def edit(tag, p, fn):
        if tag in g['applied'] or p in g['bad']:
            return
        t = g['load'](p)
        try:
            n = fn(t)
        except Exception as e:
            g['bad'][p] = '%s: %s' % (tag, e)
            return
        if n == t:
            return
        g['files'][p] = n
        g['done'].setdefault(p, []).append(tag)

    PX = 'ios/App/GMPx.swift'
    M = 'ios/App/GMMetrics.swift'
    H = 'ios/App/GMHeader.swift'
    G = 'ios/App/GMMore.swift'
    U = 'ios/App/UnifiedToken.swift'
    L = 'ios/App/GMLab.swift'

    # ---------- 1) 全 App 的 Fmt2.usd(...) 统一走 GMPx.fiat（人民币就全是 ¥，不会再一边人民币一边美元） ----------
    rep('g22_px', PX, r'''    static func cap(_ v: Double?) -> String {''', r'''    // 任意美元金额（成交额、盈亏、池子…）→ 当前计价货币的缩写文本；全 App 原来的 Fmt2.usd 都转到这里
    static func fiat(_ v: Double?, signed: Bool = false) -> String {
        guard let x = v else { return "未知" }
        let s: String = Money.format(x)
        if signed && x > 0 { return "+" + s }
        return s
    }

    static func cap(_ v: Double?) -> String {''')
    for f in sorted((g['ROOT'] / 'ios' / 'App').glob('*.swift')):
        p = 'ios/App/' + f.name
        if p == PX:
            continue
        if 'Fmt2.usd(' in g['load'](p):
            edit('g22_fiat_' + f.stem, p, lambda t: t.replace('Fmt2.usd(', 'GMPx.fiat('))

    # ---------- 2) 数据条：单行紧凑（名称 + 数值同一行） ----------
    def cell(t):
        if t.count('Text(title).underline(') != 1:
            raise Exception('cell 锚点不唯一')
        i = t.index('Text(title).underline(')
        key = 'VStack(alignment: .leading, spacing: 3) {'
        j = t.rfind(key, 0, i)
        if j < 0 or i - j > 200:
            raise Exception('cell 容器没找到')
        return t[:j] + 'HStack(alignment: .firstTextBaseline, spacing: 4) {' + t[j + len(key):]
    edit('g22_cell', M, cell)

    # ---------- 3) 头部：标签一行放下（不再横滑），链名由头像角标显示；头像略缩小 ----------
    cut('g22_h1', H, r'''private func tagsRow(_ m: DexPair) -> some View {''', r'''private func titleRow(_ m: DexPair) -> some View {''', r'''private func tagsRow(_ m: DexPair) -> some View {
        let pad: GMLaunchpad? = GMLaunchpad.detect(chain: vm.chain, address: vm.address, dex: m.dexId)
        let mk: String? = GMMarketKind.text(dex: m.dexId, pad: pad)
        return HStack(spacing: 6) {
            narrChip(m).layoutPriority(0)
            if let d = m.dexId, !d.isEmpty { GMDexChip(dex: d).fixedSize().layoutPriority(2) }
            if let p = pad { Text(p.title).font(.caption2.weight(.semibold)).foregroundStyle(Color.orange).lineLimit(1).fixedSize().layoutPriority(1) }
            if let t = mk { chipText(t, t == "内盘" ? Color.orange : Color.green).fixedSize().layoutPriority(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    ''')
    rep('g22_h2', H, r'''size: 48, dex: m.dexId)''', r'''size: 44, dex: m.dexId)''')

    # ---------- 4) 设置页加「分析分页」；首屏 K 线高度跟着头部变矮调整 ----------
    rep('g22_g1', G, r'''GMFreeSettings()''', r'''GMTabSettings()
            GMFreeSettings()''')
    rep('g22_g2', G, r'''return max(240, min(560, h - 492))''', r'''return max(240, min(560, h - 470))''')

    # ---------- 5) 代币页：K 线下面改成分析分页（替换原来的「分析功能」宫格和「最新成交」） ----------
    cut('g22_u1', U, r'''GMFuncGrid(vm: vm, onOpen: { i in''', r'''// 分析数据都放进各自的新页面（综合研判 / 成交池子 / 持有筹码 / 合约安全 / 叙事社交 / 庄家情报 / 工具）''', r'''GMTabsSection(vm: vm, onMonitor: { showMon = true }) { id in tabBody(id) }
        }
    }

    // 各分页内容：交易记录 / 钱包分析 / 持有者 / 流动性 / 综合研判 / 合约安全 / 叙事社交 / 庄家情报 / 更多工具
    @ViewBuilder
    private func tabBody(_ id: String) -> some View {
        switch id {
        case "trade":
            GMTradeLabView(vm: vm)
            flowCard
        case "wallet":
            GMWalletLabView(vm: vm)
        case "holder":
            GMTrendCard(vm: vm)
            pageBody(2)
        case "liq":
            GMLiquidityLabView(vm: vm)
            poolsCard
        case "verdict":
            pageBody(0)
        case "risk":
            pageBody(3)
        case "narr":
            pageBody(4)
        case "intel":
            pageBody(5)
        default:
            Button { NotificationCenter.default.post(name: .gmOpenTools, object: nil) } label: {
                Label("工具箱 · 全部数据源与跳转", systemImage: "wrench.and.screwdriver").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            pageBody(6)
        }
    }

    ''')
    rep('g22_u2', U, r'''if let i = n.object as? Int { openPage = i }''', r'''if let i = n.object as? Int {
                    if i == 99 { showMon = true } else { GMTabState.shared.open(i) }
                }''')

    # ---------- 6) 分析工具里几处表达式太长 / 在视图里赋值的写法，拆开 ----------
    rep('g22_l1', L, r'''add(1, "同一区块 " + String(c.wallets.count) + " 个钱包一起买", "区块 #" + String(c.block) + " 内 " + String(c.wallets.count) + " 个不同地址买入合计 " + f(c.usd) + "。可能同一控制人拆分地址，也可能行情火爆碰巧同块；共 " + String(cl.count) + " 个这样的区块。")''', r'''let cn: String = String(c.wallets.count)
            let d1: String = "区块 #" + String(c.block) + " 内 " + cn + " 个不同地址买入合计 " + f(c.usd) + "。"
            let d2: String = "可能同一控制人拆分地址，也可能行情火爆碰巧同块；共 " + String(cl.count) + " 个这样的区块。"
            add(1, "同一区块 " + cn + " 个钱包一起买", d1 + d2)''')
    rep('g22_l2', L, r'''var d: String = "窗口内买入且仍持有的钱包，平均成本 " + GMPx.usd(avgCost) + "，现价 " + GMPx.usd(cp) + "（" + String(format: "%+.1f%%", diff) + "）。按金额算 " + String(format: "%.0f%%", under) + " 的资金成本高于现价。"''', r'''let d1: String = "窗口内买入且仍持有的钱包，平均成本 " + GMPx.usd(avgCost) + "，现价 " + GMPx.usd(cp)
                let d2: String = "（" + String(format: "%+.1f%%", diff) + "）。按金额算 " + String(format: "%.0f%%", under) + " 的资金成本高于现价。"
                var d: String = d1 + d2''')
    rep('g22_l3', L, r'''let usdShare: Double = r.buyUsd / total''', r'''let usdShare: Double = r.buyUsd / total
            let bs: String = "买 " + String(r.nb) + " 笔均 " + f(avgB) + "，卖 " + String(r.ns) + " 笔均 " + f(avgS) + "。"''')
    rep('g22_l4', L, r'''"买 " + String(r.nb) + " 笔均 " + f(avgB) + "，卖 " + String(r.ns) + " 笔均 " + f(avgS) + "。笔数占优的一方不一定是资金占优的一方，小额追买、大额卖出。"''', r'''bs + "笔数占优的一方不一定是资金占优的一方，小额追买、大额卖出。"''')
    rep('g22_l5', L, r'''"买 " + String(r.nb) + " 笔均 " + f(avgB) + "，卖 " + String(r.ns) + " 笔均 " + f(avgS) + "。资金侧偏多，卖单是零散的小额。"''', r'''bs + "资金侧偏多，卖单是零散的小额。"''')
    rep('g22_l6', L, r'''GLNote(text: "最近 " + String(rep.count) + " 笔成交，覆盖约 " + Fmt2.dur(rep.span) + "；买 " + String(rep.nb) + " 笔 " + GMPx.fiat(rep.buyUsd) + " · 卖 " + String(rep.ns) + " 笔 " + GMPx.fiat(rep.sellUsd) + " · 净 " + GMPx.fiat(rep.buyUsd - rep.sellUsd, signed: true) + "。来源 GeckoTerminal 最深池子，地址是交易发起方。")''', r'''GLNote(text: headLine(rep))''')
    rep('g22_l7', L, r'''private func tierLabel(_ t: GLTier) -> String {''', r'''private func headLine(_ rep: GLReport) -> String {
        let p1: String = "最近 " + String(rep.count) + " 笔成交，覆盖约 " + Fmt2.dur(rep.span) + "；"
        let p2: String = "买 " + String(rep.nb) + " 笔 " + GMPx.fiat(rep.buyUsd) + " · 卖 " + String(rep.ns) + " 笔 " + GMPx.fiat(rep.sellUsd)
        let p3: String = " · 净 " + GMPx.fiat(rep.buyUsd - rep.sellUsd, signed: true) + "。来源 GeckoTerminal 最深池子，地址是交易发起方。"
        return p1 + p2 + p3
    }

    private func tierLabel(_ t: GLTier) -> String {''')
    rep('g22_l8', L, r'''var line: String = "买入均价 " + GMPx.usd(ab)''', r'''let line: String = costLine(w, ab)''')
    rep('g22_l9', L, r'''if let cp = vm.main?.price { line += " → 现价 " + GMPx.usd(cp) }''', r'''EmptyView()''')
    rep('g22_l10', L, r'''private func row(_ w: GLWallet) -> some View {''', r'''private func costLine(_ w: GLWallet, _ ab: Double) -> String {
        var s: String = "买入均价 " + GMPx.usd(ab)
        if let cp = vm.main?.price { s += " → 现价 " + GMPx.usd(cp) }
        return s
    }

    private func row(_ w: GLWallet) -> some View {''')
    rep('g22_l11', L, r'''var top10: Double? = fr.v["top10"]''', r'''let top10: Double? = top10Val()''')
    rep('g22_l12', L, r'''if top10 == nil, let w = vm.conc?.wallets10 { top10 = Double(w) }''', r'''// 前十占比取自顶部数据条的数据源''')
    rep('g22_l13', L, r'''private func pct(_ v: Double) -> String { return String(format: "%.1f%%", v) }''', r'''private func pct(_ v: Double) -> String { return String(format: "%.1f%%", v) }

    private func top10Val() -> Double? {
        if let x = fr.v["top10"] { return x }
        if let w = vm.conc?.wallets10 { return Double(w) }
        return nil
    }''')
