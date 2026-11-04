# 补丁清单（第三批）：网络请求日志钩子、情报与仪表盘标签页
def register(rep, cut):
    C = 'ios/Shared/Core.swift'
    rep('net_hook', C,
        '    static func fetch(_ req: URLRequest) async throws -> (Data, URLResponse) {\n        let task = Task.detached(priority: .userInitiated) { () throws -> (Data, URLResponse) in\n',
        '    static var onLog: (@Sendable (String, String, Int, Int, String?) -> Void)?\n    static var blocked: Set<String> = []\n\n    static func fetch(_ req: URLRequest) async throws -> (Data, URLResponse) {\n        let host = req.url?.host ?? "?"\n        let path = req.url?.path ?? ""\n        if blocked.contains(host) {\n            onLog?(host, path, 0, 0, "已在控制台切断（测试兜底）")\n            throw URLError(.cannotConnectToHost)\n        }\n        let t0 = Date()\n        do {\n            let r = try await fetchRaw(req)\n            let code = (r.1 as? HTTPURLResponse)?.statusCode ?? 0\n            onLog?(host, path, code, Int(Date().timeIntervalSince(t0) * 1000), nil)\n            return r\n        } catch {\n            onLog?(host, path, 0, Int(Date().timeIntervalSince(t0) * 1000), message(error))\n            throw error\n        }\n    }\n\n    static func fetchRaw(_ req: URLRequest) async throws -> (Data, URLResponse) {\n        let task = Task.detached(priority: .userInitiated) { () throws -> (Data, URLResponse) in\n')

    A = 'ios/App/TSTZMApp.swift'
    rep('app_install', A, '    init() { TZ.apply() } // 启动即应用统一时区\n', '    init() { TZ.apply(); SourceHub.install() } // 启动即应用统一时区，并开启请求日志\n')
    rep('app_tab_intel', A,
        '            WalletsRoot() // 钱包页：链上钱包 / 交易所 / 查询任意地址\n                .tabItem { Label("钱包", systemImage: "wallet.pass") }\n                .tag(1)\n',
        '            WalletsRoot() // 钱包页：链上钱包 / 交易所 / 查询任意地址\n                .tabItem { Label("钱包", systemImage: "wallet.pass") }\n                .tag(1)\n            IntelRoot() // 情报：钱包标签 + 行为信号 + 持有人全查\n                .tabItem { Label("情报", systemImage: "person.crop.rectangle.stack") }\n                .tag(5)\n')
    rep('app_tab_dash', A,
        '            FrostView()\n                .tabItem { Label("寒霜", systemImage: "snowflake") }\n                .tag(2)\n',
        '            FrostView()\n                .tabItem { Label("寒霜", systemImage: "snowflake") }\n                .tag(2)\n            DashboardView() // 仪表盘 + 控制台\n                .tabItem { Label("仪表盘", systemImage: "gauge.with.dots.needle.67percent") }\n                .tag(6)\n')
