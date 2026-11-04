import SwiftUI

// 钱包情报引擎（Solana）。两套思路的自研实现，全部由链上成交数据按固定规则算出，不依赖 AI：
// ① 钱包标签（机器人 / 狙击手 / 鲸鱼 / 做市路由 / 新钱包 / 休眠 / 聪明钱 / 净输家），参考 Solana Wallet Intel 的分类思路；
// ② 交易行为信号（报复性交易、连亏上头、过度交易、亏损聚集、时段偏好、仓位漂移、追高/摊平、套牢倾向、单币重仓、赚小亏大），参考 Psych 的「从自己的交易看行为心理」思路。
// 说明：Wallet Intel 的托管接口按次收费（x402），Psych 仓库没有开源许可证，所以这里不调用也不复制它们的代码，只自研同类算法，免费、可离线复算。金额单位全部是 SOL。

func cat(_ parts: String...) -> String { parts.joined() }

extension JV {
    var number: Double? {
        switch self {
        case .num(let n): return n
        case .str(let s): return Double(s)
        default: return nil
        }
    }
    func at(_ k: String) -> JV? {
        if case .obj(let o) = self { return o[k] }
        return nil
    }
}

struct IntelWallet: Decodable {
    var address: String?
    var stats: JV?
    var tags: JV?
    var notes: JV?
    var sample: JV?
    var positions: JV?
    var trades: JV?
    var error: JV?
    var detail: JV?
}

struct ITrade {
    let t: Double
    let side: String
    let mint: String
    let sym: String
    let q: String
    let amt: Double
    let qty: Double
    var isBuy: Bool { side.lowercased().hasPrefix("b") }
    var isSell: Bool { side.lowercased().hasPrefix("s") }
}

struct IClosed {
    let mint: String
    let sym: String
    let realized: Double
    let bought: Double
    let first: Double?
    let last: Double?
    var hold: Double? {
        if let f = first, let l = last, l >= f { return l - f }
        return nil
    }
}

struct IntelLabel: Identifiable {
    let id = UUID()
    var name: String
    var level: String
    var basis: String
}

struct IntelSignal: Identifiable {
    let id = UUID()
    var title: String
    var level: String
    var text: String
    var basis: String
}

struct IntelReport {
    var address: String
    var labels: [IntelLabel]
    var metrics: [[String]]
    var signals: [IntelSignal]
    var skipped: [String]
    var score: Int?
    var scoreWhy: [String]
    var notes: [String]
    var winRate: Double?
    var realizedSol: Double?
    var closedN: Int
    var medBuy: Double
    var at: Date
    func has(_ name: String) -> Bool { labels.contains { $0.name == name } }
}

enum WalletIntelEngine {
    static func med(_ a: [Double]) -> Double? {
        if a.isEmpty { return nil }
        let s = a.sorted()
        let m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }

    static func dur(_ sec: Double) -> String {
        if sec < 90 { return String(Int(sec)) + " 秒" }
        if sec < 5400 { return String(Int(sec / 60)) + " 分钟" }
        if sec < 172_800 { return String(format: "%.1f 小时", sec / 3600) }
        return String(format: "%.1f 天", sec / 86_400)
    }

    static func f2(_ v: Double) -> String { String(format: "%.2f", v) }
    static func pc(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }

