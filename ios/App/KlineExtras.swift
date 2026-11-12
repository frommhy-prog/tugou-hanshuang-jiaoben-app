import SwiftUI

// MARK: - 周线 / 月线：GeckoTerminal 只有分钟、小时、日三种粒度，周线和月线由日线在本地汇总
extension TF {
    var isRolled: Bool { self == .w1 || self == .mo1 }

    func rolled(_ raw: [Candle]) -> [Candle] {
        if !isRolled || raw.isEmpty { return raw }
        var out: [Candle] = []
        var curStart: Double = -1
        var o = 0.0
        var h = 0.0
        var l = 0.0
        var c = 0.0
        var v = 0.0
        let sorted = raw.sorted { $0.t < $1.t }
        for x in sorted {
            let b = kBucket(x.t, self)
            if b != curStart {
                if curStart >= 0 { out.append(Candle(t: curStart, o: o, h: h, l: l, c: c, v: v)) }
                curStart = b
                o = x.o
                h = x.h
                l = x.l
                c = x.c
                v = x.v
            } else {
                h = max(h, x.h)
                l = min(l, x.l)
                c = x.c
                v += x.v
            }
        }
        if curStart >= 0 { out.append(Candle(t: curStart, o: o, h: h, l: l, c: c, v: v)) }
        return out
    }
}

// 一根 K 线的起点：周线按 UTC 周一 0 点，月线按 UTC 每月 1 号 0 点，其余按固定秒数对齐
func kBucket(_ t: Double, _ tf: TF) -> Double {
    switch tf {
    case .w1:
        let off = 345600.0
        return ((t - off) / 604800).rounded(.down) * 604800 + off
    case .mo1:
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let d = Date(timeIntervalSince1970: t)
        if let s = cal.dateInterval(of: .month, for: d)?.start { return s.timeIntervalSince1970 }
        return t
    default:
        let sec = tf.sec
        return (t / sec).rounded(.down) * sec
    }
}

// K 线图正在显示的那一组 K 线（含周期）：深度分析卡片读它，不必再请求一遍
@MainActor
final class KLineShared: ObservableObject {
    static let shared = KLineShared()
    @Published var candles: [Candle] = []
    @Published var tf: TF = .m15
    @Published var key = ""

    func update(chain: Chain, pair: String, tf: TF, candles: [Candle]) {
        self.key = chain.rawValue + ":" + pair
        self.tf = tf
        self.candles = candles
    }
}
