import SwiftUI

// 规则分析引擎：不依赖任何 AI，只用已读到的真实数据按固定规则打分，每条结论都带依据。数据缺失的维度直接标「未知」，不拿假数凑。
struct DimFind: Identifiable {
    let id = UUID()
    var level: String
    var text: String
    var basis: String
}

struct Dim: Identifiable {
    var id: String
    var title: String
    var icon: String
    var weight: Double
    var score: Int
    var finds: [DimFind]
    var source: String
}

struct AnalysisReport {
    var score: Int?
    var grade: String
    var color: Color
    var stage: String
    var stageBasis: String
    var dims: [Dim]
    var hard: [String]
    var unknown: [String]
    var top: [DimFind]
}

@MainActor
enum AnalysisEngine {
    private struct B {
        var score = 100
        var finds: [DimFind] = []
        mutating func add(_ lvl: String, _ pen: Int, _ text: String, _ basis: String) {
            score -= pen
            finds.append(DimFind(level: lvl, text: text, basis: basis))
        }
        var value: Int { max(0, min(100, score)) }
    }

    static func build(_ vm: UTokenVM) -> AnalysisReport {
        guard let m = vm.main else {
            return AnalysisReport(score: nil, grade: "无数据", color: .gray, stage: "未知", stageBasis: "", dims: [], hard: [], unknown: ["还没有行情数据"], top: [])
        }
        var dims: [Dim] = []
        var hard: [String] = []
        var unknown: [String] = []
        let liq = m.liq
        let nowMs = Date().timeIntervalSince1970 * 1000
        let ageH: Double? = m.pairCreatedAt.map { (nowMs - $0) / 3_600_000 }

        // 1) 流动性与池子
        if liq > 0 {
            var b = B()
            let src = "Dexscreener 最深池子"
            if liq < 1_000 {
                b.add("risk", 70, "流动性只有 " + Fmt2.usd(liq) + "，基本无法正常卖出", src)
                hard.append("流动性不足 $1,000，实际不可交易")
            } else if liq < 5_000 {
                b.add("risk", 50, "流动性只有 " + Fmt2.usd(liq) + "，几百美元的卖单就能明显砸价", src)
            } else if liq < 20_000 {
                b.add("warn", 25, "流动性偏薄（" + Fmt2.usd(liq) + "），大额进出滑点大", src)
            } else if liq < 50_000 {
                b.add("info", 8, "流动性 " + Fmt2.usd(liq) + "，只能承接小额进出", src)
            } else {
                b.add("ok", 0, "流动性 " + Fmt2.usd(liq) + "，可承接中等规模进出", src)
            }
            if let mc = m.marketCap ?? m.fdv, mc > 0 {
                let r = liq / mc
                let basis = "流动性 " + Fmt2.usd(liq) + " ÷ 市值 " + Fmt2.usd(mc)
                if r < 0.02 { b.add("risk", 25, String(format: "流动性仅为市值的 %.1f%%，账面市值远大于实际能卖出的金额", r * 100), basis) }
                else if r < 0.05 { b.add("warn", 10, String(format: "流动性占市值 %.1f%%，偏低", r * 100), basis) }
            }
            if let a = ageH {
                if a < 1 { b.add("risk", 20, "池子上线不到 1 小时，处于极早期，价格和流动性都可能剧烈变化", String(format: "池龄约 %.0f 分钟", a * 60)) }
                else if a < 24 { b.add("warn", 10, String(format: "池子上线仅 %.1f 小时，仍在早期阶段", a), "最深池子创建时间") }
            }
            if let v = m.volume?["h24"], v / liq > 15 {
                b.add("warn", 10, String(format: "24 小时成交额是流动性的 %.0f 倍，高频炒作或刷量的可能性大", v / liq), "成交额 " + Fmt2.usd(v) + " ÷ 流动性 " + Fmt2.usd(liq))
            }
            if vm.pairs.count >= 2 {
                let ps = vm.pairs.filter { $0.liq >= 1000 }.compactMap { $0.price }
                if let lo = ps.min(), let hi = ps.max(), lo > 0, hi / lo > 1.05, ps.count >= 2 {
                    b.add("warn", 8, String(format: "不同池子之间价差达 %.1f%%，存在搬砖空间，也可能有池子被操纵", (hi / lo - 1) * 100), "流动性 ≥ $1,000 的池子价格对比")
                }
            }
            dims.append(Dim(id: "liq", title: "流动性与池子", icon: "drop.fill", weight: 0.22, score: b.value, finds: b.finds, source: "Dexscreener · " + String(vm.pairs.count) + " 个池子"))
        } else {
            unknown.append("流动性未知")
        }

        // 2) 筹码结构
        if let c = vm.conc {
            var b = B()
            let firstIsWallet = vm.holders.first?.kind == "wallet"
            if let t1 = c.top1 {
                if t1 >= 20 && firstIsWallet { b.add("risk", 35, String(format: "第 1 大持有人是普通钱包，持有 %.1f%%，他一个人就能砸盘", Double(t1)), "链上持有人榜单") }
                else if t1 >= 10 && firstIsWallet { b.add("warn", 15, String(format: "第 1 大持有人是普通钱包，持有 %.1f%%", Double(t1)), "链上持有人榜单") }
            }
            if let w = c.wallets10 {
                let basis = "占总供应量；已剔除池子、合约、金库"
                if w >= 30 { b.add("risk", 30, String(format: "前 10 大普通钱包合计持有 %.1f%%，筹码高度集中", Double(w)), basis) }
                else if w >= 15 { b.add("warn", 12, String(format: "前 10 大普通钱包合计持有 %.1f%%，偏集中", Double(w)), basis) }
                else { b.add("ok", 0, String(format: "前 10 大普通钱包合计持有 %.1f%%，筹码较分散", Double(w)), basis) }
            }
            if !vm.holderComplete { b.add("info", 0, "持有人榜单不完整（只读到前几页），占比为已读部分", "引擎分页读取") }
            dims.append(Dim(id: "holders", title: "筹码结构", icon: "person.3.fill", weight: 0.22, score: b.value, finds: b.finds, source: "链上持有人榜 · " + String(vm.holders.count) + " 条"))
        } else {
            unknown.append("持有人榜未读到" + (vm.holderNote.map { "：" + $0 } ?? "（加载中）"))
        }

        // 3) 大户行为（需要至少 2 个已拆解的大户）
        let a = vm.agg
        if a.withPos >= 2 {
            var b = B()
            let up = Double(a.profit) / Double(a.withPos)
            let basis = "按美元成本的平均成本法，已兑现 + 浮动"
            if up >= 0.7 { b.add("warn", 12, "已拆解 " + String(a.withPos) + " 个大户中 " + String(a.profit) + " 个账面盈利（" + String(Int(up * 100)) + "%），多数有利润可兑现，存在抛压", basis) }
            else if up <= 0.3 { b.add("info", 0, "已拆解 " + String(a.withPos) + " 个大户中只有 " + String(a.profit) + " 个盈利，多数被套", basis) }
            else { b.add("info", 0, "已拆解 " + String(a.withPos) + " 个大户盈亏分化，合计盈亏 " + Fmt2.usd(a.pnl, signed: true), basis) }
            let early = a.snipers + a.early
            if early >= 3 { b.add("warn", 22, String(a.early) + " 个大户在池子创建 10 分钟内买入（其中 " + String(a.snipers) + " 个在 1 分钟内），疑似内部或狙击筹码", "首次买入时间 − 池子创建时间") }
            else if early >= 1 { b.add("info", 5, String(early) + " 个大户在池子创建 10 分钟内买入", "首次买入时间 − 池子创建时间") }
            if liq > 0, a.valueNow > 0 {
                let imp = a.valueNow / liq
                let t = String(format: "已拆解大户的持仓价值合计 %@，相当于池子流动性的 %.0f%%", Fmt2.usd(a.valueNow), imp * 100)
                if imp >= 0.5 { b.add("risk", 30, t + "，集中抛售的价格冲击会很大", "持仓数量 × 现价 ÷ 最深池子流动性") }
                else if imp >= 0.15 { b.add("warn", 12, t + "，集中抛售会有明显冲击", "持仓数量 × 现价 ÷ 最深池子流动性") }
                else { b.add("ok", 0, t, "持仓数量 × 现价 ÷ 最深池子流动性") }
            }
            let cleared = vm.analyses.values.compactMap { $0.position }.filter { ($0.boughtUsd ?? 0) > 0 && ($0.qtyHeld ?? 1) <= 0 }.count
            if cleared >= 2 { b.add("warn", 10, String(cleared) + " 个大户已完全清仓离场", "持仓数量为 0 且有买入记录") }
            dims.append(Dim(id: "whales", title: "大户行为", icon: "fish.fill", weight: 0.18, score: b.value, finds: b.finds, source: "引擎拆解 " + String(a.withPos) + " 个大户的成本与盈亏"))
        } else {
            unknown.append("大户成本盈亏未拆解（已拆 " + String(a.withPos) + " 个，至少需要 2 个）")
        }

        // 4) 成交质量
        if vm.trades.count >= 10 {
            var b = B()
            let now = Date().timeIntervalSince1970
            let ws = FlowCalc.windows(vm.trades, now: now)
            if let w = ws.first(where: { $0.id == "1h" }), w.total >= 500 {
                let basis = "买入 " + Fmt2.usd(w.buy) + "（" + String(w.nb) + " 笔）/ 卖出 " + Fmt2.usd(w.sell) + "（" + String(w.ns) + " 笔）"
                if w.sell > w.buy * 1.5 { b.add("warn", 15, "最近 1 小时资金净流出 " + Fmt2.usd(-w.net) + "，卖出明显多于买入", basis) }
                else if w.buy > w.sell * 1.5 { b.add("ok", 0, "最近 1 小时资金净流入 " + Fmt2.usd(w.net) + "，买盘占优", basis) }
                else { b.add("info", 0, "最近 1 小时买卖基本均衡", basis) }
            }
            let ad = FlowCalc.addrs(vm.trades)
            let gross = vm.trades.reduce(0) { $0 + $1.usd }
            if gross > 0, ad.count >= 3 {
                let top5 = ad.prefix(5).reduce(0) { $0 + $1.total } / gross
                if top5 > 0.5 { b.add("warn", 10, String(format: "前 5 个交易地址贡献了最近成交额的 %.0f%%，成交高度集中", top5 * 100), "最近 " + String(vm.trades.count) + " 笔成交、" + String(ad.count) + " 个地址（交易发起方，可能是机器人或聚合器）") }
            }
            var washN = 0
            for x in ad where x.nb >= 3 && x.ns >= 3 {
                let tot: Double = max(1.0, x.buy + x.sell)
                let diff: Double = abs(x.buy - x.sell)
                if diff / tot < 0.15 { washN += 1 }
            }
            if washN > 0 { b.add("warn", 10, String(washN) + " 个地址买卖各 ≥3 笔且买卖额接近，可能是套利机器人，也可能是对敲刷量（链上无法区分）", "买卖额差额 < 15%") }
            if let tx = m.txns?["h24"], let bu = tx.buys, let se = tx.sells, bu + se >= 50, Double(se) > Double(bu) * 1.3 {
                b.add("warn", 8, "24 小时卖出笔数（" + String(se) + "）明显多于买入笔数（" + String(bu) + "）", "Dexscreener 24h 笔数")
            }
            dims.append(Dim(id: "flow", title: "成交质量", icon: "arrow.left.arrow.right", weight: 0.16, score: b.value, finds: b.finds, source: "GeckoTerminal 最近 " + String(vm.trades.count) + " 笔成交"))
        } else {
            unknown.append("成交样本不足（" + String(vm.trades.count) + " 笔，至少需要 10 笔）")
        }

        // 5) 合约安全
        if vm.chain == .solana {
            if let au = vm.authorities {
                var b = B()
                let mintOn = !(au.mint ?? "").isEmpty
                let freezeOn = !(au.freeze ?? "").isEmpty
                if mintOn { b.add("risk", 30, "仍有增发权限，发行方可以继续增发", "链上 mint 账户") }
                if freezeOn { b.add("risk", 25, "仍有冻结权限，发行方可以冻结持有人账户", "链上 mint 账户") }
                if !mintOn && !freezeOn { b.add("ok", 0, "增发与冻结权限均已放弃", "链上 mint 账户") }
                if (mintOn || freezeOn) && liq > 0 && liq < 20_000 { hard.append("权限未放弃且流动性低于 $20,000") }
                dims.append(Dim(id: "contract", title: "合约权限", icon: "lock.shield.fill", weight: 0.16, score: b.value, finds: b.finds, source: "Solana mint 账户（引擎 RPC）"))
            } else {
                unknown.append("Solana 增发/冻结权限未读到")
            }
        } else if let s = vm.security {
            var b = B()
            let src = s.riskSource ?? "合约扫描"
            if s.honeypot == true { b.add("risk", 80, "检测为蜜罐：可能买得进卖不出", src); hard.append("检测为蜜罐") }
            if let st = s.sellTax, st >= 10 { b.add(st >= 50 ? "risk" : "warn", st >= 50 ? 50 : 20, String(format: "卖出税 %.1f%%", Double(st)), src); if st >= 50 { hard.append("卖出税 ≥ 50%") } }
            if let bt = s.buyTax, bt >= 10 { b.add("warn", 10, String(format: "买入税 %.1f%%", Double(bt)), src) }
            if s.mintable == true { b.add("warn", 15, "合约可增发", src) }
            if b.finds.isEmpty { b.add("ok", 0, "未发现蜜罐、高税、可增发等风险项", src) }
            dims.append(Dim(id: "contract", title: "合约安全", icon: "lock.shield.fill", weight: 0.16, score: b.value, finds: b.finds, source: src))
        } else {
            unknown.append("合约安全扫描未读到" + (vm.chain.tokenSupported ? "" : "（该链暂不支持）"))
        }

        // 6) 价格行为
        if let c = m.priceChange, !c.isEmpty {
            var b = B()
            let basis = "Dexscreener 涨跌幅"
            if let v = c["h1"], v <= -30 { b.add("warn", 12, String(format: "最近 1 小时下跌 %.0f%%，正在快速砸盘", -v), basis) }
            if let v = c["h6"], v <= -50 { b.add("warn", 10, String(format: "最近 6 小时下跌 %.0f%%", -v), basis) }
            if let v = c["h24"] {
                if v <= -80 { b.add("risk", 25, String(format: "24 小时下跌 %.0f%%，接近归零", -v), basis) }
                else if v <= -60 { b.add("warn", 15, String(format: "24 小时下跌 %.0f%%", -v), basis) }
                else if v >= 300 { b.add("info", 8, String(format: "24 小时上涨 %.0f%%，涨幅过大时追高风险高", v), basis) }
            }
            if b.finds.isEmpty { b.add("ok", 0, "近期价格没有极端波动", basis) }
            dims.append(Dim(id: "price", title: "价格行为", icon: "chart.line.uptrend.xyaxis", weight: 0.06, score: b.value, finds: b.finds, source: "Dexscreener"))
        } else {
            unknown.append("涨跌幅未知")
        }

        // 7) 官方信息
        if let info = m.info {
            var b = B()
            let socials = info.socials ?? []
            let webs = info.websites ?? []
            if socials.isEmpty && webs.isEmpty { b.add("warn", 15, "没有登记任何官方社交或网站链接", "Dexscreener 代币资料") }
            else {
                let names = socials.compactMap { $0.type }.joined(separator: "、")
                let namesPart: String = names.isEmpty ? "" : names + "，"
                let webPart: String = webs.isEmpty ? "无官网" : "有官网"
                b.add("ok", 0, "已登记官方链接：" + namesPart + webPart, "Dexscreener 代币资料（只说明登记了链接，不代表真实可信）")
            }
            dims.append(Dim(id: "social", title: "官方信息", icon: "link", weight: 0.06, score: b.value, finds: b.finds, source: "Dexscreener 代币资料"))
        } else {
            unknown.append("没有收录官方资料（Dexscreener 未登记社交与官网）")
        }

        var score: Int? = nil
        if dims.count >= 3 {
            var wsum = 0.0
            var wtot = 0.0
            for d in dims {
                wsum += d.weight
                wtot += Double(d.score) * d.weight
            }
            let s: Double = wtot / wsum
            var v = Int(s.rounded())
            if !hard.isEmpty { v = min(v, 25) }
            score = v
        }
        var grade = "数据不足"
        var color = Color.gray
        if let s = score {
            if s >= 75 { grade = "风险较低"; color = .green }
            else if s >= 55 { grade = "中等风险"; color = .yellow }
            else if s >= 35 { grade = "高风险"; color = .orange }
            else { grade = "极高风险"; color = .red }
        }
        let st = stage(m, ageH)
        let order: [String: Int] = ["risk": 0, "warn": 1, "info": 2, "ok": 3]
        let all = dims.flatMap { $0.finds }.filter { $0.level == "risk" || $0.level == "warn" }.sorted { (order[$0.level] ?? 9) < (order[$1.level] ?? 9) }
        return AnalysisReport(score: score, grade: grade, color: color, stage: st.0, stageBasis: st.1, dims: dims, hard: hard, unknown: unknown, top: Array(all.prefix(4)))
    }

    static func stage(_ m: DexPair, _ ageH: Double?) -> (String, String) {
        let c = m.priceChange ?? [:]
        let h1 = c["h1"], h6 = c["h6"], h24 = c["h24"]
        var basis = ""
        if let a = ageH { basis += String(format: "池龄 %.1f 小时", a) }
        if let v = h24 { basis += (basis.isEmpty ? "" : "，") + String(format: "24h %+.0f%%", v) }
        if let v = h1 { basis += String(format: "，1h %+.0f%%", v) }
        if m.liq > 0 && m.liq < 1_000 { return ("已归零 / 无流动性", "流动性 " + Fmt2.usd(m.liq) + "，" + basis) }
        if let a = ageH, a < 1 { return ("发射期", basis) }
        if let v = h24, v <= -80 { return ("崩盘期", basis) }
        if let a = ageH, a < 72, let v = h24, v >= 50 { return ("拉升期", basis) }
        if let v = h24, v <= -40 { return ("回落 / 派发期", basis) }
        if let v = h24, abs(v) < 15, (h6 ?? 0) > -15 { return ("横盘整理期", basis) }
        if let a = ageH, a < 72 { return ("早期震荡", basis) }
        return ("震荡期", basis)
    }
}
