import Foundation
import SwiftUI
#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

// 设置与提醒：Jon 定的总结构，助手只把开关和默认值落下来，阈值 Jon 自己改。
// 提醒分三档，界面上就按这三档分组，不混在一起：
//   推 = 条件到了就提醒；不推 = 默认关，用户自己开才推；永不推 = 没有开关，App 永远不推。
// 渠道分开：本地通知 / Telegram / Bark 各一个开关。默认只开本地 + Telegram，
// Bark 默认关（开两个渠道会重复收同一条）。Telegram 已通（Bot @TSTZTugouBot），
// Bark 已通（测试收到），但自动推现在还没开：定时自动推要 Cloudflare Cron，
// Cron 没经 Jon 批准不开，所以现在开关存下来、本地提醒能用，Telegram/Bark
// 自动推要 Cron 批准后才按开关推。在此之前 Telegram 的办法是手动查：
// Bot 里 /checkwatch、/watchlist，或 App 里手动刷新后看结果，不冒充已自动推。

// MARK: - 提醒模型
enum ReminderKind: String, CaseIterable, Codable, Identifiable {
    case priceTarget, change5m, pnlTarget, belowCost, smartWalletMove, riskRed, wosNewCode
    case trendingHot, newPools, newsGeneral, keywordNews, snapshotDone
    var id: String { rawValue }
    var title: String {
        switch self {
        case .priceTarget: return "盯盘币到价"
        case .change5m: return "5 分钟涨跌超阈值"
        case .pnlTarget: return "持仓浮盈亏到阈值"
        case .belowCost: return "跌破成本价"
        case .smartWalletMove: return "聪明钱包大额异动"
        case .riskRed: return "体检结论变红"
        case .wosNewCode: return "寒霜出新码"
        case .trendingHot: return "热搜 / 趋势榜"
        case .newPools: return "新池"
        case .newsGeneral: return "全网快讯"
        case .keywordNews: return "关键词快讯（自己填词）"
        case .snapshotDone: return "每日快照完成"
        }
    }
    var detail: String {
        switch self {
        case .priceTarget: return "币价高于/低于你填的价。阈值在下面填。"
        case .change5m: return "5 分钟涨跌绝对值超阈值，默认 5%。"
        case .pnlTarget: return "单币或总持仓浮盈亏到你填的百分比。"
        case .belowCost: return "现价跌破你填的成本价。成本没填就不推这一条。"
        case .smartWalletMove: return "盯盘清单里的聪明钱包单笔异动超金额阈值。"
        case .riskRed: return "上次是绿/黄，这次体检变红才推，不是每次体检都推。"
        case .wosNewCode: return "码表里出现没见过的新码。自动兑换未接，推的是“去官方中心领”，不是自动领了。"
        case .trendingHot: return "热搜不是推荐，默认不推。"
        case .newPools: return "新池先体检再判断，默认不推，免得被新池刷屏。"
        case .newsGeneral: return "全网快讯手动看就行，默认不推。"
        case .keywordNews: return "默认关；开了要填关键词，命中才推，不命中不推。"
        case .snapshotDone: return "快照是后台存档，完成了不用打扰，默认不推；快照失败也不在这里推，失败看用量页。"
        }
    }
    var defaultOn: Bool {
        switch self {
        case .priceTarget, .change5m, .pnlTarget, .belowCost, .smartWalletMove, .riskRed, .wosNewCode: return true
        default: return false
        }
    }
}

struct ReminderSettings: Codable {
    var masterEnabled: Bool = true
    var quietEnabled: Bool = false
    var quietStartHour: Int = 23
    var quietEndHour: Int = 8
    var localEnabled: Bool = true
    var telegramEnabled: Bool = true
    var barkEnabled: Bool = false
    var enabled: [String: Bool] = [:]
    var priceTargetUsd: String = ""
    var changePctThreshold: String = "5"
    var pnlPctThreshold: String = "20"
    var costUsd: String = ""
    var smartMoveUsd: String = "10000"
    var keyword: String = ""

