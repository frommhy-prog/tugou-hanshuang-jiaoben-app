# 补丁清单（第九批）：去掉代币页重复的卡片与按钮、仪表盘改为代币页右上角入口（标签页超过 5 个会进「更多」，导致设置页出现两个返回按钮）、全局「全部刷新」、叙事与社交结果并入规则分析
def register(rep, cut):
    U = 'ios/App/UnifiedToken.swift'
    rep('u_rm_stats', U, '            statsGrid\n            insightsCard\n            PromoCard(vm: vm)\n', '            PromoCard(vm: vm)\n')
    rep('u_rm_links', U, '            securityCard\n            linksCard\n            AIFoldCard(vm: vm)\n', '            securityCard\n            AIFoldCard(vm: vm)\n')
    rep('u_rm_pill', U, '                    if vm.main != nil {\n                        Pill(text: vm.chain.title, color: Color.blue)\n                    }\n', '')
    rep('u_dash_state', U, '    @State private var showAlert = false\n', '    @State private var showAlert = false\n    @State private var showDash = false\n')
    rep('u_dash_toolbar', U, '            .sheet(isPresented: $shareSheet) { ShareSheet(items: shareItems) }\n', '            .toolbar {\n                ToolbarItem(placement: .topBarLeading) {\n                    Button { showDash = true } label: { Image(systemName: "gauge.with.dots.needle.67percent") }\n                }\n            }\n            .sheet(isPresented: $showDash) { DashboardView() }\n            .sheet(isPresented: $shareSheet) { ShareSheet(items: shareItems) }\n')
    rep('u_refreshable', U, '            .background(Color.page)\n            .navigationTitle("代币")\n', '            .background(Color.page)\n            .refreshable { vm.refreshAll(); try? await Task.sleep(nanoseconds: 800_000_000) }\n            .navigationTitle("代币")\n')

    A = 'ios/App/TSTZMApp.swift'
    rep('app_tab_dash_rm', A, '            DashboardView() // 仪表盘 + 控制台\n                .tabItem { Label("仪表盘", systemImage: "gauge.with.dots.needle.67percent") }\n                .tag(6)\n', '')

    D = 'ios/App/Dashboard.swift'
    rep('dash_nostack', D, '        NavigationStack {\n            ScrollView {', '        Group {\n            ScrollView {')

    M = 'ios/App/UnifiedTokenModel.swift'
    rep('m_refresh_field', M, '    @Published var analyzeTotal = 0\n', '    @Published var analyzeTotal = 0\n    @Published var refreshToken = 0\n')
    rep('m_refresh_fn', M, '        if age > 45 { start(address) }\n    }\n', '        if age > 45 { start(address) }\n    }\n\n    // 一个「全部刷新」：行情、成交、持有人、安全、AI 一起重读；叙事 / 社交 / 生命周期卡片也重新取\n    func refreshAll() {\n        guard !address.isEmpty else { return }\n        SocialCard.store = [:]\n        NarrativeRulesCard.store = [:]\n        LifecycleCard.store = [:]\n        refreshToken += 1\n        start(address)\n    }\n')

    L = 'ios/App/LifeSocial.swift'
    rep('ls_life_store', L, '    private static var store: [String: (LifeReport, Date)] = [:]\n', '    static var store: [String: (LifeReport, Date)] = [:]\n')
    rep('ls_life_key', L, '    private var key: String { cat(vm.chain.rawValue, ":", vm.main?.pairAddress ?? "") }\n', '    private var key: String { cat(vm.chain.rawValue, ":", vm.main?.pairAddress ?? "", "#", String(vm.refreshToken)) }\n')
    rep('ls_soc_store', L, '    private static var store: [String: SocialReport] = [:]\n', '    static var store: [String: SocialReport] = [:]\n')
    rep('ls_soc_key', L, '    private var key: String { cat(vm.chain.rawValue, ":", vm.address) }\n', '    private var key: String { cat(vm.chain.rawValue, ":", vm.address, "#", String(vm.refreshToken)) }\n')
    rep('ls_soc_btn', L, '                    Button("刷新") { Task { await load(force: true) } }.font(.caption)\n', '')
    rep('ls_soc_fact', L, '            facts.append(["官方链接", cat(types.isEmpty ? "无社交" : types, "；", webs.isEmpty ? "无官网" : cat(String(webs.count), " 个网站"))])\n', '')
    rep('ls_soc_notify', L, '        Self.store[key] = r\n        report = r\n        loading = false\n', '        Self.store[key] = r\n        report = r\n        loading = false\n        vm.objectWillChange.send()\n')

    N = 'ios/App/NarrativeEngine.swift'
    rep('ne_store', N, '    private static var store: [String: NarrReport] = [:]\n', '    static var store: [String: NarrReport] = [:]\n')
    rep('ne_key', N, '    private var key: String { cat(vm.chain.rawValue, ":", vm.address) }\n', '    private var key: String { cat(vm.chain.rawValue, ":", vm.address, "#", String(vm.refreshToken)) }\n')
    rep('ne_btn', N, '                    Button("刷新") { Task { await load(force: true) } }.font(.caption)\n', '')
    rep('ne_title', N, 'Label("叙事分析", systemImage: "text.book.closed").font(.headline)', 'Label("叙事 · 规则分析", systemImage: "text.book.closed").font(.headline)')
    rep('ne_allliq', N, '                guard let s = tok(p), s.liq >= 1_000 else { continue }\n', '                guard let s = tok(p) else { continue }\n')
    rep('ne_others', N,
        '        var others: [SimTok] = []\n        for (k, v) in seen where k.lowercased() != me.lowercased() { others.append(v) }\n        others.sort { $0.mc > $1.mc }\n        let top = Array(others.prefix(12))\n',
        '        var allOthers: [SimTok] = []\n        for (k, v) in seen where k.lowercased() != me.lowercased() { allOthers.append(v) }\n        let deadN = allOthers.filter { $0.liq < 1_000 }.count\n        let aliveN = allOthers.filter { $0.liq >= 20_000 }.count\n        var others = allOthers.filter { $0.liq >= 1_000 }\n        others.sort { $0.mc > $1.mc }\n        let top = Array(others.prefix(12))\n')
    rep('ne_survive', N,
        '        var heat = "平稳"\n',
        '        if !allOthers.isEmpty { items.append(["同名/同主题代币存活", cat("搜到 ", String(allOthers.count), " 个：", String(deadN), " 个流动性低于 $1,000（基本归零），", String(aliveN), " 个仍有 $20,000 以上（只统计当前还搜得到的，存活比例会被高估）")]) }\n        var heat = "平稳"\n')

    V = 'ios/App/Narrative.swift'
    rep('nv_title', V, 'Label("代币叙事", systemImage: "text.book.closed").font(.headline)', 'Label("叙事 · AI 归纳", systemImage: "sparkles").font(.headline)')
    rep('nv_nosim', V, '        await findSimilar(qs: Array(qs.prefix(3)), selfAddr: address)\n', '')
    cut('nv_cutsim', V,
        '                Divider()\n                Text("历史相似叙事：同名/同主题代币现在怎么样").font(.subheadline.weight(.semibold))\n',
        '            }\n        }\n        .task(id: chain.rawValue + address) { if AIMode.auto { await vm.load(chain: chain, address: address, main: main) } }\n',
        '')

    R = 'ios/App/ReportCard.swift'
    rep('rc_stage_rm', R,
        '                    HStack(alignment: .top, spacing: 8) {\n                        Text("阶段").font(.caption).foregroundStyle(.secondary)\n                        VStack(alignment: .leading, spacing: 2) {\n                            Text(r.stage).font(.subheadline.bold())\n                            if !r.stageBasis.isEmpty { Text(r.stageBasis).font(.caption2).foregroundStyle(.secondary) }\n                        }\n                    }\n',
        '')
    rep('rc_refresh_btn', R,
        '                    if vm.analyzing {\n                        Text("大户拆解 " + String(vm.analyzedDone) + "/" + String(vm.analyzeTotal)).font(.caption2).foregroundStyle(.secondary)\n                    }\n',
        '                    if vm.analyzing {\n                        Text("大户拆解 " + String(vm.analyzedDone) + "/" + String(vm.analyzeTotal)).font(.caption2).foregroundStyle(.secondary)\n                    }\n                    Spacer()\n                    Button("全部刷新") { vm.refreshAll() }.font(.caption2.weight(.semibold))\n')

    E = 'ios/App/AnalysisEngine.swift'
    rep('ae_social_merge', E,
        '            dims.append(Dim(id: "social", title: "官方信息", icon: "link", weight: 0.06, score: b.value, finds: b.finds, source: "Dexscreener 代币资料"))\n',
        '            if let sr = SocialCard.store[cat(vm.chain.rawValue, ":", vm.address, "#", String(vm.refreshToken))] {\n                for it in sr.items where it.level == "warn" { b.add("warn", 8, it.text, it.basis) }\n            }\n            dims.append(Dim(id: "social", title: "官方信息", icon: "link", weight: 0.06, score: b.value, finds: b.finds, source: "Dexscreener 资料 + X / Telegram / 域名"))\n')

    T = 'ios/App/TerminalHeader.swift'
    rep('th_nopct', T, '                    Spacer()\n                    Text(pct(h24)).font(.title3.bold()).foregroundStyle(col(h24))\n', '')
    rep('th_ratio_stat', T, '                    stat("前 10 持仓", vm.conc?.wallets10.map { String(format: "%.1f%%", Double($0)) } ?? "—")\n', '                    stat("流动性/市值", liqRatio(m))\n')
    rep('th_ratio_fn', T, '    private func dexName(_ m: DexPair) -> String? {\n', '    private func liqRatio(_ m: DexPair) -> String {\n        let mc: Double = m.marketCap ?? m.fdv ?? 0\n        if mc <= 0 || m.liq <= 0 { return "—" }\n        return String(format: "%.1f%%", m.liq / mc * 100)\n    }\n\n    private func dexName(_ m: DexPair) -> String? {\n')
    rep('th_externals', T,
        '        let bd: Set<String> = ["solana", "ethereum", "bsc", "base", "arbitrum", "optimism", "polygon", "avalanche"]\n',
        '        if let u = URL(string: cat("https://ave.ai/token/", a, "-", vm.chain == .eth ? "eth" : vm.chain.rawValue)) { out.append(("Ave", u)) }\n        if let u = URL(string: cat("https://x.com/search?q=", a)) { out.append(("X 搜索", u)) }\n        let bd: Set<String> = ["solana", "ethereum", "bsc", "base", "arbitrum", "optimism", "polygon", "avalanche"]\n')