    static func analyze(_ w: IntelWallet, address: String) -> IntelReport {
        // ---------- 解析 ----------
        var trades: [ITrade] = []
        for x in w.trades?.array ?? [] {
            guard let tt = x.at("t")?.number else { continue }
            let t = tt > 1e12 ? tt / 1000 : tt
            let mint = x.at("mint")?.text ?? ""
            let sym = x.at("sym")?.text ?? Addr.short(mint)
            trades.append(ITrade(t: t, side: x.at("side")?.text ?? "", mint: mint, sym: sym, q: x.at("q")?.text ?? "SOL", amt: x.at("amt")?.number ?? 0, qty: x.at("qty")?.number ?? 0))
        }
        trades.sort { $0.t < $1.t }
        let sol = trades.filter { $0.q == "SOL" && $0.amt > 0 }
        let buys = sol.filter { $0.isBuy }
        var closed: [IClosed] = []
        var perToken: [String: Double] = [:]
        var totalBought = 0.0
        for p in w.positions?.array ?? [] {
            if (p.at("q")?.text ?? "SOL") != "SOL" { continue }
            let mint = p.at("mint")?.text ?? ""
            let sym = p.at("sym")?.text ?? Addr.short(mint)
            let bought = p.at("boughtAmt")?.number ?? 0
            totalBought += bought
            perToken[sym, default: 0] += bought
            if (p.at("sells")?.number ?? 0) < 1 { continue }
            guard let rl = p.at("realized")?.number else { continue }
            let ms = sol.filter { $0.mint == mint }
            let first = ms.first(where: { $0.isBuy })?.t
            let last = ms.last(where: { $0.isSell })?.t
            closed.append(IClosed(mint: mint, sym: sym, realized: rl, bought: bought, first: first, last: last))
        }
        let closedSorted = closed.sorted { ($0.last ?? 0) < ($1.last ?? 0) }
        let wins = closed.filter { $0.realized > 0 }
        let losses = closed.filter { $0.realized < 0 }
        let sumWin = wins.reduce(0.0) { $0 + $1.realized }
        let sumLoss = -losses.reduce(0.0) { $0 + $1.realized }
        let net = sumWin - sumLoss
        let wr: Double? = closed.isEmpty ? nil : Double(wins.count) / Double(closed.count)
        let pf: Double? = sumLoss > 0 ? sumWin / sumLoss : nil
        let expect: Double? = closed.isEmpty ? nil : net / Double(closed.count)
        var cum = 0.0
        var peak = 0.0
        var dd = 0.0
        for c in closedSorted {
            cum += c.realized
            peak = max(peak, cum)
            dd = max(dd, peak - cum)
        }
        let medBuy = med(buys.map { $0.amt }) ?? 0
        let holdsAll = closed.compactMap { $0.hold }
        let medHold = med(holdsAll)
        let firstT = trades.first?.t
        let lastT = trades.last?.t
        var spanDays = 0.0
        if let a = firstT, let b = lastT { spanDays = max(0.01, (b - a) / 86_400) }
        let perDay = spanDays > 0 ? Double(trades.count) / spanDays : 0
        var complete = false
        if case .bool(let b)? = w.stats?.at("complete") { complete = b }
        let swapTx = Int(w.stats?.at("swapTx")?.number ?? 0)
        let tradeN = Int(w.stats?.at("tradeN")?.number ?? 0)
        let nowT = Date().timeIntervalSince1970

        // ---------- 标签 ----------
        var labels: [IntelLabel] = []
        if tradeN == 0 && swapTx >= 20 {
            labels.append(IntelLabel(name: "疑似做市 / 路由 / 中转账户", level: "info", basis: cat("读到 ", String(swapTx), " 笔兑换交易，但没有一笔能归属为它自己的买卖")))
        }
        let gaps: [Double] = zip(trades.dropFirst(), trades).map { $0.t - $1.t }.filter { $0 > 0 }
        if gaps.count >= 15 {
            let mean = gaps.reduce(0.0, +) / Double(gaps.count)
            var vsum = 0.0
            for g in gaps { vsum += (g - mean) * (g - mean) }
            let cv = mean > 0 ? (vsum / Double(gaps.count)).squareRoot() / mean : 9
            if cv < 0.35 { labels.append(IntelLabel(name: "机器人", level: "warn", basis: cat("相邻交易间隔非常规律（变异系数 ", f2(cv), " < 0.35），样本 ", String(gaps.count + 1), " 笔"))) }
        }
        if closed.count >= 5, let mh = medHold, mh < 300 {
            labels.append(IntelLabel(name: "狙击手 / 极短线", level: "warn", basis: cat("已平仓 ", String(closed.count), " 个代币，持仓中位数只有 ", dur(mh))))
        } else if closed.count >= 8, let mh = medHold, mh < 3600, perDay > 20 {
            labels.append(IntelLabel(name: "高频短线", level: "info", basis: cat("日均约 ", String(Int(perDay)), " 笔，持仓中位数 ", dur(mh))))
        }
        if medBuy >= 100 { labels.append(IntelLabel(name: "巨鲸", level: "info", basis: cat("中位买入额 ", f2(medBuy), " SOL（≥ 100）"))) }
        else if medBuy >= 30 { labels.append(IntelLabel(name: "大户", level: "info", basis: cat("中位买入额 ", f2(medBuy), " SOL（≥ 30）"))) }
        if complete && spanDays < 7 && !trades.isEmpty { labels.append(IntelLabel(name: "新钱包", level: "warn", basis: cat("完整历史只有 ", String(format: "%.1f", spanDays), " 天"))) }
        if let l = lastT, nowT - l > 14 * 86_400 { labels.append(IntelLabel(name: "休眠", level: "info", basis: cat("最近一笔交易在 ", String(Int((nowT - l) / 86_400)), " 天前"))) }
        var topWinShare = 0.0
        if wins.count >= 3, sumWin > 0, let mw = wins.map({ $0.realized }).max() { topWinShare = mw / sumWin }
        if closed.count >= 10, let r = wr, let p = pf, r >= 0.55, p >= 1.5, net > 0 {
            labels.append(IntelLabel(name: "聪明钱（样本内）", level: "ok", basis: cat("已平仓 ", String(closed.count), " 个，胜率 ", pc(r), "，盈亏比 ", f2(p), "，已实现 ", f2(net), " SOL")))
        }
        if closed.count >= 10, let r = wr, r < 0.4, net < 0 {
            labels.append(IntelLabel(name: "净输家", level: "risk", basis: cat("已平仓 ", String(closed.count), " 个，胜率 ", pc(r), "，已实现 ", f2(net), " SOL")))
        }
        if topWinShare > 0.5 { labels.append(IntelLabel(name: "靠单笔暴利", level: "warn", basis: cat("最大一笔盈利占全部盈利的 ", pc(topWinShare)))) }
        if closed.count < 8 { labels.append(IntelLabel(name: "样本不足", level: "info", basis: cat("只有 ", String(closed.count), " 个已平仓代币（< 8），胜率等统计不稳定"))) }

        // ---------- 行为信号 ----------
        var sig: [IntelSignal] = []
        var skipped: [String] = []

        var revenge = 0
        if medBuy > 0 {
            for c in losses {
                guard let l = c.last else { continue }
                if let nb = buys.first(where: { $0.t > l && $0.t - l <= 600 && $0.mint != c.mint }), nb.amt >= 1.5 * medBuy { revenge += 1 }
            }
        }
        if losses.count >= 3 {
            if revenge >= 2 { sig.append(IntelSignal(title: "报复性交易", level: "warn", text: cat("有 ", String(revenge), " 次亏损卖出后 10 分钟内，立刻加大仓位买入别的币"), basis: cat("买入额 ≥ 1.5 × 中位买入额（", f2(medBuy), " SOL）；亏损卖出共 ", String(losses.count), " 次"))) }
        } else { skipped.append("报复性交易（亏损样本 < 3）") }

        var tilt = 0
        var streak = 0
        for c in closedSorted {
            if c.realized < 0 {
                streak += 1
                if streak >= 3, let l = c.last, medBuy > 0, let nb = buys.first(where: { $0.t > l }), nb.amt >= 1.3 * medBuy { tilt += 1 }
            } else { streak = 0 }
        }
        if closed.count >= 8 {
            if tilt >= 1 { sig.append(IntelSignal(title: "连亏上头", level: "warn", text: cat("出现 ", String(tilt), " 次连续 3 笔以上亏损后仍加大仓位"), basis: "连亏后的下一笔买入 ≥ 1.3 × 中位买入额")) }
        } else { skipped.append("连亏上头（已平仓 < 8）") }

        var byDay: [Int: Int] = [:]
        for t in trades { byDay[Int(t.t / 86_400), default: 0] += 1 }
        let dayCounts = byDay.values.map { Double($0) }
        if dayCounts.count >= 3, let md = med(dayCounts), let mx = dayCounts.max(), mx >= 20, mx >= 3 * max(1, md) {
            sig.append(IntelSignal(title: "过度交易", level: "warn", text: cat("单日最多 ", String(Int(mx)), " 笔，是日常（中位 ", String(Int(md)), " 笔）的 ", String(Int(mx / max(1, md))), " 倍"), basis: "按自然日统计成交笔数"))
        } else if dayCounts.count < 3 { skipped.append("过度交易（不足 3 个交易日）") }

        if losses.count >= 4, let a = firstT, let b = lastT, b > a {
            let ls = losses.compactMap { c in c.last.map { ($0, -c.realized) } }.sorted { $0.0 < $1.0 }
            let total = ls.reduce(0.0) { $0 + $1.1 }
            let win = (b - a) * 0.2
            var best = 0.0
            for i in 0..<ls.count {
                var s = 0.0
                for j in i..<ls.count where ls[j].0 - ls[i].0 <= win { s += ls[j].1 }
                best = max(best, s)
            }
            if total > 0, best / total >= 0.6 { sig.append(IntelSignal(title: "亏损聚集", level: "warn", text: cat("约 ", pc(best / total), " 的亏损集中在整个观察期 20% 的时间里"), basis: cat("亏损合计 ", f2(total), " SOL"))) }
        } else { skipped.append("亏损聚集（亏损样本 < 4）") }

        if trades.count >= 30 {
            var hist = [Int](repeating: 0, count: 24)
            for t in trades { hist[Calendar.current.component(.hour, from: Date(timeIntervalSince1970: t.t))] += 1 }
            var bestStart = 0
            var bestSum = 0
            for h in 0..<24 {
                let s = hist[h] + hist[(h + 1) % 24] + hist[(h + 2) % 24]
                if s > bestSum { bestSum = s; bestStart = h }
            }
            let share = Double(bestSum) / Double(trades.count)
            if share >= 0.45 { sig.append(IntelSignal(title: "时段偏好", level: "info", text: cat("约 ", pc(share), " 的交易集中在 ", String(bestStart), ":00–", String((bestStart + 3) % 24), ":00（手机本地时区）"), basis: cat("样本 ", String(trades.count), " 笔"))) }
            let night = hist[0] + hist[1] + hist[2] + hist[3] + hist[4]
            if Double(night) / Double(trades.count) >= 0.3 { sig.append(IntelSignal(title: "深夜交易", level: "info", text: cat("约 ", pc(Double(night) / Double(trades.count)), " 的交易发生在 0–5 点"), basis: "手机本地时区")) }
        } else { skipped.append("时段偏好（成交 < 30 笔）") }

        if buys.count >= 12 {
            let n = buys.count / 3
            let early = med(buys.prefix(n).map { $0.amt }) ?? 0
            let late = med(buys.suffix(n).map { $0.amt }) ?? 0
            if early > 0, late / early >= 2 { sig.append(IntelSignal(title: "仓位放大", level: "warn", text: cat("近期买入额是早期的 ", String(format: "%.1f", late / early), " 倍，仓位在持续放大"), basis: cat("最早 1/3 买入中位 ", f2(early), " SOL → 最近 1/3 中位 ", f2(late), " SOL")))}
            else if late > 0, early / late >= 2 { sig.append(IntelSignal(title: "仓位收缩", level: "info", text: cat("近期买入额只有早期的 ", String(format: "%.0f%%", late / early * 100), "，在降低风险暴露"), basis: cat("最早 1/3 买入中位 ", f2(early), " SOL → 最近 1/3 中位 ", f2(late), " SOL"))) }
        } else { skipped.append("仓位漂移（买入 < 12 笔）") }

        var multi = 0
        var chase = 0
        var down = 0
        var byMint: [String: [ITrade]] = [:]
        for b in buys where b.qty > 0 { byMint[b.mint, default: []].append(b) }
        for (_, bs) in byMint where bs.count >= 2 {
            multi += 1
            var c = false
            var d = false
            for i in 1..<bs.count {
                var s = 0.0
                for k in 0..<i { s += bs[k].amt / bs[k].qty }
                let avg = s / Double(i)
                let px = bs[i].amt / bs[i].qty
                if avg > 0 {
                    if px / avg >= 1.25 { c = true }
                    if px / avg <= 0.8 { d = true }
                }
            }
            if c { chase += 1 }
            if d { down += 1 }
        }
        if multi >= 3 {
            if Double(chase) / Double(multi) >= 0.4 { sig.append(IntelSignal(title: "追高加仓", level: "warn", text: cat(String(chase), " / ", String(multi), " 个多次买入的代币，后续买入价比之前均价高 25% 以上"), basis: "买入价 = 花费 ÷ 数量")) }
            if Double(down) / Double(multi) >= 0.4 { sig.append(IntelSignal(title: "越跌越买", level: "info", text: cat(String(down), " / ", String(multi), " 个多次买入的代币，后续在更低价格摊平"), basis: "买入价比之前均价低 20% 以上")) }
        } else { skipped.append("追高 / 摊平（多次买入的代币 < 3）") }

        let lh = closed.filter { $0.realized < 0 }.compactMap { $0.hold }
        let wh = closed.filter { $0.realized > 0 }.compactMap { $0.hold }
        if lh.count >= 4, wh.count >= 4, let a = med(lh), let b = med(wh), b > 0, a / b >= 2 {
            sig.append(IntelSignal(title: "套牢倾向", level: "warn", text: cat("亏损单拿得比盈利单久：持仓中位 ", dur(a), " 对 ", dur(b)), basis: "亏损单中位持仓 ≥ 2 × 盈利单"))
        } else { skipped.append("套牢倾向（盈利或亏损样本 < 4）") }

        if perToken.count >= 3, totalBought > 0, let top = perToken.max(by: { $0.value < $1.value }), top.value / totalBought >= 0.5 {
            sig.append(IntelSignal(title: "单币重仓", level: "warn", text: cat(top.key, " 占全部买入额的 ", pc(top.value / totalBought)), basis: cat("买入合计 ", f2(totalBought), " SOL")))
        }

        let wp = wins.filter { $0.bought > 0 }.map { $0.realized / $0.bought }
        let lp = losses.filter { $0.bought > 0 }.map { -$0.realized / $0.bought }
        if wp.count >= 4, lp.count >= 4, let r = wr, r > 0.5 {
            let aw = wp.reduce(0.0, +) / Double(wp.count)
            let al = lp.reduce(0.0, +) / Double(lp.count)
            if aw > 0, al > 1.5 * aw { sig.append(IntelSignal(title: "赚小亏大", level: "warn", text: cat("胜率虽有 ", pc(r), "，但平均亏损 ", pc(al), " 远大于平均盈利 ", pc(aw)), basis: "按单个代币的 已实现 ÷ 买入额")) }
        }

        // ---------- 跟单价值分（样本内表现，不是投资建议） ----------
        var score: Int? = nil
        var why: [String] = []
        if closed.count >= 8 {
            var s = 50
            if let r = wr {
                if r >= 0.55 { s += 15; why.append(cat("+15 胜率 ", pc(r))) } else if r < 0.4 { s -= 15; why.append(cat("-15 胜率仅 ", pc(r))) }
            }
            if let p = pf {
                if p >= 1.5 { s += 15; why.append(cat("+15 盈亏比 ", f2(p))) } else if p < 1 { s -= 15; why.append(cat("-15 盈亏比 ", f2(p))) }
            }
            if let e = expect { if e > 0 { s += 10; why.append("+10 每笔期望为正") } else { s -= 10; why.append("-10 每笔期望为负") } }
            if closed.count >= 30 { s += 5; why.append("+5 样本 ≥ 30") }
            if topWinShare > 0.5 { s -= 15; why.append("-15 靠单笔暴利") }
            if sumWin > 0, dd > 0.6 * sumWin { s -= 10; why.append("-10 回撤超过盈利的 60%") }
            if labels.contains(where: { $0.name == "机器人" }) { s -= 10; why.append("-10 疑似机器人，行为难以复制") }
            if revenge >= 2 { s -= 10; why.append("-10 报复性交易") }
            if tilt >= 1 { s -= 10; why.append("-10 连亏上头") }
            score = max(0, min(100, s))
        }

        var metrics: [[String]] = []
        metrics.append(["解析成交", cat(String(trades.count), " 笔（SOL 计价 ", String(sol.count), "）")])
        metrics.append(["已平仓代币", String(closed.count)])
        if let r = wr { metrics.append(["胜率", cat(pc(r), "（", String(wins.count), "胜 ", String(losses.count), "负）")]) }
        metrics.append(["已实现盈亏", cat(net >= 0 ? "+" : "", f2(net), " SOL")])
        if let p = pf { metrics.append(["盈亏比", f2(p)]) }
        if let e = expect { metrics.append(["每笔期望", cat(e >= 0 ? "+" : "", f2(e), " SOL")]) }
        if dd > 0 { metrics.append(["最大回撤", cat(f2(dd), " SOL")]) }
        if let mh = medHold { metrics.append(["持仓中位时长", dur(mh)]) }
        if medBuy > 0 { metrics.append(["中位买入额", cat(f2(medBuy), " SOL")]) }
        if perDay > 0 { metrics.append(["日均交易", String(format: "%.1f 笔", perDay)]) }

        var notes: [String] = []
        for n in w.notes?.strings ?? [] { notes.append(n) }
        if let s = w.sample?.text { notes.append(s) }
        if !complete { notes.append("交易历史未读完整（只读了最近几页），统计只代表这段样本") }
        return IntelReport(address: address, labels: labels, metrics: metrics, signals: sig, skipped: skipped, score: score, scoreWhy: why, notes: notes, winRate: wr, realizedSol: net, closedN: closed.count, medBuy: medBuy, at: Date())
    }
}

