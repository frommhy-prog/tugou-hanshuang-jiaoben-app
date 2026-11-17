import SwiftUI

// MARK: - 第二代：交易记录 / 钱包分析
// 1) 成交在本机累积（最多 3000 笔，离开页面太久出现缺口就重置窗口），窗口越长越准
// 2) 钱包按 FIFO 配对买卖：已兑现 / 浮动盈亏、持有时长、胜率、买入位置、同块买卖（MEV）
// 3) 全窗口级别：买卖方均价、累计净流入 vs 价格背离、大卖单承接率、近期买家成本分布、盈利盘 / 套牢盘、持有榜大户动向

// MARK: - 成交本机库
enum GLArchive {
    private static var cache: [String: [GLTrade]] = [:]

    private static func url(_ k: String) -> URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        var h: UInt64 = 5381
        for b in k.utf8 { h = (h &* 33) &+ UInt64(b) }
        return base.appendingPathComponent("gl_trades_" + String(h, radix: 16) + ".json")
    }

    static func tid(_ t: GLTrade) -> String {
        return t.tx + "|" + t.who + "|" + String(Int(t.t)) + "|" + (t.buy ? "b" : "s") + "|" + String(Int(t.usd * 100))
    }

    static func load(_ k: String) -> [GLTrade] {
        if let c = cache[k] { return c }
        guard let u = url(k), let d = try? Data(contentsOf: u), let a = try? JSONDecoder().decode([GLTrade].self, from: d) else { return [] }
        cache[k] = a
        return a
    }

    // 合并新读到的成交；新一批和库里的最新成交接不上（中间有缺口）就丢掉旧库，窗口重新开始
    static func merge(_ k: String, _ add: [GLTrade]) -> [GLTrade] {
        var arr: [GLTrade] = load(k)
        let oldestNew: Double = add.map { $0.t }.min() ?? 0
        let newestOld: Double = arr.map { $0.t }.max() ?? 0
        if !arr.isEmpty && oldestNew > newestOld + 1 { arr = [] }
        var seen: Set<String> = Set(arr.map { tid($0) })
        for t in add {
            let i: String = tid(t)
            if !seen.contains(i) {
                arr.append(t)
                seen.insert(i)
            }
        }
        arr.sort { $0.t > $1.t }
        if arr.count > 3000 { arr = Array(arr.prefix(3000)) }
        cache[k] = arr
        if let u = url(k), let d = try? JSONEncoder().encode(arr) { try? d.write(to: u, options: .atomic) }
        return arr
    }

    static func clear(_ k: String) {
        cache[k] = nil
        if let u = url(k) { try? FileManager.default.removeItem(at: u) }
    }
}

// MARK: - 结构
struct GL2Holder {
    let addr: String
    let pct: Double
    let rank: Int
}

struct GL2Lot {
    var amt: Double
    let px: Double
    let t: Double
}

struct GL2Wallet: Identifiable {
    let addr: String
    var nb: Int = 0
    var ns: Int = 0
    var buyUsd: Double = 0
    var sellUsd: Double = 0
    var buyAmt: Double = 0
    var sellAmt: Double = 0
    var firstT: Double = 0
    var lastT: Double = 0
    var realized: Double = 0
    var matchedCost: Double = 0
    var holdAmt: Double = 0
    var holdCost: Double = 0
    var unrealized: Double?
    var preSellUsd: Double = 0
    var holdSecs: [Double] = []
    var wins: Int = 0
    var losses: Int = 0
    var buyPos: Double?
    var sameBlock: Int = 0
    var tags: [String] = []
    var holderPct: Double?
    var status: String = ""
    var pnl: Double = 0
    var roi: Double?
    var id: String { addr }
    var gross: Double { buyUsd + sellUsd }
    var isBot: Bool {
        return tags.contains("对倒嫌疑") || (tags.contains("定时节奏") && tags.contains("固定金额")) || tags.contains("同块买卖(MEV)")
    }
}

struct GL2Move: Identifiable {
    let id: String
    let holder: GL2Holder
    let buy: Double
    let sell: Double
    let seen: Bool
    var net: Double { buy - sell }
}

struct GL2Bin: Identifiable {
    let id: Int
    let lo: Double
    let hi: Double
    let amt: Double
}

struct GL2Report {
    var base = GLReport()
    var count: Int = 0
    var span: Double = 0
    var wallets: [GL2Wallet] = []
    var insights: [GLInsight] = []
    var cvd: [Double] = []
    var pxs: [Double] = []
    var bins: [GL2Bin] = []
    var curBin: Int = -1
    var buyVwap: Double = 0
    var sellVwap: Double = 0
    var pxLo: Double = 0
    var pxHi: Double = 0
    var bigThr: Double = 0
    var moves: [GL2Move] = []
    var winners: [GL2Wallet] = []
    var losers: [GL2Wallet] = []
}

// MARK: - 计算
enum GL2Calc {
    static func f(_ v: Double) -> String { return GMPx.fiat(v) }

