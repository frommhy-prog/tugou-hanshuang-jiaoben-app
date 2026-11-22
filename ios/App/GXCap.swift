import Foundation

// 市值口径：marketCap 与 fdv 都有时取较小的那个。
// marketCap > fdv 不可能成立，说明 marketCap 是全网口径（CoinGecko 流通量），并不是这条链上的供应；Ave / GMGN 按链上供应算，这里与它们对齐。
extension GMPx {
    static func minCap(_ a: Double?, _ f: Double?) -> Double? {
        if let x = a, let y = f, x > 0, y > 0 { return min(x, y) }
        if let x = a, x > 0 { return x }
        if let y = f, y > 0 { return y }
        return nil
    }
}
