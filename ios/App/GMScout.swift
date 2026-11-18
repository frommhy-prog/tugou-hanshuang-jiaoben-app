import SwiftUI
import UIKit

extension Notification.Name {
    static let gmCloseDash = Notification.Name("gm.closeDash")
}

// MARK: - 今日雷达：API 空余时自动按当天大盘热度找热门链、可靠代币和聪明钱
struct GMScoutChain: Codable, Identifiable {
    var id: String
    var vol24: Double
    var txns: Int
    var pools: Int
    var heat: Double
}

struct GMScoutToken: Codable, Identifiable {
    var id: String
    var chain: String
    var address: String
    var symbol: String
    var pool: String
    var dex: String
    var liq: Double
    var vol24: Double
    var mcap: Double?
    var ch1: Double?
    var ch24: Double?
    var buyers: Int
    var sellers: Int
    var ageH: Double
    var score: Double
    var secOK: Bool?
    var oks: [String]
    var warns: [String]
}

struct GMScoutWallet: Codable, Identifiable {
    var id: String
    var chain: String
    var addr: String
    var winUsd: Double
    var tokens: [String]
    var score: Double
    var tags: [String]
    var source: String
}

struct GMScoutReport: Codable {
    var at: Double
    var chains: [GMScoutChain]
    var metas: [String]
    var tokens: [GMScoutToken]
    var wallets: [GMScoutWallet]
    var calls: Int
    var note: String
}

// 钱包累积榜：同一个币只记最近一次估算，避免重复扫描把同一批成交算两遍
fileprivate struct GMBoardEntry: Codable {
    var chain: String
    var addr: String
    var perToken: [String: Double]
    var tags: [String]
    var source: String
    var last: Double
}

struct GMSec {
    var pass: Bool
    var oks: [String]
    var warns: [String]
}

struct GMScoutPool {
    var chain: Chain
    var addr: String
    var sym: String
    var pool: String
    var dex: String
    var liq: Double
    var vol24: Double
    var mc: Double?
    var fdv: Double?
    var ch1: Double?
    var ch24: Double?
    var buys: Int
    var sells: Int
    var buyers: Int
    var sellers: Int
    var ageH: Double
}

struct GMScoutCand {
    var p: GMScoutPool
    var score: Double
    var oks: [String]
    var warns: [String]
}

// 扫描用的请求一律是后台优先级，网关会让你自己的操作先走
enum GMScoutNet {
    static func json(_ s: String) async -> Any? {
        guard let u = URL(string: s) else { return nil }
        if let p = GMUsage.provider(host: u.host ?? "") { GMUsage.shared.scoutHit(p) }
        var req = URLRequest(url: u, timeoutInterval: 25)
        req.networkServiceType = .background
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let r = try? await Net.fetch(req), let http = r.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONSerialization.jsonObject(with: r.0)
    }
}

enum GMScoutScan {
    static let chains: [Chain] = [.solana, .bsc, .base, .eth, .arbitrum, .polygon, .optimism]

    struct WAcc {
        var bUsd: Double = 0
        var bQty: Double = 0
        var sUsd: Double = 0
        var sQty: Double = 0
        var n: Int = 0
    }

