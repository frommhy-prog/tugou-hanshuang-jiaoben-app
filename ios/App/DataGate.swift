import SwiftUI

// 数据源限流：排队、间隔、缓存、冷却、重试已统一由 GateNet.swift 的全局网关（URLProtocol）处理；
// 这里保留原接口（调用方不用改），但不再单独排队，避免同一个请求被排两次队
actor DataGate {
    static let shared = DataGate()
    private var store: [String: (at: Double, data: Data)] = [:]

    static func interval(_ host: String) -> Double { 0 } // 排队间隔改由全局网关负责

    func wait(_ host: String) async {} // 不再单独排队

    func penalize(_ host: String, _ sec: Double) {} // 冷却改由全局网关按 429 / Retry-After 处理

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
