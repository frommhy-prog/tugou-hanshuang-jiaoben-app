import Foundation
import SwiftUI

// 计价货币：App 里所有金额都从美元换算过来，不在各处硬编码 $。
// 汇率来自 Worker /api/fx（免 Key，每日参考价，KV 缓存 1 小时），不是实时外汇牌价，
// 这一点在设置页明说。汇率没拿到、或所选货币没有汇率时，一律回落美元，
// 绝不把美元数直接贴上人民币/欧元符号。
// 列表是主流货币，不是 160 个全量：全量表在 Worker 返回里，App 只列常用的 36 个，
// 再多 picker 就翻不动了；不在列表里的币，Worker 有汇率也先不进 picker，不冒充全覆盖。

enum AppCurrency: String, CaseIterable, Codable, Identifiable {
    case USD, CNY, EUR, GBP, JPY, KRW, CAD, AUD, HKD, TWD, SGD, CHF, NZD
    case INR, BRL, MXN, THB, MYR, IDR, PHP, VND, AED, SAR, PLN, SEK, NOK, DKK
    case CZK, HUF, ILS, ZAR, TRY, RUB
    var id: String { rawValue }
    var name: String {
        switch self {
        case .USD: return "美元"; case .CNY: return "人民币"; case .EUR: return "欧元"; case .GBP: return "英镑"
        case .JPY: return "日元"; case .KRW: return "韩元"; case .CAD: return "加元"; case .AUD: return "澳元"
        case .HKD: return "港元"; case .TWD: return "新台币"; case .SGD: return "新加坡元"; case .CHF: return "瑞郎"
        case .NZD: return "新西兰元"; case .INR: return "印度卢比"; case .BRL: return "巴西雷亚尔"; case .MXN: return "墨西哥比索"
        case .THB: return "泰铢"; case .MYR: return "马来西亚林吉特"; case .IDR: return "印尼盾"; case .PHP: return "菲律宾比索"
        case .VND: return "越南盾"; case .AED: return "阿联酋迪拉姆"; case .SAR: return "沙特里亚尔"; case .PLN: return "波兰兹罗提"
        case .SEK: return "瑞典克朗"; case .NOK: return "挪威克朗"; case .DKK: return "丹麦克朗"; case .CZK: return "捷克克朗"
        case .HUF: return "匈牙利福林"; case .ILS: return "以色列谢克尔"; case .ZAR: return "南非兰特"; case .TRY: return "土耳其里拉"
        case .RUB: return "俄罗斯卢布"
        }
    }
    var symbol: String {
        switch self {
        case .USD, .AUD, .CAD, .HKD, .TWD, .SGD, .NZD, .MXN, .BRL: return "$"
        case .CNY, .JPY: return "¥"
        case .EUR: return "€"; case .GBP: return "£"; case .KRW: return "₩"
        case .CHF: return "CHF "; case .INR: return "₹"; case .THB: return "฿"
        case .MYR: return "RM "; case .IDR: return "Rp "; case .PHP: return "₱"
        case .VND: return "₫"; case .AED, .SAR: return "﷼ "
        case .PLN: return "zł "; case .SEK, .NOK, .DKK: return "kr "
        case .CZK: return "Kč "; case .HUF: return "Ft "; case .ILS: return "₪ "
        case .ZAR: return "R "; case .TRY: return "₺ "; case .RUB: return "₽ "
        }
    }
    // 日元、韩元、印尼盾、越南盾不带小数，其他 2 位小数。
    var decimals: Int {
        switch self { case .JPY, .KRW, .IDR, .VND: return 0; default: return 2 }
    }
    var label: String { "\(rawValue) \(name)" }
}