    static func build(_ raw: [GLTrade], curPx: Double?, holders: [GL2Holder]) -> GL2Report {
        var out = GL2Report()
        var hd: [String: Double] = [:]
        for h in holders { hd[h.addr.lowercased()] = h.pct }
        out.base = GLCalc.build(raw, curPx: curPx, holders: hd)
        let ts: [GLTrade] = raw.sorted { $0.t < $1.t }
        out.count = ts.count
        guard ts.count >= 2, let first = ts.first, let last = ts.last else { return out }
        out.span = last.t - first.t
        let total: Double = out.base.totalUsd

        // 价格区间（去掉两端 5% 的极端值）
        let pxAll: [Double] = ts.map { $0.px }.filter { $0 > 0 }.sorted()
        var lo: Double = 0
        var hi: Double = 0
        if pxAll.count >= 10 {
            lo = pxAll[Int(Double(pxAll.count - 1) * 0.05)]
            hi = pxAll[Int(Double(pxAll.count - 1) * 0.95)]
        } else if let a = pxAll.first, let b = pxAll.last {
            lo = a
            hi = b
        }
        if hi <= lo { hi = lo * 1.0001 }
        out.pxLo = lo
        out.pxHi = hi
        let sizes: [Double] = ts.map { $0.usd }.sorted()
        out.bigThr = sizes[Int(Double(sizes.count - 1) * 0.9)]

        // 买卖方均价
        var bu: Double = 0
        var ba: Double = 0
        var su: Double = 0
        var sa: Double = 0
        for t in ts where t.amt > 0 {
            if t.buy {
                bu += t.usd
                ba += t.amt
            } else {
                su += t.usd
                sa += t.amt
            }
        }
        out.buyVwap = ba > 0 ? bu / ba : 0
        out.sellVwap = sa > 0 ? su / sa : 0

        // 累计净流入 + 价格序列
        var cum: Double = 0
        var cv: [Double] = []
        var pv: [Double] = []
        var lastPx: Double = ts.first(where: { $0.px > 0 })?.px ?? 0
        for t in ts {
            cum += t.buy ? t.usd : -t.usd
            if t.px > 0 { lastPx = t.px }
            cv.append(cum)
            pv.append(lastPx)
        }
        let step: Int = max(1, cv.count / 100)
        var cvd: [Double] = []
        var pxs: [Double] = []
        var k: Int = 0
        while k < cv.count {
            cvd.append(cv[k])
            pxs.append(pv[k])
            k += step
        }
        if (cv.count - 1) % step != 0 {
            cvd.append(cv[cv.count - 1])
            pxs.append(pv[pv.count - 1])
        }
        out.cvd = cvd
        out.pxs = pxs

        // 钱包 FIFO
        var ws: [String: GL2Wallet] = [:]
        var lots: [String: [GL2Lot]] = [:]
        var perT: [String: [Double]] = [:]
        var perUsd: [String: [Double]] = [:]
        var bf: [String: [Int: Int]] = [:]
        for t in ts {
            if t.who.isEmpty { continue }
            var w: GL2Wallet = ws[t.who] ?? GL2Wallet(addr: t.who)
            if w.firstT == 0 { w.firstT = t.t }
            w.lastT = t.t
            perT[t.who, default: []].append(t.t)
            perUsd[t.who, default: []].append(t.usd)
            if t.block > 0 { bf[t.who, default: [:]][t.block, default: 0] |= (t.buy ? 1 : 2) }
            if t.buy {
                w.nb += 1
                w.buyUsd += t.usd
                w.buyAmt += t.amt
                if t.amt > 0 && t.px > 0 { lots[t.who, default: []].append(GL2Lot(amt: t.amt, px: t.px, t: t.t)) }
            } else {
                w.ns += 1
                w.sellUsd += t.usd
                w.sellAmt += t.amt
                if t.amt > 0 && t.px > 0 {
                    var rem: Double = t.amt
                    var arr: [GL2Lot] = lots[t.who] ?? []
                    while rem > 0 && !arr.isEmpty {
                        let m: Double = min(rem, arr[0].amt)
                        let lp: Double = arr[0].px
                        w.realized += m * (t.px - lp)
                        w.matchedCost += m * lp
                        w.holdSecs.append(t.t - arr[0].t)
                        if t.px >= lp { w.wins += 1 } else { w.losses += 1 }
                        arr[0].amt -= m
                        rem -= m
                        if arr[0].amt <= 1e-12 { arr.removeFirst() }
                    }
                    lots[t.who] = arr
                    if rem > 0 { w.preSellUsd += rem * t.px }
                }
            }
            ws[t.who] = w
        }

        var list: [GL2Wallet] = []
        var allLots: [GL2Lot] = []
        var mevUsd: Double = 0
        for (addr, w0) in ws {
            var w: GL2Wallet = w0
            var ha: Double = 0
            var hc: Double = 0
            for l in lots[addr] ?? [] {
                ha += l.amt
                hc += l.amt * l.px
                allLots.append(l)
            }
            w.holdAmt = ha
            w.holdCost = hc
            if let cp = curPx, ha > 0 { w.unrealized = ha * cp - hc }
            w.pnl = w.realized + (w.unrealized ?? 0)
            let denom: Double = w.matchedCost + hc
            if denom > 0 { w.roi = w.pnl / denom * 100 }
            if w.nb == 0 && w.ns > 0 {
                w.status = "老仓卖出"
            } else if w.buyAmt > 0 && ha / w.buyAmt >= 0.02 {
                w.status = "持有中"
            } else if w.ns > 0 {
                w.status = "已清仓"
            } else {
                w.status = "持有中"
            }
            if w.buyAmt > 0 {
                let v: Double = w.buyUsd / w.buyAmt
                w.buyPos = min(1, max(0, (v - lo) / (hi - lo)))
                if w.nb >= 3, let p = w.buyPos {
                    if p >= 0.75 { w.tags.append("追高买入") }
                    if p <= 0.25 { w.tags.append("低吸") }
                }
            }
            if w.holdSecs.count >= 2 {
                let med: Double = GLCalc.median(w.holdSecs)
                if med < 300 { w.tags.append("秒进秒出") } else if med < 1800 { w.tags.append("短线") } else if med >= 3600 { w.tags.append("拿得住") }
            }
            let times: [Double] = (perT[addr] ?? []).sorted()
            let szs: [Double] = perUsd[addr] ?? []
            let n: Int = w.nb + w.ns
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
                let med: Double = GLCalc.median(szs)
                if med > 0 {
                    let near: Int = szs.filter { abs($0 - med) / med <= 0.03 }.count
                    if near >= max(4, Int(Double(n) * 0.6)) { w.tags.append("固定金额") }
                }
            }
            if w.nb >= 3 && w.ns >= 3 {
                let a: Double = max(w.buyUsd, w.sellUsd)
                let b: Double = min(w.buyUsd, w.sellUsd)
                if a > 0 && b / a >= 0.85 { w.tags.append("对倒嫌疑") }
            }
            let both: Int = (bf[addr] ?? [:]).values.filter { $0 == 3 }.count
            w.sameBlock = both
            if both >= 1 { mevUsd += w.gross }
            if both >= 2 { w.tags.append("同块买卖(MEV)") }
            if let hp = hd[addr.lowercased()] {
                w.holderPct = hp
                w.tags.append("持有榜 " + String(format: "%.1f%%", hp))
            }
            list.append(w)
        }
        list.sort { $0.gross > $1.gross }
        out.wallets = list

