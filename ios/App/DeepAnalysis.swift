import SwiftUI

// MARK: - 深度分析：全部由已加载的行情、K 线、成交、持有人数据按固定规则算出，不依赖 AI，每条结论附依据

enum DeepCalc {
    static func sma(_ a: [Double], _ n: Int) -> Double? {
        if n <= 0 || a.count < n { return nil }
        var s = 0.0
        for v in a.suffix(n) { s += v }
        return s / Double(n)
    }

    static func rsi(_ c: [Double], _ n: Int) -> Double? {
        if n <= 0 || c.count <= n + 1 { return nil }
        var g = 0.0
        var l = 0.0
        for i in 1...n {
            let d = c[i] - c[i - 1]
            if d >= 0 { g += d } else { l -= d }
        }
        g /= Double(n)
        l /= Double(n)
        for i in (n + 1)..<c.count {
            let d = c[i] - c[i - 1]
            let up = d > 0 ? d : 0
            let dn = d < 0 ? -d : 0
            g = (g * Double(n - 1) + up) / Double(n)
            l = (l * Double(n - 1) + dn) / Double(n)
        }
        if l == 0 { return 100 }
        return 100 - 100 / (1 + g / l)
    }

    // 摆动高低点：左右各 k 根都不比它更高 / 更低
    static func swings(_ cs: [Candle], _ k: Int) -> ([Double], [Double]) {
        var highs: [Double] = []
        var lows: [Double] = []
        if cs.count < 2 * k + 1 { return (highs, lows) }
        for i in k..<(cs.count - k) {
            var isHigh = true
            var isLow = true
            for j in (i - k)...(i + k) where j != i {
                if cs[j].h > cs[i].h { isHigh = false }
                if cs[j].l < cs[i].l { isLow = false }
            }
            if isHigh { highs.append(cs[i].h) }
            if isLow { lows.append(cs[i].l) }
        }
        return (highs, lows)
    }

    // 把相近（3% 以内）的价位合并成一个价位，并数被触及的次数
    static func levels(_ vals: [Double]) -> [(Double, Int)] {
        let s = vals.sorted()
        var out: [(Double, Int)] = []
        var cur: [Double] = []
        for v in s {
            if let f = cur.first, v <= f * 1.03 {
                cur.append(v)
            } else {
                if !cur.isEmpty { out.append((cur.reduce(0, +) / Double(cur.count), cur.count)) }
                cur = [v]
            }
        }
        if !cur.isEmpty { out.append((cur.reduce(0, +) / Double(cur.count), cur.count)) }
        return out
    }

    // 恒定乘积池估算：liq 是池子总流动性（美元），单边约 liq/2
    static func buyImpact(_ a: Double, _ liq: Double) -> Double {
        let h = liq / 2
        if h <= 0 { return 0 }
        let r = 1 + a / h
        return r * r - 1
    }

    static func sellImpact(_ a: Double, _ liq: Double) -> Double {
        let h = liq / 2
        if h <= 0 { return 0 }
        let r = h / (h + a)
        return 1 - r * r
    }

    static func med(_ a: [Double]) -> Double? {
        if a.isEmpty { return nil }
        let s = a.sorted()
        let m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }
}

// 选中一根 K 线时「交易分析」里补一行：买卖双方各多少个地址、人均多少、大单占比
enum KDeep {
    static func sliceExtra(_ ts: [UTrade]) -> String {
        let buys = ts.filter { $0.buy }
        let sells = ts.filter { !$0.buy }
        let bw = Set(buys.map { $0.who }).count
        let sw = Set(sells.map { $0.who }).count
        let bu = buys.reduce(0.0) { $0 + $1.usd }
        let su = sells.reduce(0.0) { $0 + $1.usd }
        var s = cat("买方 ", String(bw), " 个地址")
        if bw > 0 { s += cat("（人均 ", Fmt2.usd(bu / Double(bw)), "）") }
        s += cat(" · 卖方 ", String(sw), " 个地址")
        if sw > 0 { s += cat("（人均 ", Fmt2.usd(su / Double(sw)), "）") }
        let big = ts.filter { $0.usd >= 1000 }.reduce(0.0) { $0 + $1.usd }
        let tot = bu + su
        if tot > 0 { s += String(format: " · 千美元以上大单占 %.0f%%", big / tot * 100) }
        return s
    }
}

