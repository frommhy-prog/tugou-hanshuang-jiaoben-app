import SwiftUI

// 综合研判：把规则分析（流动性/筹码/大户/成交/合约/价格/官方信息）+ 生命周期 + 叙事定位 + 社交预警合成一个结论，
// 并给出「为什么、利好利空、盯什么、较上次变了什么、数据有多全、AI 与规则是否冲突」。全部由已读到的真实数据按固定规则算出，不是买卖建议。
struct VerdictReason: Identifiable {
    let id = UUID()
    var level: String
    var text: String
    var basis: String
}

struct VerdictDelta: Identifiable {
    let id = UUID()
    var text: String
    var good: Bool?
}

struct Verdict {
    var score: Int?
    var grade: String
    var color: Color
    var headline: String
    var stage: String
    var risks: [VerdictReason]
    var goods: [VerdictReason]
    var watch: [String]
    var deltas: [VerdictDelta]
    var deltaTitle: String
    var completeness: String
    var conflict: String?
}

struct ReportDigest: Codable {
    var t: Double
    var score: Int?
    var liq: Double
    var mc: Double
    var price: Double
    var w10: Double?
}

@MainActor
enum VerdictEngine {
    static func tokenKey(_ vm: UTokenVM) -> String { cat(vm.chain.rawValue, ":", vm.address, "#", String(vm.refreshToken)) }
    static func pairKey(_ vm: UTokenVM) -> String { cat(vm.chain.rawValue, ":", vm.main?.pairAddress ?? "", "#", String(vm.refreshToken)) }

    static func grade(_ s: Int?) -> (String, Color) {
        guard let s = s else { return ("数据不足", .gray) }
        if s >= 75 { return ("风险较低", .green) }
        if s >= 55 { return ("中等风险", .yellow) }
        if s >= 35 { return ("高风险", .orange) }
        return ("极高风险", .red)
    }

    private static func dgKey(_ vm: UTokenVM) -> String { "dg:" + (Addr.isEVM(vm.address) ? vm.address.lowercased() : vm.address) }

    static func prevDigest(_ vm: UTokenVM) -> ReportDigest? {
        guard let d = Cfg.defaults.data(forKey: dgKey(vm)) else { return nil }
        return try? JSONDecoder().decode(ReportDigest.self, from: d)
    }

    static func saveIfDue(_ vm: UTokenVM) {
        guard let m = vm.main, !vm.address.isEmpty else { return }
        let now = Date().timeIntervalSince1970
        if let p = prevDigest(vm), now - p.t < 1800 { return }
        let score = build(vm).score
        if score == nil { return }
        var w10: Double? = nil
        if let w = vm.conc?.wallets10 { w10 = Double(w) }
        let d = ReportDigest(t: now, score: score, liq: m.liq, mc: m.marketCap ?? m.fdv ?? 0, price: m.price ?? 0, w10: w10)
        if let data = try? JSONEncoder().encode(d) { Cfg.defaults.set(data, forKey: dgKey(vm)) }
    }

    static func pctText(_ c: Double) -> String { String(format: "%+.0f%%", c * 100) }

