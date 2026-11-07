# 补丁清单（第六批）：土狗终端头部、叙事分析接入、钱包入口合并（去掉重复的「情报」标签页）、启动即刷新旧数据、K 线标记防重叠
def register(rep, cut):
    U = 'ios/App/UnifiedToken.swift'
    rep('tok_header', U, '            headerCard\n            FreshnessRow(vm: vm)\n', '            TerminalHeader(vm: vm)\n            FreshnessRow(vm: vm)\n')
    rep('tok_narr', U, '            KLineCard(vm: vm)\n            ReportCard(vm: vm)\n', '            KLineCard(vm: vm)\n            NarrativeRulesCard(vm: vm)\n            ReportCard(vm: vm)\n')

    A = 'ios/App/TSTZMApp.swift'
    rep('app_tab_intel_rm', A, '            IntelRoot() // 情报：钱包标签 + 行为信号 + 持有人全查\n                .tabItem { Label("情报", systemImage: "person.crop.rectangle.stack") }\n                .tag(5)\n', '')

    C = 'ios/App/CexView.swift'
    rep('cex_detail_intel', C,
        '        WalletDetailView(wallet: w, result: result)\n            .task {\n',
        '        WalletDetailView(wallet: w, result: result)\n            .toolbar {\n                if Addr.isSolana(target.address) && !Addr.isEVM(target.address) {\n                    ToolbarItem(placement: .topBarTrailing) {\n                        NavigationLink { SolIntelPage(address: target.address) } label: { Label("情报", systemImage: "person.crop.rectangle.stack") }\n                    }\n                }\n            }\n            .task {\n')
    rep('cex_mywallets_var', C,
        '    private func chainsFor(_ a: String) -> [String] {\n',
        '    private var myWallets: [Wallet] { Cfg.wallets }\n\n    private func chainsFor(_ a: String) -> [String] {\n')
    rep('cex_mywallets_sec', C,
        '                Section {\n                    if hist.isEmpty { Text("还没有查询记录").foregroundStyle(.secondary) }\n',
        '                if !myWallets.isEmpty {\n                    Section("我的钱包（点一下查询）") {\n                        ForEach(myWallets) { w in\n                            Button { open(w.address) } label: {\n                                HStack {\n                                    Text(w.label.isEmpty ? "钱包" : w.label).foregroundStyle(Color.primary)\n                                    Spacer()\n                                    Text(Addr.short(w.address)).font(.caption.monospaced()).foregroundStyle(.secondary)\n                                }\n                            }\n                        }\n                    }\n                }\n                Section {\n                    if hist.isEmpty { Text("还没有查询记录").foregroundStyle(.secondary) }\n')
    rep('cex_hint', C, 'Section("查询任意钱包地址（Solana / EVM 自动识别）") {', 'Section("查询任意钱包地址（Solana / EVM 自动识别；Solana 结果页右上角有「情报」）") {')

    P = 'ios/App/ProChart.swift'
    rep('kl_marks_limit', P, '        cvm.extraMarks = Array(marks.prefix(40))\n', '        cvm.extraMarks = Array(marks.prefix(16))\n')
    rep('kl_footnote', P,
        'Text("来源 GeckoTerminal 最深池子 · 主图可叠加多个指标，副图单选 · 绿/红箭头 = 该根里的大额买/卖，圆点 #n = 已拆解的第 n 大持有人的成交 · 市值 = 价格 × 当前供应量（按现在的市值÷现价折算）· 点一根 K 线选中，再点取消 · 往左拖自动补历史").font(.caption2).foregroundStyle(.secondary)',
        'Text("来源 GeckoTerminal · 箭头 = 大额买卖，圆点 #n = 第 n 大持有人的成交 · 点 K 线选中，再点取消").font(.caption2).foregroundStyle(.secondary)')

    M = 'ios/App/UnifiedTokenModel.swift'
    rep('model_stale_refresh', M,
        '            apply(s)\n            input = s.address\n        }\n    }\n',
        '            apply(s)\n            input = s.address\n            Task { @MainActor [weak self] in\n                try? await Task.sleep(nanoseconds: 800_000_000)\n                self?.refreshIfStale()\n            }\n        }\n    }\n\n    // 打开 App 时，如果恢复出来的是旧数据，立刻在后台刷新（旧数据先显示，带时间）\n    func refreshIfStale() {\n        guard !address.isEmpty, !pairs.isEmpty else { return }\n        let age = stamps.pairs.map { Date().timeIntervalSince($0) } ?? 9999\n        if age > 45 { start(address) }\n    }\n')

    N = 'ios/App/NarrativeEngine.swift'
    rep('narr_guard', N, '        guard let b = p.baseToken, let a = b.address, !a.isEmpty else { return nil }\n', '        guard let b = p.baseToken else { return nil }\n        let a: String = p.baseToken?.address ?? ""\n        if a.isEmpty { return nil }\n')

    T = 'ios/App/TerminalHeader.swift'
    rep('th_pair', T, '        if let p = m.pairAddress, let u = URL(string: cat("https://dexscreener.com/", cid, "/", p)) { out.append(("Dexscreener", u)) }\n', '        let pa: String? = m.pairAddress\n        if let p = pa, let u = URL(string: cat("https://dexscreener.com/", cid, "/", p)) { out.append(("Dexscreener", u)) }\n')
    rep('th_dex', T, '                        if let d = m.dexId { chip(d, Color.gray) }\n', '                        if let d = dexName(m) { chip(d, Color.gray) }\n')
    rep('th_dexfn', T, '    private func safetyChips() -> [(String, Color)] {\n', '    private func dexName(_ m: DexPair) -> String? {\n        let d: String? = m.dexId\n        return d\n    }\n\n    private func safetyChips() -> [(String, Color)] {\n')
    rep('th_task', T, '            .task { if vm.rows.isEmpty || vm.rows.first.map({ _ in false }) ?? true { await vm.runBatch(holders: tok.holders) } }\n', '            .task { if vm.rows.isEmpty { await vm.runBatch(holders: tok.holders) } }\n')