struct BatchRow: Identifiable {
    var id: String
    var owner: String
    var pct: Double?
    var report: IntelReport?
    var err: String?
}

@MainActor
final class IntelVM: ObservableObject {
    static let shared = IntelVM()
    @Published var input = ""
    @Published var report: IntelReport?
    @Published var loading = false
    @Published var error: String?
    @Published var rows: [BatchRow] = []
    @Published var batchBusy = false
    @Published var batchDone = 0
    @Published var batchTotal = 0
    private var cache: [String: IntelReport] = [:]

    func fetch(_ addr: String, pages: Int, fresh: Bool) async throws -> IntelReport {
        var q: [String: String] = ["address": addr, "pages": String(pages)]
        if fresh { q["fresh"] = "1" }
        let w: IntelWallet = try await Engine.get("/e/sol/wallet", q)
        if let e = w.error?.text {
            let d = w.detail?.text ?? ""
            throw APIError.network(d.isEmpty ? e : cat(e, "：", d))
        }
        let r = WalletIntelEngine.analyze(w, address: addr)
        cache[addr] = r
        return r
    }

    func query(_ raw: String, fresh: Bool = false) async {
        let addr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Addr.isSolana(addr), !Addr.isEVM(addr) else {
            error = "目前钱包情报覆盖 Solana 地址（32–44 位 Base58）。EVM 钱包请用「钱包 → 查询任意地址」"
            return
        }
        input = addr
        loading = true
        error = nil
        defer { loading = false }
        do {
            report = try await fetch(addr, pages: 3, fresh: fresh)
        } catch {
            if let old = cache[addr] {
                report = old
                self.error = cat("刷新失败，显示的是 ", old.at.formatted(date: .omitted, time: .standard), " 的旧数据：", Net.message(error))
            } else {
                report = nil
                self.error = Net.message(error)
            }
        }
    }