// MARK: - 代币深度研判：盘面温度 / K 线结构 / 承接与滑点
struct TokenDeepCard: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var kl = KLineShared.shared

    private var candles: [Candle] {
        let k = vm.chain.rawValue + ":" + (vm.main?.pairAddress ?? "")
        return kl.key == k ? kl.candles : []
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("深度研判（盘面 · 结构 · 承接）", systemImage: "scope").font(.headline)
                if let m = vm.main {
                    heatSection(m)
                    Divider()
                    structSection(m)
                    Divider()
                    depthSection(m)
                } else {
                    Text("行情还在加载").font(.footnote).foregroundStyle(.secondary)
                }
                Text("全部按固定规则，从已加载的行情、K 线、流动性算出，不依赖 AI；K 线结构取自当前图表周期和已加载的范围，换周期会重算。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 盘面温度
    private func windowRows(_ m: DexPair) -> [(String, Int, Int, Double)] {
        let defs: [(String, String)] = [("5 分钟", "m5"), ("1 小时", "h1"), ("6 小时", "h6"), ("24 小时", "h24")]
        var out: [(String, Int, Int, Double)] = []
        for d in defs {
            let b = m.txns?[d.1]?.buys ?? 0
            let s = m.txns?[d.1]?.sells ?? 0
            let v = m.volume?[d.1] ?? 0
            out.append((d.0, b, s, v))
        }
        return out
    }

    private func heatFindings(_ m: DexPair) -> [Finding] {
        var out: [Finding] = []
        let v1 = m.volume?["h1"] ?? 0
        let v6 = m.volume?["h6"] ?? 0
        let v24 = m.volume?["h24"] ?? 0
        if v6 > v1 && v1 > 0 {
            let avg = (v6 - v1) / 5
            if avg > 0 {
                let r = v1 / avg
                let basis = cat("1 小时成交额 ", Fmt2.usd(v1), " ÷ 前 5 小时均值 ", Fmt2.usd(avg))
                if r >= 2.5 {
                    out.append(Finding(level: "info", text: String(format: "最近 1 小时成交额是前 5 小时均值的 %.1f 倍，正在放量", r), basis: basis))
                } else if r <= 0.35 {
                    out.append(Finding(level: "warn", text: String(format: "最近 1 小时成交额只有前 5 小时均值的 %.0f%%，热度在退潮", r * 100), basis: basis))
                }
            }
        }
        if let mc = m.marketCap ?? m.fdv, mc > 0, v24 > 0 {
            let t = v24 / mc
            let basis = cat("24 小时成交额 ", Fmt2.usd(v24), " ÷ 市值 ", Fmt2.usd(mc))
            if t >= 3 {
                out.append(Finding(level: "warn", text: String(format: "24 小时换手率 %.1f 倍市值，筹码换手极快，炒作味很重", t), basis: basis))
            } else if t < 0.05 {
                out.append(Finding(level: "info", text: String(format: "24 小时换手率只有 %.1f%%，交投清淡", t * 100), basis: basis))
            }
        }
        let ch: [Double?] = [m.priceChange?["m5"], m.priceChange?["h1"], m.priceChange?["h6"], m.priceChange?["h24"]]
        let vals = ch.compactMap { $0 }
        if vals.count == 4 {
            let up = vals.filter { $0 > 0 }.count
            let basis = String(format: "5分 %+.1f%% · 1时 %+.1f%% · 6时 %+.1f%% · 24时 %+.1f%%", vals[0], vals[1], vals[2], vals[3])
            if up == 4 {
                out.append(Finding(level: "ok", text: "四个周期全部上涨，多周期同向走强", basis: basis))
            } else if up == 0 {
                out.append(Finding(level: "warn", text: "四个周期全部下跌，空头占优", basis: basis))
            } else if vals[0] > 0 && vals[3] < 0 {
                out.append(Finding(level: "info", text: "短线在反弹但 24 小时仍为跌，先判断是不是下跌途中的反抽", basis: basis))
            } else if vals[0] < 0 && vals[3] > 0 {
                out.append(Finding(level: "info", text: "24 小时仍在涨，但最近 5 分钟转跌，短线在回落", basis: basis))
            }
        }
        let b1 = m.txns?["h1"]?.buys ?? 0
        let s1 = m.txns?["h1"]?.sells ?? 0
        if b1 + s1 >= 50 {
            let r = Double(b1) / Double(b1 + s1) * 100
            let basis = cat("最近 1 小时 买 ", String(b1), " 笔 / 卖 ", String(s1), " 笔")
            if r >= 60 { out.append(Finding(level: "ok", text: String(format: "最近 1 小时买单笔数占 %.0f%%，买盘更活跃", r), basis: basis)) }
            else if r <= 40 { out.append(Finding(level: "warn", text: String(format: "最近 1 小时买单笔数只占 %.0f%%，卖单更密集", r), basis: basis)) }
        }
        return out
    }

    private func heatSection(_ m: DexPair) -> some View {
        let rows = windowRows(m)
        let fs = heatFindings(m)
        return VStack(alignment: .leading, spacing: 8) {
            Text("盘面温度").font(.subheadline.weight(.semibold))
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                let total = r.1 + r.2
                let ratio: String = total > 0 ? String(format: "买 %.0f%%", Double(r.1) / Double(total) * 100) : "—"
                HStack {
                    Text(r.0).font(.caption).frame(width: 56, alignment: .leading)
                    Text(cat(String(r.1), " 买 / ", String(r.2), " 卖")).font(.caption.monospacedDigit())
                    Spacer()
                    Text(ratio).font(.caption.weight(.semibold)).foregroundStyle(total > 0 && r.1 >= r.2 ? Color.green : Color.red)
                    Text(Fmt2.usd(r.3)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
                }
            }
            ForEach(fs) { FindingRow(f: $0) }
        }
    }

    // MARK: K 线结构
    private func structFindings(_ cs: [Candle], _ m: DexPair) -> ([[String]], [Finding]) {
        var tiles: [[String]] = []
        var fs: [Finding] = []
        guard let last = cs.last else { return (tiles, fs) }
        let hi = cs.map { $0.h }.max() ?? 0
        let lo = cs.map { $0.l }.min() ?? 0
        if hi <= lo || last.c <= 0 { return (tiles, fs) }
        let cur = last.c
        let fromHi = (cur / hi - 1) * 100
        let pos = (cur - lo) / (hi - lo) * 100
        let closes = cs.map { $0.c }
        let rsi14 = DeepCalc.rsi(closes, 14)
        let tail = cs.suffix(20)
        var ampSum = 0.0
        for c in tail where c.l > 0 { ampSum += (c.h / c.l - 1) * 100 }
        let amp = tail.isEmpty ? 0 : ampSum / Double(tail.count)
        tiles.append(["距区间最高", String(format: "%+.1f%%", fromHi)])
        tiles.append(["区间位置", String(format: "%.0f%%（0 最低 · 100 最高）", pos)])
        tiles.append(["RSI(14)", rsi14.map { String(format: "%.0f", $0) } ?? "—"])
        tiles.append(["近 20 根平均振幅", String(format: "%.1f%%", amp)])

        // 均线排列
        let ma5 = DeepCalc.sma(closes, 5)
        let ma10 = DeepCalc.sma(closes, 10)
        let ma20 = DeepCalc.sma(closes, 20)
        var bull = false
        var bear = false
        if let a = ma5, let b = ma10, let c = ma20 {
            let basis = cat("MA5 ", Money.price(a), " · MA10 ", Money.price(b), " · MA20 ", Money.price(c))
            if a > b && b > c {
                bull = true
                fs.append(Finding(level: "ok", text: "均线多头排列（MA5 > MA10 > MA20），短中期趋势向上", basis: basis))
            } else if a < b && b < c {
                bear = true
                fs.append(Finding(level: "warn", text: "均线空头排列（MA5 < MA10 < MA20），短中期趋势向下", basis: basis))
            } else {
                fs.append(Finding(level: "info", text: "均线缠绕，没有明确趋势", basis: basis))
            }
        }
        if let r = rsi14 {
            if r >= 75 { fs.append(Finding(level: "warn", text: String(format: "RSI %.0f，超买区，追高要小心回落", r), basis: "RSI(14) ≥ 75")) }
            else if r <= 25 { fs.append(Finding(level: "info", text: String(format: "RSI %.0f，超卖区，可能出现技术性反弹，但不等于见底", r), basis: "RSI(14) ≤ 25")) }
        }

        // 支撑 / 阻力
        let sw = DeepCalc.swings(cs, 3)
        let res = DeepCalc.levels(sw.0).filter { $0.0 > cur * 1.01 }.min(by: { $0.0 < $1.0 })
        let sup = DeepCalc.levels(sw.1).filter { $0.0 < cur * 0.99 }.max(by: { $0.0 < $1.0 })
        if let r = res {
            fs.append(Finding(level: "info", text: cat("上方最近阻力 ", Money.price(r.0), String(format: "（距现价 %+.1f%%，被触及 %d 次）", (r.0 / cur - 1) * 100, r.1)), basis: "已加载 K 线里的局部高点聚类（3% 内合并）"))
        }
        if let s = sup {
            fs.append(Finding(level: "info", text: cat("下方最近支撑 ", Money.price(s.0), String(format: "（距现价 %+.1f%%，被触及 %d 次）", (s.0 / cur - 1) * 100, s.1)), basis: "已加载 K 线里的局部低点聚类（3% 内合并）"))
        }

        // 量能
        var vr = 0.0
        let recent = cs.suffix(5)
        let before = cs.dropLast(5).suffix(20)
        if recent.count == 5 && before.count >= 10 {
            var rv = 0.0
            for c in recent { rv += c.v }
            var bv = 0.0
            for c in before { bv += c.v }
            let rAvg = rv / 5
            let bAvg = bv / Double(before.count)
            if bAvg > 0 {
                vr = rAvg / bAvg
                let basis = cat("最近 5 根均值 ", Fmt2.usd(rAvg), " ÷ 之前 ", String(before.count), " 根均值 ", Fmt2.usd(bAvg))
                if vr >= 2 { fs.append(Finding(level: "info", text: String(format: "最近 5 根 K 线量能是之前的 %.1f 倍，放量", vr), basis: basis)) }
                else if vr <= 0.4 { fs.append(Finding(level: "info", text: String(format: "最近 5 根 K 线量能只有之前的 %.0f%%，缩量", vr * 100), basis: basis)) }
            }
        }

        // 阶段判断
        var stage = "震荡整理"
        var why = String(format: "距区间最高 %+.1f%%，均线缠绕或趋势不明", fromHi)
        var ageH: Double? = nil
        if let c = m.pairCreatedAt { ageH = (Date().timeIntervalSince1970 * 1000 - c) / 3_600_000 }
        if let a = ageH, a < 6 {
            stage = "发射初期"
            why = String(format: "池龄 %.1f 小时（< 6 小时），价格与流动性都还不稳定", a)
        } else if fromHi <= -70 {
            stage = "高位崩盘后的阴跌 / 横盘"
            why = String(format: "距区间最高 %+.1f%%（跌幅 ≥ 70%%）", fromHi)
        } else if fromHi <= -30 && bear {
            stage = "回调 / 下跌中继"
            why = String(format: "距区间最高 %+.1f%%，且均线空头排列", fromHi)
        } else if fromHi >= -10 && bull && vr >= 1.5 {
            stage = "放量拉升 / 突破"
            why = String(format: "贴近区间最高（%+.1f%%），均线多头排列，量能 %.1f 倍", fromHi, vr)
        } else if bull {
            stage = "温和上行"
            why = "均线多头排列，但没有明显放量"
        }
        fs.append(Finding(level: "info", text: "当前阶段：" + stage, basis: why))
        return (tiles, fs)
    }

    private func structSection(_ m: DexPair) -> some View {
        let cs = candles
        return VStack(alignment: .leading, spacing: 8) {
            Text("K 线结构（当前周期 " + kl.tf.title + "）").font(.subheadline.weight(.semibold))
            if cs.count < 30 {
                Text("K 线还在加载，或已加载根数不足 30 根，暂时无法判断结构").font(.footnote).foregroundStyle(.secondary)
            } else {
                let r = structFindings(cs, m)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(r.0, id: \.self) { t in StatTile(title: t[0], value: t[1]) }
                }
                ForEach(r.1) { FindingRow(f: $0) }
            }
        }
    }

    // MARK: 承接与滑点
    private func depthSection(_ m: DexPair) -> some View {
        let liq = m.liq
        let amounts: [Double] = [100, 500, 1000, 5000]
        let h = liq / 2
        let buy5 = h * (1.05.squareRoot() - 1)
        let sell5 = h * (1 / 0.95.squareRoot() - 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("承接力与滑点（按恒定乘积池估算）").font(.subheadline.weight(.semibold))
            if liq <= 0 {
                Text("没有读到流动性，无法估算").font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(amounts, id: \.self) { a in
                    HStack {
                        Text(Fmt2.usd(a)).font(.caption).frame(width: 56, alignment: .leading)
                        Text(String(format: "买入推高 %+.1f%%", DeepCalc.buyImpact(a, liq) * 100)).font(.caption.monospacedDigit()).foregroundStyle(Color.green)
                        Spacer()
                        Text(String(format: "卖出砸价 -%.1f%%", DeepCalc.sellImpact(a, liq) * 100)).font(.caption.monospacedDigit()).foregroundStyle(Color.red)
                    }
                }
                Text(cat("买入约 ", Fmt2.usd(buy5), "、卖出约 ", Fmt2.usd(sell5), " 就会让价格移动 5%")).font(.footnote)
                Text(cat("依据：池子总流动性 ", Fmt2.usd(liq), "，单边约 ", Fmt2.usd(h), "。集中流动性池（如 Raydium CLMM、Uniswap V3）实际冲击可能更小或更大，这里只给量级；不含手续费与链上 MEV。")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 成交深度分析：按单笔大小分档、买卖地址数、节奏、连续同向、对倒嫌疑
struct TradeDeepCard: View {
    @ObservedObject var vm: UTokenVM

    private struct Tier {
        let name: String
        let lo: Double
        let hi: Double
        var buy = 0.0
        var sell = 0.0
        var nb = 0
        var ns = 0
        var net: Double { buy - sell }
    }

    private func tiers(_ ts: [UTrade]) -> [Tier] {
        var list: [Tier] = [
            Tier(name: "散户 < $100", lo: 0, hi: 100),
            Tier(name: "中单 $100–1K", lo: 100, hi: 1000),
            Tier(name: "大单 $1K–10K", lo: 1000, hi: 10000),
            Tier(name: "巨单 ≥ $10K", lo: 10000, hi: Double.greatestFiniteMagnitude),
        ]
        for t in ts {
            for i in list.indices where t.usd >= list[i].lo && t.usd < list[i].hi {
                if t.buy { list[i].buy += t.usd; list[i].nb += 1 } else { list[i].sell += t.usd; list[i].ns += 1 }
            }
        }
        return list
    }

    private func findings(_ ts: [UTrade], _ tr: [Tier]) -> [Finding] {
        var out: [Finding] = []
        let now = Date().timeIntervalSince1970
        let sorted = ts.sorted { $0.t < $1.t }

        // 大单 vs 散户
        let bigNet = tr[2].net + tr[3].net
        let smallNet = tr[0].net + tr[1].net
        let basisNet = cat("大单+巨单净 ", Fmt2.usd(bigNet, signed: true), "；散户+中单净 ", Fmt2.usd(smallNet, signed: true))
        if bigNet < 0 && smallNet > 0 && abs(bigNet) > 1000 {
            out.append(Finding(level: "warn", text: "大单在净卖、小单在净买：筹码可能从大户流向散户（出货形态）", basis: basisNet))
        } else if bigNet > 0 && smallNet < 0 && abs(bigNet) > 1000 {
            out.append(Finding(level: "ok", text: "大单在净买、小单在净卖：筹码可能从散户流向大户（吸筹形态）", basis: basisNet))
        }

        // 买卖地址数
        let buyers = Set(ts.filter { $0.buy && !$0.who.isEmpty }.map { $0.who })
        let sellers = Set(ts.filter { !$0.buy && !$0.who.isEmpty }.map { $0.who })
        let both = buyers.intersection(sellers)
        let basisAddr = cat("买方 ", String(buyers.count), " 个地址 · 卖方 ", String(sellers.count), " 个地址 · 双向 ", String(both.count), " 个")
        if buyers.count >= 5 && sellers.count >= 5 {
            let ratio = Double(buyers.count) / Double(sellers.count)
            if ratio >= 1.5 { out.append(Finding(level: "ok", text: String(format: "买方地址数是卖方的 %.1f 倍，参与买入的人更多", ratio), basis: basisAddr)) }
            else if ratio <= 0.67 { out.append(Finding(level: "warn", text: String(format: "卖方地址数是买方的 %.1f 倍，想走的人更多", 1 / ratio), basis: basisAddr)) }
        }
        let tot = Double(buyers.count + sellers.count)
        if tot > 0 && Double(both.count) * 2 / tot >= 0.3 {
            out.append(Finding(level: "info", text: "有相当比例的地址既买又卖，更像机器人 / 套利，而不是真实散户在交易", basis: basisAddr))
        }

        // 节奏：最近 5 分钟 vs 之前 25 分钟
        let n5 = ts.filter { now - $0.t <= 300 }.count
        let n25 = ts.filter { now - $0.t > 300 && now - $0.t <= 1800 }.count
        if let oldest = sorted.first, now - oldest.t >= 1800, n25 >= 10 {
            let r5 = Double(n5) / 5
            let r25 = Double(n25) / 25
            let basis = cat("最近 5 分钟 ", String(n5), " 笔 · 之前 25 分钟 ", String(n25), " 笔")
            if r25 > 0 {
                let r = r5 / r25
                if r >= 2 { out.append(Finding(level: "info", text: String(format: "成交节奏加快：最近 5 分钟的成交速度是之前的 %.1f 倍", r), basis: basis)) }
                else if r <= 0.4 { out.append(Finding(level: "info", text: String(format: "成交节奏放慢：最近 5 分钟的成交速度只有之前的 %.0f%%", r * 100), basis: basis)) }
            }
        }

        // 连续同向
        var best = 0
        var bestBuy = true
        var run = 0
        var runBuy = true
        for t in sorted {
            if run > 0 && t.buy == runBuy { run += 1 } else { run = 1; runBuy = t.buy }
            if run > best { best = run; bestBuy = runBuy }
        }
        if best >= 8 {
            out.append(Finding(level: "info", text: cat("样本内最长连续", bestBuy ? "买入 " : "卖出 ", String(best), " 笔"), basis: cat("当前正在连续", runBuy ? "买入 " : "卖出 ", String(run), " 笔")))
        }

        // 对倒嫌疑：同一地址 90 秒内买卖金额相近
        var rt = Set<String>()
        for a in sorted where a.buy && !a.who.isEmpty {
            for b in sorted where !b.buy && b.who == a.who && abs(b.t - a.t) <= 90 {
                if a.usd > 0 {
                    let r = b.usd / a.usd
                    if r > 0.8 && r < 1.25 { rt.insert(a.who) }
                }
            }
        }
        if !rt.isEmpty {
            out.append(Finding(level: "warn", text: cat(String(rt.count), " 个地址在 90 秒内买卖金额相近（±25%），疑似对倒刷量或套利机器人"), basis: "同一地址、先后各一笔买卖、时间差 ≤ 90 秒、金额比 0.8–1.25"))
        }
        return out
    }

    var body: some View {
        let ts = vm.trades
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("成交深度分析（谁在买卖、多大单）", systemImage: "chart.bar.doc.horizontal").font(.headline)
                if ts.count < 20 {
                    Text("成交样本只有 \(ts.count) 笔（< 20），不足以做分档和行为判断").font(.footnote).foregroundStyle(.secondary)
                } else {
                    let tr = tiers(ts)
                    ForEach(Array(tr.enumerated()), id: \.offset) { _, t in
                        HStack {
                            Text(t.name).font(.caption).frame(width: 96, alignment: .leading)
                            Text(cat("买 ", Fmt2.usd(t.buy), "·", String(t.nb))).font(.caption2.monospacedDigit()).foregroundStyle(Color.green)
                            Text(cat("卖 ", Fmt2.usd(t.sell), "·", String(t.ns))).font(.caption2.monospacedDigit()).foregroundStyle(Color.red)
                            Spacer()
                            Text(Fmt2.usd(t.net, signed: true)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(t.net >= 0 ? Color.green : Color.red)
                        }
                    }
                    ForEach(findings(ts, tr)) { FindingRow(f: $0) }
                    Text("样本是 GeckoTerminal 提供的最近约 300 笔成交；地址是交易发起方，可能是机器人或聚合器。").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 筹码深度分析：成本中枢、获利盘 / 套牢盘、同批入场簇、兑现程度、等效持有人数
struct HolderDeepCard: View {
    @ObservedObject var vm: UTokenVM

    private func clusterText(_ t: Double) -> String { TZ.short(Date(timeIntervalSince1970: t)) }

    private func findings(_ wallets: [UHolder]) -> [Finding] {
        var out: [Finding] = []
        var qty = 0.0
        var cost = 0.0
        var profitVal = 0.0
        var lossVal = 0.0
        var lossQty = 0.0
        var lossCost = 0.0
        var cleared = 0
        var holding = 0
        var withPos = 0
        var rois: [Double] = []
        var firsts: [(Double, String, Double)] = []
        for h in wallets {
            guard let p = vm.analyses[h.owner]?.position else { continue }
            withPos += 1
            let q = p.qtyHeld ?? 0
            let c = p.costHeldUsd ?? 0
            let v = p.valueNowUsd ?? 0
            if q > 0 {
                holding += 1
                qty += q
                cost += c
                if (p.unrealizedUsd ?? 0) >= 0 {
                    profitVal += v
                } else {
                    lossVal += v
                    lossQty += q
                    lossCost += c
                }
            } else {
                cleared += 1
            }
            if let r = p.roi { rois.append(r) }
            if let f = p.firstBuy { firsts.append((f, h.owner, h.pct ?? 0)) }
        }
        if withPos < 3 { return out }

        // 成本中枢
        if qty > 0, let px = vm.main?.price, px > 0 {
            let avg = cost / qty
            let basis = cat("已拆解大户中仍持仓的 ", String(holding), " 个，持仓成本合计 ", Fmt2.usd(cost), " ÷ 持仓数量")
            let d = (px / avg - 1) * 100
            if d >= 0 {
                out.append(Finding(level: "info", text: cat("大户持仓加权成本约 ", Money.price(avg), String(format: "，现价高出 %.0f%%，整体账面盈利", d)), basis: basis))
            } else {
                out.append(Finding(level: "warn", text: cat("大户持仓加权成本约 ", Money.price(avg), String(format: "，现价低于成本 %.0f%%，整体被套", -d)), basis: basis))
            }
        }
        // 获利盘 / 套牢盘（按持仓价值）
        let totalVal = profitVal + lossVal
        if totalVal > 0 {
            let basis = cat("盈利持仓价值 ", Fmt2.usd(profitVal), " · 亏损持仓价值 ", Fmt2.usd(lossVal))
            out.append(Finding(level: "info", text: String(format: "按持仓价值，获利盘 %.0f%% / 套牢盘 %.0f%%", profitVal / totalVal * 100, lossVal / totalVal * 100), basis: basis))
        }
        if lossQty > 0, let px = vm.main?.price, px > 0 {
            let lossAvg = lossCost / lossQty
            if lossAvg > px * 1.05 {
                out.append(Finding(level: "info", text: cat("套牢盘成本中枢约 ", Money.price(lossAvg), String(format: "，比现价高 %.0f%%：价格涨回这一带可能有解套抛压", (lossAvg / px - 1) * 100)), basis: "只统计已拆解、仍持仓且浮亏的大户"))
            }
        }
        // 兑现程度
        out.append(Finding(level: "info", text: cat("已拆解 ", String(withPos), " 个大户：仍持仓 ", String(holding), " 个，已清仓 ", String(cleared), " 个"), basis: "清仓 = 当前持仓数量为 0"))
        if let m = DeepCalc.med(rois) {
            let basis = cat("样本 ", String(rois.count), " 个大户，已兑现 + 浮动，相对投入")
            out.append(Finding(level: m >= 0 ? "info" : "warn", text: String(format: "大户综合回报中位数 %+.0f%%", m * 100), basis: basis))
        }
        // 同批入场簇
        var groups: [Int: [(Double, String, Double)]] = [:]
        for f in firsts { groups[Int(f.0 / 60), default: []].append(f) }
        for (_, g) in groups.sorted(by: { $0.key < $1.key }) where g.count >= 3 {
            var share = 0.0
            for x in g { share += x.2 }
            let when = clusterText(g[0].0)
            out.append(Finding(level: "warn", text: cat(String(g.count), " 个大户在同一分钟（", when, "）首次买入，合计持有 ", String(format: "%.1f%%", share), " 供应，疑似同一操盘 / 批量分仓"), basis: "首次买入时间落在同一个 60 秒窗口；链上只能提示，无法证明是同一人"))
        }
        return out
    }

    var body: some View {
        let wallets = vm.holders.filter { $0.kind == "wallet" }
        let pcts = wallets.compactMap { $0.pct }
        var sumP = 0.0
        var sumSq = 0.0
        for p in pcts { sumP += p; sumSq += p * p }
        let effN = sumSq > 0 ? sumP * sumP / sumSq : 0
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("筹码深度分析（成本 · 获利盘 · 抱团）", systemImage: "person.3.fill").font(.headline)
                if wallets.isEmpty {
                    Text("还没有读到持有人榜单，读到后这里自动出结果").font(.footnote).foregroundStyle(.secondary)
                } else {
                    if effN > 0 {
                        let basis = cat("前 ", String(pcts.count), " 个普通钱包合计 ", String(format: "%.1f%%", sumP), "；等效持有人数 = (Σ占比)² ÷ Σ(占比²)")
                        FindingRow(f: Finding(level: effN < 4 ? "warn" : "info", text: String(format: "榜单上的筹码相当于只有约 %.1f 个等权大户", effN), basis: basis))
                    }
                    ForEach(findings(wallets)) { FindingRow(f: $0) }
                    if vm.analyses.count < 3 {
                        Text("大户拆解还没完成或样本不足 3 个，成本与获利盘分析暂不出结果").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Solana 钱包分析页内嵌「钱包情报」：标签、行为信号、跟单价值分（自研规则）
struct WalletIntelInline: View {
    let address: String
    @StateObject private var ivm = IntelVM()

    var body: some View {
        VStack(spacing: 14) {
            if ivm.loading {
                Card { HStack(spacing: 10) { ProgressView(); Text("正在计算钱包情报（标签 + 行为信号 + 跟单价值分）…").font(.subheadline) } }
            }
            if let e = ivm.error, ivm.report == nil {
                Card { Text(e).font(.footnote).foregroundStyle(Color.orange) }
            }
            if let r = ivm.report { IntelReportView(r: r) }
        }
        .task { if ivm.report == nil { await ivm.query(address) } }
    }
}

// MARK: - 持仓结构分析（任意链的钱包持仓页顶部）
struct HoldingsDeepCard: View {
    let result: WalletResult?

    private static let stables: Set<String> = ["USDT", "USDC", "DAI", "FDUSD", "USDE", "USD1", "TUSD", "BUSD", "PYUSD", "USDS", "USDC.E"]
    private static let majors: Set<String> = ["ETH", "WETH", "BTC", "WBTC", "CBBTC", "SOL", "WSOL", "BNB", "WBNB", "STETH", "WSTETH", "JITOSOL", "MSOL"]

    var body: some View {
        let all = result?.resp?.merged?.holdings ?? []
        let spamN = all.filter { $0.spamLikely == true }.count
        let priced = all.compactMap { h -> (String, String, Double, Double?)? in
            if h.spamLikely == true { return nil }
            guard let u = h.usd, u > 0 else { return nil }
            return (h.symbol ?? "?", h.chain ?? "", u, h.priceChange24hPct)
        }
        let total = priced.reduce(0.0) { $0 + $1.2 }
        return Group {
            if total > 0 { card(priced, total, spamN) }
        }
    }

    private func card(_ priced: [(String, String, Double, Double?)], _ total: Double, _ spamN: Int) -> some View {
        let sorted = priced.sorted { $0.2 > $1.2 }
        let top1 = (sorted.first?.2 ?? 0) / total * 100
        let top3 = sorted.prefix(3).reduce(0.0) { $0 + $1.2 } / total * 100
        var stable = 0.0
        var major = 0.0
        var chains: [String: Double] = [:]
        var prev = 0.0
        var now = 0.0
        for p in priced {
            let s = p.0.uppercased()
            if HoldingsDeepCard.stables.contains(s) { stable += p.2 }
            else if HoldingsDeepCard.majors.contains(s) { major += p.2 }
            chains[p.1, default: 0] += p.2
            if let c = p.3, c > -99 {
                now += p.2
                prev += p.2 / (1 + c / 100)
            }
        }
        let other = max(0, total - stable - major)
        let ch24: Double? = prev > 0 ? (now / prev - 1) * 100 : nil
        var fs: [Finding] = []
        let basisTop = cat("最大持仓 ", sorted.first?.0 ?? "?", " ", Fmt2.usd(sorted.first?.2 ?? 0), " ÷ 总估值 ", Fmt2.usd(total))
        if top1 >= 60 { fs.append(Finding(level: "warn", text: String(format: "单一持仓占 %.0f%%，风险集中在一个币上", top1), basis: basisTop)) }
        if other / total >= 0.7 && stable / total < 0.05 {
            fs.append(Finding(level: "warn", text: String(format: "约 %.0f%% 在稳定币和主流币之外，且稳定币不到 5%%：基本满仓，没有现金缓冲", other / total * 100), basis: cat("稳定币 ", Fmt2.usd(stable), " · 主流币 ", Fmt2.usd(major), " · 其他 ", Fmt2.usd(other))))
        }
        if chains.count >= 3 { fs.append(Finding(level: "info", text: cat("资产分布在 ", String(chains.count), " 条链上"), basis: chains.sorted { $0.value > $1.value }.prefix(4).map { cat($0.key, " ", Fmt2.usd($0.value)) }.joined(separator: " · "))) }
        if spamN > 0 { fs.append(Finding(level: "info", text: cat("另有 ", String(spamN), " 个疑似垃圾 / 空投币已排除，不计入上面的占比"), basis: "按报价与名称规则判定")) }
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("持仓结构", systemImage: "chart.pie").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    StatTile(title: "已估值总额", value: Money.format(total))
                    StatTile(title: "前 1 / 前 3 占比", value: String(format: "%.0f%% / %.0f%%", top1, top3))
                    StatTile(title: "稳定币 / 主流币 / 其他", value: String(format: "%.0f / %.0f / %.0f%%", stable / total * 100, major / total * 100, other / total * 100))
                    StatTile(title: "24h 估算涨跌", value: ch24.map { String(format: "%+.1f%%", $0) } ?? "—", tint: (ch24 ?? 0) >= 0 ? Color.green : Color.red)
                }
                ForEach(fs) { FindingRow(f: $0) }
                Text("按已报价的持仓计算；24h 涨跌由各币 24 小时涨跌幅按持仓价值反推，是估算值。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
