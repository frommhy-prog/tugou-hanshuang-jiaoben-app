import SwiftUI

// MARK: - 交易记录 / 钱包 / 流动性 分析工具（自带数据，不依赖 GMGN Key）
// 数据：GeckoTerminal 最深池子的最近 300 笔成交（含代币数量、区块号、发起地址）。
// 所有结论都带数字依据；样本不足的项直接不出，不编数。

struct GLTrade {
    let t: Double
    let buy: Bool
    let usd: Double
    let amt: Double
    let px: Double
    let who: String
    let block: Int
    let tx: String
}

struct GLTier: Identifiable {
    let id: Int
    let lo: Double
    let hi: Double
    var buyUsd: Double = 0
    var sellUsd: Double = 0
    var nb: Int = 0
    var ns: Int = 0
    var net: Double { buyUsd - sellUsd }
}

struct GLWallet: Identifiable {
    let addr: String
    var buyUsd: Double = 0
    var sellUsd: Double = 0
    var buyAmt: Double = 0
    var sellAmt: Double = 0
    var nb: Int = 0
    var ns: Int = 0
    var firstT: Double = 0
    var lastT: Double = 0
    var tags: [String] = []
    var avgBuy: Double?
    var realized: Double = 0
    var unrealized: Double?
    var roi: Double?
    var netTok: Double = 0
    var preHold: Bool = false
    var holderPct: Double?
    var id: String { addr }
    var gross: Double { buyUsd + sellUsd }
}

struct GLCluster: Identifiable {
    let block: Int
    let wallets: [String]
    let usd: Double
    var id: Int { block }
}

struct GLInsight: Identifiable {
    let id: Int
    let level: Int   // 0 信息  1 注意  2 风险  3 利好
    let title: String
    let detail: String
}

struct GLReport {
    var count: Int = 0
    var span: Double = 0
    var buyUsd: Double = 0
    var sellUsd: Double = 0
    var nb: Int = 0
    var ns: Int = 0
    var totalUsd: Double = 0
    var tiers: [GLTier] = []
    var wallets: [GLWallet] = []
    var clusters: [GLCluster] = []
    var insights: [GLInsight] = []
    var uniqBuyers: Int = 0
    var uniqSellers: Int = 0
    var botWallets: Int = 0
    var washShare: Double = 0
    var slope: Double?
    var slopeR2: Double?
    var slopeN: Int = 0
}

