import Foundation

// 汇率版本号：汇率刷新后 +1，代币页据此重绘
@MainActor
final class GMFXState: ObservableObject {
    static let shared = GMFXState()
    @Published var tick = 0
}

// 价格 / 市值 统一开关：全 App 只认 kMcap 一个开关。金额跟随「设置 → 计价货币」（人民币就显示 ¥），汇率缺失时回落美元，绝不贴错符号。
enum GMPx {
    // 当前币的总供应量 = 市值 / 价格，由代币页在行情刷新时同步
    static var supply: Double = 0

    static var mcapMode: Bool { Cfg.defaults.bool(forKey: "kMcap") }

    // 美元 → 当前计价货币 的汇率与符号
    static var rate: Double { Money.resolved().1 }
    static var sym: String { Money.resolved().0.symbol }

    static func sync(_ m: DexPair?) {
        guard let m = m, let p = m.price, p > 0, let mc = (m.marketCap ?? m.fdv), mc > 0 else { return }
        supply = mc / p
    }

    private static let subs: [Character] = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"]

    private static func sub(_ n: Int) -> String {
        String(String(n).compactMap { ch -> Character? in
            guard let d = ch.wholeNumberValue, d >= 0, d <= 9 else { return nil }
            return subs[d]
        })
    }

    // 已换算好的金额 → 文本：小数点后连续 4 个以上的 0 用下标表示（¥0.0₄27493），和 GMGN 写法一致
    private static func fmt(_ v: Double, _ s: String) -> String {
        if v == 0 { return s + "0" }
        let a = abs(v)
        let sign = v < 0 ? "-" : ""
        if a >= 1 { return sign + s + String(format: "%.2f", a) }
        if a >= 0.01 { return sign + s + String(format: "%.4f", a) }
        var zeros = Int(floor(-log10(a))) - 1
        if zeros < 0 { zeros = 0 }
        var m = a * pow(10.0, Double(zeros + 1))
        var t = String(format: "%.3f", m)
        if t.hasPrefix("10") {
            zeros -= 1
            m = m / 10
            t = String(format: "%.3f", m)
        }
        var digits = t.replacingOccurrences(of: ".", with: "")
        while digits.count > 1 && digits.hasSuffix("0") { digits.removeLast() }
        if zeros >= 4 { return sign + s + "0.0" + sub(zeros) + digits }
        let zs = String(repeating: "0", count: max(0, zeros))
        return sign + s + "0." + zs + digits
    }

    // 币价（输入是美元）→ 当前计价货币的价格文本
    static func usd(_ v: Double) -> String {
        let r = Money.resolved()
        return fmt(v * r.1, r.0.symbol)
    }

    // 市值 / 流动性 / 成交额（输入是美元）→ 当前计价货币的缩写文本（¥21.40M）
    // 任意美元金额（成交额、盈亏、池子…）→ 当前计价货币的缩写文本；全 App 原来的 Fmt2.usd 都转到这里
    static func fiat(_ v: Double?, signed: Bool = false) -> String {
        guard let x = v else { return "未知" }
        let s: String = Money.format(x)
        if signed && x > 0 { return "+" + s }
        return s
    }

    static func cap(_ v: Double?) -> String {
        guard let x = v else { return "—" }
        return Money.format(x)
    }

    // 币价 → 文本；市值模式下 = 价格 × 总供应量（总供应量未知时退回价格，不编数）
    static func tp(_ v: Double?) -> String {
        guard let x = v else { return "未知" }
        if mcapMode, supply > 0 { return Money.format(x * supply) }
        return usd(x)
    }

    // 头部大数字：价格模式显示价格，市值模式显示市值
    static func headline(_ m: DexPair, mcap: Bool? = nil) -> String {
        let on: Bool = mcap ?? mcapMode
        if on { return cap(m.marketCap ?? m.fdv) }
        return m.price.map { usd($0) } ?? "—"
    }

    // 汇率缺失或超过 6 小时：直连免费汇率接口（不需要令牌），失败再退回引擎的 /api/fx
    @MainActor
    static func ensureFX() async {
        let c: String = Money.code
        if c == "USD" { return }
        let now: Double = Date().timeIntervalSince1970
        let at: Double = Cfg.defaults.double(forKey: "fxAt2")
        let old: Double? = Money.rates[c]
        if old != nil && now - at < 6 * 3600 { return }
        var got: [String: Double] = [:]
        if let o = try? await MarketAPI.json("https://open.er-api.com/v6/latest/USD"), let d = o as? [String: Any], let rs = d["rates"] as? [String: Any] {
            for (k, v) in rs {
                if let x = MarketAPI.num(v), x > 0 { got[k] = x }
            }
        }
        if got[c] == nil, let o = try? await MarketAPI.json("https://api.frankfurter.dev/v1/latest?base=USD"), let d = o as? [String: Any], let rs = d["rates"] as? [String: Any] {
            for (k, v) in rs {
                if let x = MarketAPI.num(v), x > 0 { got[k] = x }
            }
        }
        if got[c] == nil {
            await FX.refresh()
            if Money.rates[c] != nil {
                Cfg.defaults.set(now, forKey: "fxAt2")
                if old == nil { GMFXState.shared.tick += 1 }
            }
            return
        }
        var m: [String: Double] = Money.rates
        for (k, v) in got { m[k] = v }
        Money.rates = m
        Cfg.defaults.set(now, forKey: "fxAt2")
        if let nv = got[c] {
            if let o = old {
                if abs(nv - o) / o > 0.002 { GMFXState.shared.tick += 1 }
            } else {
                GMFXState.shared.tick += 1
            }
        }
    }
}