    // 趋势池：GeckoTerminal 各链 24h 热门池
    static func pools(_ chain: Chain) async -> [GMScoutPool] {
        let u: String = "https://api.geckoterminal.com/api/v2/networks/" + chain.geckoId + "/trending_pools?duration=24h"
        guard let o = await GMScoutNet.json(u), let arr = (o as? [String: Any])?["data"] as? [[String: Any]] else { return [] }
        let prefix: String = chain.geckoId + "_"
        let iso = ISO8601DateFormatter()
        var out: [GMScoutPool] = []
        for item in arr {
            guard let a = item["attributes"] as? [String: Any] else { continue }
            let rel = item["relationships"] as? [String: Any]
            let bt = (rel?["base_token"] as? [String: Any])?["data"] as? [String: Any]
            let rid: String = (bt?["id"] as? String) ?? ""
            if !rid.hasPrefix(prefix) { continue }
            let addr: String = String(rid.dropFirst(prefix.count))
            if addr.isEmpty { continue }
            let dexData = (rel?["dex"] as? [String: Any])?["data"] as? [String: Any]
            let dexId: String = (dexData?["id"] as? String) ?? ""
            let name: String = (a["name"] as? String) ?? ""
            let sym: String = name.components(separatedBy: " / ").first ?? name
            let pc = a["price_change_percentage"] as? [String: Any]
            let vol = a["volume_usd"] as? [String: Any]
            let tx = (a["transactions"] as? [String: Any])?["h24"] as? [String: Any]
            var age: Double = 0
            if let s = a["pool_created_at"] as? String, let d = iso.date(from: s) { age = Date().timeIntervalSince(d) / 3600 }
            let p = GMScoutPool(
                chain: chain, addr: addr, sym: sym, pool: (a["address"] as? String) ?? "", dex: dexId,
                liq: MarketAPI.num(a["reserve_in_usd"]) ?? 0, vol24: MarketAPI.num(vol?["h24"]) ?? 0,
                mc: MarketAPI.num(a["market_cap_usd"]), fdv: MarketAPI.num(a["fdv_usd"]),
                ch1: MarketAPI.num(pc?["h1"]), ch24: MarketAPI.num(pc?["h24"]),
                buys: Int(MarketAPI.num(tx?["buys"]) ?? 0), sells: Int(MarketAPI.num(tx?["sells"]) ?? 0),
                buyers: Int(MarketAPI.num(tx?["buyers"]) ?? 0), sellers: Int(MarketAPI.num(tx?["sellers"]) ?? 0),
                ageH: age)
            out.append(p)
        }
        return out
    }

    // Dexscreener 热门叙事（官方 /metas/trending/v1，每分钟 60 次限额）
    static func metas() async -> [String] {
        guard let o = await GMScoutNet.json("https://api.dexscreener.com/metas/trending/v1") else { return [] }
        var arr: [[String: Any]] = []
        if let a = o as? [[String: Any]] {
            arr = a
        } else if let d = o as? [String: Any], let a = d["metas"] as? [[String: Any]] {
            arr = a
        }
        var out: [String] = []
        for m in arr.prefix(12) {
            if let n = (m["name"] as? String) ?? (m["slug"] as? String), !n.isEmpty { out.append(n) }
        }
        return out
    }

    // 可靠性初筛：不合格返回 nil
    static func filter(_ p: GMScoutPool) -> (oks: [String], warns: [String])? {
        if p.liq < 50_000 { return nil }
        if p.ageH < 6 { return nil }
        if p.buyers < 150 || p.sellers < 80 { return nil }
        let ratio: Double = p.sells > 0 ? Double(p.buys) / Double(p.sells) : 99
        if ratio < 0.6 || ratio > 1.8 { return nil }
        let turn: Double = p.vol24 / max(p.liq, 1)
        if turn < 0.2 || turn > 30 { return nil }
        if let f = p.fdv, f / max(p.liq, 1) > 150 { return nil }
        if let c = p.ch24, c < -50 { return nil }
        if let c = p.ch1, c > 150 { return nil }
        var oks: [String] = []
        var warns: [String] = []
        oks.append("流动性 " + GMPx.fiat(p.liq))
        oks.append("24h 买家 " + String(p.buyers) + " / 卖家 " + String(p.sellers))
        oks.append("池龄 " + Fmt2.dur(p.ageH * 3600))
        oks.append(String(format: "买卖笔数比 %.2f，成交/流动性 %.1f 倍", ratio, turn))
        if turn > 12 { warns.append("换手偏高，留意刷量") }
        if let c = p.ch1, c > 60 { warns.append(String(format: "1h 涨幅 %.0f%%，追高风险", c)) }
        return (oks, warns)
    }

