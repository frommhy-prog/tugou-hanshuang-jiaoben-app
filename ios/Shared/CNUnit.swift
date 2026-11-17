import Foundation
import CoreGraphics

// 中文数字缩写：万、亿（不显示 K / M / B）。
// 全 App 里 String(format: "%.2fM", x / 1_000_000) 这类写法，由补丁 plist24 统一改成 CNUnit.wrap。
enum CNUnit {
    static func short(_ v: Double, _ d: Int = 2) -> String {
        if v.isNaN || v.isInfinite { return "—" }
        let a: Double = abs(v)
        let sign: String = v < 0 ? "-" : ""
        let dd: Int = max(d, 2)
        if a >= 1e12 { return sign + String(format: "%.\(dd)f", a / 1e12) + "万亿" }
        if a >= 1e8 { return sign + String(format: "%.\(dd)f", a / 1e8) + "亿" }
        if a >= 1e4 { return sign + String(format: "%.\(dd)f", a / 1e4) + "万" }
        if a == a.rounded() || a >= 1000 { return sign + String(format: "%.0f", a) }
        return sign + String(format: "%.\(d)f", a)
    }

    static func wrap(_ pre: String, _ v: Double, _ d: Int, _ suf: String) -> String { pre + short(v, d) + suf }
    static func wrap(_ pre: String, _ v: Int, _ d: Int, _ suf: String) -> String { pre + short(Double(v), d) + suf }
    static func wrap(_ pre: String, _ v: CGFloat, _ d: Int, _ suf: String) -> String { pre + short(Double(v), d) + suf }
    static func wrap(_ pre: String, _ v: Float, _ d: Int, _ suf: String) -> String { pre + short(Double(v), d) + suf }
}