enum GLCalc {
    static func median(_ a: [Double]) -> Double {
        if a.isEmpty { return 0 }
        let s: [Double] = a.sorted()
        let n: Int = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    static func f(_ v: Double) -> String { return GMPx.fiat(v) }

    static func short(_ a: String) -> String {
        if a.count <= 12 { return a }
        return String(a.prefix(6)) + "…" + String(a.suffix(4))
    }

    static func build(_ raw: [GLTrade], curPx: Double?, holders: [String: Double]) -> GLReport {
        var r = GLReport()
        let ts: [GLTrade] = raw.sorted { $0.t < $1.t }
        r.count = ts.count
        guard let first = ts.first, let last = ts.last else { return r }
        r.span = last.t - first.t
        for t in ts {
            if t.buy {
                r.buyUsd += t.usd
                r.nb += 1
            } else {
                r.sellUsd += t.usd
                r.ns += 1
            }
        }
        r.totalUsd = r.buyUsd + r.sellUsd

        // 1) 档位：谁在买、谁在卖
        let edges: [Double] = [0, 100, 1000, 10000, Double.infinity]
        var tiers: [GLTier] = []
        for i in 0..<4 { tiers.append(GLTier(id: i, lo: edges[i], hi: edges[i + 1])) }
        for t in ts {
            var idx: Int = 3
            if t.usd < 100 { idx = 0 } else if t.usd < 1000 { idx = 1 } else if t.usd < 10000 { idx = 2 }
            if t.buy {
                tiers[idx].buyUsd += t.usd
                tiers[idx].nb += 1
            } else {
                tiers[idx].sellUsd += t.usd
                tiers[idx].ns += 1
            }
        }
        r.tiers = tiers

        // 2) 钱包聚合
        var map: [String: GLWallet] = [:]
        var perT: [String: [Double]] = [:]
        var perUsd: [String: [Double]] = [:]
        for t in ts {
            if t.who.isEmpty { continue }
            var w: GLWallet = map[t.who] ?? GLWallet(addr: t.who)
            if t.buy {
                w.buyUsd += t.usd
                w.buyAmt += t.amt
                w.nb += 1
            } else {
                w.sellUsd += t.usd
                w.sellAmt += t.amt
                w.ns += 1
            }
            if w.firstT == 0 { w.firstT = t.t }
            w.lastT = t.t
            map[t.who] = w
            perT[t.who, default: []].append(t.t)
            perUsd[t.who, default: []].append(t.usd)
        }
        var buyers: Int = 0
        var sellers: Int = 0
        var washUsd: Double = 0
        var wl: [GLWallet] = []
        for (addr, w0) in map {
            var w: GLWallet = w0
            let times: [Double] = (perT[addr] ?? []).sorted()
            let sizes: [Double] = perUsd[addr] ?? []
            let n: Int = w.nb + w.ns
            if w.nb > 0 { buyers += 1 }
            if w.ns > 0 { sellers += 1 }
            if w.buyAmt > 0 { w.avgBuy = w.buyUsd / w.buyAmt }
            var covered: Bool = true
            if let ab = w.avgBuy, w.sellAmt > 0 {
                let sp: Double = w.sellUsd / w.sellAmt
                let matched: Double = min(w.sellAmt, w.buyAmt)
                w.realized = matched * (sp - ab)
                if w.sellAmt > w.buyAmt * 1.05 { covered = false }
            } else if w.sellAmt > 0 {
                covered = false
            }
            let netTok: Double = max(0, w.buyAmt - w.sellAmt)
            w.netTok = netTok
            if let ab = w.avgBuy, let cp = curPx, netTok > 0 { w.unrealized = netTok * (cp - ab) }
            if w.buyUsd > 0 && covered && w.avgBuy != nil {
                w.roi = (w.realized + (w.unrealized ?? 0)) / w.buyUsd * 100
            }
            w.preHold = !covered

            if n >= 6 && times.count >= 6 {
                var iv: [Double] = []
                for i in 1..<times.count { iv.append(times[i] - times[i - 1]) }
                let mean: Double = iv.reduce(0, +) / Double(iv.count)
                if mean > 0 {
                    var v: Double = 0
                    for x in iv { v += (x - mean) * (x - mean) }
                    let sd: Double = (v / Double(iv.count)).squareRoot()
                    if sd / mean < 0.3 { w.tags.append("定时节奏") }
                }
            }
            if n >= 4 {
                let med: Double = median(sizes)
                if med > 0 {
                    let near: Int = sizes.filter { abs($0 - med) / med <= 0.03 }.count
                    if near >= max(4, Int(Double(n) * 0.6)) { w.tags.append("固定金额") }
                }
            }
            if w.nb >= 3 && w.ns >= 3 {
                let hi: Double = max(w.buyUsd, w.sellUsd)
                let lo: Double = min(w.buyUsd, w.sellUsd)
                if hi > 0 && lo / hi >= 0.85 { w.tags.append("对倒嫌疑") }
            }
            if w.nb == 0 && w.ns >= 2 { w.tags.append("窗口内只卖") }
            if w.ns == 0 && w.nb >= 2 { w.tags.append("窗口内只买") }
            if let hp = holders[addr.lowercased()] {
                w.holderPct = hp
                w.tags.append("持有榜 " + String(format: "%.1f%%", hp))
            }
            let bot: Bool = w.tags.contains("对倒嫌疑") || (w.tags.contains("定时节奏") && w.tags.contains("固定金额"))
            if bot {
                washUsd += w.gross
                r.botWallets += 1
            }
            wl.append(w)
        }
        wl.sort { $0.gross > $1.gross }
        r.wallets = wl
        r.uniqBuyers = buyers
        r.uniqSellers = sellers
        r.washShare = r.totalUsd > 0 ? washUsd / r.totalUsd : 0

        // 3) 同区块多钱包买入
        var byBlock: [Int: [GLTrade]] = [:]
        for t in ts where t.buy && t.block > 0 { byBlock[t.block, default: []].append(t) }
        var cl: [GLCluster] = []
        for (b, arr) in byBlock {
            let set: Set<String> = Set(arr.map { $0.who })
            if set.count >= 4 {
                cl.append(GLCluster(block: b, wallets: Array(set), usd: arr.reduce(0) { $0 + $1.usd }))
            }
        }
        cl.sort { $0.usd > $1.usd }
        r.clusters = cl

        // 4) 价格冲击斜率：5 分钟一段，净买入额 → 段内涨跌
        var bk: [Int: [GLTrade]] = [:]
        for t in ts { bk[Int(t.t / 300), default: []].append(t) }
        var xs: [Double] = []
        var ys: [Double] = []
        for (_, arr) in bk {
            if arr.count < 2 { continue }
            let a: [GLTrade] = arr.sorted { $0.t < $1.t }
            let p0: Double = a.first?.px ?? 0
            let p1: Double = a.last?.px ?? 0
            if p0 <= 0 || p1 <= 0 { continue }
            let dp: Double = (p1 - p0) / p0 * 100
            if abs(dp) > 50 { continue }
            var net: Double = 0
            for t in a { net += t.buy ? t.usd : -t.usd }
            xs.append(net / 1000)
            ys.append(dp)
        }
        if xs.count >= 6 {
            let n: Double = Double(xs.count)
            let mx: Double = xs.reduce(0, +) / n
            let my: Double = ys.reduce(0, +) / n
            var sxx: Double = 0
            var sxy: Double = 0
            var syy: Double = 0
            for i in 0..<xs.count {
                let dx: Double = xs[i] - mx
                let dy: Double = ys[i] - my
                sxx += dx * dx
                sxy += dx * dy
                syy += dy * dy
            }
            if sxx > 0 && syy > 0 {
                r.slope = sxy / sxx
                r.slopeR2 = (sxy * sxy) / (sxx * syy)
                r.slopeN = xs.count
            }
        }

        // 5) 结论（每条带依据）
        var out: [GLInsight] = []
        func add(_ level: Int, _ title: String, _ detail: String) {
            out.append(GLInsight(id: out.count, level: level, title: title, detail: detail))
        }
        let total: Double = r.totalUsd
        if total > 0 {
            let bigNet: Double = tiers[2].net + tiers[3].net
            let smallNet: Double = tiers[0].net + tiers[1].net
            let bigStr: String = "大单（≥" + f(1000) + "）净 " + GMPx.fiat(bigNet, signed: true)
            let smallStr: String = "小单（<" + f(1000) + "）净 " + GMPx.fiat(smallNet, signed: true)
            if bigNet > 0 && smallNet < 0 && abs(bigNet) > total * 0.05 {
                add(3, "大单在接小单的卖盘", bigStr + "，" + smallStr + "。大额资金在吸，小额资金在出。")
            } else if bigNet < 0 && smallNet > 0 && abs(bigNet) > total * 0.05 {
                add(2, "大单在向小单派发", bigStr + "，" + smallStr + "。大额资金在卖，小额买盘在接，这是典型的派发结构。")
            } else if bigNet > 0 && smallNet > 0 {
                add(0, "大小单同向净买", bigStr + "，" + smallStr + "。")
            } else if bigNet < 0 && smallNet < 0 {
                add(1, "大小单同向净卖", bigStr + "，" + smallStr + "。")
            }
        }
        if wl.count >= 3 && total > 0 {
            let top3: Double = wl.prefix(3).reduce(0) { $0 + $1.gross }
            let share: Double = top3 / total * 100
            let names: String = wl.prefix(3).map { short($0.addr) }.joined(separator: "、")
            if share >= 50 {
                add(1, "成交被少数地址主导", "前 3 个地址贡献了 " + String(format: "%.0f%%", share) + " 的成交额（" + names + "）。看到的成交量不等于真实参与人数。")
            } else {
                add(0, "成交较分散", "前 3 个地址只占 " + String(format: "%.0f%%", share) + " 的成交额；买家 " + String(buyers) + " 个、卖家 " + String(sellers) + " 个（发起地址去重）。")
            }
        }
        if r.washShare >= 0.15 {
            let real: Double = total * (1 - r.washShare)
            add(1, "疑似机器人 / 刷量占 " + String(format: "%.0f%%", r.washShare * 100), String(r.botWallets) + " 个地址呈现定时节奏 + 固定金额，或买卖几乎对倒。扣掉后真实成交额约 " + f(real) + "（总 " + f(total) + "）。")
        } else if r.botWallets > 0 {
            add(0, "有 " + String(r.botWallets) + " 个机器人特征地址", "合计只占成交额 " + String(format: "%.0f%%", r.washShare * 100) + "，对整体影响小。")
        }
        if let c = cl.first {
            add(1, "同一区块 " + String(c.wallets.count) + " 个钱包一起买", "区块 #" + String(c.block) + " 内 " + String(c.wallets.count) + " 个不同地址买入合计 " + f(c.usd) + "。可能同一控制人拆分地址，也可能行情火爆碰巧同块；共 " + String(cl.count) + " 个这样的区块。")
        }
        let sellersSorted: [GLWallet] = wl.filter { $0.sellUsd > 0 }.sorted { $0.sellUsd > $1.sellUsd }
        if let s = sellersSorted.first, total > 0 {
            let share: Double = s.sellUsd / max(r.sellUsd, 1) * 100
            var d: String = short(s.addr) + " 卖出 " + f(s.sellUsd) + "，占窗口卖出额 " + String(format: "%.0f%%", share) + "。"
            var lv: Int = 0
            if s.preHold {
                d += "窗口内没有对应买入，卖的是更早的持仓。"
                lv = share >= 25 ? 2 : 1
            } else if let roi = s.roi {
                d += "窗口内买入均价 " + GMPx.usd(s.avgBuy ?? 0) + "，估算已兑现 " + GMPx.fiat(s.realized, signed: true) + "（综合回报 " + String(format: "%+.0f%%", roi) + "）。"
                lv = share >= 30 ? 1 : 0
            }
            add(lv, "最大卖家", d)
        }
        if let cp = curPx, cp > 0 {
            var cost: Double = 0
            var tokens: Double = 0
            var underCost: Double = 0
            for w in wl {
                if let ab = w.avgBuy, w.netTok > 0, !w.preHold {
                    cost += w.netTok * ab
                    tokens += w.netTok
                    if ab > cp { underCost += w.netTok * ab }
                }
            }
            if tokens > 0 && cost > 0 {
                let avgCost: Double = cost / tokens
                let diff: Double = (cp - avgCost) / avgCost * 100
                let under: Double = underCost / cost * 100
                var d: String = "窗口内买入且仍持有的钱包，平均成本 " + GMPx.usd(avgCost) + "，现价 " + GMPx.usd(cp) + "（" + String(format: "%+.1f%%", diff) + "）。按金额算 " + String(format: "%.0f%%", under) + " 的资金成本高于现价。"
                var lv: Int = 0
                if under >= 60 {
                    d += "价格回到它们的成本区会有解套抛压。"
                    lv = 1
                } else if under <= 25 {
                    d += "近期买家大多是盈利状态，短线抛压多来自获利了结。"
                }
                add(lv, "近期买家的持仓成本", d)
            }
        }
        if let sl = r.slope, let r2 = r.slopeR2, r2 >= 0.15, sl > 0 {
            add(0, "价格冲击：每净买 " + f(1000) + " 约推高 " + String(format: "%.2f%%", sl), "按 " + String(r.slopeN) + " 个 5 分钟段回归（拟合度 R²=" + String(format: "%.2f", r2) + "）。数值越大说明盘口越薄，同样的资金更容易把价格拉起或砸下。")
        }
        if r.span >= 1200 {
            let recent: Int = ts.filter { $0.t > last.t - 600 }.count
            let prior: Int = ts.filter { $0.t <= last.t - 600 && $0.t > last.t - 3600 }.count
            let priorSpan: Double = min(3000, r.span - 600)
            if prior > 0 && priorSpan > 0 {
                let rateNow: Double = Double(recent) / 10
                let ratePrev: Double = Double(prior) / (priorSpan / 60)
                if ratePrev > 0 {
                    let x: Double = rateNow / ratePrev
                    if x >= 2 {
                        add(1, "成交在加速", "最近 10 分钟每分钟 " + String(format: "%.1f", rateNow) + " 笔，是此前的 " + String(format: "%.1f", x) + " 倍。")
                    } else if x <= 0.4 {
                        add(0, "成交在降温", "最近 10 分钟每分钟 " + String(format: "%.1f", rateNow) + " 笔，只有此前的 " + String(format: "%.1f", x) + " 倍。")
                    }
                }
            }
        }
        if r.nb > 5 && r.ns > 5 && total > 0 {
            let avgB: Double = r.buyUsd / Double(r.nb)
            let avgS: Double = r.sellUsd / Double(r.ns)
            let cntShare: Double = Double(r.nb) / Double(r.nb + r.ns)
            let usdShare: Double = r.buyUsd / total
            if cntShare >= 0.55 && usdShare <= 0.45 {
                add(1, "买单多但金额小，卖单少但金额大", "买 " + String(r.nb) + " 笔均 " + f(avgB) + "，卖 " + String(r.ns) + " 笔均 " + f(avgS) + "。笔数占优的一方不一定是资金占优的一方，小额追买、大额卖出。")
            } else if cntShare <= 0.45 && usdShare >= 0.55 {
                add(3, "买单少但金额大", "买 " + String(r.nb) + " 笔均 " + f(avgB) + "，卖 " + String(r.ns) + " 笔均 " + f(avgS) + "。资金侧偏多，卖单是零散的小额。")
            }
        }
        if !holders.isEmpty {
            var n: Int = 0
            var pctSum: Double = 0
            var usd: Double = 0
            for w in wl where w.ns > 0 {
                if let hp = w.holderPct {
                    n += 1
                    pctSum += hp
                    usd += w.sellUsd
                }
            }
            if n > 0 {
                add(n >= 2 ? 2 : 1, "窗口内有 " + String(n) + " 个持有榜地址在卖", "它们合计持仓 " + String(format: "%.1f%%", pctSum) + "，窗口内卖出 " + f(usd) + "。榜单大户出货比普通卖盘更需要警惕。")
            }
        }
        r.insights = out
        return r
    }
}

// MARK: - 数据：成交读取 + 报告
@MainActor
final class GMLabStore: ObservableObject {
    static let shared = GMLabStore()
    @Published var trades: [GLTrade] = []
    @Published var rep = GLReport()
    @Published var note: String?
    @Published var loading = false
    private var key = ""
    private var tAt = Date.distantPast