        // 近期买家成本分布
        if let cp = curPx, cp > 0, lo > 0, hi > lo, !allLots.isEmpty {
            let nb: Int = 12
            var amt: [Double] = Array(repeating: 0, count: nb)
            for l in allLots {
                let r: Double = (min(hi, max(lo, l.px)) - lo) / (hi - lo)
                let idx: Int = min(nb - 1, Int(r * Double(nb)))
                amt[idx] += l.amt
            }
            var bins: [GL2Bin] = []
            for i in 0..<nb {
                let a: Double = lo + (hi - lo) * Double(i) / Double(nb)
                let b: Double = lo + (hi - lo) * Double(i + 1) / Double(nb)
                bins.append(GL2Bin(id: i, lo: a, hi: b, amt: amt[i]))
            }
            out.bins = bins
            let cr: Double = (min(hi, max(lo, cp)) - lo) / (hi - lo)
            out.curBin = min(nb - 1, Int(cr * Double(nb)))
        }

        // 持有榜大户动向
        var wmap: [String: GL2Wallet] = [:]
        for w in list { wmap[w.addr.lowercased()] = w }
        var moves: [GL2Move] = []
        for h in holders.sorted(by: { $0.pct > $1.pct }).prefix(12) {
            if let w = wmap[h.addr.lowercased()] {
                moves.append(GL2Move(id: h.addr, holder: h, buy: w.buyUsd, sell: w.sellUsd, seen: true))
            } else {
                moves.append(GL2Move(id: h.addr, holder: h, buy: 0, sell: 0, seen: false))
            }
        }
        out.moves = moves
        out.winners = Array(list.filter { $0.pnl > 0 && $0.roi != nil }.sorted { $0.pnl > $1.pnl }.prefix(5))
        out.losers = Array(list.filter { $0.pnl < 0 && $0.roi != nil }.sorted { $0.pnl < $1.pnl }.prefix(5))

