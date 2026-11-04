import SwiftUI

// MARK: - 付费推广（Dexscreener 订单）与 DEV（创建者）
struct PromoOrder: Identifiable {
    let type: String
    let status: String
    let ts: Double
    var id: String { type + String(ts) }
    var typeText: String {
        switch type {
        case "tokenProfile": return "代币资料页"
        case "communityTakeover": return "社区接管"
        case "tokenAd": return "代币广告"
        case "trendingBarAd": return "趋势栏广告"
        default: return type
        }
    }
    var statusText: String {
        switch status {
        case "approved": return "已通过"
        case "processing": return "处理中"
        case "on-hold": return "暂缓"
        case "cancelled": return "已取消"
        case "rejected": return "已驳回"
        default: return status
        }
    }
}

struct DevInfo {
    var address: String?
    var pct: Double?
    var source: String
    var note: String?
}

enum PromoAPI {
    // https://docs.dexscreener.com/api ：/orders/v1/{chainId}/{tokenAddress} 只返回 type / status / paymentTimestamp
    static func orders(_ chain: Chain, _ token: String) async throws -> [PromoOrder] {
        let o: Any
        do {
            o = try await MarketAPI.json("https://api.dexscreener.com/orders/v1/\(chain.dexId)/\(token)")
        } catch APIError.http(let code, _) where code == 404 {
            return []
        }
        var arr: [[String: Any]] = []
        if let a = o as? [[String: Any]] { arr = a }
        else if let d = o as? [String: Any], let a = d["orders"] as? [[String: Any]] { arr = a }
        var out: [PromoOrder] = []
        for x in arr {
            var ts = MarketAPI.num(x["paymentTimestamp"]) ?? 0
            if ts > 1e12 { ts /= 1000 }
            out.append(PromoOrder(type: (x["type"] as? String) ?? "?", status: (x["status"] as? String) ?? "?", ts: ts))
        }
        return out.sorted { $0.ts > $1.ts }
    }

    // 当前生效的 Boost 数（tokens/v1 里每个池子的 boosts.active，取最大）
    static func boosts(_ chain: Chain, _ token: String) async -> Int? {
        guard let a = try? await MarketAPI.json("https://api.dexscreener.com/tokens/v1/\(chain.dexId)/\(token)") as? [[String: Any]] else { return nil }
        var best: Int?
        for p in a {
            let base = ((p["baseToken"] as? [String: Any])?["address"] as? String) ?? ""
            if base.lowercased() != token.lowercased() { continue }
            if let n = MarketAPI.num((p["boosts"] as? [String: Any])?["active"]) { best = max(best ?? 0, Int(n)) }
        }
        return best
    }

    // DEV = 代币创建者。Solana 用 RugCheck，EVM 用 GoPlus（都免费、不需要密钥）
    static func dev(_ chain: Chain, _ token: String) async -> DevInfo {
        if chain == .solana {
            guard let o = try? await MarketAPI.json("https://api.rugcheck.xyz/v1/tokens/\(token)/report") as? [String: Any] else {
                return DevInfo(address: nil, pct: nil, source: "RugCheck", note: "RugCheck 暂时读不到这个币的报告")
            }
            let c = (o["creator"] as? String) ?? ""
            var pct: Double?
            if let bal = MarketAPI.num(o["creatorBalance"]) {
                if bal == 0 { pct = 0 }
                else if let sup = MarketAPI.num((o["token"] as? [String: Any])?["supply"]), sup > 0, bal / sup <= 1 { pct = bal / sup * 100 }
            }
            return DevInfo(address: c.isEmpty ? nil : c, pct: pct, source: "RugCheck", note: c.isEmpty ? "RugCheck 没有给出创建者地址" : nil)
        }
        let ids: [String: Int] = ["ethereum": 1, "bsc": 56, "base": 8453, "arbitrum": 42161, "optimism": 10, "polygon": 137, "xlayer": 196]
        guard let cid = ids[chain.dexId] else {
            return DevInfo(address: nil, pct: nil, source: "GoPlus", note: "这条链暂不支持查创建者")
        }
        let key = token.lowercased()
        guard let o = try? await MarketAPI.json("https://api.gopluslabs.io/api/v1/token_security/\(cid)?contract_addresses=\(key)") as? [String: Any],
              let res = o["result"] as? [String: Any], let d = res[key] as? [String: Any] else {
            return DevInfo(address: nil, pct: nil, source: "GoPlus", note: "GoPlus 暂时读不到这个币")
        }
        let c = (d["creator_address"] as? String) ?? ""
        let pct = MarketAPI.num(d["creator_percent"]).map { $0 * 100 }
        return DevInfo(address: c.isEmpty ? nil : c, pct: pct, source: "GoPlus", note: c.isEmpty ? "GoPlus 没有给出创建者地址" : nil)
    }
}