    private static func num(_ x: Any?) -> Double? {
        if let n = x as? NSNumber { return n.doubleValue }
        if let s = x as? String { return Double(s) }
        return nil
    }

    private static func parseTime(_ s: String) -> Double? {
        let a = ISO8601DateFormatter()
        if let d = a.date(from: s) { return d.timeIntervalSince1970 }
        let b = ISO8601DateFormatter()
        b.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return b.date(from: s)?.timeIntervalSince1970
    }

    func rebuild(_ vm: UTokenVM) {
        var hd: [String: Double] = [:]
        for h in vm.holders {
            if let p = h.pct { hd[h.owner.lowercased()] = p }
        }
        for w in GMFreeStore.shared.wallets where !w.isContract { hd[w.addr.lowercased()] = w.pct }
        rep = GLCalc.build(trades, curPx: vm.main?.price, holders: hd)
    }

    func load(_ vm: UTokenVM, force: Bool = false) async {
        guard let pa = vm.main?.pairAddress, !pa.isEmpty else {
            note = "还没有池子地址"
            return
        }
        let me: String = vm.address.lowercased()
        let k: String = vm.chain.rawValue + ":" + me + ":" + pa
        if k == key && !force && Date().timeIntervalSince(tAt) < 25 {
            rebuild(vm)
            return
        }
        if k != key {
            trades = []
            rep = GLReport()
            note = nil
        }
        key = k
        tAt = Date()
        loading = true
        defer { loading = false }
        let u: String = "https://api.geckoterminal.com/api/v2/networks/" + vm.chain.geckoId + "/pools/" + pa + "/trades"
        do {
            let o = try await MarketAPI.json(u, ttl: 15)
            guard let top = o as? [String: Any], let arr = top["data"] as? [[String: Any]] else {
                note = "成交数据格式异常"
                return
            }
            var out: [GLTrade] = []
            for el in arr {
                guard let a = el["attributes"] as? [String: Any] else { continue }
                let usd: Double = GMLabStore.num(a["volume_in_usd"]) ?? 0
                if usd <= 0 { continue }
                guard let ts = a["block_timestamp"] as? String, let t = GMLabStore.parseTime(ts) else { continue }
                let kind: String = (a["kind"] as? String) ?? ""
                let fromA: String = ((a["from_token_address"] as? String) ?? "").lowercased()
                let toA: String = ((a["to_token_address"] as? String) ?? "").lowercased()
                let fromAmt: Double = GMLabStore.num(a["from_token_amount"]) ?? 0
                let toAmt: Double = GMLabStore.num(a["to_token_amount"]) ?? 0
                var buy: Bool = kind == "buy"
                var amt: Double = buy ? toAmt : fromAmt
                if toA == me {
                    buy = true
                    amt = toAmt
                } else if fromA == me {
                    buy = false
                    amt = fromAmt
                }
                let px: Double = amt > 0 ? usd / amt : 0
                let who: String = (a["tx_from_address"] as? String) ?? ""
                let blk: Int = Int(GMLabStore.num(a["block_number"]) ?? 0)
                let tx: String = (a["tx_hash"] as? String) ?? ""
                out.append(GLTrade(t: t, buy: buy, usd: usd, amt: amt, px: px, who: who, block: blk, tx: tx))
            }
            if out.isEmpty {
                note = "池子暂时没有成交记录"
                return
            }
            trades = out.sorted { $0.t > $1.t }
            note = nil
            rebuild(vm)
        } catch {
            note = "成交读取失败：" + error.localizedDescription
        }
    }
}

// MARK: - 本机趋势记录（持有者 / 前十 / 流动性 / 市值 / 价格随时间的变化）
struct GLPoint: Codable {
    let t: Double
    let px: Double
    let liq: Double
    let mc: Double
    let holders: Double
    let top10: Double
}

enum GMTrend {
    static func key(_ c: Chain, _ a: String) -> String { return "gmTrend:" + c.rawValue + ":" + a.lowercased() }

