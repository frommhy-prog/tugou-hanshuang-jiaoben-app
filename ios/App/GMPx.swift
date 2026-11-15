import Foundation

// 价格 / 市值 统一开关：全 App 只认 kMcap 一个开关（K 线的「价格 ⇄ 市值」、代币头部、收藏页、各分析页都读它）。
enum GMPx {
    // 当前币的总供应量 = 市值 / 价格，由代币页在行情刷新时同步
    static var supply: Double = 0

    static var mcapMode: Bool { Cfg.defaults.bool(forKey: "kMcap") }

    static func sync(_ m: DexPair?) {
        guard let m = m, let p = m.price, p > 0, let mc = (m.marketCap ?? m.fdv), mc > 0 else { return }
        supply = mc / p
    }

    // 币价 → 文本；市值模式下 = 价格 × 总供应量（总供应量未知时退回价格，不编数）
    static func tp(_ usd: Double?) -> String {
        guard let v = usd else { return "未知" }
        if mcapMode, supply > 0 { return Money.format(v * supply) }
        return Money.price(v)
    }

    // 头部大数字：价格模式显示价格，市值模式显示市值
    static func headline(_ m: DexPair, mcap: Bool? = nil) -> String {
        let on: Bool = mcap ?? mcapMode
        if on { return Fmt2.usd(m.marketCap ?? m.fdv) }
        return m.price.map { Money.price($0) } ?? "—"
    }
}