struct PromoCard: View {
    @ObservedObject var vm: UTokenVM
    @State private var orders: [PromoOrder]?
    @State private var ordersErr: String?
    @State private var boosts: Int?
    @State private var dev: DevInfo?
    @State private var devAn: UHolderAnalysis?
    @State private var devAnErr: String?
    @State private var devLoading = false
    @State private var payer = ""
    @State private var loadedKey = ""

    private var key: String { vm.chain.rawValue + ":" + vm.address + ":" + (vm.main?.pairAddress ?? "") }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("付费推广 · DEV", systemImage: "megaphone.fill").font(.headline)
                promoSection
                Divider()
                devSection
                Divider()
                relationSection
            }
        }
        .task(id: key) { await load() }
    }

    private func load() async {
        if vm.address.isEmpty || vm.main == nil { return }
        if loadedKey == key && orders != nil { return }
        loadedKey = key
        let chain = vm.chain
        let token = vm.address
        orders = nil
        ordersErr = nil
        boosts = nil
        dev = nil
        devAn = nil
        devAnErr = nil
        payer = ""
        async let d: DevInfo = PromoAPI.dev(chain, token)
        async let b: Int? = PromoAPI.boosts(chain, token)
        do { orders = try await PromoAPI.orders(chain, token) } catch { ordersErr = Net.message(error) }
        boosts = await b
        dev = await d
        if let list = orders, !list.isEmpty, let a = dev?.address { await analyzeDev(a) }
    }

    private func analyzeDev(_ addr: String) async {
        devLoading = true
        devAnErr = nil
        defer { devLoading = false }
        do {
            let r: UHolderAnalysis = try await Engine.get("/e/v2/holder", ["chain": vm.chain.rawValue, "token": vm.address, "owner": addr, "pages": "2"])
            if let e = r.error { devAnErr = e + (r.detail.map { "：" + $0 } ?? "") } else { devAn = r }
        } catch {
            devAnErr = Net.message(error)
        }
    }

    private func devAnalysis() -> UHolderAnalysis? {
        guard let a = dev?.address else { return nil }
        if let hit = vm.analyses.first(where: { kNorm($0.key) == kNorm(a) }) { return hit.value }
        return devAn
    }

    private func devPct(_ a: String, _ d: DevInfo) -> (Double, String)? {
        if let h = vm.holders.first(where: { kNorm($0.owner) == kNorm(a) }), let p = h.pct { return (p, "持有人榜第 \(h.rank) 名") }
        if let p = d.pct { return (p, d.source) }
        return nil
    }

    private func gapText(_ s: Double) -> String {
        if s < 0 { return "付款时间早于最深池子的创建时间" }
        return "建池后 " + Fmt2.dur(s) + " 付款"
    }

    // 付款时点之后 DEV 在这个币上的买卖（只用引擎读到的最近几笔，覆盖不到的如实标出）
    private func behavior(_ list: [PromoOrder], _ an: UHolderAnalysis) -> [String] {
        var rows: [String] = []
        if let p = an.position {
            if let e = p.entry { rows.append("DEV 入场：" + e) }
            if let st = p.state { rows.append("DEV 状态：" + st) }
            rows.append("DEV 累计买入 " + Fmt2.usd(p.boughtUsd) + "，卖出 " + Fmt2.usd(p.soldUsd))
        }
        let trades = an.trades ?? []
        if let pay = list.filter({ $0.ts > 0 }).map({ $0.ts }).min() {
            var b = 0.0
            var s = 0.0
            var nb = 0
            var ns = 0
            for t in trades where t.t >= pay {
                let u = t.usd ?? 0
                if t.side == "buy" { b += u; nb += 1 } else { s += u; ns += 1 }
            }
            rows.append("最早一次付款（" + TZ.short(Date(timeIntervalSince1970: pay)) + "）之后：DEV 买 " + Fmt2.usd(b) + "（\(nb) 笔），卖 " + Fmt2.usd(s) + "（\(ns) 笔）")
            if trades.isEmpty { rows.append("没有读到 DEV 在这个币上的成交记录（可能从未交易，也可能是数据源没覆盖）") }
            else if let oldest = trades.map({ $0.t }).min(), pay < oldest { rows.append("付款早于读到的最早一笔 DEV 成交（" + TZ.short(Date(timeIntervalSince1970: oldest)) + "），付款后的成交可能没读全") }
        }
        return rows
    }

    private var compareText: String {
        let p = payer.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return "" }
        var rows: [String] = []
        if let a = dev?.address { rows.append(kNorm(a) == kNorm(p) ? "付款地址 = DEV 地址（同一个钱包）" : "付款地址 ≠ DEV 地址（不同钱包不等于无关，DEV 常用小号付款，资金来源要看链上转账）") }
        if let h = vm.holders.first(where: { kNorm($0.owner) == kNorm(p) }) {
            rows.append("付款地址是持有人榜第 \(h.rank) 名，占 " + (h.pct.map { String(format: "%.2f%%", $0) } ?? "?"))
        } else {
            rows.append("付款地址不在已读取的持有人榜里")
        }
        return rows.joined(separator: "；")
    }

    @ViewBuilder
    private var promoSection: some View {
        if let list = orders {
            if list.isEmpty {
                Text("Dexscreener 没有这个币的付费订单（资料页、广告、趋势栏、社区接管都没有）").font(.footnote)
            } else {
                ForEach(list) { o in
                    HStack {
                        Pill(text: o.typeText, color: Color.orange)
                        Text(o.statusText).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(o.ts > 0 ? TZ.short(Date(timeIntervalSince1970: o.ts)) : "时间未知").font(.caption.monospacedDigit())
                    }
                    if let cr = vm.main?.pairCreatedAt, o.ts > 0 {
                        Text(gapText(o.ts - cr / 1000)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            if let b = boosts, b > 0 { Text("当前有 \(b) 个加速（Boost）生效").font(.footnote) }
        } else if let e = ordersErr {
            Text("读取失败：" + e).font(.footnote).foregroundStyle(Color.orange)
        } else {
            HStack { ProgressView(); Text("读取付费推广订单…").font(.footnote).foregroundStyle(.secondary) }
        }
        Text("付费推广 = 向 Dexscreener 花钱买的资料页 / 广告 / 加速。只说明项目方愿意花钱宣传，不代表币安全；没有订单也不代表没在其他平台投放。").font(.caption2).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var devSection: some View {
        HStack {
            Text("DEV（创建者）").font(.subheadline.weight(.semibold))
            Spacer()
            if let d = dev { Text("来源 " + d.source).font(.caption2).foregroundStyle(.secondary) }
        }
        if let d = dev {
            if let a = d.address {
                Text(a).font(.caption.monospaced()).textSelection(.enabled)
                if let p = devPct(a, d) { Text(String(format: "DEV 现持有 %.2f%%（%@）", p.0, p.1)).font(.footnote) }
                else { Text("DEV 现持仓占比：未知").font(.footnote).foregroundStyle(.secondary) }
            } else {
                Text(d.note ?? "DEV 地址未知").font(.footnote).foregroundStyle(.secondary)
            }
        } else {
            HStack { ProgressView(); Text("读取 DEV…").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder
    private var relationSection: some View {
        Text("付款地址 ↔ DEV").font(.subheadline.weight(.semibold))
        Text("付款地址：未知。Dexscreener 订单接口只给「类型、状态、付款时间」，不公开付款人地址，任何公开接口都查不到，所以没法验证「付款人 = DEV」或「DEV 给付款人转过钱」。能验证的是：付款时点前后 DEV 在这个币上做了什么。").font(.footnote)
        if let list = orders, !list.isEmpty, dev?.address != nil {
            if let an = devAnalysis() {
                ForEach(Array(behavior(list, an).enumerated()), id: \.offset) { _, r in Text("· " + r).font(.footnote) }
            } else if devLoading {
                HStack { ProgressView(); Text("分析 DEV 买卖…").font(.footnote).foregroundStyle(.secondary) }
            } else if let e = devAnErr {
                Text("DEV 买卖分析失败：" + e).font(.footnote).foregroundStyle(Color.orange)
            }
        } else if let a = dev?.address, devAnalysis() == nil {
            Button("分析 DEV 在这个币上的买卖") { Task { await analyzeDev(a) } }.font(.footnote.weight(.semibold))
        }
        TextField("已知的付款地址（可选，手动填入对比）", text: $payer)
            .font(.caption.monospaced())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        if !compareText.isEmpty { Text(compareText).font(.footnote) }
    }
}