    static func score(_ p: GMScoutPool) -> Double {
        let ratio: Double = p.sells > 0 ? Double(p.buys) / Double(p.sells) : 2
        let liqS: Double = min(1, max(0, log10(max(p.liq, 1) / 50_000) / 1.5))
        let crowd: Double = min(1, Double(p.buyers) / 1500)
        let age: Double = min(1, p.ageH / 72)
        let turn: Double = p.vol24 / max(p.liq, 1)
        let health: Double = 1 - min(1, abs(log10(max(turn, 0.01)) - 0.7) / 1.2)
        let bal: Double = 1 - min(1, abs(ratio - 1))
        let mom: Double = min(1, max(0, p.ch1 ?? 0) / 25)
        return 100 * (0.28 * liqS + 0.2 * crowd + 0.12 * age + 0.15 * health + 0.1 * bal + 0.15 * mom)
    }

    static func goplusId(_ c: Chain) -> String? {
        switch c {
        case .eth: return "1"
        case .bsc: return "56"
        case .base: return "8453"
        case .arbitrum: return "42161"
        case .optimism: return "10"
        case .polygon: return "137"
        default: return nil
        }
    }

    private static func flag(_ d: [String: Any], _ k: String) -> Bool? {
        guard let v = d[k] else { return nil }
        if let s = v as? String { return s == "1" }
        if let n = v as? NSNumber { return n.intValue == 1 }
        return nil
    }

    // EVM：GoPlus 合约扫描
    static func goplus(_ chain: Chain, _ addrs: [String]) async -> [String: GMSec] {
        guard let cid = goplusId(chain), !addrs.isEmpty else { return [:] }
        let u: String = "https://api.gopluslabs.io/api/v1/token_security/" + cid + "?contract_addresses=" + addrs.joined(separator: ",")
        guard let o = await GMScoutNet.json(u), let res = (o as? [String: Any])?["result"] as? [String: Any] else { return [:] }
        var out: [String: GMSec] = [:]
        for (k, v) in res {
            guard let d = v as? [String: Any] else { continue }
            out[k.lowercased()] = judge(d)
        }
        return out
    }

    private static func judge(_ d: [String: Any]) -> GMSec {
        var fails: [String] = []
        var warns: [String] = []
        var oks: [String] = []
        if flag(d, "is_honeypot") == true { fails.append("蜜罐（只能买不能卖）") }
        if flag(d, "cannot_sell_all") == true { fails.append("不能全部卖出") }
        if flag(d, "hidden_owner") == true { fails.append("存在隐藏所有者") }
        if flag(d, "can_take_back_ownership") == true { fails.append("可收回所有权") }
        if flag(d, "owner_change_balance") == true { fails.append("所有者可改余额") }
        let bt: Double = MarketAPI.num(d["buy_tax"]) ?? 0
        let st: Double = MarketAPI.num(d["sell_tax"]) ?? 0
        if bt > 0.10 || st > 0.10 {
            fails.append(String(format: "税率偏高 买%.0f%% / 卖%.0f%%", bt * 100, st * 100))
        } else {
            oks.append(String(format: "税 买%.0f%% / 卖%.0f%%", bt * 100, st * 100))
        }
        if flag(d, "is_open_source") == false { warns.append("合约未开源") }
        if flag(d, "is_mintable") == true { warns.append("可增发") }
        if flag(d, "transfer_pausable") == true { warns.append("可暂停转账") }
        if flag(d, "is_blacklisted") == true { warns.append("有黑名单功能") }
        if flag(d, "is_proxy") == true { warns.append("代理合约，可升级") }
        if let hc = MarketAPI.num(d["holder_count"]), hc < 300 { warns.append("持有者仅 " + String(Int(hc))) }
        if let lps = d["lp_holders"] as? [[String: Any]] {
            var locked: Double = 0
            for l in lps where flag(l, "is_locked") == true { locked += MarketAPI.num(l["percent"]) ?? 0 }
            if locked >= 0.5 {
                oks.append(String(format: "LP 锁定/烧毁 %.0f%%", locked * 100))
            } else {
                warns.append("LP 锁定不足 50%")
            }
        }
        if fails.isEmpty { oks.insert("GoPlus 扫描通过", at: 0) }
        return GMSec(pass: fails.isEmpty, oks: oks, warns: fails + warns)
    }

