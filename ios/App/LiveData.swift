import SwiftUI

extension Notification.Name {
    static let tstzmFullChart = Notification.Name("tstzm.fullChart")
}

enum KHero {
    // 头部 + K 线整体占满一屏：图表高度随屏幕高度变化
    static var chartHeight: CGFloat { max(340, min(560, UIScreen.main.bounds.height * 0.5)) }
}

struct DexPairsWrap: Codable {
    var pairs: [DexPair]?
}

extension MarketAPI {
    // 实时价：Dexscreener 单池接口（几秒级更新），用来把最新一根 K 线补到「现在」
    static func livePrice(_ chain: Chain, _ pair: String) async throws -> Double? {
        let o = try await json("https://api.dexscreener.com/latest/dex/pairs/" + chain.dexId + "/" + pair)
        guard let a = (o as? [String: Any])?["pairs"] as? [[String: Any]], let p = a.first else { return nil }
        return num(p["priceUsd"])
    }

    // 查空兜底：新币在新接口里还没收录时，换老接口再查一次
    static func legacyPairs(_ chain: Chain, _ addr: String) async -> [DexPair] {
        guard let url = URL(string: "https://api.dexscreener.com/latest/dex/tokens/" + addr) else { return [] }
        await DataGate.shared.wait("api.dexscreener.com")
        guard let r = try? await Net.fetch(URLRequest(url: url, timeoutInterval: 20)),
              let w = try? JSONDecoder().decode(DexPairsWrap.self, from: r.0) else { return [] }
        let key = addr.lowercased()
        let list = (w.pairs ?? []).filter { ($0.chainId ?? "") == chain.dexId && ($0.baseToken?.address ?? "").lowercased() == key }
        return list.sorted { $0.liq > $1.liq }
    }
}
