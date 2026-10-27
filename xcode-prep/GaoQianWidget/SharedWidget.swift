import Foundation
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

// 搞钱：App 在手机上显示的名字。仓库名 tugou-hanshuang-jiaoben-app 与
// Cloudflare 项目名 tugou-hanshuang-jiaoben-app 不动，只改用户看到的显示名。
// 旧的“土狗寒霜脚本app”不是 Jon 定的显示名，本文件起以“搞钱”为准，待 Jon 确认后在 Xcode 里把 Display Name 也改成搞钱。

// App Group 共享存储：App 与小组件读同一份数据。
// groupID 只是占位常量，不是已建好的真实 ID：在 Xcode Signing & Capabilities 里
// 新建同名 App Group 后核对这一处，两边共用这一个常量，不要各写各的。
// 建好前自动回落到 UserDefaults.standard，不丢钱包、不崩小组件。
enum SharedStore {
    static let groupID = "group.tugou-hanshuang-jiaoben-app"
    static let walletsKey = "tugou.wallets.v1"
    static let snapshotKey = "gaoqian.widget.snapshot.v1"
    static let remindersKey = "gaoqian.reminders.v1"

    static var defaults: UserDefaults {
        if let suite = UserDefaults(suiteName: groupID) { return suite }
        return .standard
    }

    // 从旧 standard 迁移一次：App Group 建好后第一次读到空，就把旧钱包拷过来。
    static func migrateWalletsIfNeeded() {
        let shared = defaults
        if shared.data(forKey: walletsKey) != nil { return }
        if let old = UserDefaults.standard.data(forKey: walletsKey) {
            shared.set(old, forKey: walletsKey)
        }
    }

    static func saveSnapshot(_ snapshot: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
    }

    static func loadSnapshot() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

// 小组件快照：只存 App 已经查到的真实数。没查到就是 nil，不编。
// App 在“我的钱包全量分析”成功后写一次；小组件只读快照，不自己调上游，
// 所以小组件不烧 Dex/Gecko 额度，也不把限流空回当成数据。
struct WidgetHolding: Codable, Hashable {
    var symbol: String?
    var usd: Double?
    var changePct: Double?
}

struct WidgetSnapshot: Codable {
    var fetchedAtMs: Int?
    var totalUsd: Double?
    var walletCount: Int?
    var topSymbol: String?
    var topSharePct: Double?
    var topChangePct: Double?
    var risk: String?
    var holdings: [WidgetHolding]?

    // 年龄：>15 分钟就是旧数据，小组件必须标出来，不能当现价。
    var ageText: String? {
        guard let ms = fetchedAtMs else { return nil }
        let ageSec = Int(Date().timeIntervalSince1970 * 1000 - Double(ms)) / 1000
        if ageSec < 60 { return "刚才同步" }
        if ageSec < 3600 { return "\(ageSec / 60) 分钟前" }
        return "\(ageSec / 3600) 小时前"
    }
    var isStale: Bool {
        guard let ms = fetchedAtMs else { return true }
        return Date().timeIntervalSince1970 * 1000 - Double(ms) > 900_000
    }
}

#if canImport(ActivityKit)
// 灵动岛（本地 Live Activity）：只在 App 里手动启动盯盘，价格更新靠 App 前台 /
// 后台刷新，不走远程 APNs。没有付费开发者账号，远程灵动岛更新本来就做不了，
// 这里不冒充远程更新。成本与浮盈亏只有用户在盯盘时填了成本才显示，没填就不显示。
struct TokenLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var symbol: String
        var priceUsd: Double?
        var changePct: Double?
        var costUsd: Double?
        var pnlPct: Double?
        var risk: String?
        var fetchedAtMs: Int?
    }
    var chain: String
    var address: String
}
#endif

// 壁纸语言（两张壁纸共用一套黑底硬核，不各搞一套花色）：
// 黑底 + 灰字 + 白字重点，涨跌才用绿/红。锁屏小组件 iOS 会强制单色渲染，
// 所以锁屏款不靠颜色区分涨跌，靠 ▲▼ 符号；桌面款可以用绿/红。
enum WallpaperStyle {
    static let background = Color.black
    static let card = Color(white: 0.08)
    static let border = Color(white: 0.30)
    static let grayText = Color(white: 0.55)
    static let whiteText = Color.white
    static let up = Color.green
    static let down = Color.red
}
