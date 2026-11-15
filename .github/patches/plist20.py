# 2026-11-15 第二轮：紧凑首屏、真实图标、数据条、收藏分组、提醒进设置、下拉刷新动画
import re
import subprocess


def tol_sub(rep, tag, p, pattern, repl):
    # 正则替换：没匹配到就跳过（只用于不影响编译的外观调整）
    g = rep.__globals__
    if tag in g['applied'] or p in g['bad']:
        return
    t = g['load'](p)
    n, c = re.subn(pattern, repl, t, flags=re.M)
    if c < 1:
        return
    g['files'][p] = n
    g['done'].setdefault(p, []).append(tag)


def register(rep, cut):
    # 0) 抿真实的链 / 发射台 / DEX 图标（已有的跳过，失败不影响构建）
    try:
        r = subprocess.run(['bash', 'ios/tools/fetch_logos.sh'], capture_output=True, text=True, timeout=420)
        print('LOGOS:\n' + r.stdout[-3500:])
        if r.stderr:
            print(r.stderr[-400:])
    except Exception as e:
        print('LOGO_FETCH_ERROR', e)

    FAV = 'ios/App/Favorites.swift'
    rep('g20_fav_fields', FAV, r'''    var change5m: Double?
    var id: String { chain + ":" + address.lowercased() }''', r'''    var change5m: Double?
    var group: String?
    var note: String?
    var vols: [String: Double]?
    var txs: [String: Int]?
    var chgs: [String: Double]?
    var id: String { chain + ":" + address.lowercased() }''')
    rep('g20_fav_notify', FAV, r'''        let c = UNMutableNotificationContent()
        c.title = it.symbol + " 监控提醒"''', r'''        if (Cfg.defaults.object(forKey: "alertCh.local") as? Bool) == false { return }
        let c = UNMutableNotificationContent()
        c.title = it.symbol + " 监控提醒"''')

    AV = 'ios/App/Avatars.swift'
    rep('g20_av_chain', AV, r'''            GMChainGlyph(chain: chain, size: size)''', r'''            GMChainLogo(chain: chain, size: size)''')

    MK = 'ios/App/GMMarks.swift'
    rep('g20_mk_launch', MK, r'''            GMLaunchMark(pad: p, size: d)
''', r'''            GMLaunchLogo(pad: p, size: d)
''')

    LK = 'ios/App/LogoKit.swift'
    rep('g20_lk_old', LK, r'''struct LogoRefreshHook: UIViewRepresentable {''', r'''struct LogoRefreshHookOld: UIViewRepresentable {''')
    rep('g20_lk_coin', LK, r'''        let w: CGFloat = size * 0.8
        return base(w)''', r'''        let w: CGFloat = size * 0.9
        return base(w)''')
    rep('g20_lk_flip', LK, r'''        let flip: Double = spinning ? sin(t * 2.4) * 58.0 : p * 270.0''', r'''        let flip: Double = spinning ? sin(t * 2.2) * 36.0 : p * 270.0''')

    UT = 'ios/App/UnifiedToken.swift'
    rep('g20_ut_state', UT, r'''    @State private var showMon = false
''', r'''    @State private var showMon = false
    @State private var showSearch = false
''')
    rep('g20_ut_top', UT, r'''                    VStack(spacing: 10) {
                        inputCard
                        FavBar(vm: vm)
                    }
                    .padding(.horizontal, 16)
''', r'''                    if vm.main == nil {
                        VStack(spacing: 10) {
                            inputCard
                            FavBar(vm: vm)
                        }
                        .padding(.horizontal, 16)
                    }
''')
    rep('g20_ut_pad', UT, r'''                .padding(.vertical, 12)
                .background(LogoRefreshHook {''', r'''                .padding(.top, 2)
                .padding(.bottom, 12)
                .background(LogoRefreshHook {''')
    rep('g20_ut_fresh', UT, r'''            FreshnessRow(vm: vm).padding(.horizontal, 16)
''', '')
    rep('g20_ut_tool', UT, r'''                ToolbarItem(placement: .topBarLeading) {
                    Button { showDash = true } label: { Image(systemName: "gauge.with.dots.needle.67percent") }
                }''', r'''                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { showDash = true } label: { Image(systemName: "gauge.with.dots.needle.67percent") }
                    if vm.main != nil {
                        Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                    }
                }''')
    rep('g20_ut_sheet', UT, r'''            .sheet(isPresented: $showMon) { MonitorSheet() }
''', r'''            .sheet(isPresented: $showMon) { MonitorSheet() }
            .sheet(isPresented: $showSearch) { GMSearchSheet(vm: vm, hist: $hist) }
''')

    PC = 'ios/App/ProChart.swift'
    tol_sub(rep, 'g20_pc_h', PC, r'\.frame\(height: KHero\.chartHeight\)', '.frame(height: GMLayout.chartHeight)')
    tol_sub(rep, 'g20_pc_status', PC, r'^[ \t]*Text\(cvm\.statusText\)[^\n]*\n', '')
    tol_sub(rep, 'g20_pc_foot', PC, r'^[ \t]*Text\("K 线 GeckoTerminal[^\n]*\n', '')

    AP = 'ios/App/TSTZMApp.swift'
    rep('g20_app_alert', AP, r'''            AlertsView()
                .tabItem { Label("提醒", systemImage: "bell.badge") }
                .tag(3)
''', '')

    ST = 'ios/App/SettingsView.swift'
    rep('g20_set_sections', ST, r'''                Section("计价货币") {''', r'''                GMSettingsSections()
                Section("计价货币") {''')