// 单例 + App Group 共享：设置页改货币，所有用 fmtUsd 的界面下次刷新时自动跟上；
// 小组件不直接读这个单例（扩展进程不同），它读 SharedStore 里的货币码和汇率表，见 CurrencyFormatter。
final class CurrencyStore: ObservableObject {
    static let shared = CurrencyStore()
    @Published var currency: AppCurrency = .USD {
        didSet { SharedStore.defaults.set(currency.rawValue, forKey: "gaoqian.currency.v1") }
    }
    @Published var rates: [String: Double] = [:]
    @Published var rateSource: String?
    @Published var rateDate: String?
    @Published var rateError: String?

    init() {
        if let code = SharedStore.defaults.string(forKey: "gaoqian.currency.v1"),
           let c = AppCurrency(rawValue: code) { currency = c }
        if let data = SharedStore.defaults.data(forKey: "gaoqian.fx.v1"),
           let map = try? JSONDecoder().decode([String: Double].self, from: data) { rates = map }
    }

    func rate(for currency: AppCurrency) -> Double? {
        if currency == .USD { return 1 }
        return rates[currency.rawValue]
    }

    func refresh() async {
        do {
            let fx = try await APIClient.fetchFx()
            if let r = fx.rates, !r.isEmpty {
                rates = r; rateSource = fx.source; rateDate = fx.rateDate; rateError = nil
                if let data = try? JSONEncoder().encode(r) { SharedStore.defaults.set(data, forKey: "gaoqian.fx.v1") }
                if let s = fx.source { SharedStore.defaults.set(s, forKey: "gaoqian.fx.source.v1") }
                if let d = fx.rateDate { SharedStore.defaults.set(d, forKey: "gaoqian.fx.date.v1") }
            } else {
                rateError = "汇率没拿到，本次按美元显示"
            }
        } catch {
            rateError = "汇率没拿到，本次按美元显示"
        }
    }
}

// 全局金额格式化：Views 和 Widget 都用这一个，不各写各的 $。
// amount 是美元；currency 不是美元且汇率缺失时回落美元并在设置页提示，不静默贴错符号。
enum CurrencyFormatter {
    static func formatUsd(_ usd: Double?) -> String {
        guard let usd else { return "—" }
        let store = CurrencyStore.shared
        let cur = store.currency
        guard cur != .USD, let rate = store.rate(for: cur) else {
            return usdFormat(usd, symbol: "$", decimals: 2)
        }
        let converted = usd * rate
        return usdFormat(converted, symbol: cur.symbol, decimals: cur.decimals)
    }

    // 小额币价：不用 K/M 缩写，保留有效数字，否则 0.000001 的土狗价会被缩成 0。
    static func formatPrice(_ usd: Double?) -> String {
        guard let usd else { return "—" }
        let store = CurrencyStore.shared
        let cur = store.currency
        let value: Double
        let symbol: String
        if cur == .USD || store.rate(for: cur) == nil {
            value = usd; symbol = "$"
        } else {
            value = usd * (store.rate(for: cur) ?? 1); symbol = cur.symbol
        }
        if value == 0 { return "\(symbol)0" }
        if abs(value) >= 1000 { return usdFormat(value, symbol: symbol, decimals: 2) }
        if abs(value) >= 1 { return String(format: "\(symbol)%.4f", value) }
        if abs(value) >= 0.0001 { return String(format: "\(symbol)%.6f", value) }
        return String(format: "\(symbol)%.6g", value)
    }

    private static func usdFormat(_ v: Double, symbol: String, decimals: Int) -> String {
        let absV = abs(v)
        let sign = v < 0 ? "-" : ""
        if absV >= 1_000_000 {
            return String(format: "\(sign)\(symbol)%.2fM", absV / 1_000_000)
        }
        if absV >= 1_000 {
            return String(format: "\(sign)\(symbol)%.1fK", absV / 1_000)
        }
        return String(format: "\(sign)\(symbol)%.\(decimals)f", absV)
    }
}

// Views 里旧的 "$\(v)" 全部改走这个，不再硬编码美元符号。
func fmtUsd(_ usd: Double?) -> String { CurrencyFormatter.formatUsd(usd) }
func fmtPrice(_ usd: Double?) -> String { CurrencyFormatter.formatPrice(usd) }