    // Solana：RugCheck 摘要
    static func rug(_ mint: String) async -> GMSec? {
        guard let o = await GMScoutNet.json("https://api.rugcheck.xyz/v1/tokens/" + mint + "/report/summary"), let d = o as? [String: Any] else { return nil }
        var fails: [String] = []
        var warns: [String] = []
        var oks: [String] = []
        for r in (d["risks"] as? [[String: Any]]) ?? [] {
            let lv: String = ((r["level"] as? String) ?? "").lowercased()
            let nm: String = (r["name"] as? String) ?? "风险项"
            if lv == "danger" {
                fails.append(nm)
            } else if lv == "warn" {
                warns.append(nm)
            }
        }
        if let lp = MarketAPI.num(d["lpLockedPct"]), lp >= 50 { oks.append(String(format: "LP 锁定 %.0f%%", lp)) }
        if fails.isEmpty { oks.insert("RugCheck 无高危项", at: 0) }
        return GMSec(pass: fails.isEmpty, oks: oks, warns: fails + Array(warns.prefix(3)))
    }

    // 池子最近成交（GeckoTerminal，最多 300 笔）
    static func trades(_ chain: Chain, _ pool: String) async -> [[String: Any]] {
        let u: String = "https://api.geckoterminal.com/api/v2/networks/" + chain.geckoId + "/pools/" + pool + "/trades"
        guard let o = await GMScoutNet.json(u), let arr = (o as? [String: Any])?["data"] as? [[String: Any]] else { return [] }
        return arr.compactMap { $0["attributes"] as? [String: Any] }
    }

    // 窗口内的盈利钱包（粗估：买卖都有、卖价 ≥ 买价 1.15 倍、成交 ≤ 40 笔，排除机器人 / 路由）
    static func winners(_ trades: [[String: Any]], pool: String) -> [(String, Double)] {
        var acc: [String: WAcc] = [:]
        for t in trades {
            guard let w = t["tx_from_address"] as? String, let kind = t["kind"] as? String else { continue }
            let usd: Double = MarketAPI.num(t["volume_in_usd"]) ?? 0
            let px: Double = MarketAPI.num(kind == "buy" ? t["price_to_in_usd"] : t["price_from_in_usd"]) ?? 0
            if usd <= 0 || px <= 0 { continue }
            var a: WAcc = acc[w] ?? WAcc()
            a.n += 1
            if kind == "buy" {
                a.bUsd += usd
                a.bQty += usd / px
            } else {
                a.sUsd += usd
                a.sQty += usd / px
            }
            acc[w] = a
        }
        var out: [(String, Double)] = []
        for (w, a) in acc {
            if a.n > 40 || a.bQty <= 0 || a.sQty <= 0 { continue }
            let avgB: Double = a.bUsd / a.bQty
            let avgS: Double = a.sUsd / a.sQty
            let matched: Double = min(a.bQty, a.sQty)
            let pnl: Double = matched * (avgS - avgB)
            if pnl >= 300 && avgS >= avgB * 1.15 && w.lowercased() != pool.lowercased() { out.append((w, pnl)) }
        }
        let sorted = out.sorted { $0.1 > $1.1 }
        return Array(sorted.prefix(12))
    }
}

@MainActor
final class GMScout: ObservableObject {
    static let shared = GMScout()
    @Published var report: GMScoutReport?
    @Published var running: Bool = false
    @Published var status: String = "等待空闲"
    fileprivate var board: [String: GMBoardEntry] = [:]
    private var loop: Task<Void, Never>?
    private var started: Bool = false

    private static func cacheFile(_ n: String) -> URL {
        let d: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return d.appendingPathComponent(n)
    }
    private static var reportURL: URL { cacheFile("gmscout_report_v1.json") }
    private static var boardURL: URL { cacheFile("gmscout_board_v1.json") }

