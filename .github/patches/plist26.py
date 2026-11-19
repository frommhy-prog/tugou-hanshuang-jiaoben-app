# 2026-11-19：Ave 风格紧凑数据条、具体叙事、OG/股票币、剪贴板检测、钱包标签与头像卡片、大户直接拆解、设置重排、分享快照
import re


def sub_all(rep, tag, p, pattern, repl, minimum=1):
    # 正则替换（DOTALL）：命中数不足就整条跳过，不影响该文件其他补丁
    g = rep.__globals__
    if tag in g['applied'] or p in g['bad']:
        return
    t = g['load'](p)
    n, c = re.subn(pattern, repl, t, flags=re.S)
    if c < minimum:
        print('G26_SKIP', tag, 'matches', c)
        return
    g['files'][p] = n
    g['done'].setdefault(p, []).append(tag)


def register(rep, cut):
    # ---------- 顶部数据条：紧凑图标版 + 本机推算兜底 ----------
    MET = 'ios/App/GMMetrics.swift'
    rep('g26_met_props', MET, r'''    @ObservedObject private var fr = GMFreeStore.shared
    @State private var showEditor = false
''', r'''    @ObservedObject private var fr = GMFreeStore.shared
    @ObservedObject private var gxd = GXHoldersStore.shared
    @ObservedObject private var gxi = GXInfoStore.shared
    @AppStorage("gxChip", store: Cfg.defaults) private var chipStyle = "icon"
    @State private var showEditor = false
''')
    cut('g26_met_cell', MET, '''        return Button { sheet = GMSheetID(id: id) } label: {''', r'''    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ids, id: \.self) { id in cell(id) }''', r'''        let compact: Bool = chipStyle == "icon"
        return Button { sheet = GMSheetID(id: id) } label: {
            GXChipView(id: id, title: title, v: v, compact: compact)
        }
        .buttonStyle(.plain)
    }

''')
    rep('g26_met_eval', MET, r'''        switch id {
        case "top10":
            var v: Double? = gm.num("top_10_holder_rate", "stat.top_10_holder_rate").map { $0 * 100 }''', r'''        if let gx = GXHoldersStore.shared.override(id, vm: vm, gm: gm) { return gx }
        switch id {
        case "top10":
            var v: Double? = gm.num("top_10_holder_rate", "stat.top_10_holder_rate").map { $0 * 100 }''')

    # ---------- 代币头部：徽标、点头像出面板、具体叙事、App 图标 ----------
    HD = 'ios/App/GMHeader.swift'
    rep('g26_hd_state', HD, r'''    @State private var narr: NarrReport?
''', r'''    @State private var narr: NarrReport?
    @State private var showTokenSheet = false
''')
    rep('g26_hd_badge', HD, r'''            narrChip(m).layoutPriority(0)
''', r'''            narrChip(m).layoutPriority(0)
            GXBadgeRow(vm: vm, pair: m).fixedSize().layoutPriority(3)
''')
    rep('g26_hd_logo', HD, r'''            AvTokenLogo(chain: vm.chain, address: vm.address, symbol: m.baseToken?.symbol ?? vm.symbol, hint: m.info?.imageUrl, size: 44, dex: m.dexId)
''', r'''            Button { showTokenSheet = true } label: {
                AvTokenLogo(chain: vm.chain, address: vm.address, symbol: m.baseToken?.symbol ?? vm.symbol, hint: m.info?.imageUrl, size: 44, dex: m.dexId)
            }
            .buttonStyle(.plain)
''')
    rep('g26_hd_narr', HD, r'''            contractRow(m)
            headline(m, h24)
''', r'''            contractRow(m)
            GXNarrLine(vm: vm)
            headline(m, h24)
''')
    rep('g26_hd_icons', HD, r'''                ForEach(ex.indices, id: \.self) { i in
                    Link(destination: ex[i].1) { extIcon(ex[i].0) }
                }
''', r'''                GXAppIcons(chain: vm.chain, addr: vm.address, pair: m.pairAddress, size: 22)
''')
    rep('g26_hd_body', HD, r'''        .task(id: nKey) { await loadNarr() }
''', r'''        .task(id: nKey) { await loadNarr() }
        .task(id: nKey) { await GXInfoStore.shared.load(vm: vm) }
        .sheet(isPresented: $showTokenSheet) { GXTokenSheet(vm: vm) }
''')

    # ---------- 钱包地址菜单：每项带 App 图标，开关可控 ----------
    GN = 'ios/App/GMGNApi.swift'
    cut('g26_gn_menu', GN, 'struct GMWalletMenuContent: View {', 'struct GMPaid {', r'''struct GMWalletMenuContent: View {
    let chain: Chain
    let addr: String

    var body: some View {
        GXWalletMenuBody(chain: chain, addr: addr)
    }
}

// MARK: - Dexscreener 付费状态（资料页 / CTO / 广告）
''')

    # ---------- 交易记录 / 钱包分析里的钱包地址：头像 + 标签 + 点开钱包卡片 ----------
    sub_all(rep, 'g26_lab2_wallet', 'ios/App/GMLab2.swift',
            r'Menu \{\s*GMWalletMenuContent\(chain: ([A-Za-z0-9_.]+), addr: ([A-Za-z0-9_.]+)\)\s*\} label: \{\s*Text\(Addr\.short\([A-Za-z0-9_.]+\)\)\.font\(\.caption2?\.monospaced\(\)\)\.foregroundStyle\(Color\.accentColor\)\s*\}',
            r'GXWalletLabel(chain: \1, addr: \2)')

    # ---------- FOMO 图标 ----------
    rep('g26_brands_fomo', 'ios/tools/brands.txt', 'upbit upbit.com\n', 'upbit upbit.com\nfomo fomo.family\n')

    # ---------- 代币页：大户直接拆解 + 分享快照 ----------
    UT = 'ios/App/UnifiedToken.swift'
    rep('g26_ut_holders', UT, r'''            HoldersIntelButton(vm: vm)
            HolderDeepCard(vm: vm)
''', r'''            GXHoldersInline(vm: vm)
            HolderDeepCard(vm: vm)
''')
    rep('g26_ut_state', UT, r'''    @State private var shareSheet = false
''', r'''    @State private var shareSheet = false
    @State private var showGXShare = false
''')
    rep('g26_ut_sheet', UT, r'''            .sheet(isPresented: $shareSheet) { ShareSheet(items: shareItems) }
''', r'''            .sheet(isPresented: $shareSheet) { ShareSheet(items: shareItems) }
            .sheet(isPresented: $showGXShare) { GXShareSheet(vm: vm) }
''')
    rep('g26_ut_share', UT, r'''        shareItems = ShareKit.tokenItems(vm)
        shareSheet = true
''', r'''        showGXShare = true
''')

    # ---------- 根视图：进入 App 检测剪贴板 ----------
    AP = 'ios/App/TSTZMApp.swift'
    rep('g26_app_state', AP, r'''    @State private var needSetup = Cfg.token.isEmpty
''', r'''    @State private var needSetup = Cfg.token.isEmpty
    @ObservedObject private var clip = GXClip.shared
''')
    rep('g26_app_clip', AP, r'''        .task { GMScout.shared.start() }
''', r'''        .task { GMScout.shared.start() }
        .sheet(item: $clip.card) { c in GXClipSheet(card: c) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            Task { await GXClip.shared.check() }
        }
        .task { await GXClip.shared.check() }
''')

    # ---------- 设置页：旧版改名，新版在 GXSettings.swift ----------
    rep('g26_set_rename', 'ios/App/SettingsView.swift', 'struct SettingsView: View {', 'struct SettingsViewLegacy: View {')

    # ---------- GX 自己的文件：币安 Web3 动态数据（Dev / 聪明钱 / KOL，不需要 Key）----------
    DT = 'ios/App/GXData.swift'
    rep('g26_dt_fn', DT, r'''    // GeckoTerminal 代币资料
''', r'''    // 币安 Web3 公共接口：Dev 持仓、聪明钱 / KOL / 专业用户持仓（不需要 Key）
    static func binanceDynamic(_ chain: Chain, _ addr: String) async -> [String: Double] {
        let ids: [Chain: String] = [.eth: "1", .bsc: "56", .base: "8453", .solana: "CT_501"]
        guard let cid = ids[chain] else { return [:] }
        let u: String = "https://web3.binance.com/bapi/defi/v4/public/wallet-direct/buw/wallet/market/token/dynamic/info?chainId=" + cid + "&contractAddress=" + addr
        guard let o = await GXNet.json(u, headers: ["User-Agent": "binance-web3/1.1 (Skill)"]) as? [String: Any], let d = o["data"] as? [String: Any] else { return [:] }
        let map: [(String, String)] = [("dev", "devHoldingPercent"), ("smartN", "smartMoneyHolders"), ("smartPct", "smartMoneyHoldingPercent"), ("kolN", "kolHolders"), ("kolPct", "kolHoldingPercent"), ("proN", "proHolders"), ("proPct", "proHoldingPercent"), ("kyc", "kycHolderCount")]
        var out: [String: Double] = [:]
        for (k, f) in map {
            if let v = gmNum(d[f]) { out[k] = v }
        }
        return out
    }

    // GeckoTerminal 代币资料
''')
    rep('g26_dt_pub', DT, r'''    @Published var created: Date?
    @Published var loading = false
''', r'''    @Published var created: Date?
    @Published var bin: [String: Double] = [:]
    @Published var loading = false
''')
    rep('g26_dt_reset', DT, r'''            tgHandle = nil; tgPosts = []; website = nil; created = nil
''', r'''            tgHandle = nil; tgPosts = []; website = nil; created = nil; bin = [:]
''')
    rep('g26_dt_fetch', DT, r'''        async let gk = GXSrc.geckoInfo(chain, addr)
        let b: GXMeta? = await bm
        let g: GXMeta? = await gk
''', r'''        async let gk = GXSrc.geckoInfo(chain, addr)
        async let bd = GXSrc.binanceDynamic(chain, addr)
        let b: GXMeta? = await bm
        let g: GXMeta? = await gk
        let dyn: [String: Double] = await bd
''')
    rep('g26_dt_set', DT, r'''        website = web
        created = b?.created
''', r'''        website = web
        created = b?.created
        bin = dyn
''')

    HS = 'ios/App/GXHolders.swift'
    rep('g26_hs_dev', HS, r'''        case "sniper":
''', r'''        case "devhold":
            if gm.num("creator_balance_rate", "stat.creator_hold_rate") != nil || gm.str("creator_token_status") != nil || fs.v["dev"] != nil { return nil }
            let bin2: [String: Double] = GXInfoStore.shared.key == GXInfoStore.k(vm) ? GXInfoStore.shared.bin : [:]
            guard let dv = bin2["dev"] else { return nil }
            return GMVal(text: String(format: "%.1f%%", dv), color: dv > 5 ? Color.red : Color.orange, rows: [
                ("创建者持仓占比", String(format: "%.2f%%", dv)),
                ("数据来源", "币安 Web3（公共接口，不需要 Key）"),
            ])
        case "sniper":
''')
    rep('g26_hs_smart', HS, r'''            if gm.num("wallet_tags_stat.smart_wallets") != nil || fs.v["smartN"] != nil || fs.v["kolN"] != nil { return nil }
''', r'''            if gm.num("wallet_tags_stat.smart_wallets") != nil || fs.v["smartN"] != nil || fs.v["kolN"] != nil { return nil }
            let bin: [String: Double] = GXInfoStore.shared.key == GXInfoStore.k(vm) ? GXInfoStore.shared.bin : [:]
            if bin["smartN"] != nil || bin["kolN"] != nil {
                let sn: Int = Int(bin["smartN"] ?? 0)
                let kn: Int = Int(bin["kolN"] ?? 0)
                return GMVal(text: String(sn) + "/" + String(kn), color: sn > 0 ? Color.green : Color.secondary, rows: [
                    ("聪明钱钱包", String(sn) + " 个，持有 " + String(format: "%.3f%%", bin["smartPct"] ?? 0)),
                    ("KOL 钱包", String(kn) + " 个，持有 " + String(format: "%.3f%%", bin["kolPct"] ?? 0)),
                    ("专业用户", String(Int(bin["proN"] ?? 0)) + " 个，持有 " + String(format: "%.3f%%", bin["proPct"] ?? 0)),
                    ("数据来源", "币安 Web3（公共接口，不需要 Key）"),
                ])
            }
''')