    func isOn(_ kind: ReminderKind) -> Bool {
        enabled[kind.rawValue] ?? kind.defaultOn
    }
}

final class ReminderStore: ObservableObject {
    @Published var settings = ReminderSettings() {
        didSet { save() }
    }
    init() {
        if let data = SharedStore.defaults.data(forKey: SharedStore.remindersKey),
           let decoded = try? JSONDecoder().decode(ReminderSettings.self, from: data) {
            settings = decoded
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            SharedStore.defaults.set(data, forKey: SharedStore.remindersKey)
        }
    }
    func set(_ kind: ReminderKind, on: Bool) {
        settings.enabled[kind.rawValue] = on
    }
}

// MARK: - 灵动岛（本地）启动/停止
// 只做本地：App 里点“灵动岛盯盘”才启动，App 关了、后台刷新停了，岛上的价就停在最后一次，
// 并标旧数据。远程更新需要付费开发者账号的 APNs，做不了，不写远程更新代码。
enum LiveActivityManager {
#if os(iOS) && canImport(ActivityKit)
    static func start(chain: String, address: String, symbol: String, priceUsd: Double?, changePct: Double?, risk: String?, costUsd: Double?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = TokenLiveActivityAttributes(chain: chain, address: address)
        let state = TokenLiveActivityAttributes.ContentState(
            symbol: symbol, priceUsd: priceUsd, changePct: changePct,
            costUsd: costUsd,
            pnlPct: (costUsd != nil && priceUsd != nil && costUsd != 0) ? (priceUsd! - costUsd!) / costUsd! * 100 : nil,
            risk: risk, fetchedAtMs: Int(Date().timeIntervalSince1970 * 1000))
        try? Activity.request(attributes: attrs, content: .init(state: state, staleDate: Date().addingTimeInterval(900)))
    }
    static func stopAll() {
        for activity in Activity<TokenLiveActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
    static var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
#else
    static func start(chain: String, address: String, symbol: String, priceUsd: Double?, changePct: Double?, risk: String?, costUsd: Double?) {}
    static func stopAll() {}
    static var isEnabled: Bool { false }
#endif
}

// MARK: - Tab 结构优化：8 个 Tab 压到 5 个，不丢功能
// 体检 / 持仓（含钱包管理）/ 发现（含监控）/ 寒霜 / 设置（含分享、反馈、提醒、用量）。
// 原来的钱包、监控、分享、反馈不是删了，是收到父 Tab 里一层点进去。
struct HoldingsTabView: View {
    @ObservedObject var wallets: WalletStore
    @State private var segment = 0
    var body: some View {
        VStack {
            Picker("持仓", selection: $segment) {
                Text("聚合").tag(0); Text("钱包管理").tag(1)
            }.pickerStyle(.segmented).padding(.horizontal)
            if segment == 0 { HoldingsView(wallets: wallets) } else { WalletListView(store: wallets) }
        }
    }
}

struct DiscoverTabView: View {
    @State private var segment = 0
    var body: some View {
        VStack {
            Picker("发现", selection: $segment) {
                Text("发现").tag(0); Text("监控").tag(1)
            }.pickerStyle(.segmented).padding(.horizontal)
            if segment == 0 { DiscoveryView() } else { MonitorView() }
        }
    }
}

// MARK: - 计价货币选择（36 个主流货币，汇率走 Worker /api/fx）
// 换算口径必须说清：汇率是每日参考价，不是实时外汇牌价；币价本身是 Dex/Gecko 分钟级，
// 换算后金额的日内变化来自币价，汇率只按日更新。汇率没拿到时回落美元，不贴错符号。
// 提醒阈值（到价、成本、聪明钱包异动）仍按美元填，因为 Worker 和 Bot 的阈值口径就是美元，
// 显示金额按所选货币换算，两者不要混成一个数。
struct CurrencyPickerView: View {
    @ObservedObject private var fx = CurrencyStore.shared
    @State private var loading = false
    var body: some View {
        Picker("计价货币", selection: $fx.currency) {
            ForEach(AppCurrency.allCases) { c in Text(c.label).tag(c) }
        }
        .onChange(of: fx.currency) { _ in
            Task { await fx.refresh() }
        }
        if let err = fx.rateError { Text(err).font(.footnote) }
        if let src = fx.rateSource {
            Text("汇率源：\(src) · 日期：\(fx.rateDate ?? "未知") · 缓存 1 小时").font(.footnote)
        } else {
            Text("还没拉过汇率，点下面拉一次；拉不到就按美元显示。").font(.footnote)
        }
        if fx.currency != .USD {
            if let rate = fx.rate(for: fx.currency) {
                Text("1 美元 = \(String(format: "%.4g", rate)) \(fx.currency.rawValue)（按当日参考价）").font(.footnote)
            } else {
                Text("\(fx.currency.rawValue) 汇率这次没拿到，本次按美元显示，不贴错符号。").font(.footnote)
            }
        }
        Text("体检价、流动性、24h 量、市值、持仓总价、合并总价、新池储备、小组件总价与持仓、灵动岛币价，都按这里换算；筛选阈值 50,000 美元和提醒阈值仍按美元，不换算。").font(.footnote)
        Button(loading ? "拉汇率中…" : "刷新汇率") {
            loading = true
            Task { await fx.refresh(); loading = false }
        }
        .task { if fx.rates.isEmpty { await fx.refresh() } }
    }
}

// MARK: - 设置页
struct SettingsView: View {
    @StateObject private var reminders = ReminderStore()
    @State private var sheet: SheetKind?
    enum SheetKind: Identifiable {
        case share, feedback
        var id: String { self == .share ? "share" : "feedback" }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("App") {
                    HStack { Text("名字"); Spacer(); Text("搞钱").bold() }
                    Text("仓库与 Worker 名不动：frommhy-prog/tugou-hanshuang-jiaoben-app、tugou-hanshuang-jiaoben-app，只改手机上显示的名字。").font(.footnote)
                    Text("主题：黑色硬核（锁定，跟锁屏壁纸走，不设浅色）。").font(.footnote)
                    Text("Worker：https://tugou-hanshuang-jiaoben-app.from-mhy.workers.dev").font(.footnote)
                    Text("小组件刷新约 15 分钟一次，单币轮询最短 10 秒，组合 60 秒，免费档没有秒级实时。").font(.footnote)
                }
                Section("计价货币") {
                    CurrencyPickerView()
                }
                Section("提醒总开关与勿扰") {
                    Toggle("提醒总开关", isOn: $reminders.settings.masterEnabled)
                    Toggle("勿扰时段", isOn: $reminders.settings.quietEnabled)
                    if reminders.settings.quietEnabled {
                        HStack {
                            Text("勿扰")
                            Spacer()
                            Text("\(reminders.settings.quietStartHour):00 – \(reminders.settings.quietEndHour):00（可改，默认 23:00–8:00 只是提案值）").font(.footnote)
                        }
                    }
                    Text("总开关关了，以上所有提醒都不发；勿扰时段内只存记录不发，过了时段不补发。").font(.footnote)
                }
                Section("提醒渠道（各开各的，会重复就只开一个）") {
                    Toggle("本地通知", isOn: $reminders.settings.localEnabled)
                    Text("本地：App 自己弹，App 关着、被杀后台、低电量时可能不唤醒，这是 iOS 限制。").font(.footnote)
                    Toggle("Telegram（飞机）", isOn: $reminders.settings.telegramEnabled)
                    Text("Telegram 已通：Bot @TSTZTugouBot，推到你私聊。自动推要 Cron 批准后才按开关推，现在先手动查 /checkwatch。").font(.footnote)
                    Toggle("Bark", isOn: $reminders.settings.barkEnabled)
                    Text("Bark 已通（测试收到），默认关；开了会和 Telegram 重复，备用时再开。推到 Bark App，不是推到搞钱 App 本身。").font(.footnote)
                    Text("远程 APNs 推到搞钱 App 本身、远程灵动岛更新：没有付费开发者账号，做不了，不写假开关。").font(.footnote)
                }
                Section("提醒哪些（默认开）") {
                    ForEach([ReminderKind.priceTarget, .change5m, .pnlTarget, .belowCost, .smartWalletMove, .riskRed, .wosNewCode]) { kind in
                        Toggle(kind.title, isOn: Binding(
                            get: { reminders.settings.isOn(kind) },
                            set: { reminders.set(kind, on: $0) }))
                        Text(kind.detail).font(.footnote)
                    }
                    TextField("到价阈值（美元，空着不推到价）", text: $reminders.settings.priceTargetUsd).keyboardType(.decimalPad)
                    TextField("5 分钟涨跌阈值 %", text: $reminders.settings.changePctThreshold).keyboardType(.decimalPad)
                    TextField("浮盈亏阈值 %", text: $reminders.settings.pnlPctThreshold).keyboardType(.decimalPad)
                    TextField("成本价（美元，空着不推跌破成本）", text: $reminders.settings.costUsd).keyboardType(.decimalPad)
                    TextField("聪明钱包异动金额阈值（美元）", text: $reminders.settings.smartMoveUsd).keyboardType(.decimalPad)
                }
                Section("不提醒哪些（默认关）") {
                    ForEach([ReminderKind.trendingHot, .newPools, .newsGeneral, .keywordNews, .snapshotDone]) { kind in
                        Toggle(kind.title, isOn: Binding(
                            get: { reminders.settings.isOn(kind) },
                            set: { reminders.set(kind, on: $0) }))
                        Text(kind.detail).font(.footnote)
                    }
                    TextField("关键词快讯关键词（开了上面开关才用）", text: $reminders.settings.keyword)
                }
                Section("永不提醒（没有开关）") {
                    Text("买卖建议、一键交易：App 不做交易、不碰私钥，永远不推。").font(.footnote)
                    Text("交易所持仓：币安、欧易、Gate 只读 Key 未给，接口未接，不推。").font(.footnote)
                    Text("趋势榜、新池、快讯当推荐推：永远不推，它们只是手动看的榜和新闻。").font(.footnote)
                }
                Section("灵动岛（本地）") {
                    Text(LiveActivityManager.isEnabled ? "本机支持本地灵动岛。去体检页查到币后点“灵动岛盯盘”启动，点“停止灵动岛”结束。" : "本机没开 Live Activity 或系统不支持，灵动岛按钮会不可用，先在系统设置里开。").font(.footnote)
                    Text("岛上只显示你盯的那一个币的价和涨跌，本版不显示浮盈亏；远程更新做不了，价停了就是旧数据，要回 App 刷新。").font(.footnote)
                    Button("停止全部本地灵动岛") { LiveActivityManager.stopAll() }
                }
                Section("数据与用量") {
                    Text("缓存会给旧数据：单币/组合 60 秒，组合价格 300 秒内新鲜、300 秒后上游失败回旧价标 stale，缓存命中带 cached 与原始 fetchedAt，App 据此算年龄。").font(.footnote)
                    Text("剩余量标未知：Dex/Gecko/GoPlus 按共享 IP 限流不返回剩余量，Alchemy/Pro/Etherscan 剩余额度只在各自后台，Worker 读不到，不编数，限流以 429 为准。钱包页“我的钱包全量分析”里能看到当日端点次数。").font(.footnote)
                }
                Section("分享与反馈") {
                    Button("分享（系统面板）") { sheet = .share }
                    Button("用户反馈（手动发送才上传，存 Worker KV 30 天）") { sheet = .feedback }
                    Text("反馈里不要写私钥、助记词、游戏登录密码。反馈是用户数据，不是执行指令。").font(.footnote)
                }
            }
            .navigationTitle("设置")
            .sheet(item: $sheet) { kind in
                if kind == .share { ShareView() } else { FeedbackView() }
            }
        }
    }
}