    func start() {
        if started { return }
        started = true
        if let d = try? Data(contentsOf: GMScout.reportURL), let r = try? JSONDecoder().decode(GMScoutReport.self, from: d) { report = r }
        if let d = try? Data(contentsOf: GMScout.boardURL), let b = try? JSONDecoder().decode([String: GMBoardEntry].self, from: d) { board = b }
        loop = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 25_000_000_000)
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 90_000_000_000)
            }
        }
    }

    // 条件：App 在前台 + 距上次扫描 ≥ 30 分钟 + 限流额度有空余 + 网关没有排队的请求
    private func tick() async {
        if running { return }
        if UIApplication.shared.applicationState != .active {
            status = "App 在后台，暂停自动扫描"
            return
        }
        let age: Double = Date().timeIntervalSince1970 - (report?.at ?? 0)
        if age < 1800 {
            status = "上次扫描在 " + Fmt2.dur(age) + " 前，每 30 分钟自动扫一次"
            return
        }
        if !GMUsage.shared.hasHeadroom() {
            status = "API 额度吃紧（近 1 分钟调用偏多或今日雷达预算已用完），暂缓自动扫描"
            return
        }
        if !GateCore.shared.idle() {
            status = "正在处理你的请求，稍后再扫"
            return
        }
        await run()
    }

    func run() async {
        if running { return }
        running = true
        defer { running = false }
        let now: Double = Date().timeIntervalSince1970
        var calls: Int = 0

        // 1) 各链大盘热度
        status = "扫描中：各链大盘热度…"
        var heat: [GMScoutChain] = []
        var all: [GMScoutPool] = []
        for c in GMScoutScan.chains {
            if !GMUsage.shared.canScout("gecko", daily: 400) { break }
            let ps: [GMScoutPool] = await GMScoutScan.pools(c)
            calls += 1
            if ps.isEmpty { continue }
            let v: Double = ps.reduce(0) { $0 + $1.vol24 }
            let tx: Int = ps.reduce(0) { $0 + $1.buys + $1.sells }
            heat.append(GMScoutChain(id: c.rawValue, vol24: v, txns: tx, pools: ps.count, heat: 0))
            all.append(contentsOf: ps)
        }
        let maxV: Double = max(heat.map { $0.vol24 }.max() ?? 1, 1)
        let maxT: Double = max(Double(heat.map { $0.txns }.max() ?? 1), 1)
        for i in heat.indices { heat[i].heat = 70 * heat[i].vol24 / maxV + 30 * Double(heat[i].txns) / maxT }
        heat.sort { $0.heat > $1.heat }
        var heatMap: [String: Double] = [:]
        for h in heat { heatMap[h.id] = h.heat }

        // 2) 热门叙事
        status = "扫描中：热门叙事…"
        var metas: [String] = []
        if GMUsage.shared.canScout("dexscreener", daily: 600) {
            metas = await GMScoutScan.metas()
            calls += 1
        }

        // 3) 可靠性初筛 + 打分（同一个币只留分最高的池）
        var best: [String: GMScoutCand] = [:]
        for p in all {
            guard let f = GMScoutScan.filter(p) else { continue }
            let sc: Double = GMScoutScan.score(p) * 0.8 + (heatMap[p.chain.rawValue] ?? 0) * 0.2
            let key: String = p.chain.rawValue + ":" + p.addr.lowercased()
            if let old = best[key], old.score >= sc { continue }
            best[key] = GMScoutCand(p: p, score: sc, oks: f.oks, warns: f.warns)
        }
        let top: [GMScoutCand] = Array(best.values.sorted { $0.score > $1.score }.prefix(10))

        // 4) 合约安全：EVM 用 GoPlus（每条链一次批量），Solana 用 RugCheck
        status = "扫描中：合约安全…"
        var sec: [String: GMSec] = [:]
        var evmRows: [String: [GMScoutCand]] = [:]
        for r in top where r.p.chain != .solana { evmRows[r.p.chain.rawValue, default: []].append(r) }
        for (cid, rows) in evmRows {
            guard let chain = Chain(rawValue: cid), GMUsage.shared.canScout("goplus", daily: 120) else { continue }
            let res: [String: GMSec] = await GMScoutScan.goplus(chain, rows.map { $0.p.addr })
            calls += 1
            for (a, s) in res { sec[cid + ":" + a] = s }
        }
        for r in top where r.p.chain == .solana {
            if !GMUsage.shared.canScout("rugcheck", daily: 120) { break }
            if let s = await GMScoutScan.rug(r.p.addr) { sec["solana:" + r.p.addr.lowercased()] = s }
            calls += 1
        }
        var tokens: [GMScoutToken] = []
        for r in top {
            let key: String = r.p.chain.rawValue + ":" + r.p.addr.lowercased()
            var oks: [String] = r.oks
            var warns: [String] = r.warns
            var secOK: Bool? = nil
            if let s = sec[key] {
                if !s.pass { continue }
                oks.append(contentsOf: s.oks)
                warns.append(contentsOf: s.warns)
                secOK = true
            } else {
                warns.append("合约扫描未完成，先去风险页查")
            }
            tokens.append(GMScoutToken(id: key, chain: r.p.chain.rawValue, address: r.p.addr, symbol: r.p.sym, pool: r.p.pool, dex: r.p.dex, liq: r.p.liq, vol24: r.p.vol24, mcap: r.p.mc, ch1: r.p.ch1, ch24: r.p.ch24, buyers: r.p.buyers, sellers: r.p.sellers, ageH: r.p.ageH, score: r.score, secOK: secOK, oks: oks, warns: warns))
        }

        // 5) 聪明钱：可靠代币的最近成交里找盈利钱包，累计到本机榜单；GMGN 有密钥时再补官方「聪明钱」成交
        status = "扫描中：聪明钱…"
        for t in tokens.prefix(4) {
            guard let chain = Chain(rawValue: t.chain), GMUsage.shared.canScout("gecko", daily: 400), !t.pool.isEmpty else { continue }
            let tr: [[String: Any]] = await GMScoutScan.trades(chain, t.pool)
            calls += 1
            for (w, pnl) in GMScoutScan.winners(tr, pool: t.pool) {
                let k: String = chain.rawValue + ":" + w
                var e: GMBoardEntry = board[k] ?? GMBoardEntry(chain: chain.rawValue, addr: w, perToken: [:], tags: ["链上盈利"], source: "链上成交", last: now)
                e.perToken[t.id] = pnl
                e.last = now
                board[k] = e
            }
        }
        if GMGNStore.shared.hasKey {
            for c in [Chain.solana, Chain.bsc, Chain.base] { calls += await gmgnSmart(c, now: now) }
        }

        // 榜单清理：14 天没再出现的删掉，最多保留 400 个
        board = board.filter { $0.value.last >= now - 14 * 86400 }
        if board.count > 400 {
            let keep = board.sorted { $0.value.last > $1.value.last }.prefix(400)
            var nb: [String: GMBoardEntry] = [:]
            for (k, v) in keep { nb[k] = v }
            board = nb
        }
        var ws: [GMScoutWallet] = []
        for (k, e) in board {
            let win: Double = e.perToken.values.reduce(0, +)
            let n: Int = e.perToken.count
            var sc: Double = win > 0 ? log10(win) * 20 : 0
            sc += Double(max(0, n - 1)) * 12
            var tags: [String] = e.tags
            if n >= 2 { tags.append("多币盈利 " + String(n) + " 个") }
            if e.source == "GMGN" {
                sc = max(sc, 80)
            } else if win < 300 {
                continue
            }
            ws.append(GMScoutWallet(id: k, chain: e.chain, addr: e.addr, winUsd: win, tokens: Array(e.perToken.keys), score: min(100, sc), tags: tags, source: e.source))
        }
        ws.sort { $0.score > $1.score }

        let note: String = "来源：GeckoTerminal 趋势池、Dexscreener 热门叙事、GoPlus / RugCheck 合约扫描、最近 300 笔链上成交估算。「可靠」只表示通过流动性 / 买家数 / 换手率 / 合约扫描的筛选，不是买入建议；聪明钱盈利是窗口内粗估，要点进钱包再验证。"
        let r = GMScoutReport(at: now, chains: heat, metas: metas, tokens: tokens, wallets: Array(ws.prefix(30)), calls: calls, note: note)
        report = r
        persist(r)
        status = "扫描完成，本次用掉 " + String(calls) + " 次请求"
    }

    private func persist(_ r: GMScoutReport) {
        if let d = try? JSONEncoder().encode(r) { try? d.write(to: GMScout.reportURL, options: .atomic) }
        if let d = try? JSONEncoder().encode(board) { try? d.write(to: GMScout.boardURL, options: .atomic) }
    }

    // GMGN 官方「聪明钱成交」（需要你的 GMGN 密钥，每次权重 1）
    private func gmgnSmart(_ chain: Chain, now: Double) async -> Int {
        guard let cc = GMGNApi.code(chain) else { return 0 }
        GMUsage.shared.scoutHit("gmgn")
        let r = await GMGNApi.fetch("/v1/user/smartmoney", ["chain": cc, "limit": "50"])
        guard case .success(let v) = r else { return 1 }
        var list: [[String: Any]] = []
        if let d = v as? [String: Any] {
            list = (d["list"] as? [[String: Any]]) ?? (d["data"] as? [[String: Any]]) ?? []
        } else if let a = v as? [[String: Any]] {
            list = a
        }
        for d in list {
            var wallet: String = ""
            for k in ["maker", "wallet_address", "wallet", "address"] {
                if let s = gmStr(d[k]), !s.isEmpty {
                    wallet = s
                    break
                }
            }
            if wallet.isEmpty { continue }
            var tk: String = ""
            for k in ["base_address", "token_address", "token"] {
                if let s = gmStr(d[k]), !s.isEmpty {
                    tk = s
                    break
                }
            }
            let key: String = chain.rawValue + ":" + wallet
            var e: GMBoardEntry = board[key] ?? GMBoardEntry(chain: chain.rawValue, addr: wallet, perToken: [:], tags: ["GMGN 聪明钱"], source: "GMGN", last: now)
            e.source = "GMGN"
            if !tk.isEmpty { e.perToken[chain.rawValue + ":" + tk.lowercased()] = max(e.perToken[chain.rawValue + ":" + tk.lowercased()] ?? 0, 0) }
            e.last = now
            board[key] = e
        }
        return 1
    }
}