    static func load(_ c: Chain, _ a: String) -> [GLPoint] {
        guard let d = Cfg.defaults.data(forKey: key(c, a)), let arr = try? JSONDecoder().decode([GLPoint].self, from: d) else { return [] }
        return arr
    }

    @MainActor
    static func record(_ vm: UTokenVM) {
        guard let m = vm.main, let px = m.price, px > 0, !vm.address.isEmpty else { return }
        var arr: [GLPoint] = load(vm.chain, vm.address)
        let now: Double = Date().timeIntervalSince1970
        if let l = arr.last, now - l.t < 120 { return }
        let fr = GMFreeStore.shared
        let holders: Double = fr.v["holders"] ?? -1
        var top10: Double = fr.v["top10"] ?? -1
        if top10 < 0, let w = vm.conc?.wallets10 { top10 = Double(w) }
        arr.append(GLPoint(t: now, px: px, liq: m.liq, mc: m.marketCap ?? m.fdv ?? 0, holders: holders, top10: top10))
        if arr.count > 400 { arr.removeFirst(arr.count - 400) }
        if let d = try? JSONEncoder().encode(arr) { Cfg.defaults.set(d, forKey: key(vm.chain, vm.address)) }
    }
}

// MARK: - 小组件
struct GLInsightRow: View {
    let i: GLInsight
    var body: some View {
        let c: Color = i.level == 2 ? Color.red : (i.level == 1 ? Color.orange : (i.level == 3 ? Color.green : Color.blue))
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(c).frame(width: 7, height: 7).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(i.title).font(.subheadline.weight(.semibold))
                Text(i.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct GLNote: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 交易记录分析
struct GMTradeLabView: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var lab = GMLabStore.shared
    @State private var shown = 25

    private func tierLabel(_ t: GLTier) -> String {
        if t.lo == 0 { return "<" + GMPx.fiat(t.hi) }
        if t.hi == Double.infinity { return "≥" + GMPx.fiat(t.lo) }
        return GMPx.fiat(t.lo) + "–" + GMPx.fiat(t.hi)
    }

    var body: some View {
        let rep: GLReport = lab.rep
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("交易记录分析", systemImage: "list.bullet.rectangle").font(.headline)
                        Spacer()
                        if lab.loading { ProgressView() }
                    }
                    if let n = lab.note, lab.trades.isEmpty {
                        Text(n).font(.footnote).foregroundStyle(.secondary)
                    } else if lab.trades.isEmpty {
                        HStack(spacing: 8) { ProgressView(); Text("读取成交…").font(.footnote).foregroundStyle(.secondary) }
                    } else {
                        GLNote(text: "最近 " + String(rep.count) + " 笔成交，覆盖约 " + Fmt2.dur(rep.span) + "；买 " + String(rep.nb) + " 笔 " + GMPx.fiat(rep.buyUsd) + " · 卖 " + String(rep.ns) + " 笔 " + GMPx.fiat(rep.sellUsd) + " · 净 " + GMPx.fiat(rep.buyUsd - rep.sellUsd, signed: true) + "。来源 GeckoTerminal 最深池子，地址是交易发起方。")
                        if rep.insights.isEmpty {
                            Text("样本里没有触发任何值得说的结构，不硬编结论。").font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(rep.insights) { GLInsightRow(i: $0) }
                    }
                }
            }
            if !lab.trades.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("谁在买、谁在卖（按单笔金额分档）").font(.subheadline.weight(.semibold))
                        ForEach(rep.tiers) { t in
                            HStack(spacing: 6) {
                                Text(tierLabel(t)).font(.caption).frame(width: 78, alignment: .leading)
                                Text("买 " + GMPx.fiat(t.buyUsd) + "·" + String(t.nb)).font(.caption2.monospacedDigit()).foregroundStyle(Color.green)
                                Text("卖 " + GMPx.fiat(t.sellUsd) + "·" + String(t.ns)).font(.caption2.monospacedDigit()).foregroundStyle(Color.red)
                                Spacer(minLength: 2)
                                Text(GMPx.fiat(t.net, signed: true)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(t.net >= 0 ? Color.green : Color.red)
                            }
                        }
                        GLNote(text: "每行：买入额·笔数 / 卖出额·笔数 / 净额。大单资金方向比总体买卖笔数更能说明主力在做什么。")
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("成交明细（最新在上）").font(.subheadline.weight(.semibold))
                        ForEach(Array(lab.trades.prefix(shown).enumerated()), id: \.offset) { _, t in
                            HStack(spacing: 8) {
                                Text(TZ.short(Date(timeIntervalSince1970: t.t))).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
                                Text(t.buy ? "买" : "卖").font(.caption.weight(.bold)).foregroundStyle(t.buy ? Color.green : Color.red).frame(width: 16)
                                Text(GMPx.fiat(t.usd)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(t.buy ? Color.green : Color.red)
                                Text(t.px > 0 ? GMPx.usd(t.px) : "—").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                                Spacer(minLength: 2)
                                Menu {
                                    GMWalletMenuContent(chain: vm.chain, addr: t.who)
                                } label: {
                                    Text(Addr.short(t.who)).font(.caption2.monospaced()).foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        if shown < lab.trades.count {
                            Button("再显示 50 笔") { shown += 50 }.font(.caption.weight(.semibold))
                        }
                    }
                }
            }
        }
        .task(id: vm.address + "|" + String(vm.refreshToken)) { await lab.load(vm, force: true) }
    }
}

// MARK: - 钱包分析
struct GMWalletLabView: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var lab = GMLabStore.shared
    @State private var shown = 12