    static func build(_ vm: UTokenVM) -> Verdict {
        let r = AnalysisEngine.build(vm)
        guard let m = vm.main else {
            return Verdict(score: nil, grade: "数据不足", color: .gray, headline: "还没有行情数据", stage: "未知", risks: [], goods: [], watch: [], deltas: [], deltaTitle: "", completeness: "", conflict: nil)
        }
        let life = LifecycleCard.store[pairKey(vm)]?.0
        let narr = NarrativeRulesCard.store[tokenKey(vm)]
        var score = r.score
        var risks: [VerdictReason] = []
        var goods: [VerdictReason] = []

        for d in r.dims {
            for f in d.finds {
                if f.level == "risk" { risks.append(VerdictReason(level: "risk", text: f.text, basis: f.basis)) }
            }
        }
        for d in r.dims {
            for f in d.finds {
                if f.level == "warn" { risks.append(VerdictReason(level: "warn", text: f.text, basis: f.basis)) }
                if f.level == "ok" { goods.append(VerdictReason(level: "ok", text: f.text, basis: f.basis)) }
            }
        }

        // 生命周期：已经崩盘的币，账面上的流动性和权限再「干净」也不能算安全
        var stage = r.stage
        if let l = life {
            stage = l.stage
            let ddT = String(format: "%.0f%%", -l.dd * 100)
            let rT = String(format: "%.0f%%", l.ratio * 100)
            if var s = score {
                if l.dd <= -0.9 && l.ratio < 0.05 {
                    s = min(s, 15)
                    risks.insert(VerdictReason(level: "risk", text: cat("已进入死亡期：距最高点跌了 ", ddT, "，近 24 小时成交额只有峰值的 ", rT), basis: "全生命周期 K 线"), at: 0)
                } else if l.dd <= -0.9 {
                    s = min(s, 25)
                    risks.insert(VerdictReason(level: "risk", text: cat("崩盘后残局：距最高点跌了 ", ddT), basis: "全生命周期 K 线"), at: 0)
                } else if l.dd <= -0.7 {
                    s = min(s, 40)
                    risks.insert(VerdictReason(level: "risk", text: cat("派发后期：距最高点已跌 ", ddT), basis: "全生命周期 K 线"), at: 0)
                } else if l.dd <= -0.4 {
                    s -= 8
                    risks.append(VerdictReason(level: "warn", text: cat("回落期：距最高点跌了 ", ddT), basis: "全生命周期 K 线"))
                }
                if l.dd <= -0.4 && l.ratio > 0 && l.ratio < 0.1 {
                    s -= 6
                    risks.append(VerdictReason(level: "warn", text: cat("量能萎缩：近 24 小时成交额只有峰值的 ", rT), basis: "滚动 24 小时成交额对比峰值"))
                }
                if l.dd >= -0.15 && l.athAgoH <= 48 && l.mult >= 10 {
                    s -= 8
                    risks.append(VerdictReason(level: "warn", text: cat("高位追入风险：从开盘已涨 ", String(format: "%.0f", l.mult), " 倍，现价贴近最高点"), basis: "最高价 ÷ 首根开盘价"))
                }
                score = s
            }
        }

        // 叙事：龙头 / 跟风 / 边缘，热度升温或退潮
        if let n = narr, var s = score {
            if n.position.contains("边缘") {
                s -= 6
                risks.append(VerdictReason(level: "warn", text: cat("叙事里是边缘币：", n.position), basis: n.positionBasis))
            } else if n.position.contains("跟风") {
                s -= 3
                risks.append(VerdictReason(level: "warn", text: cat("叙事里是跟风币：", n.position), basis: n.positionBasis))
            } else if n.position.hasPrefix("龙头") {
                s += 4
                goods.append(VerdictReason(level: "ok", text: cat("叙事龙头：", n.position), basis: n.positionBasis))
            }
            if n.heat.hasPrefix("冷") || n.heat.hasPrefix("退潮") {
                s -= 5
                risks.append(VerdictReason(level: "warn", text: cat("叙事热度：", n.heat), basis: "同类代币的成交额、新建池数、涨跌中位数"))
            } else if n.heat.hasPrefix("跟风多但") {
                s -= 4
                risks.append(VerdictReason(level: "warn", text: cat("叙事热度：", n.heat), basis: "同类代币的成交额、新建池数、涨跌中位数"))
            } else if n.heat.hasPrefix("升温") {
                s += 3
                goods.append(VerdictReason(level: "ok", text: cat("叙事热度：", n.heat), basis: "同类代币的成交额、新建池数、涨跌中位数"))
            }
            score = s
        }
        if var s = score {
            s = max(0, min(100, s))
            if !r.hard.isEmpty { s = min(s, 25) }
            score = s
        }
        let g = grade(score)

        var parts: [String] = [g.0, stage]
        if let n = narr, let h = n.hits.first { parts.append(cat(h.title, " · ", n.position.components(separatedBy: " · ").first ?? n.position)) }
        if let t = risks.first { parts.append(String(t.text.prefix(30))) }
        let headline = parts.joined(separator: " ｜ ")

        // 盯盘阈值：现在的数值 + 触发线
        var watch: [String] = []
        if m.liq > 0 { watch.append(cat("流动性跌破 ", Fmt2.usd(m.liq * 0.7), "（当前 ", Fmt2.usd(m.liq), "，−30%）≈ 疑似撤池")) }
        if let p = m.price, p > 0 { watch.append(cat("价格跌破 ", Money.price(p * 0.8), "（当前 ", Money.price(p), "，−20%）")) }
        if let w = vm.conc?.wallets10 { watch.append(cat("前 10 普通钱包占比升到 ", String(format: "%.1f%%", Double(w) + 5), " 以上（当前 ", String(format: "%.1f%%", Double(w)), "）")) }
        if let w1 = FlowCalc.windows(vm.trades, now: Date().timeIntervalSince1970).first(where: { $0.id == "1h" }), w1.total >= 500 {
            watch.append(cat("1 小时资金净流向转为", w1.net >= 0 ? "净流出" : "净流入", "（当前 ", Fmt2.usd(w1.net, signed: true), "）"))
        }
        let a = vm.agg
        if a.withPos >= 2 {
            let cleared = vm.analyses.values.compactMap { $0.position }.filter { ($0.boughtUsd ?? 0) > 0 && ($0.qtyHeld ?? 1) <= 0 }.count
            watch.append(cat("已拆解大户里新增清仓（当前 ", String(cleared), " 个，共拆解 ", String(a.withPos), " 个）"))
        }

        // 较上次
        var deltas: [VerdictDelta] = []
        var deltaTitle = ""
        let now = Date().timeIntervalSince1970
        if let p = prevDigest(vm), now - p.t >= 120 {
            deltaTitle = cat("较 ", Fmt2.dur(now - p.t), " 前")
            if p.liq > 0 && m.liq > 0 {
                let c = m.liq / p.liq - 1
                if abs(c) >= 0.1 { deltas.append(VerdictDelta(text: cat("流动性 ", pctText(c), "（", Fmt2.usd(p.liq), " → ", Fmt2.usd(m.liq), "）"), good: c > 0)) }
            }
            let mc = m.marketCap ?? m.fdv ?? 0
            if p.mc > 0 && mc > 0 {
                let c = mc / p.mc - 1
                if abs(c) >= 0.1 { deltas.append(VerdictDelta(text: cat("市值 ", pctText(c), "（", Fmt2.usd(p.mc), " → ", Fmt2.usd(mc), "）"), good: nil)) }
            }
            if let a0 = p.w10, let w = vm.conc?.wallets10 {
                let d = Double(w) - a0
                if abs(d) >= 3 { deltas.append(VerdictDelta(text: cat("前 10 占比 ", String(format: "%+.1f", d), " 个百分点"), good: d < 0)) }
            }
            if let ps = p.score, let s = score, abs(s - ps) >= 5 { deltas.append(VerdictDelta(text: cat("安全分 ", String(ps), " → ", String(s)), good: s > ps)) }
        }

        // 数据完整度（9 项：7 个规则维度 + 生命周期 + 叙事）
        var have = r.dims.count
        if life != nil { have += 1 }
        if narr != nil { have += 1 }
        var comp = cat("数据覆盖 ", String(have), "/9 项")
        if let t = vm.stamps.pairs, now - t.timeIntervalSince1970 > 180 { comp += "；行情不是最新" }
        if let t = vm.stamps.holders, now - t.timeIntervalSince1970 > 3600 { comp += "；持有人数据偏旧" }
        if !r.unknown.isEmpty { comp += cat("；未知 ", String(r.unknown.count), " 项") }

        // AI 与规则冲突提示
        var conflict: String? = nil
        if let s = score, let st = vm.ai?.analysis?.stance {
            let ai = st.contains("险") ? 0 : (st.contains("积极") ? 2 : (st.contains("不足") ? -1 : 1))
            let rules = s >= 75 ? 2 : (s >= 55 ? 1 : 0)
            if ai >= 0 && abs(ai - rules) >= 2 { conflict = cat("AI 判断「", st, "」，规则判断「", g.0, "」，两边冲突。以各项依据里的真实数据为准，AI 只是辅助。") }
        }
        return Verdict(score: score, grade: g.0, color: g.1, headline: headline, stage: stage, risks: Array(risks.prefix(6)), goods: Array(goods.prefix(4)), watch: Array(watch.prefix(5)), deltas: deltas, deltaTitle: deltaTitle, completeness: comp, conflict: conflict)
    }
}

