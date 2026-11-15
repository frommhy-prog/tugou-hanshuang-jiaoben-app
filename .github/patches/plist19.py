# 2026-11-15 GMGN 风格改版补丁：收藏字段、头像徽标、代币页功能入口、K 线头部与全屏、标签页、价格/市值统一


def sub_all(rep, tag, p, old, new):
    # 同一文件里把 old 全部替换成 new（apply.py 的 rep 只允许单次匹配，这里借它的全局表做批量替换）
    g = rep.__globals__
    if tag in g['applied'] or p in g['bad']:
        return
    t = g['load'](p)
    if old not in t:
        return
    g['files'][p] = t.replace(old, new)
    g['done'].setdefault(p, []).append(tag)


def register(rep, cut):
    FAV = 'ios/App/Favorites.swift'
    rep('g19_fav_fields', FAV, r'''    var addedAt: Double
    var id: String { chain + ":" + address.lowercased() }''', r'''    var addedAt: Double
    var mcap: Double?
    var vol24h: Double?
    var dex: String?
    var created: Double?
    var change1h: Double?
    var change5m: Double?
    var id: String { chain + ":" + address.lowercased() }''')
    rep('g19_fav_scan', FAV, r'''            FavStore.shared.update(id: it.id, price: m.price, change: m.priceChange?["h24"], liq: m.liq)''', r'''            FavStore.shared.update(id: it.id, price: m.price, change: m.priceChange?["h24"], liq: m.liq)
            FavStore.shared.fill(m, id: it.id)''')

    AV = 'ios/App/Avatars.swift'
    rep('g19_av_glyph', AV, r'''            Text(chain.avMark)
                .font(.system(size: size * 0.58, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)''', r'''            GMChainGlyph(chain: chain, size: size)''')
    rep('g19_av_dexparam', AV, r'''    var badge: Bool = true
    @State private var img: UIImage?''', r'''    var badge: Bool = true
    var dex: String? = nil
    @State private var img: UIImage?''')
    rep('g19_av_launch', AV, r'''        .task(id: key + "|" + (hint ?? "")) { await resolve() }''', r'''        .overlay(alignment: .topTrailing) { GMLaunchBadge(chain: chain, address: address, dex: dex, size: size) }
        .task(id: key + "|" + (hint ?? "")) { await resolve() }''')

    UT = 'ios/App/UnifiedToken.swift'
    rep('g19_ut_state', UT, r'''    @AppStorage("tokTab", store: Cfg.defaults) private var tokTab = 0
''', r'''    @AppStorage("tokTab", store: Cfg.defaults) private var tokTab = 0
    @AppStorage("kMcap", store: Cfg.defaults) private var mcapMode = false
    @State private var openPage: Int?
    @State private var showMon = false
''')
    rep('g19_ut_title', UT, r'''        let p: String = m.price.map { Money.price($0) } ?? ""''', r'''        let p: String = GMPx.headline(m, mcap: mcapMode)''')
    rep('g19_ut_pagebody', UT, r'''    private var tabBody: some View {
        switch tokTab {''', r'''    private func pageBody(_ t: Int) -> some View {
        switch t {''')
    rep('g19_ut_content', UT, r'''            tabBar.padding(.horizontal, 16)
        }
        Group {
            tabBody.padding(.horizontal, 16)
        }
    }''', r'''            GMFuncGrid(vm: vm, onOpen: { i in
                if i == 99 { showMon = true } else { openPage = i }
            }).padding(.horizontal, 16)
            GMTradesMini(vm: vm, onMore: { openPage = 1 }).padding(.horizontal, 16)
        }
    }

    // 分析数据都放进各自的新页面（综合研判 / 成交池子 / 持有筹码 / 合约安全 / 叙事社交 / 庄家情报 / 工具）
    private func analysisPage(_ i: Int) -> some View {
        ScrollView {
            VStack(spacing: 14) { pageBody(i) }
                .padding(16)
        }
        .background(Color.page)
        .navigationTitle(i < tabNames.count ? tabNames[i] : "分析")
        .navigationBarTitleDisplayMode(.inline)
    }''')
    rep('g19_ut_nav', UT, r'''            .sheet(isPresented: $showDash) { DashboardView() }''', r'''            .sheet(isPresented: $showDash) { DashboardView() }
            .sheet(isPresented: $showMon) { MonitorSheet() }
            .navigationDestination(item: $openPage) { i in analysisPage(i) }
            .onReceive(NotificationCenter.default.publisher(for: .tstzmOpenPage)) { n in
                if let i = n.object as? Int { openPage = i }
            }
            .onChange(of: vm.main?.price) { _, _ in GMPx.sync(vm.main) }
            .onAppear { GMPx.sync(vm.main) }''')

    PC = 'ios/App/ProChart.swift'
    rep('g19_pc_sel', PC, r'''            KLineDetailCard(vm: vm, cvm: cvm).padding(.horizontal, 16)''', r'''            GMKSelBar(vm: vm, cvm: cvm).padding(.horizontal, 16)''')
    rep('g19_pc_hdr', PC, r'''CompactHeader(vm: vm, embedded: true).padding(.horizontal, 14)''', r'''GMHeader(vm: vm).padding(.horizontal, 14)''')
    rep('g19_pc_full', PC, r'''        .fullScreenCover(isPresented: $showFull) { fullCover }''', r'''        .fullScreenCover(isPresented: $showFull) { GMFullChart(vm: vm, cvm: cvm, onFail: { webFailed = true }) }''')

    AP = 'ios/App/TSTZMApp.swift'
    rep('g19_app_delegate', AP, r'''    @Environment(\.scenePhase) private var phase
''', r'''    @Environment(\.scenePhase) private var phase
    @UIApplicationDelegateAdaptor(TSTZAppDelegate.self) private var appDelegate
''')
    rep('g19_app_tab', AP, r'''                .tag(0)
            WalletsRoot()''', r'''                .tag(0)
            GMFavoritesRoot()
                .tabItem { Label("收藏", systemImage: "star") }
                .tag(2)
            WalletsRoot()''')

    # 价格/市值统一：代币相关页面里的币价文本全部走 GMPx.tp（市值模式下自动换成市值）
    for f in ['UnifiedToken', 'ProChart', 'DeepAnalysis', 'FlowIntel', 'LifeSocial']:
        sub_all(rep, 'g19_px_' + f, 'ios/App/' + f + '.swift', 'Money.price(', 'GMPx.tp(')