        // 结论
        var ins: [GLInsight] = []
        func add(_ level: Int, _ title: String, _ detail: String) {
            ins.append(GLInsight(id: ins.count, level: level, title: title, detail: detail))
        }
        func seg(_ from: Int) -> (Double, Double)? {
            if from >= ts.count - 2 { return nil }
            let a: Double = pv[from]
            let b: Double = pv[ts.count - 1]
            if a <= 0 || b <= 0 { return nil }
            let base: Double = from > 0 ? cv[from - 1] : 0
            return ((b - a) / a * 100, cv[ts.count - 1] - base)
        }
        if total > 0 {
            if let w = seg(0) {
                if w.0 >= 2 && w.1 < -total * 0.03 {
                    add(2, "价格涨了，但资金在净流出", "窗口内价格 " + String(format: "%+.1f%%", w.0) + "，累计净流入却是 " + GMPx.fiat(w.1, signed: true) + "。上涨没有资金支撑，常见于小单拉起、大户边涨边出。")
                } else if w.0 <= -2 && w.1 > total * 0.03 {
                    add(3, "价格跌了，但资金在净流入", "窗口内价格 " + String(format: "%+.1f%%", w.0) + "，累计净流入 " + GMPx.fiat(w.1, signed: true) + "。有大资金在下跌里承接。")
                }
            }
            if let r = seg(ts.count * 2 / 3) {
                if r.0 >= 1 && r.1 < -total * 0.01 {
                    add(1, "最近一段：涨价但净流出", "最近三分之一窗口价格 " + String(format: "%+.1f%%", r.0) + "，净流入 " + GMPx.fiat(r.1, signed: true) + "，短线动能在转弱。")
                } else if r.0 <= -1 && r.1 > total * 0.01 {
                    add(3, "最近一段：跌价但净流入", "最近三分之一窗口价格 " + String(format: "%+.1f%%", r.0) + "，净流入 " + GMPx.fiat(r.1, signed: true) + "，下跌被接住。")
                }
            }
        }
        var profitVal: Double = 0
        var underVal: Double = 0
        var underCostLo: Double = 0
        var underCostHi: Double = 0
        for w in list where w.holdAmt > 0 {
            if let u = w.unrealized, let cp = curPx {
                let v: Double = w.holdAmt * cp
                if u >= 0 {
                    profitVal += v
                } else {
                    underVal += v
                    let ac: Double = w.holdCost / w.holdAmt
                    if underCostLo == 0 || ac < underCostLo { underCostLo = ac }
                    if ac > underCostHi { underCostHi = ac }
                }
            }
        }
        let holdTot: Double = profitVal + underVal
        if holdTot > 0 {
            let ps: Double = profitVal / holdTot * 100
            let d1: String = "窗口内买入且仍持有的筹码，" + String(format: "%.0f%%", ps) + " 处于盈利（市值 " + f(profitVal) + "），" + String(format: "%.0f%%", 100 - ps) + " 被套（市值 " + f(underVal) + "）。"
            if ps >= 70 {
                add(1, "近期买家多数盈利，获利盘压力大", d1 + "价格每冲高一点，都有人想落袋。")
            } else if ps <= 30 {
                add(1, "近期买家多数被套，反弹有解套盘", d1 + "被套成本区约 " + GMPx.usd(underCostLo) + " – " + GMPx.usd(underCostHi) + "。")
            } else {
                add(0, "近期买家盈亏参半", d1)
            }
        }
        if !out.moves.isEmpty {
            var sellers: Int = 0
            var buyers: Int = 0
            var idle: Int = 0
            var sold: Double = 0
            for m in out.moves {
                if !m.seen {
                    idle += 1
                } else if m.sell > m.buy * 1.2 && m.sell > 0 {
                    sellers += 1
                    sold += m.sell
                } else if m.buy > m.sell * 1.2 && m.buy > 0 {
                    buyers += 1
                }
            }
            let d: String = "持有榜前 " + String(out.moves.count) + " 名：" + String(sellers) + " 个在减持（卖出 " + f(sold) + "）、" + String(buyers) + " 个在增持、" + String(idle) + " 个窗口内没有成交。"
            if sellers >= 2 {
                add(2, "持有榜大户在出货", d + "（只能匹配到直接以该地址发起交易的大户，经路由合约成交的看不到。）")
            } else if sellers == 1 {
                add(1, "持有榜有大户在减持", d)
            } else if buyers >= 2 {
                add(3, "持有榜大户在增持", d)
            } else {
                add(0, "持有榜大户动向", d)
            }
        }
        if let s = list.filter({ $0.sellUsd > 0 }).max(by: { $0.sellUsd < $1.sellUsd }), out.base.sellUsd > 0 {
            let share: Double = s.sellUsd / out.base.sellUsd * 100
            var d: String = GLCalc.short(s.addr) + " 卖出 " + f(s.sellUsd) + "（占窗口卖出额 " + String(format: "%.0f%%", share) + "）。"
            var lv: Int = 0
            if s.status == "老仓卖出" {
                d += "窗口内没有买入，卖的是更早的仓位，成本看不到。"
                lv = share >= 25 ? 2 : 1
            } else if let roi = s.roi {
                d += "FIFO 估算已兑现 " + GMPx.fiat(s.realized, signed: true) + "，综合回报 " + String(format: "%+.0f%%", roi) + "，" + s.status + "。"
                lv = share >= 30 ? 1 : 0
            }
            add(lv, "最大卖家", d)
        }
        // 大卖单承接
        let bigSells: [GLTrade] = ts.filter { !$0.buy && $0.px > 0 }.sorted { $0.usd > $1.usd }.prefix(8).map { $0 }
        var tested: Int = 0
        var absorbed: Int = 0
        var drops: [Double] = []
        for s in bigSells {
            let pre: [Double] = ts.filter { $0.t >= s.t - 180 && $0.t < s.t && $0.px > 0 }.map { $0.px }
            let post: [Double] = ts.filter { $0.t > s.t && $0.t <= s.t + 300 && $0.px > 0 }.map { $0.px }
            if pre.count < 2 || post.count < 2 { continue }
            let p0: Double = GLCalc.median(pre)
            let p1: Double = GLCalc.median(post)
            if p0 <= 0 { continue }
            tested += 1
            drops.append((p1 - p0) / p0 * 100)
            if p1 >= p0 * 0.99 { absorbed += 1 }
        }
        if tested >= 4 {
            let rate: Double = Double(absorbed) / Double(tested)
            let avg: Double = drops.reduce(0, +) / Double(drops.count)
            let d: String = "最大的 " + String(bigSells.count) + " 笔卖单里可评估 " + String(tested) + " 笔，其中 " + String(absorbed) + " 笔在 5 分钟内价格回到卖前；平均冲击 " + String(format: "%+.1f%%", avg) + "。"
            if rate >= 0.7 {
                add(3, "大卖单被承接", d + "买盘有深度。")
            } else if rate <= 0.3 {
                add(2, "大卖单砸下去就没回来", d + "买盘接不住，大额出货会直接留下价格缺口。")
            } else {
                add(0, "大卖单承接一般", d)
            }
        }
        // 已兑现利润集中
        let pos: [GL2Wallet] = list.filter { $0.realized > 0 }.sorted { $0.realized > $1.realized }
        let posSum: Double = pos.reduce(0) { $0 + $1.realized }
        if pos.count >= 3 && posSum > 0 {
            let top3: Double = pos.prefix(3).reduce(0) { $0 + $1.realized }
            let exited: Int = pos.filter { $0.status == "已清仓" }.count
            add(0, "已兑现利润", "窗口内共 " + String(pos.count) + " 个钱包已落袋盈利，合计 " + f(posSum) + "，前 3 个拿走 " + String(format: "%.0f%%", top3 / posSum * 100) + "；其中 " + String(exited) + " 个已清仓离场。")
        }
        // 买卖方均价
        if out.buyVwap > 0 && out.sellVwap > 0 {
            let diff: Double = (out.buyVwap - out.sellVwap) / out.sellVwap * 100
            if abs(diff) >= 1.5 {
                let d: String = "窗口内买方平均成交价 " + GMPx.usd(out.buyVwap) + "，卖方平均成交价 " + GMPx.usd(out.sellVwap) + "（" + String(format: "%+.1f%%", diff) + "）。"
                if diff > 0 {
                    add(0, "买盘集中在更高的价位", d + "买的人在追高，卖的人更早在低位出了货。结合价格走势看。")
                } else {
                    add(0, "卖盘集中在更高的价位", d + "卖的人在高位出货，买的人是低位进来的。结合价格走势看。")
                }
            }
        }
        // MEV / 套利
        if total > 0 {
            let share: Double = mevUsd / total * 100
            if share >= 10 {
                add(1, "同块买卖（MEV / 套利）占 " + String(format: "%.0f%%", share), "有钱包在同一个区块里既买又卖，成交额合计 " + f(mevUsd) + "。这部分不是真实方向性资金，看成交量时应扣除。")
            }
        }
        // 单笔规模趋势
        if ts.count >= 40 {
            let mid: Int = ts.count / 2
            let m1: Double = GLCalc.median(ts[0..<mid].map { $0.usd })
            let m2: Double = GLCalc.median(ts[mid...].map { $0.usd })
            if m1 > 0 && m2 > 0 {
                let x: Double = m2 / m1
                if x >= 1.6 {
                    add(0, "单笔成交在变大", "窗口后半段单笔成交中位数 " + f(m2) + "，是前半段 " + f(m1) + " 的 " + String(format: "%.1f", x) + " 倍，大一点的资金在进场。")
                } else if x <= 0.6 {
                    add(0, "单笔成交在变小", "窗口后半段单笔成交中位数 " + f(m2) + "，只有前半段 " + f(m1) + " 的 " + String(format: "%.1f", x) + " 倍，大资金在退场或观望。")
                }
            }
        }
        out.insights = ins
        return out
    }
}