    // 持有人一键全查：前 N 个普通钱包三路并行，边出结果边显示
    func runBatch(holders: [UHolder], limit: Int = 20) async {
        if batchBusy { return }
        let ws = holders.filter { $0.kind == "wallet" }.prefix(limit)
        rows = ws.map { BatchRow(id: $0.owner, owner: $0.owner, pct: $0.pct, report: cache[$0.owner], err: nil) }
        batchTotal = rows.count
        batchDone = 0
        batchBusy = true
        defer { batchBusy = false }
        let targets = rows.map { $0.owner }
        let lanes = 3
        await withTaskGroup(of: Void.self) { g in
            for lane in 0..<lanes {
                g.addTask { [weak self] in
                    var i = lane
                    while i < targets.count {
                        await self?.batchOne(targets[i])
                        i += lanes
                    }
                }
            }
        }
    }

    private func batchOne(_ owner: String) async {
        var rep: IntelReport?
        var err: String?
        do { rep = try await fetch(owner, pages: 2, fresh: false) } catch { err = Net.message(error) }
        if let i = rows.firstIndex(where: { $0.owner == owner }) {
            if let r = rep { rows[i].report = r; rows[i].err = nil } else { rows[i].err = err }
        }
        batchDone += 1
    }

    // 队列整体画像：按供应占比加权，判断筹码被什么类型的钱包持有
    struct Cohort {
        var lines: [IntelSignal] = []
        var done = 0
        var total = 0
    }