    private func tagColor(_ s: String) -> Color {
        if s.contains("对倒") || s.contains("定时") || s.contains("固定") { return Color.orange }
        if s.contains("持有榜") { return Color.purple }
        if s.contains("只卖") { return Color.red }
        if s.contains("只买") { return Color.green }
        return Color.gray
    }

    private func row(_ w: GLWallet) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Menu {
                    GMWalletMenuContent(chain: vm.chain, addr: w.addr)
                } label: {
                    Text(Addr.short(w.addr)).font(.caption.monospaced()).foregroundStyle(Color.accentColor)
                }
                Spacer()
                if let r = w.roi {
                    Text(String(format: "%+.0f%%", r)).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(r >= 0 ? Color.green : Color.red)
                } else if w.preHold {
                    Text("含窗口前持仓").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !w.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(w.tags.prefix(4), id: \.self) { s in
                        Text(s).font(.system(size: 9.5, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 2)
                            .background(tagColor(s).opacity(0.15), in: Capsule()).foregroundStyle(tagColor(s))
                    }
                }
            }
            HStack(spacing: 8) {
                Text("买 " + GMPx.fiat(w.buyUsd) + "·" + String(w.nb)).foregroundStyle(Color.green)
                Text("卖 " + GMPx.fiat(w.sellUsd) + "·" + String(w.ns)).foregroundStyle(Color.red)
                Spacer()
                Text(TZ.short(Date(timeIntervalSince1970: w.firstT)) + " 起").foregroundStyle(.secondary)
            }
            .font(.caption2.monospacedDigit())
            if let ab = w.avgBuy {
                var line: String = "买入均价 " + GMPx.usd(ab)
                if let cp = vm.main?.price { line += " → 现价 " + GMPx.usd(cp) }
                Text(line).font(.caption2).foregroundStyle(.secondary)
                if w.ns > 0 && !w.preHold { Text("已兑现 " + GMPx.fiat(w.realized, signed: true) + (w.unrealized != nil ? " · 浮动 " + GMPx.fiat(w.unrealized, signed: true) : "")).font(.caption2).foregroundStyle(.secondary) }
                else if let u = w.unrealized { Text("浮动 " + GMPx.fiat(u, signed: true)).font(.caption2).foregroundStyle(.secondary) }
            }
            Divider()
        }
    }

    var body: some View {
        let rep: GLReport = lab.rep
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("钱包分析（窗口内活跃地址）", systemImage: "person.crop.rectangle.stack").font(.headline)
                        Spacer()
                        if lab.loading { ProgressView() }
                    }
                    if lab.trades.isEmpty {
                        Text(lab.note ?? "读取成交…").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        GLNote(text: "窗口内 " + String(rep.uniqBuyers) + " 个买家 · " + String(rep.uniqSellers) + " 个卖家。成本与盈亏只按窗口内（约 " + Fmt2.dur(rep.span) + "）的买卖估算，窗口以前的仓位看不到；按成交额排序。")
                        ForEach(rep.wallets.prefix(shown)) { row($0) }
                        if shown < rep.wallets.count { Button("再显示 12 个") { shown += 12 }.font(.caption.weight(.semibold)) }
                    }
                }
            }
            if !rep.clusters.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("同一区块多钱包买入").font(.subheadline.weight(.semibold))
                        ForEach(rep.clusters.prefix(5)) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("区块 #" + String(c.block) + " · " + String(c.wallets.count) + " 个地址 · " + GMPx.fiat(c.usd)).font(.caption.weight(.semibold))
                                Text(c.wallets.prefix(4).map { Addr.short($0) }.joined(separator: "、") + (c.wallets.count > 4 ? " 等" : "")).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        GLNote(text: "同块出现 4 个以上不同买家，可能是同一控制人拆分的地址（捆绑 / 狙击），也可能是行情火爆时碰巧同块。需要结合这些钱包后续是否同时卖出来判断。")
                    }
                }
            }
        }
        .task(id: vm.address + "|" + String(vm.refreshToken)) { await lab.load(vm) }
    }
}