// MARK: - 小图
struct GL2Spark: View {
    let price: [Double]
    let flow: [Double]

    private func line(_ v: [Double], _ s: CGSize, _ c: Color) -> some View {
        Path { p in
            guard v.count >= 2, let lo = v.min(), let hi = v.max(), hi > lo else { return }
            for (i, x) in v.enumerated() {
                let px: CGFloat = CGFloat(i) / CGFloat(v.count - 1) * s.width
                let py: CGFloat = s.height - CGFloat((x - lo) / (hi - lo)) * s.height
                if i == 0 {
                    p.move(to: CGPoint(x: px, y: py))
                } else {
                    p.addLine(to: CGPoint(x: px, y: py))
                }
            }
        }
        .stroke(c, lineWidth: 1.6)
    }

    var body: some View {
        GeometryReader { g in
            ZStack {
                line(flow, g.size, Color.orange)
                line(price, g.size, Color.blue)
            }
        }
        .frame(height: 90)
    }
}

struct GL2Chips: View {
    let bins: [GL2Bin]
    let cur: Int

    var body: some View {
        let mx: Double = bins.map { $0.amt }.max() ?? 1
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(bins) { b in
                    let h: CGFloat = max(2, CGFloat(b.amt / max(mx, 1e-12)) * 70)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(b.id <= cur ? Color.green.opacity(0.75) : Color.red.opacity(0.75))
                        .frame(height: h)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(b.id == cur ? Color.primary : Color.clear, lineWidth: 1.5)
                        )
                }
            }
            .frame(height: 70, alignment: .bottom)
            HStack {
                Text(GMPx.usd(bins.first?.lo ?? 0)).font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Text("现价所在价位（黑框）").font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Text(GMPx.usd(bins.last?.hi ?? 0)).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 交易记录分析（第二代）
struct GMTradeLab2View: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var lab = GMLabStore.shared
    @State private var shown = 25
    @State private var filt = 0

    private func tierLabel(_ t: GLTier) -> String {
        if t.lo == 0 { return "<" + GMPx.fiat(t.hi) }
        if t.hi == Double.infinity { return "≥" + GMPx.fiat(t.lo) }
        return GMPx.fiat(t.lo) + "–" + GMPx.fiat(t.hi)
    }

    private func allInsights(_ r: GL2Report) -> [GLInsight] {
        let skip: Set<String> = ["最大卖家", "近期买家的持仓成本"]
        var out: [GLInsight] = r.insights
        for i in r.base.insights where !skip.contains(i.title) {
            out.append(GLInsight(id: out.count, level: i.level, title: i.title, detail: i.detail))
        }
        return out
    }

    private func headLine(_ r: GL2Report) -> String {
        let b: GLReport = r.base
        let p1: String = "本机累积 " + String(r.count) + " 笔成交，覆盖约 " + Fmt2.dur(r.span) + "（停留越久越准；离开太久出现缺口会重置窗口）。"
        let p2: String = "买 " + String(b.nb) + " 笔 " + GMPx.fiat(b.buyUsd) + " · 卖 " + String(b.ns) + " 笔 " + GMPx.fiat(b.sellUsd)
        let p3: String = " · 净 " + GMPx.fiat(b.buyUsd - b.sellUsd, signed: true) + "。来源 GeckoTerminal 最深池，地址是交易发起方。"
        return p1 + p2 + p3
    }

    private func filtered(_ r: GL2Report) -> [GLTrade] {
        switch filt {
        case 1: return lab.trades.filter { $0.buy }
        case 2: return lab.trades.filter { !$0.buy }
        case 3: return lab.trades.filter { $0.usd >= r.bigThr }
        default: return lab.trades
        }
    }

    private func filterBar() -> some View {
        let names: [String] = ["全部", "只看买", "只看卖", "大单"]
        return HStack(spacing: 6) {
            ForEach(0..<names.count, id: \.self) { i in
                Button { filt = i } label: {
                    Text(names[i]).font(.caption.weight(filt == i ? .bold : .regular))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(filt == i ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: Capsule())
                        .foregroundStyle(filt == i ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    var body: some View {
        let r: GL2Report = lab.rep2
        let b: GLReport = r.base
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
                        GLNote(text: headLine(r))
                        let list: [GLInsight] = allInsights(r)
                        if list.isEmpty {
                            Text("样本里没有触发任何值得说的结构，不硬编结论。").font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(list) { GLInsightRow(i: $0) }
                    }
                }
            }
            if !lab.trades.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("买方 vs 卖方").font(.subheadline.weight(.semibold))
                        GLRow(k: "买方平均成交价", v: r.buyVwap > 0 ? GMPx.usd(r.buyVwap) : "—", c: Color.green)
                        GLRow(k: "卖方平均成交价", v: r.sellVwap > 0 ? GMPx.usd(r.sellVwap) : "—", c: Color.red)
                        GLRow(k: "窗口价格区间", v: GMPx.usd(r.pxLo) + " – " + GMPx.usd(r.pxHi), c: Color.primary)
                        GLRow(k: "买家 / 卖家（去重）", v: String(b.uniqBuyers) + " / " + String(b.uniqSellers), c: Color.primary)
                    }
                }
                if r.cvd.count >= 2 {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("资金 vs 价格").font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("● 价格").font(.caption2).foregroundStyle(Color.blue)
                                Text("● 累计净流入").font(.caption2).foregroundStyle(Color.orange)
                            }
                            GL2Spark(price: r.pxs, flow: r.cvd)
                            GLNote(text: "两条线各自缩放到同一高度。价格向上、净流入向下 = 上涨没资金；价格向下、净流入向上 = 有人在接。")
                        }
                    }
                }
                if !r.bins.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("近期买家筹码成本分布").font(.subheadline.weight(.semibold))
                            GL2Chips(bins: r.bins, cur: r.curBin)
                            GLNote(text: "窗口内买入、至今没卖出的筹码，按买入价分布。绿 = 现价以下买的（盈利），红 = 现价以上买的（被套，反弹时的解套抛压区）。")
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("谁在买、谁在卖（按单笔金额分档）").font(.subheadline.weight(.semibold))
                        ForEach(b.tiers) { t in
                            HStack(spacing: 6) {
                                Text(tierLabel(t)).font(.caption).frame(width: 78, alignment: .leading)
                                Text("买 " + GMPx.fiat(t.buyUsd) + "·" + String(t.nb)).font(.caption2.monospacedDigit()).foregroundStyle(Color.green)
                                Text("卖 " + GMPx.fiat(t.sellUsd) + "·" + String(t.ns)).font(.caption2.monospacedDigit()).foregroundStyle(Color.red)
                                Spacer(minLength: 2)
                                Text(GMPx.fiat(t.net, signed: true)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(t.net >= 0 ? Color.green : Color.red)
                            }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("成交明细（最新在上）").font(.subheadline.weight(.semibold))
                            Spacer()
                            Button("清空本币成交库") { lab.clearArchive(vm) }.font(.caption2)
                        }
                        filterBar()
                        let rows: [GLTrade] = filtered(r)
                        ForEach(Array(rows.prefix(shown).enumerated()), id: \.offset) { _, t in
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
                        if shown < rows.count {
                            Button("再显示 50 笔（共 " + String(rows.count) + "）") { shown += 50 }.font(.caption.weight(.semibold))
                        }
                    }
                }
            }
        }
        .task(id: vm.address + "|" + String(vm.refreshToken)) { await lab.load(vm, force: true) }
    }
}