    func cohort() -> Cohort {
        var c = Cohort()
        c.total = rows.count
        let ok = rows.filter { $0.report != nil }
        c.done = ok.count
        if ok.count < 3 { return c }
        func share(_ names: [String]) -> (Int, Double) {
            var n = 0
            var p = 0.0
            for r in ok { if let rep = r.report, names.contains(where: { rep.has($0) }) { n += 1; p += r.pct ?? 0 } }
            return (n, p)
        }
        let bots = share(["机器人", "狙击手 / 极短线"])
        let smart = share(["聪明钱（样本内）"])
        let loser = share(["净输家"])
        let fresh = share(["新钱包"])
        let router = share(["疑似做市 / 路由 / 中转账户"])
        let tot = ok.count
        if bots.0 > 0 { c.lines.append(IntelSignal(title: "机器人 / 狙击手", level: bots.0 * 3 >= tot ? "warn" : "info", text: cat(String(bots.0), " / ", String(tot), " 个大户是机器人或极短线，合计持有 ", String(format: "%.1f%%", bots.1), " 供应"), basis: "这类钱包随时可能同时卖出")) }
        if fresh.0 > 0 { c.lines.append(IntelSignal(title: "新钱包", level: fresh.0 * 3 >= tot ? "warn" : "info", text: cat(String(fresh.0), " / ", String(tot), " 个大户是不到 7 天的新钱包，合计持有 ", String(format: "%.1f%%", fresh.1), " 供应"), basis: "新钱包集中持仓常见于一人分仓控盘（链上只能提示，无法证明同一人）")) }
        if smart.0 > 0 { c.lines.append(IntelSignal(title: "聪明钱在场", level: "ok", text: cat(String(smart.0), " / ", String(tot), " 个大户在样本内表现优秀，合计持有 ", String(format: "%.1f%%", smart.1), " 供应"), basis: "样本内表现，不代表未来")) }
        if loser.0 > 0 { c.lines.append(IntelSignal(title: "净输家持仓", level: "info", text: cat(String(loser.0), " / ", String(tot), " 个大户长期净亏损，合计持有 ", String(format: "%.1f%%", loser.1), " 供应"), basis: "历史上频繁亏钱的钱包")) }
        if router.0 > 0 { c.lines.append(IntelSignal(title: "做市 / 路由账户", level: "info", text: cat(String(router.0), " 个大户疑似做市、路由或中转账户，合计 ", String(format: "%.1f%%", router.1), " 供应"), basis: "交易无法归属为自己的买卖")) }
        let wrs = ok.compactMap { $0.report?.winRate }
        if wrs.count >= 3, let m = WalletIntelEngine.med(wrs) { c.lines.append(IntelSignal(title: "大户整体胜率", level: "info", text: cat("已查询大户的历史胜率中位数 ", WalletIntelEngine.pc(m)), basis: cat("样本 ", String(wrs.count), " 个钱包"))) }
        return c
    }
}