struct GMScoutView: View {
    @ObservedObject private var sc = GMScout.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                statusCard
                if let r = sc.report {
                    heatCard(r)
                    if !r.metas.isEmpty { metaCard(r) }
                    tokensCard(r)
                    walletsCard(r)
                    Text(r.note).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Card {
                        Text("还没有扫描结果。App 在前台且 API 有空余时会自动扫描，也可以点右上角立即扫描。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.page)
        .navigationTitle("今日雷达")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if sc.running {
                    ProgressView()
                } else {
                    Button { Task { await sc.run() } } label: { Image(systemName: "dot.radiowaves.left.and.right") }
                }
            }
        }
    }

    private var statusCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(sc.status).font(.footnote.weight(.semibold))
                if let r = sc.report {
                    Text("上次扫描 " + TZ.format(Date(timeIntervalSince1970: r.at)) + "，用掉 " + String(r.calls) + " 次请求").font(.caption2).foregroundStyle(.secondary)
                }
                Text("自动规则：App 在前台、近 1 分钟 API 没怎么用、没有排队请求时扫，每 30 分钟一次；扫描请求排在你的操作后面，有每日预算（见 API 用量控制台）。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func heatCard(_ r: GMScoutReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("今日大盘热度（各链趋势池 24h 成交 + 笔数）").font(.headline)
                ForEach(r.chains) { c in
                    let chain: Chain = Chain(rawValue: c.id) ?? .solana
                    HStack(spacing: 8) {
                        AvChainBadge(chain: chain, size: 18)
                        Text(chain.title).font(.subheadline.weight(.semibold)).frame(width: 64, alignment: .leading)
                        ProgressView(value: min(1, max(0, c.heat / 100)))
                        Text(String(format: "%.0f", c.heat)).font(.caption.weight(.bold).monospacedDigit()).frame(width: 28, alignment: .trailing)
                    }
                    Text("24h 成交 " + GMPx.fiat(c.vol24) + " · " + String(c.txns) + " 笔 · " + String(c.pools) + " 个热门池").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metaCard(_ r: GMScoutReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("热门叙事（Dexscreener）").font(.headline)
                Text(r.metas.joined(separator: " · ")).font(.footnote)
            }
        }
    }

