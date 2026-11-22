import SwiftUI
import UIKit

// MARK: - 设置页重排：首页只放 8 个分类，点进去才是具体选项
struct SettingsView: View {
    private func row(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(Color.accentColor).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                EmptyView()
            }
        }
        .padding(.vertical, 2)
    }

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1") + ")"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("显示") {
                    NavigationLink { GXPageDisplay() } label: { row("paintbrush", "外观与显示", "主题 · 计价货币 · 时区 · 顶部数据条 · 分析分页") }
                    NavigationLink { GXPageApps() } label: { row("arrow.up.right.square", "跳转 App", "币安 · 欧易 · AVE · Gate · 海妖 · FOMO · GMGN …开关") }
                }
                Section("数据") {
                    NavigationLink { GXPageData() } label: { row("externaldrive.connected.to.line.below", "数据源与密钥", "GMGN · OKX Web3 · 免费数据源 · API 用量") }
                    NavigationLink { GXPageAI() } label: { row("sparkles", "AI 分析", "触发方式 · 额度") }
                }
                Section("互动") {
                    NavigationLink { GXPageShare() } label: { row("square.and.arrow.up", "分享", "分享哪些内容 · 联系方式") }
                    NavigationLink { GXPageAlerts2() } label: { row("bell.badge", "提醒", "") }
                    NavigationLink { GXScoutSettingsView() } label: { row("dot.radiowaves.left.and.right", "自动找币", "") }
                    NavigationLink { GXPageConnect() } label: { row("link", "连接", "服务令牌 · 连接测试") }
                }
                Section("其他") {
                    NavigationLink { FeedbackView() } label: { row("bubble.left.and.text.bubble.right", "反馈问题", "文字或文字加截图") }
                    HStack { Text("版本"); Spacer(); Text(version).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("设置")
        }
    }
}

// MARK: 外观与显示
struct GXPageDisplay: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("currency", store: Cfg.defaults) private var currency = "USD"
    @AppStorage("gxChip", store: Cfg.defaults) private var chip = "icon"
    @State private var tz = TZ.id
    @State private var showEditor = false

    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: $theme) {
                    Text("跟随系统").tag("system")
                    Text("日间").tag("light")
                    Text("夜间").tag("dark")
                }
                .pickerStyle(.segmented)
                NavigationLink {
                    CurrencyPicker(selected: $currency)
                } label: {
                    HStack { Text("计价货币"); Spacer(); Text(currency).foregroundStyle(.secondary) }
                }
            }
            Section("时间与时区") {
                Picker("时区", selection: $tz) {
                    ForEach(TZ.options, id: \.id) { o in Text(o.name).tag(o.id) }
                }
                .onChange(of: tz) { _, n in TZ.id = n }
                Text("全 App 的时间统一按此时区显示。当前 " + TZ.label + "，现在是 " + TZ.format(Date()) + "。").font(.caption).foregroundStyle(.secondary)
            }
            Section("代币页顶部数据条") {
                Picker("样式", selection: $chip) {
                    Text("紧凑图标（一屏约 7 个半）").tag("icon")
                    Text("文字详细").tag("text")
                }
                Button { showEditor = true } label: { Label("调整显示项和顺序", systemImage: "slider.horizontal.3") }
                Text("紧凑图标样式只显示 图标 + 数值，点任意一格进入详情；图标是 App 内统一的概念图标。").font(.caption).foregroundStyle(.secondary)
            }
            GMTabSettings()
        }
        .navigationTitle("外观与显示")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) { GMMetricEditor() }
    }
}

// MARK: 跳转 App
struct GXPageApps: View {
    @AppStorage("gxClip", store: Cfg.defaults) private var clip = true