struct IntelReportView: View {
    let r: IntelReport

    private func col(_ l: String) -> Color {
        switch l {
        case "risk": return .red
        case "warn": return .orange
        case "ok": return .green
        default: return .blue
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(Addr.short(r.address)).font(.system(.subheadline, design: .monospaced))
                        Spacer()
                        Text(cat("计算于 ", r.at.formatted(date: .omitted, time: .standard))).font(.caption2).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(r.labels) { l in
                            Text(l.name).font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4).background(col(l.level).opacity(0.15), in: Capsule()).foregroundStyle(col(l.level))
                        }
                    }
                    ForEach(r.labels) { l in
                        Text(cat("· ", l.name, "：", l.basis)).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let s = r.score {
                        HStack(spacing: 10) {
                            Text(String(s)).font(.system(size: 30, weight: .bold, design: .rounded))
                            VStack(alignment: .leading, spacing: 4) {
                                ScoreBar(score: s, color: s >= 70 ? .green : (s >= 45 ? .yellow : .orange))
                                Text("跟单价值分：只反映这段样本内的表现，不是买卖建议").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        ForEach(r.scoreWhy, id: \.self) { w in Text(w).font(.caption2).foregroundStyle(.secondary) }
                    } else {
                        Text("已平仓代币不足 8 个，不给评分").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("核心指标").font(.headline)
                    ForEach(r.metrics, id: \.self) { m in
                        HStack { Text(m[0]).font(.subheadline).foregroundStyle(.secondary); Spacer(); Text(m[1]).font(.subheadline.bold()) }
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("交易行为信号").font(.headline)
                    if r.signals.isEmpty { Text("没有触发任何行为信号（样本足够的前提下，这是好事）").font(.caption).foregroundStyle(.secondary) }
                    ForEach(r.signals) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .top, spacing: 6) {
                                Circle().fill(col(s.level)).frame(width: 7, height: 7).padding(.top, 6)
                                Text(s.title).font(.subheadline.bold())
                            }
                            Text(s.text).font(.caption).padding(.leading, 13)
                            Text(cat("依据：", s.basis)).font(.caption2).foregroundStyle(.secondary).padding(.leading, 13)
                        }
                    }
                    if !r.skipped.isEmpty {
                        Text("样本不足、没有计算的信号").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                        ForEach(r.skipped, id: \.self) { s in Text(cat("· ", s)).font(.caption2).foregroundStyle(.secondary) }
                    }
                    ForEach(r.notes, id: \.self) { n in Text(cat("提示：", n)).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

struct IntelRoot: View {
    @ObservedObject private var vm = IntelVM.shared
    @ObservedObject private var tok = UTokenVM.shared
    @State private var seg = 0
    @State private var picked: IntelReport?

    private var myWallets: [Wallet] { Cfg.wallets.filter { Addr.isSolana($0.address) && !Addr.isEVM($0.address) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("", selection: $seg) {
                        Text("他人钱包").tag(0)
                        Text("我的钱包").tag(1)
                        Text("持有人全查").tag(2)
                    }
                    .pickerStyle(.segmented)
                    if seg == 0 { other }
                    if seg == 1 { mine }
                    if seg == 2 { holdersTab }
                    if seg != 2 {
                        if vm.loading { Card { HStack(spacing: 10) { ProgressView(); Text("正在读取并计算…").font(.subheadline) } } }
                        if let e = vm.error { Card { Text(e).font(.footnote).foregroundStyle(Color.orange) } }
                        if let r = vm.report { IntelReportView(r: r) }
                    }
                }
                .padding()
            }
            .navigationTitle("情报")
        }
    }

    private var other: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("查询任意 Solana 钱包").font(.headline)
                TextField("粘贴钱包地址", text: $vm.input).textInputAutocapitalization(.never).autocorrectionDisabled().font(.system(.footnote, design: .monospaced)).textFieldStyle(.roundedBorder)
                HStack {
                    Button("粘贴") { vm.input = UIPasteboard.general.string ?? vm.input }
                    Spacer()
                    Button("查询") { Task { await vm.query(vm.input) } }.buttonStyle(.borderedProminent).disabled(vm.loading)
                }
            }
        }
    }

    private var mine: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("我的 Solana 钱包").font(.headline)
                if myWallets.isEmpty { Text("还没有添加 Solana 钱包：到「钱包」页添加后这里直接点查").font(.caption).foregroundStyle(.secondary) }
                ForEach(myWallets) { w in
                    Button { Task { await vm.query(w.address, fresh: true) } } label: {
                        HStack { Text(w.label.isEmpty ? "钱包" : w.label); Spacer(); Text(Addr.short(w.address)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
                    }
                }
            }
        }
    }

    private var holdersTab: some View {
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("代币持有人一键全查").font(.headline)
                    if tok.address.isEmpty || tok.chain != .solana {
                        Text("先在「代币」页查一个 Solana 代币，这里会对它的前 20 个普通钱包逐个出情报（EVM 大户在代币页已有成本盈亏拆解）。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(cat("当前代币：", tok.symbol, "（", Addr.short(tok.address), "）")).font(.subheadline)
                        Button { Task { await vm.runBatch(holders: tok.holders) } } label: {
                            HStack { Text(vm.batchBusy ? cat("查询中 ", String(vm.batchDone), "/", String(vm.batchTotal)) : "一键查询全部大户"); if vm.batchBusy { ProgressView() } }
                        }
                        .buttonStyle(.borderedProminent).disabled(vm.batchBusy || tok.holders.isEmpty)
                    }
                }
            }
            let c = vm.cohort()
            if !c.lines.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("大户整体画像").font(.headline)
                        ForEach(c.lines) { l in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(l.text).font(.subheadline)
                                Text(cat("依据：", l.basis)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !vm.rows.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("逐个钱包").font(.headline)
                        ForEach(vm.rows) { r in
                            Button { picked = r.report } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(Addr.short(r.owner)).font(.system(.footnote, design: .monospaced))
                                        if let p = r.pct { Text(String(format: "%.2f%%", p)).font(.caption).foregroundStyle(.secondary) }
                                        Spacer()
                                        if let s = r.report?.score { Text(cat("分 ", String(s))).font(.caption.bold()) }
                                    }
                                    if let rep = r.report {
                                        Text(rep.labels.map { $0.name }.joined(separator: "、")).font(.caption2).foregroundStyle(.secondary)
                                    } else if let e = r.err {
                                        Text(e).font(.caption2).foregroundStyle(Color.orange)
                                    } else {
                                        Text("排队中…").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }
        .sheet(item: Binding(get: { picked.map { PickedReport(r: $0) } }, set: { if $0 == nil { picked = nil } })) { p in
            NavigationStack { ScrollView { IntelReportView(r: p.r).padding() }.navigationTitle("钱包情报") }
        }
    }
}

struct PickedReport: Identifiable {
    let r: IntelReport
    var id: String { r.address }
}
