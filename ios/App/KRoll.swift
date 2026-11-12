import Foundation

// 周线 / 月线：GeckoTerminal 只提供分钟、小时、日线，这里用日线在本地汇总（UTC：周线从周一 00:00 起，月线从每月 1 日 00:00 起）
extension TF {
    var isRolled: Bool { self == .w1 || self == .mo1 }

    // 这根 K 线的开盘时刻
    func bucketStart(_ t: Double) -> Double {
        switch self {
        case .w1:
            let off = 345600.0
            return ((t - off) / 604800).rounded(.down) * 604800 + off
        case .mo1:
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
            let d = Date(timeIntervalSince1970: t)
            let c = cal.dateComponents([.year, .month], from: d)
            return (cal.date(from: c) ?? d).timeIntervalSince1970
        default:
            let s = sec
            return (t / s).rounded(.down) * s
        }
    }

    func rolled(_ daily: [Candle]) -> [Candle] {
        if !isRolled { return daily }
        var out: [Candle] = []
        var cur: Candle?
        var curStart = -1.0
        for c in daily.sorted(by: { $0.t < $1.t }) {
            let s = bucketStart(c.t)
            if let k = cur, s == curStart {
                cur = Candle(t: k.t, o: k.o, h: max(k.h, c.h), l: min(k.l, c.l), c: c.c, v: k.v + c.v)
            } else {
                if let k = cur { out.append(k) }
                cur = Candle(t: s, o: c.o, h: c.h, l: c.l, c: c.c, v: c.v)
                curStart = s
            }
        }
        if let k = cur { out.append(k) }
        return out
    }
}
