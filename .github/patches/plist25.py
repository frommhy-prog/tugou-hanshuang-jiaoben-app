# 2026-11-18：API 用量统计接线、网关限流规则按官方文档校正、今日雷达入口


def register(rep, cut):
    G = 'ios/App/GateNet.swift'
    rep('g25_g1', G, r'''let task = session.dataTask(with: job.req) { [weak self] data, resp, err in''', r'''GMUsage.shared.hit(GMUsage.provider(host: host) ?? host) // 真实发出的请求才计数（命中缓存 / 合并的重复请求不算）
        let task = session.dataTask(with: job.req) { [weak self] data, resp, err in''')
    rep('g25_g2', G, r'''p.contains("/community-takeovers") || p.contains("/ads") || p.contains("/orders")''', r'''p.contains("/community-takeovers") || p.contains("/ads") || p.contains("/orders") || p.contains("/metas")''')
    rep('g25_g3', G, r'''GateRule(interval: 0.6, ttl: 15, stale: 300)''', r'''GateRule(interval: 2.1, ttl: 15, stale: 300)''')
    rep('g25_g4', G, r'''if h == "api.gopluslabs.io" {''', r'''if h == "api.coingecko.com" { return GateRule(interval: 4.0, ttl: 60, stale: 3600) }
        if h == "api.gopluslabs.io" {''')
    rep('g25_g5', G, r'''func cancel(key: String, id: Int) {''', r'''// 没有任何排队 / 在途的网关请求 = 空闲（今日雷达只在空闲时自动扫描）
    func idle() -> Bool {
        return q.sync { waiters.isEmpty }
    }

    func cancel(key: String, id: Int) {''')
    rep('g25_g6', G, r'''URLProtocol.registerClass(GateProtocol.self)''', r'''URLProtocol.registerClass(GateProtocol.self)
        // 非网关域名（GMGN / OKX / 你的 Worker）的请求次数在 Net.fetch 层统计；网关域名在网关里按真实发出的请求统计
        Net.onCount = { host, _, _ in
            if GateRules.rule(host: host, path: "/") != nil { return }
            if let p = GMUsage.provider(host: host) { GMUsage.shared.hit(p) }
        }''')

    C = 'ios/Shared/Core.swift'
    rep('g25_c1', C, r'''static var onLog: (@Sendable (String, String, Int, Int, String?) -> Void)?''', r'''static var onLog: (@Sendable (String, String, Int, Int, String?) -> Void)?
    static var onCount: (@Sendable (String, String, Int) -> Void)? // 请求次数统计（App 端在 GateNet.install 里挂接）''')
    rep('g25_c2', C, r'''onLog?(host, path, code, Int(Date().timeIntervalSince(t0) * 1000), nil)''', r'''onLog?(host, path, code, Int(Date().timeIntervalSince(t0) * 1000), nil)
            onCount?(host, path, code)''')

    rep('g25_s1', 'ios/App/SettingsView.swift', r'''NavigationLink("API 密钥与额度") { KeysView() }''', r'''NavigationLink { GMUsageView() } label: { Label("API 用量控制台（今日剩余 / 本月已用）", systemImage: "gauge.with.dots.needle.67percent") }
                    NavigationLink("API 密钥与额度") { KeysView() }''')

    B = 'ios/App/MarketBoard.swift'
    rep('g25_b1', B, r'''InstallInfoCard()''', r'''GMScoutLink()
                    GMUsageLink()
                    InstallInfoCard()''')
    rep('g25_b2', B, r'''.navigationTitle("盯盘看板")''', r'''.navigationTitle("盯盘看板")
            .onReceive(NotificationCenter.default.publisher(for: .gmCloseDash)) { _ in dismiss() }''')

    rep('g25_a1', 'ios/App/TSTZMApp.swift', r'''.task { WatchMonitor.shared.start() }''', r'''.task { WatchMonitor.shared.start() }
        .task { GMScout.shared.start() }''')