    var body: some View {
        Form {
            Section("剪贴板") {
                Toggle("进入 App 自动检测剪贴板里的合约 / 钱包地址", isOn: $clip)
                Text("复制合约后切回 App 会弹出卡片（代币行情 / 钱包标签），一键去分析。首次会有系统的「允许粘贴」提示，选「始终允许」就不再打扰；在 iOS 设置 → TSTZ-M → 从其他 App 粘贴 里也能改。").font(.caption).foregroundStyle(.secondary)
            }
            Section("显示哪些 App 的跳转图标") {
                ForEach(GXApp.allCases) { a in GXAppToggleRow(app: a) }
                Text("开关同时作用于：代币页头部图标、点代币头像的面板、钱包卡片、钱包地址长按菜单。币安 / 欧易 / AVE 链接按官网公开格式拼接，个别链打不开请反馈；Gate、海妖、FOMO 没有公开的代币页链接，点击会先复制地址再打开。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("跳转 App")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: 数据源与密钥
struct GXPageData: View {
    @AppStorage("gmgnKey", store: Cfg.defaults) private var gmgnKey = ""
    @State private var test: String?
    @State private var testing = false
    private let pubKey = "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAqnZdV/OvVE2OmSlRh/0JOrqeRF2YtiLe7IhCI0LmJHk=\n-----END PUBLIC KEY-----"

    private func testGMGN() async {
        testing = true
        test = nil
        let r = await GMGNApi.fetch("/v1/token/info", ["chain": "sol", "address": "So11111111111111111111111111111111111111112"])
        switch r {
        case .success: test = "GMGN 连接正常，代币页顶部数据条会自动带上 GMGN 的完整数据"
        case .failure(let e): test = e.localizedDescription
        }
        testing = false
    }

    var body: some View {
        Form {
            Section("现在没有任何 Key 也能拿到的数据") {
                Text("币安 Web3（持有者、前十、Dev、聪明钱 / KOL / 专业用户持仓、项目描述）· GoPlus · RugCheck · Honeypot.is · Jupiter · Blockscout · GeckoTerminal · Dexscreener，另外「大户情报」会用本机链上推算 狙击持仓、聪明钱、机器人、新钱包。填了 GMGN / OKX Key 则优先用它们。").font(.caption).foregroundStyle(.secondary)
            }
            Section("用量") {
                NavigationLink { GMUsageView() } label: { Label("API 用量控制台（今日剩余 / 本月已用）", systemImage: "gauge.with.dots.needle.67percent") }
                NavigationLink("API 密钥与额度") { KeysView() }
                NavigationLink { ConnectorsView() } label: { Label("MCP 连接器", systemImage: "puzzlepiece.extension") }
            }
            Section("GMGN 数据（免费 API Key，可选）") {
                SecureField(gmgnKey.isEmpty ? "粘贴 GMGN API Key" : "Key 已保存（粘贴新 Key 可替换）", text: $gmgnKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button("测试连接") { Task { await testGMGN() } }.disabled(testing || gmgnKey.isEmpty)
                    if testing { Spacer(); ProgressView() }
                }
                if let t = test { Text(t).font(.footnote).foregroundStyle(.secondary) }
                Text("获取方法：gmgn.ai/ai → 创建 API Key → 把下面这段公钥粘贴进去 → 把生成的 API Key 填到上面。GMGN 只支持 IPv4。").font(.caption).foregroundStyle(.secondary)
                Text(pubKey).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                Button("复制公钥") { UIPasteboard.general.string = pubKey }
            }
            GMFreeSettings()
        }
        .navigationTitle("数据源与密钥")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: AI
struct GXPageAI: View {
    @AppStorage("aiAuto", store: Cfg.defaults) private var aiAuto = true

    var body: some View {
        Form {
            Section("AI 触发方式") {
                Picker("触发方式", selection: $aiAuto) {
                    Text("自动").tag(true)
                    Text("手动").tag(false)
                }
                .pickerStyle(.segmented)
                Text("自动：查币、查钱包、停在 K 线上都自动请求 AI。手动：只在点按钮时请求，省 Groq 额度。规则分析引擎始终独立并行，不依赖 AI。").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink("API 密钥与额度（Groq 剩余次数）") { KeysView() }
            }
        }
        .navigationTitle("AI 分析")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: 分享
struct GXPageShare: View {
    var body: some View {
        Form {
            Section("分享链接 / 摘要卡里包含哪些内容") {
                ForEach(GXShareKey.allCases) { k in GXShareToggleRow(k: k) }
                Text("分享的是点击那一刻的全部最新数据和分析快照，网页按类别折叠；关掉的类别不会出现在链接里。").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ShareLink(item: "TSTZ-M：土狗体检 + 钱包 + 大户情报，一个 App 搞定") {
                    Label("分享 TSTZ-M", systemImage: "square.and.arrow.up")
                }
                NavigationLink { ContactSettingsView() } label: { Label("联系方式与分享设置", systemImage: "person.crop.rectangle") }
            }
        }
        .navigationTitle("分享")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: 提醒
struct GXPageAlerts: View {
    @AppStorage("alertCh.local", store: Cfg.defaults) private var chLocal = true
    @State private var tgOK: Bool?
    @State private var barkOK: Bool?
    @State private var pushInfo: String?
    @State private var showAlerts = false

    private func statusText(_ v: Bool?) -> String {
        guard let v = v else { return "读取中" }
        return v ? "已绑定·已开启" : "未绑定·未开启"
    }

    private func loadKeys() async {
        do {
            let k: KeysResponse = try await API.get("/v1/keys")
            let has = { (id: String) -> Bool in k.providers.first { $0.id == id }?.present ?? false }
            tgOK = has("telegram_token") && has("telegram_chat")
            barkOK = has("bark")
        } catch {
            tgOK = nil
            barkOK = nil
        }
    }

    private func testPush() async {
        struct R: Decodable { var telegram: Bool?; var bark: Bool? }
        do {
            let r: R = try await API.get("/v1/push/test")
            if r.telegram == nil && r.bark == nil { pushInfo = "还没配置推送通道" }
            else { pushInfo = "测试已发送：Telegram " + (r.telegram.map { $0 ? "成功" : "失败" } ?? "未配置") + "，Bark " + (r.bark.map { $0 ? "成功" : "失败" } ?? "未配置") }
        } catch { pushInfo = error.localizedDescription }
    }

    var body: some View {
        Form {
            Section("通道（可同时开启）") {
                Toggle("本地通知（App 在前台时监控收藏）", isOn: $chLocal)
                HStack { Text("Telegram 推送"); Spacer(); Text(statusText(tgOK)).font(.footnote).foregroundStyle(.secondary) }
                HStack { Text("Bark 推送"); Spacer(); Text(statusText(barkOK)).font(.footnote).foregroundStyle(.secondary) }
                NavigationLink("绑定 / 更换 Telegram 和 Bark") { KeysView() }
                Button("发送测试推送") { Task { await testPush() } }
                if let p = pushInfo { Text(p).font(.footnote).foregroundStyle(.secondary) }
            }
            Section("规则") {
                Button { showAlerts = true } label: { Label("我的提醒规则（价格、涨跌、流动性）", systemImage: "bell.badge") }
                Text("Telegram / Bark 绑定密钥就开启、删除密钥就关闭，由服务器每 5 分钟检查提醒规则并推送。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("提醒")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAlerts) { AlertsView() }
        .task { await loadKeys() }
    }
}

// MARK: 连接
struct GXPageConnect: View {
    @State private var tokenInput = ""
    @State private var pingText: String?
    @State private var testing = false

    private func test() async {
        testing = true
        if !tokenInput.trimmingCharacters(in: .whitespaces).isEmpty { Cfg.token = tokenInput; tokenInput = "" }
        do {
            let p: Ping = try await API.get("/v1/ping")
            var s: String = p.ok == true ? "连接正常" : "服务无响应"
            if let e = p.lastEval, let at = e.at {
                s += " · 提醒检查上次运行 " + TZ.format(Date(timeIntervalSince1970: at / 1000))
            } else {
                s += " · 提醒检查器已启动，约 5 分钟内首次运行"
            }
            pingText = s
        } catch { pingText = error.localizedDescription }
        testing = false
    }

    var body: some View {
        Form {
            Section("服务令牌") {
                SecureField(Cfg.token.isEmpty ? "粘贴令牌" : "令牌已保存（粘贴新令牌可替换）", text: $tokenInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button("保存并测试") { Task { await test() } }.disabled(testing)
                    if testing { Spacer(); ProgressView() }
                }
                if let p = pingText { Text(p).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("连接")
        .navigationBarTitleDisplayMode(.inline)
    }
}