// MARK: - 流动性 / 退出深度
struct GMLiquidityLabView: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var fr = GMFreeStore.shared

    private func pct(_ v: Double) -> String { return String(format: "%.1f%%", v) }

    var body: some View {
        let L: Double = vm.main?.liq ?? 0
        let T: Double = L / 2
        let mc: Double = vm.main?.marketCap ?? vm.main?.fdv ?? 0
        let vol: Double = vm.main?.volume?["h24"] ?? 0
        let amounts: [Double] = [500, 1000, 5000, 10000, 50000]
        var top10: Double? = fr.v["top10"]
        if top10 == nil, let w = vm.conc?.wallets10 { top10 = Double(w) }
        let dev: Double? = fr.v["dev"]
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("退出深度（卖出会砸多少）", systemImage: "drop.triangle").font(.headline)
                    if T <= 0 {
                        Text("没有流动性数据").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(amounts, id: \.self) { x in
                            let slip: Double = x / (T + x) * 100
                            let drop: Double = (1 - pow(T / (T + x), 2)) * 100
                            HStack {
                                Text("卖 " + GMPx.fiat(x)).font(.caption.weight(.semibold)).frame(width: 78, alignment: .leading)
                                Text("成交滑点 " + pct(slip)).font(.caption.monospacedDigit()).foregroundStyle(slip >= 10 ? Color.red : (slip >= 3 ? Color.orange : Color.green))
                                Spacer()
                                Text("池价 −" + pct(drop)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        let caps: [Double] = [0.03, 0.05, 0.10]
                        HStack(spacing: 10) {
                            ForEach(caps, id: \.self) { s in
                                VStack(spacing: 2) {
                                    Text("滑点 ≤" + String(format: "%.0f%%", s * 100)).font(.caption2).foregroundStyle(.secondary)
                                    Text(GMPx.fiat(s * T / (1 - s))).font(.caption.weight(.bold).monospacedDigit())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        GLNote(text: "最深池流动性 " + GMPx.fiat(L) + "，按 v2 恒定乘积粗估（单边深度 " + GMPx.fiat(T) + "）。集中流动性（v3 / v4）和聚合器拆单会让实际更深或更浅，只作量级参考。上面三格是不同滑点容忍下大约能一次卖出的金额。")
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("抛压 vs 池子").font(.subheadline.weight(.semibold))
                    if L > 0 && mc > 0 {
                        GLRow(k: "市值 / 流动性", v: String(format: "%.1f 倍", mc / L), c: mc / L > 40 ? Color.red : (mc / L > 15 ? Color.orange : Color.green))
                    }
                    if L > 0 && vol > 0 {
                        GLRow(k: "24h 成交 / 流动性", v: String(format: "%.1f 倍", vol / L), c: vol / L > 15 ? Color.orange : Color.primary)
                    }
                    if let t10 = top10, mc > 0, T > 0 {
                        let val: Double = mc * t10 / 100
                        GLRow(k: "前十钱包持仓市值", v: GMPx.fiat(val) + "（池子单边深度的 " + String(format: "%.1f", val / T) + " 倍）", c: val / T > 3 ? Color.red : (val / T > 1 ? Color.orange : Color.green))
                    }
                    if let d = dev, mc > 0, T > 0 {
                        let val: Double = mc * d / 100
                        GLRow(k: "Dev 持仓市值", v: GMPx.fiat(val) + "（" + String(format: "%.1f", val / T) + " 倍）", c: val / T > 1 ? Color.red : Color.primary)
                    }
                    GLNote(text: "持仓市值 = 市值 × 占比。倍数大于 1 表示这些钱包一旦同时卖出，池子根本接不住，价格会被砸穿；倍数越大越危险。占比来自顶部数据条的数据源。")
                }
            }
            if vm.pairs.count > 1 {
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("流动性分布").font(.subheadline.weight(.semibold))
                        let tot: Double = vm.pairs.reduce(0) { $0 + $1.liq }
                        ForEach(Array(vm.pairs.prefix(5).enumerated()), id: \.offset) { _, p in
                            HStack {
                                Text((p.dexId ?? "?") + " · " + (p.quoteToken?.symbol ?? "?")).font(.caption)
                                Spacer()
                                Text(GMPx.fiat(p.liq) + (tot > 0 ? String(format: "（%.0f%%）", p.liq / tot * 100) : "")).font(.caption.monospacedDigit())
                            }
                        }
                        GLNote(text: "共 " + String(vm.pairs.count) + " 个池子，合计 " + GMPx.fiat(tot) + "。流动性越分散，单个池子的滑点越比表面大，但聚合器会跨池拆单。")
                    }
                }
            }
            GMTrendCard(vm: vm)
        }
    }
}

struct GLRow: View {
    let k: String
    let v: String
    let c: Color
    var body: some View {
        HStack {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(c).multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - 本机趋势
struct GMTrendCard: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var fr = GMFreeStore.shared

    private func delta(_ a: Double, _ b: Double) -> Double? {
        if a <= 0 || b <= 0 { return nil }
        return (b - a) / a * 100
    }

    private func line(_ title: String, _ d: Double?, _ extra: String = "") -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if let x = d {
                Text(String(format: "%+.1f%%", x) + extra).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(x >= 0 ? Color.green : Color.red)
            } else {
                Text("—").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        let pts: [GLPoint] = GMTrend.load(vm.chain, vm.address)
        let now: Double = Date().timeIntervalSince1970
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("本机监控趋势").font(.subheadline.weight(.semibold))
                if pts.count < 2 {
                    Text("这个币在本机只有 " + String(pts.count) + " 个记录点。停留在代币页每 2 分钟记一点，攒够 10 分钟以上才有趋势；这是别处看不到的变化量（持有者增减、前十占比漂移、流动性撤出）。").font(.caption).foregroundStyle(.secondary)
                } else if let f = pts.first, let l = pts.last {
                    let hourAgo: GLPoint? = pts.last(where: { $0.t <= now - 3600 })
                    Text("自 " + TZ.short(Date(timeIntervalSince1970: f.t)) + " 起共 " + String(pts.count) + " 个点，跨度 " + Fmt2.dur(l.t - f.t)).font(.caption2).foregroundStyle(.secondary)
                    line("价格（全程）", delta(f.px, l.px))
                    line("流动性（全程）", delta(f.liq, l.liq))
                    if f.holders > 0 && l.holders > 0 {
                        let d: Double = l.holders - f.holders
                        HStack {
                            Text("持有者（全程）").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%+.0f", d) + "（" + String(format: "%.0f", f.holders) + " → " + String(format: "%.0f", l.holders) + "）").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(d >= 0 ? Color.green : Color.red)
                        }
                    }
                    if f.top10 >= 0 && l.top10 >= 0 {
                        let d: Double = l.top10 - f.top10
                        HStack {
                            Text("前十占比（全程）").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f%% → %.1f%%", f.top10, l.top10)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(d <= 0 ? Color.green : Color.orange)
                        }
                    }
                    if let h = hourAgo {
                        Divider()
                        line("流动性（近 1 小时）", delta(h.liq, l.liq))
                        line("价格（近 1 小时）", delta(h.px, l.px))
                    }
                }
            }
        }
        .onAppear { GMTrend.record(vm) }
    }
}