struct VerdictCard: View {
    @ObservedObject var vm: UTokenVM

    private func col(_ l: String) -> Color { l == "risk" ? .red : (l == "warn" ? .orange : (l == "ok" ? .green : .blue)) }

    var body: some View {
        let v = VerdictEngine.build(vm)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Label("综合研判", systemImage: "scope").font(.headline)
                    Spacer()
                    Text(v.grade).font(.title3.bold()).foregroundStyle(v.color)
                }
                if let s = v.score {
                    HStack(spacing: 10) {
                        Text(String(s)).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(v.color)
                        VStack(alignment: .leading, spacing: 4) {
                            ScoreBar(score: s, color: v.color)
                            Text("安全分（越高越安全）").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Text(v.headline).font(.subheadline.weight(.semibold))
                if let c = v.conflict { Text(c).font(.caption).foregroundStyle(Color.orange) }

                if !v.risks.isEmpty {
                    Text("利空 / 风险").font(.caption).foregroundStyle(.secondary)
                    ForEach(v.risks) { f in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .top, spacing: 6) {
                                Circle().fill(col(f.level)).frame(width: 7, height: 7).padding(.top, 6)
                                Text(f.text).font(.subheadline)
                            }
                            Text(cat("依据：", f.basis)).font(.caption2).foregroundStyle(.secondary).padding(.leading, 13)
                        }
                    }
                }
                if !v.goods.isEmpty {
                    Text("利好").font(.caption).foregroundStyle(.secondary)
                    ForEach(v.goods) { f in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .top, spacing: 6) {
                                Circle().fill(Color.green).frame(width: 7, height: 7).padding(.top, 6)
                                Text(f.text).font(.subheadline)
                            }
                            Text(cat("依据：", f.basis)).font(.caption2).foregroundStyle(.secondary).padding(.leading, 13)
                        }
                    }
                }
                if !v.watch.isEmpty {
                    Divider()
                    Text("盯盘阈值（触发线，不是买卖建议）").font(.caption).foregroundStyle(.secondary)
                    ForEach(v.watch, id: \.self) { w in Text(cat("· ", w)).font(.footnote) }
                }
                if !v.deltas.isEmpty {
                    Divider()
                    Text(v.deltaTitle).font(.caption).foregroundStyle(.secondary)
                    ForEach(v.deltas) { d in
                        Text(cat("· ", d.text)).font(.footnote).foregroundStyle(d.good == nil ? Color.primary : (d.good == true ? Color.green : Color.red))
                    }
                }
                Text(cat(v.completeness, " · 各项明细见下方「分项明细」")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task(id: vm.stamps.analyses) { VerdictEngine.saveIfDue(vm) }
    }
}
