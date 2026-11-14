import SwiftUI

// 数据源限流网关：同一域名的请求排队间隔发出（GeckoTerminal 免费 30 次/分钟），429 后整体退避，短时间重复请求走缓存
actor DataGate {
    static let shared = DataGate()
    private var nextAt: [String: Double] = [:]
    private var store: [String: (at: Double, data: Data)] = [:]

    static func interval(_ host: String) -> Double {
        if host.contains("geckoterminal") { return 2.1 }
        if host.contains("dexscreener") { return 0.22 }
        if host.contains("gopluslabs") { return 1.1 }
        return 0
    }

    func wait(_ host: String) async {
        let iv = DataGate.interval(host)
        if iv <= 0 { return }
        let now = Date().timeIntervalSince1970
        let at = max(now, nextAt[host] ?? 0)
        nextAt[host] = at + iv
        if at > now { try? await Task.sleep(nanoseconds: UInt64((at - now) * 1_000_000_000)) }
    }

    func penalize(_ host: String, _ sec: Double) {
        nextAt[host] = max(nextAt[host] ?? 0, Date().timeIntervalSince1970 + sec)
    }

    func cached(_ k: String, ttl: Double) -> Data? {
        if let e = store[k], Date().timeIntervalSince1970 - e.at < ttl { return e.data }
        return nil
    }

    func put(_ k: String, _ d: Data) {
        let now = Date().timeIntervalSince1970
        store[k] = (at: now, data: d)
        if store.count > 80 { store = store.filter { now - $0.value.at < 120 } }
    }
}