// MARK: - 钱包行
struct GL2WalletRow: View {
    let w: GL2Wallet
    let vm: UTokenVM
    let trades: [GLTrade]
    let watched: Bool
    let onWatch: () -> Void
    @State private var open = false

    private func tagColor(_ s: String) -> Color {
        if s.contains("对倒") || s.contains("定时") || s.contains("固定") || s.contains("MEV") { return Color.orange }
        if s.contains("持有榜") { return Color.purple }
        if s.contains("追高") { return Color.red }
        if s.contains("低吸") || s.contains("拿得住") { return Color.green }
        if s.contains("秒进") || s.contains("短线") { return Color.blue }
        return Color.gray
    }

    private func statusColor() -> Color {
        if w.status == "持有中" { return Color.blue }
        if w.status == "老仓卖出" { return Color.orange }
        return Color.gray
    }

    private func tok(_ v: Double) -> String {
        let a: Double = abs(v)
        if a >= 1e9 { return CNUnit.wrap("", v, 2, "") }
        if a >= 1e6 { return CNUnit.wrap("", v, 2, "") }
        if a >= 1e3 { return CNUnit.wrap("", v, 1, "") }
        return String(format: "%.2f", v)
    }

    private func txURL(_ tx: String) -> URL? {
        if tx.isEmpty { return nil }
        return URL(string: GFMap.es(vm.chain) + "/tx/" + tx)
    }

