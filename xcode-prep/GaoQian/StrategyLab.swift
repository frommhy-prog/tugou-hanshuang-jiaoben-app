import SwiftUI

// 策略实验室（Freqtrade / Hummingbot / OctoBot / Jesse / CCXT / ai-hedge-fund / TradingAgents / FinRL-FinGPT 的只读能力等价）。
// 不交易、不下单、不控任何 Bot 的启停、不碰私钥、不给买卖建议；大模型意见待 Groq Key 验证后另接，这里恒为空。
struct StrategyLabView: View {
    @ObservedObject private var fx = CurrencyStore.shared
    @State private var chain: Chain = .base
    @State private var address = ""
    @State private var symbol = ""
    @State private var lab: APIClient.StrategyLabResponse?
    @State private var arb: APIClient.ArbResponse?
    @State private var agents: APIClient.AgentsResponse?
    @State private var errorText: String?
    @State private var loading = false

    var body: some View {
        Form {
            Section("策略实验室（只读，只看不交易）") {
                Picker("链", selection: $chain) { ForEach(Chain.allCases) { c in Text(c.displayName).tag(c) } }
                TextField("合约地址", text: $address)
                Button(loading ? "加载中…" : "策略检查 + 网格/DCA 计算器") {
                    Task { loading = true; errorText = nil; do { lab = try await APIClient.fetchStrategyLab(chain: chain, address: address) } catch { errorText = "策略失败：\(error.localizedDescription)" }; loading = false }
                }.disabled(loading)
                Button(loading ? "加载中…" : "套利比价（多源价差，不是利润）") {
                    Task { loading = true; errorText = nil; do { arb = try await APIClient.fetchArb(chain: chain, address: address) } catch { errorText = "比价失败：\(error.localizedDescription)" }; loading = false }
                }.disabled(loading)
                Button(loading ? "加载中…" : "多智能体（技术/基本面/情绪/风控，规则版）") {
                    Task { loading = true; errorText = nil; do { agents = try await APIClient.fetchAgents(chain: chain, address: address) } catch { errorText = "智能体失败：\(error.localizedDescription)" }; loading = false }
                }.disabled(loading)
                TextField("主流币符号（只比 CEX 现货，如 ETH）", text: $symbol)
                Button(loading ? "加载中…" : "统一交易所价（Gate/Kraken/Coinbase）") {
                    Task { loading = true; errorText = nil; do { arb = try await APIClient.fetchArbSymbol(symbol: symbol) } catch { errorText = "统一价失败：\(error.localizedDescription)" }; loading = false }
                }.disabled(loading)
                if let e = errorText { Text(e).font(.footnote) }
            }
            if let l = lab {
                Section("策略检查（规则通过 ≠ 推荐）") {
                    Text("\(l.symbol ?? "") · 价 \(fmtPrice(l.priceUsd)) · 流动性 \(fmtUsd(l.liquidityUsd)) · 24h 量 \(fmtUsd(l.volume24hUsd)) · 买盘 \(l.buyShare24hPct ?? 0)% · 池龄 \(l.poolAgeDays ?? 0) 天").font(.footnote)
                    if let rules = l.rules { ForEach(rules.indices, id: \.self) { i in Text("\(rules[i].pass == true ? "✓" : "✗") \(rules[i].name ?? "")：\(rules[i].value ?? 0)").font(.caption) } }
                    if let g = l.grid { Text("网格（当前价 ±，算术而已）：\(g.map { "\($0.pct ?? 0)% \(fmtPrice($0.priceUsd))" }.joined(separator: " · "))").font(.caption) }
                    if let d = l.dcaExample { Text("DCA 示例：100 美元在当前价约 \(d.tokensAtCurrentPrice ?? 0) 个币，未来价未知").font(.caption) }
                    if let b = l.backtest { Text("回测：\(b.available == true ? "有" : "没有")。\(b.reason ?? "")").font(.footnote) }
                    if let n = l.note { Text(n).font(.footnote) }
                }
            }
            if let a = arb {
                Section("比价") {
                    Text("模式 \(a.mode ?? "") · 价差 \(a.spreadPct ?? 0)%（价差 ≠ 利润，手续费/滑点/Gas 未计）").font(.footnote)
                    if let ps = a.prices { ForEach(Array(ps.keys.sorted()), id: \.self) { k in Text("\(k)：\(fmtPrice(ps[k] ?? 0))").font(.caption) } }
                    if let n = a.note { Text(n).font(.footnote) }
                }
            }
            if let ag = agents {
                Section("多智能体（规则版，不是大模型）") {
                    Text("技术：\(ag.roles?.technical?.conclusion ?? "")").font(.footnote)
                    Text("基本面：\(ag.roles?.fundamental?.conclusion ?? "")").font(.footnote)
                    Text("情绪：无（情绪分 null，不编，另走社媒/快讯）").font(.footnote)
                    Text("风控：\(ag.roles?.risk?.conclusion ?? "")").font(.footnote)
                    Text("大模型意见：无（Groq Key 未验证前恒为空）").font(.footnote)
                    if let c = ag.consensus { Text(c).font(.footnote) }
                }
            }
            Section("8 个仓库怎么落的（没落的也写清楚）") {
                Text("Freqtrade：落了规则检查与筛选，没有真回测、没有超参优化、没有启停控制（那是交易执行，App 不做）。").font(.footnote)
                Text("Hummingbot：落了多源比价，没有做市、没有套利执行。").font(.footnote)
                Text("OctoBot：落了网格/DCA 计算器，AI 模式待 Groq Key，不假装有 AI。").font(.footnote)
                Text("Jesse：落了零前视原则（只用已发生数据），没有历史 K 线回测。").font(.footnote)
                Text("CCXT：落了 Gate/Kraken/Coinbase 统一价表，土狗不在 CEX 上所以只覆盖主流币。").font(.footnote)
                Text("ai-hedge-fund / TradingAgents：落了四角色分工展示，交易员下单与交易决策不落地。").font(.footnote)
                Text("FinRL：落了状态快照，没有训练模型、没有动作、没有奖励。FinGPT：大模型意见待 Groq Key 验证后另接。").font(.footnote)
                Text("以上全部不跑 Python、不需常驻服务器、不碰交易所 Key，免费 Worker 就能跑；原仓库本身（Python、数据库、常驻进程、交易连接）在免费 Worker 上跑不了，硬搬就是假的。").font(.footnote)
            }
        }
        .navigationTitle("策略实验室")
    }
}
