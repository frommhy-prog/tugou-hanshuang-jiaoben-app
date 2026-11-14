import SwiftUI

// 持有人兜底：云端读转账读不完（热门币转账太多）或失败时，手机直连 GoPlus（前 10 大 + 持有人数），再退 GeckoTerminal 的分布统计
enum HolderFallback {
    struct Out {
        var holders: [UHolder]
        var conc: Conc
        var findings: [Finding]
        var note: String
    }

    static let goplusId: [String: String] = ["bsc": "56", "eth": "1", "base": "8453", "arbitrum": "42161", "optimism": "10", "polygon": "137", "avalanche": "43114"]

    static func load(chain: Chain, address: String, pair: String?) async -> Out? {
        if let o = await goplus(chain, address, pair) { return o }
        return await gecko(chain, address)
    }

    private static func isBurn(_ a: String) -> Bool {
        let l = a.lowercased()
        return l.hasSuffix("dead") || l == "0x0000000000000000000000000000000000000000"
    }

    private static func goplus(_ chain: Chain, _ addr: String, _ pair: String?) async -> Out? {
        guard let cid = goplusId[chain.rawValue] else { return nil }
        let low = addr.lowercased()
        guard let o = try? await MarketAPI.json("https://api.gopluslabs.io/api/v1/token_security/" + cid + "?contract_addresses=" + low, ttl: 60),
              let root = o as? [String: Any],
              let res = root["result"] as? [String: Any] else { return nil }
        let d0: [String: Any]? = (res[low] as? [String: Any]) ?? (res.values.first as? [String: Any])
        guard let d = d0, let hs = d["holders"] as? [[String: Any]], !hs.isEmpty else { return nil }
        var list: [UHolder] = []
        var rank = 0
        for h in hs {
            guard let a = h["address"] as? String, let frac = MarketAPI.num(h["percent"]) else { continue }
            rank += 1
            let isC = (MarketAPI.num(h["is_contract"]) ?? 0) >= 1
            let tag = ((h["tag"] as? String) ?? "").lowercased()
            var kind = "wallet"
            if let p = pair, a.lowercased() == p.lowercased() { kind = "pool" }
            else if isBurn(a) { kind = "contract" }
            else if tag.contains("pancake") || tag.contains("uniswap") || tag.contains("lp") || tag.contains("pool") { kind = "pool" }
            else if isC { kind = "contract" }
            list.append(UHolder(rank: rank, owner: a, kind: kind, pct: frac * 100))
        }
        if list.isEmpty { return nil }
        func sum(_ n: Int) -> Double { list.prefix(n).reduce(0.0) { $0 + ($1.pct ?? 0) } }
        let walletSum = list.filter { $0.kind == "wallet" }.prefix(10).reduce(0.0) { $0 + ($1.pct ?? 0) }
        let conc = Conc(top1: sum(1), top5: sum(5), top10: sum(10), top20: sum(10), wallets10: walletSum, nonWallet: max(0, sum(10) - walletSum), listed: list.count)
        var f: [Finding] = []
        let cnt = MarketAPI.num(d["holder_count"]).map { Int($0) }
        f.append(Finding(level: "info", text: "共 " + (cnt.map { String($0) } ?? "未知") + " 个持有人；这里只有前 " + String(list.count) + " 大（GoPlus）", basis: "云端按转账累加没读完，已改用手机直连 GoPlus 的持有人榜单"))
        if let first = list.first, first.kind == "wallet", (first.pct ?? 0) >= 20 {
            f.append(Finding(level: "risk", text: String(format: "第 1 大持有人是普通钱包，持有 %.1f%%", first.pct ?? 0), basis: "GoPlus 持有人榜单"))
        }
        if walletSum >= 30 { f.append(Finding(level: "risk", text: String(format: "前 10 大里普通钱包合计持有 %.1f%%", walletSum), basis: "GoPlus，已剔除池子、合约、销毁地址")) }
        else if walletSum >= 15 { f.append(Finding(level: "warn", text: String(format: "前 10 大里普通钱包合计持有 %.1f%%", walletSum), basis: "GoPlus，已剔除池子、合约、销毁地址")) }
        if let cp = MarketAPI.num(d["creator_percent"]), cp * 100 >= 3 {
            f.append(Finding(level: cp * 100 >= 10 ? "risk" : "warn", text: String(format: "创建者地址仍持有 %.1f%%", cp * 100), basis: "GoPlus creator_percent"))
        }
        return Out(holders: list, conc: conc, findings: f, note: "持有人榜单只有前 " + String(list.count) + " 大（GoPlus 直连），不是全部持有人")
    }

    private static func gecko(_ chain: Chain, _ addr: String) async -> Out? {
        guard let o = try? await MarketAPI.json("https://api.geckoterminal.com/api/v2/networks/" + chain.geckoId + "/tokens/" + addr + "/info", ttl: 60),
              let d = (o as? [String: Any])?["data"] as? [String: Any],
              let a = d["attributes"] as? [String: Any],
              let h = a["holders"] as? [String: Any] else { return nil }
        let cnt = MarketAPI.num(h["count"]).map { Int($0) }
        let dist = h["distribution_percentage"] as? [String: Any]
        let t10 = MarketAPI.num(dist?["top_10"])
        if cnt == nil && t10 == nil { return nil }
        var f: [Finding] = []
        f.append(Finding(level: "info", text: "持有人 " + (cnt.map { String($0) } ?? "未知") + " 个" + (t10.map { String(format: "，前 10 大合计 %.1f%%", $0) } ?? ""), basis: "GeckoTerminal 代币信息（只有统计，没有榜单明细）"))
        let conc = Conc(top1: nil, top5: nil, top10: t10, top20: nil, wallets10: nil, nonWallet: nil, listed: 0)
        return Out(holders: [], conc: conc, findings: f, note: "只拿到持有人统计（GeckoTerminal），没有榜单明细，无法做大户拆解")
    }
}