    private func detail() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GLRow(k: "已兑现（FIFO 配对）", v: GMPx.fiat(w.realized, signed: true), c: w.realized >= 0 ? Color.green : Color.red)
            if let u = w.unrealized {
                GLRow(k: "浮动盈亏", v: GMPx.fiat(u, signed: true), c: u >= 0 ? Color.green : Color.red)
            }
            if w.holdAmt > 0 {
                GLRow(k: "窗口内买入仍持有", v: tok(w.holdAmt) + " 枚，成本 " + GMPx.fiat(w.holdCost), c: Color.primary)
            }
            if w.preSellUsd > 0 {
                GLRow(k: "卖出里窗口前的老仓", v: GMPx.fiat(w.preSellUsd), c: Color.orange)
            }
            if w.wins + w.losses > 0 {
                GLRow(k: "配对盈 / 亏", v: String(w.wins) + " / " + String(w.losses), c: Color.primary)
            }
            if w.holdSecs.count >= 1 {
                GLRow(k: "平均持有时长（中位）", v: Fmt2.dur(GLCalc.median(w.holdSecs)), c: Color.primary)
            }
            if let p = w.buyPos {
                GLRow(k: "买入位置（0 最低 / 100 最高）", v: String(format: "%.0f", p * 100), c: p >= 0.75 ? Color.red : (p <= 0.25 ? Color.green : Color.primary))
            }
            if w.sameBlock > 0 {
                GLRow(k: "同块既买又卖", v: String(w.sameBlock) + " 次", c: Color.orange)
            }
            Divider()
            ForEach(Array(trades.prefix(12).enumerated()), id: \.offset) { _, t in
                HStack(spacing: 8) {
                    Text(TZ.short(Date(timeIntervalSince1970: t.t))).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
                    Text(t.buy ? "买" : "卖").font(.caption.weight(.bold)).foregroundStyle(t.buy ? Color.green : Color.red).frame(width: 16)
                    Text(GMPx.fiat(t.usd)).font(.caption.monospacedDigit())
                    Text(t.px > 0 ? GMPx.usd(t.px) : "—").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    if let u = txURL(t.tx) {
                        Link(destination: u) { Image(systemName: "arrow.up.right.square").font(.caption) }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Menu {
                    GMWalletMenuContent(chain: vm.chain, addr: w.addr)
                } label: {
                    Text(Addr.short(w.addr)).font(.caption.monospaced()).foregroundStyle(Color.accentColor)
                }
                Button(action: onWatch) {
                    Image(systemName: watched ? "star.fill" : "star").font(.caption).foregroundStyle(watched ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                Text(w.status).font(.system(size: 9.5, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 2)
                    .background(statusColor().opacity(0.15), in: Capsule()).foregroundStyle(statusColor())
                Spacer()
                if w.roi != nil || w.pnl != 0 {
                    Text(GMPx.fiat(w.pnl, signed: true)).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(w.pnl >= 0 ? Color.green : Color.red)
                    if let r = w.roi { Text(String(format: "%+.0f%%", r)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
                }
                Button { open.toggle() } label: {
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if !w.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(w.tags.prefix(5), id: \.self) { s in
                        Text(s).font(.system(size: 9.5, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 2)
                            .background(tagColor(s).opacity(0.15), in: Capsule()).foregroundStyle(tagColor(s))
                    }
                }
            }
            HStack(spacing: 8) {
                Text("买 " + GMPx.fiat(w.buyUsd) + "·" + String(w.nb)).foregroundStyle(Color.green)
                Text("卖 " + GMPx.fiat(w.sellUsd) + "·" + String(w.ns)).foregroundStyle(Color.red)
                Spacer()
                Text(TZ.short(Date(timeIntervalSince1970: w.lastT))).foregroundStyle(.secondary)
            }
            .font(.caption2.monospacedDigit())
            if open { detail() }
            Divider()
        }
    }
}

// MARK: - 钱包分析（第二代）
struct GMWalletLab2View: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var lab = GMLabStore.shared
    @AppStorage("gmWatchList", store: Cfg.defaults) private var watchStr = ""
    @State private var sort = 0
    @State private var flt = 0
    @State private var shown = 15

    private var watchSet: Set<String> {
        return Set(watchStr.split(separator: ",").map { String($0).lowercased() })
    }

    private func toggleWatch(_ a: String) {
        var arr: [String] = watchStr.split(separator: ",").map { String($0) }
        if let i = arr.firstIndex(where: { $0.lowercased() == a.lowercased() }) {
            arr.remove(at: i)
        } else {
            arr.append(a)
        }
        watchStr = arr.joined(separator: ",")
    }

    private func pass(_ w: GL2Wallet) -> Bool {
        switch flt {
        case 1: return w.pnl > 0
        case 2: return w.pnl < 0
        case 3: return w.status == "持有中"
        case 4: return w.status == "已清仓"
        case 5: return w.isBot
        case 6: return w.holderPct != nil
        case 7: return watchSet.contains(w.addr.lowercased())
        default: return true
        }
    }

    private func ordered(_ ws: [GL2Wallet]) -> [GL2Wallet] {
        switch sort {
        case 1: return ws.sorted { abs($0.pnl) > abs($1.pnl) }
        case 2: return ws.sorted { $0.lastT > $1.lastT }
        default: return ws.sorted { $0.gross > $1.gross }
        }
    }

    private func chipBar() -> some View {
        let names: [String] = ["全部", "盈利", "亏损", "持有中", "已清仓", "机器人", "持有榜", "关注"]
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(0..<names.count, id: \.self) { i in
                    Button { flt = i } label: {
                        Text(names[i]).font(.caption.weight(flt == i ? .bold : .regular))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(flt == i ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: Capsule())
                            .foregroundStyle(flt == i ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func rankRow(_ w: GL2Wallet) -> some View {
        HStack(spacing: 8) {
            Menu {
                GMWalletMenuContent(chain: vm.chain, addr: w.addr)
            } label: {
                Text(Addr.short(w.addr)).font(.caption.monospaced()).foregroundStyle(Color.accentColor)
            }
            Text(w.status).font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(GMPx.fiat(w.pnl, signed: true)).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(w.pnl >= 0 ? Color.green : Color.red)
            if let r = w.roi { Text(String(format: "%+.0f%%", r)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
        }
    }

    private func moveRow(_ m: GL2Move) -> some View {
        let act: String = !m.seen ? "窗口内没有成交" : (m.net > 0 ? "增持 " + GMPx.fiat(m.net, signed: true) : "减持 " + GMPx.fiat(m.net, signed: true))
        let col: Color = !m.seen ? Color.secondary : (m.net > 0 ? Color.green : Color.red)
        return HStack(spacing: 8) {
            Text("#" + String(m.holder.rank)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
            Menu {
                GMWalletMenuContent(chain: vm.chain, addr: m.holder.addr)
            } label: {
                Text(Addr.short(m.holder.addr)).font(.caption.monospaced()).foregroundStyle(Color.accentColor)
            }
            Text(String(format: "%.2f%%", m.holder.pct)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            Text(act).font(.caption2.weight(.semibold)).foregroundStyle(col)
        }
    }

    var body: some View {
        let r: GL2Report = lab.rep2
        let all: [GL2Wallet] = r.wallets
        let shownList: [GL2Wallet] = ordered(all.filter { pass($0) })
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("钱包分析", systemImage: "person.crop.rectangle.stack").font(.headline)
                        Spacer()
                        if lab.loading { ProgressView() }
                    }
                    if lab.trades.isEmpty {
                        Text(lab.note ?? "读取成交…").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        GLNote(text: "窗口 " + Fmt2.dur(r.span) + "、" + String(all.count) + " 个活跃地址。盈亏按 FIFO 把窗口内的买入和卖出配对；窗口之前的仓位没有成本，只标记为老仓。点 ☆ 可关注钱包，点地址跳转 GMGN / 浏览器。")
                        Picker("排序", selection: $sort) {
                            Text("成交额").tag(0)
                            Text("盈亏").tag(1)
                            Text("最近活跃").tag(2)
                        }
                        .pickerStyle(.segmented)
                        chipBar()
                    }
                }
            }
            if !r.winners.isEmpty || !r.losers.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        if !r.winners.isEmpty {
                            Text("赚得最多").font(.subheadline.weight(.semibold))
                            ForEach(r.winners) { rankRow($0) }
                        }
                        if !r.losers.isEmpty {
                            Divider()
                            Text("亏得最多").font(.subheadline.weight(.semibold))
                            ForEach(r.losers) { rankRow($0) }
                        }
                    }
                }
            }
            if !r.moves.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("持有榜大户动向").font(.subheadline.weight(.semibold))
                        ForEach(r.moves) { moveRow($0) }
                        GLNote(text: "按持有占比排序，对比他们在窗口内的净买卖。只能匹配到直接以该地址发起交易的大户；经路由合约、多签成交的看不到，会显示窗口内没有成交。")
                    }
                }
            }
            if !all.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("钱包列表（" + String(shownList.count) + "）").font(.subheadline.weight(.semibold))
                        if shownList.isEmpty {
                            Text("这个筛选条件下没有钱包").font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(shownList.prefix(shown)) { w in
                            GL2WalletRow(w: w, vm: vm, trades: lab.trades.filter { $0.who == w.addr }, watched: watchSet.contains(w.addr.lowercased()), onWatch: { toggleWatch(w.addr) })
                        }
                        if shown < shownList.count {
                            Button("再显示 15 个") { shown += 15 }.font(.caption.weight(.semibold))
                        }
                    }
                }
            }
            if !r.base.clusters.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("同一区块多钱包买入").font(.subheadline.weight(.semibold))
                        ForEach(r.base.clusters.prefix(5)) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("区块 #" + String(c.block) + " · " + String(c.wallets.count) + " 个地址 · " + GMPx.fiat(c.usd)).font(.caption.weight(.semibold))
                                Text(c.wallets.prefix(4).map { Addr.short($0) }.joined(separator: "、") + (c.wallets.count > 4 ? " 等" : "")).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                        GLNote(text: "同块出现 4 个以上不同买家，可能是同一控制人拆分的地址（捆绑 / 狙击），也可能是行情火爆时碰巧同块。看这些钱包后续是否同时卖出。")
                    }
                }
            }
        }
        .task(id: vm.address + "|" + String(vm.refreshToken)) { await lab.load(vm) }
    }
}