    private func tokensCard(_ r: GMScoutReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("可靠热门代币（热度 + 流动性 + 买家数 + 合约扫描）").font(.headline)
                if r.tokens.isEmpty {
                    Text("今天还没有同时通过所有筛选的代币。").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(r.tokens) { t in
                    tokenRow(t)
                    Divider()
                }
            }
        }
    }

    private func chg(_ label: String, _ v: Double?) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(v.map { String(format: "%+.1f%%", $0) } ?? "—")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle((v ?? 0) >= 0 ? Color.green : Color.red)
        }
    }

    private func tokenRow(_ t: GMScoutToken) -> some View {
        let chain: Chain = Chain(rawValue: t.chain) ?? .solana
        let col: Color = t.score >= 60 ? Color.green : (t.score >= 40 ? Color.orange : Color.secondary)
        return Button {
            UTokenVM.shared.start(t.address)
            AppRouter.shared.tab = 0
            NotificationCenter.default.post(name: .gmCloseDash, object: nil)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                AvTokenLogo(chain: chain, address: t.address, symbol: t.symbol, hint: nil, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(t.symbol).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)
                        Text(String(format: "可靠度 %.0f", t.score))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(col.opacity(0.2), in: Capsule())
                            .foregroundStyle(col)
                    }
                    Text(chain.title + " · 流动性 " + GMPx.fiat(t.liq) + " · 24h 成交 " + GMPx.fiat(t.vol24)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Text(t.oks.prefix(4).joined(separator: " · ")).font(.caption2).foregroundStyle(Color.green).lineLimit(3)
                    if !t.warns.isEmpty {
                        Text("注意：" + t.warns.joined(separator: " · ")).font(.caption2).foregroundStyle(Color.orange).lineLimit(3)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    chg("1h", t.ch1)
                    chg("24h", t.ch24)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func walletsCard(_ r: GMScoutReport) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("聪明钱（链上成交盈利 + GMGN 标记，累计到本机榜单）").font(.headline)
                if r.wallets.isEmpty {
                    Text("还没有满足条件的钱包：需要在同一个币里买卖都有、卖价不低于买价 1.15 倍且估算盈利 ≥ $300。").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(r.wallets) { w in
                    walletRow(w)
                    Divider()
                }
            }
        }
    }

    private func walletRow(_ w: GMScoutWallet) -> some View {
        let chain: Chain = Chain(rawValue: w.chain) ?? .solana
        return Menu {
            GMWalletMenuContent(chain: chain, addr: w.addr)
        } label: {
            HStack(spacing: 8) {
                AvChainBadge(chain: chain, size: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Addr.short(w.addr)).font(.caption.monospaced()).foregroundStyle(Color.primary)
                    Text(w.tags.joined(separator: " · ") + " · " + w.source).font(.caption2).foregroundStyle(Color.orange).lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(w.winUsd > 0 ? GMPx.fiat(w.winUsd, signed: true) : "—").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Color.green)
                    Text(String(format: "评分 %.0f", w.score)).font(.caption2).foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.up.right.square").font(.caption).foregroundStyle(Color.accentColor)
            }
        }
    }
}

struct GMScoutLink: View {
    @ObservedObject private var sc = GMScout.shared

    private var summary: String {
        guard let r = sc.report else { return "还没扫描过：API 有空余时自动找热门链、可靠代币、聪明钱" }
        let top: String = r.chains.first.flatMap { Chain(rawValue: $0.id)?.title } ?? "—"
        return "最热的链 " + top + " · 可靠代币 " + String(r.tokens.count) + " 个 · 聪明钱 " + String(r.wallets.count) + " 个 · " + TZ.format(Date(timeIntervalSince1970: r.at))
    }

    var body: some View {
        NavigationLink {
            GMScoutView()
        } label: {
            Card {
                HStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.title3).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("今日雷达：热门链 · 可靠代币 · 聪明钱").font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                        Text(summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
