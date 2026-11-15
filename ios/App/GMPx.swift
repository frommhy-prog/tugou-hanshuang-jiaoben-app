import Foundation

// 价格 / 市值 统一开关：全 App 只认 kMcap 一个开关。代币页里的币价、市值一律用「美元」显示（和 K 线轴、GMGN 一致），不再混用人民币等计价货币。
enum GMPx {
    // 当前币的总供应量 = 市值 / 价格，由代币页在行情刷新时同步
    static var supply: Double = 0

    static var mcapMode: Bool { Cfg.defaults.bool(forKey: "kMcap") }

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

    // 美元价格：小数点后连续 4 个以上的 0 用下标表示（$0.0₄27493），和 GMGN 写法一致
    static func usd(_ v: Double) -> String {
        if v == 0 { return "$0" }
        let a = abs(v)
        let sign = v < 0 ? "-" : ""
        if a >= 1000 { return sign + Fmt2.usd(a) }
        if a >= 1 { return sign + String(format: "$%.2f", a) }
        if a >= 0.01 { return sign + String(format: "$%.4f", a) }
        var zeros = Int(floor(-log10(a))) - 1
        if zeros < 0 { zeros = 0 }
        var s = a * pow(10.0, Double(zeros + 1))
        var t = String(format: "%.3f", s)
        if t.hasPrefix("10") {
            zeros -= 1
            s = s / 10
            t = String(format: "%.3f", s)
        }
        var digits = t.replacingOccurrences(of: ".", with: "")
        while digits.count > 1 && digits.hasSuffix("0") { digits.removeLast() }
        if zeros >= 4 { return sign + "$0.0" + sub(zeros) + digits }
        let zs = String(repeating: "0", count: max(0, zeros))
        return sign + "$0." + zs + digits
    }

    // 币价 → 文本；市值模式下 = 价格 × 总供应量（总供应量未知时退回价格，不编数）
    static func tp(_ v: Double?) -> String {
        guard let x = v else { return "未知" }
        if mcapMode, supply > 0 { return Fmt2.usd(x * supply) }
        return usd(x)
    }

    // 头部大数字：价格模式显示价格，市值模式显示市值
    static func headline(_ m: DexPair, mcap: Bool? = nil) -> String {
        let on: Bool = mcap ?? mcapMode
        if on { return Fmt2.usd(m.marketCap ?? m.fdv) }
        return m.price.map { usd($0) } ?? "—"
    }
}
