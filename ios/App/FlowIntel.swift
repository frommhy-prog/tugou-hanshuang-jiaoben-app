import SwiftUI

// MARK: - 情报：庄家画像 / 洗盘 / 机器人 / 聪明钱 / 钱包关联 / 交易复盘（全部用已有的成交、持有人、拆解数据现算，每条附依据）
struct LinkRow: Codable, Identifiable {
    var owner: String
    var funder: String?
    var amt: Double?
    var asset: String?
    var ts: Double?
    var hash: String?
    var name: String?
    var type: String?
    var id: String { owner }
}

struct LinkCluster: Codable, Identifiable {
    var funder: String
    var owners: [String]
    var name: String?
    var contract: Bool?
    var id: String { funder }
}

struct LinksResp: Codable {
    var links: [LinkRow]?
    var clusters: [LinkCluster]?
    var error: String?
    var detail: String?
}

enum Intel {
    // 洗盘：同地址买卖往返、固定金额、同秒多笔、成交高度集中
    static func wash(_ ts: [UTrade]) -> (Int, [Finding]) {
        var rows: [Finding] = []
        if ts.count < 20 {
            rows.append(Finding(level: "info", text: "成交样本只有 " + String(ts.count) + " 笔（至少需要 20 笔），无法判断洗盘", basis: "成交来自 GeckoTerminal 最近约 300 笔"))
            return (0, rows)
        }
        let gross = ts.reduce(0.0) { $0 + $1.usd }
        var score = 0.0
        let ad = FlowCalc.addrs(ts)
        var rtVol = 0.0
        var rtN = 0
        for a in ad where a.nb >= 2 && a.ns >= 2 {
            let hi = max(a.buy, a.sell)
            let lo = min(a.buy, a.sell)
            if hi > 0 && lo / hi >= 0.7 { rtVol += lo * 2; rtN += 1 }
        }
        let rtShare = gross > 0 ? rtVol / gross : 0
        if rtN >= 1 {
            score += min(45, rtShare * 120)
            rows.append(Finding(level: rtShare >= 0.25 ? "risk" : "warn", text: String(rtN) + " 个地址买卖各 ≥2 笔且买卖额接近（差额 ≤30%），往返成交约占总成交额 " + String(format: "%.0f%%", rtShare * 100), basis: "同一发起地址自买自卖是洗盘的典型形态，也可能是套利机器人，链上无法区分"))
        }
        var freq: [Int: Int] = [:]
        for t in ts where t.usd >= 5 { freq[Int(t.usd.rounded()), default: 0] += 1 }
        if let top = freq.max(by: { $0.value < $1.value }), top.value >= 6, Double(top.value) / Double(ts.count) >= 0.2 {
            score += 20
            rows.append(Finding(level: "warn", text: "有 " + String(top.value) + " 笔成交额都约为 $" + String(top.key) + "（占 " + String(format: "%.0f%%", Double(top.value) / Double(ts.count) * 100) + "），金额高度固定", basis: "程序化刷量常用固定额度"))
        }
        var sec: [String: Int] = [:]
        for t in ts { sec[t.who + "|" + String(Int(t.t)), default: 0] += 1 }
        let burst = sec.values.filter { $0 >= 3 }.count
        if burst >= 3 {
            score += 15
            rows.append(Finding(level: "warn", text: String(burst) + " 个时间点同一地址在 1 秒内成交 ≥3 笔", basis: "人工操作做不到，说明是脚本"))
        }
        let top5 = ad.prefix(5).reduce(0.0) { $0 + $1.total }
        if gross > 0, ad.count >= 5, top5 / gross > 0.6 {
            score += 15
            rows.append(Finding(level: "warn", text: "前 5 个地址贡献了 " + String(format: "%.0f%%", top5 / gross * 100) + " 的成交额", basis: "成交集中在极少数地址，真实散户参与度低"))
        }
        if rows.isEmpty { rows.append(Finding(level: "ok", text: "最近 " + String(ts.count) + " 笔成交里没有发现明显洗盘特征", basis: "检查了往返成交、固定金额、同秒多笔、成交集中度")) }
        return (Int(min(100, score)), rows)
    }

    // 机器人：成交间隔极短 / 间隔高度规整 / 拆解标签里的程序化标记
    static func bots(_ ts: [UTrade], _ vm: UTokenVM) -> [(String, String)] {
        var by: [String: [Double]] = [:]
        for t in ts where !t.who.isEmpty { by[t.who, default: []].append(t.t) }
        var out: [(String, String)] = []
        for (w, arr) in by where arr.count >= 6 {
            let s = arr.sorted()
            var gaps: [Double] = []
            for i in 1..<s.count { gaps.append(s[i] - s[i - 1]) }
            let mean = gaps.reduce(0, +) / Double(gaps.count)
            var sq = 0.0
            for g in gaps { sq += (g - mean) * (g - mean) }
            let sd = (sq / Double(gaps.count)).squareRoot()
            let med = gaps.sorted()[gaps.count / 2]
            if med <= 6 {
                out.append((w, String(arr.count) + " 笔，成交间隔中位数 " + String(format: "%.1f", med) + " 秒（高频）"))
            } else if mean > 0 && sd / mean < 0.3 {
                out.append((w, String(arr.count) + " 笔，成交间隔高度规整（离散度 " + String(format: "%.2f", sd / mean) + "）"))
            }
        }
        for (owner, an) in vm.analyses {
            for t in an.tags ?? [] where t.tag.contains("程序化") || t.tag.contains("高频") {
                out.append((owner, t.tag + "（" + (t.basis ?? "拆解标签") + "）"))
            }
        }
        return out
    }

    // 聪明钱：已拆解的大户里，历史胜率高且样本够的钱包
    static func smart(_ vm: UTokenVM) -> [(String, String)] {
        var out: [(String, String)] = []
        for (owner, an) in vm.analyses {
            guard let s = an.stats, let wr = s.winRate, (s.realizedN ?? 0) >= 5, wr >= 0.6 else { continue }
            var line = "胜率 " + String(format: "%.0f%%", wr * 100) + "（" + String(s.realizedN ?? 0) + " 个已兑现币）"
            if let m = s.medHoldSec { line += "，持仓中位 " + Fmt2.dur(m) }
            if let p = an.position {
                line += "；本币：" + (p.state ?? "—")
                if let r = p.roi { line += "，综合 " + Fmt2.pct(r) }
            }
            out.append((owner, line))
        }
        return out.sorted { $0.0 < $1.0 }
    }

    // 庄家 / 控盘画像：集中度、早期筹码、吸筹/出货迹象、资金同源集团
    static func whale(_ vm: UTokenVM, _ links: LinksResp?) -> [Finding] {
        var rows: [Finding] = []
        let wallets = vm.holders.filter { $0.kind == "wallet" }
        if wallets.count >= 3 {
            let t3 = wallets.prefix(3).reduce(0.0) { $0 + ($1.pct ?? 0) }
            rows.append(Finding(level: t3 >= 30 ? "risk" : (t3 >= 15 ? "warn" : "ok"), text: String(format: "前 3 大普通钱包合计持有 %.1f%%", t3), basis: "持有人榜单，已剔除池子与合约"))
        }
        var earlyPct = 0.0
        var earlyN = 0
        var selling = 0
        var accumulating = 0
        var holding = 0
        for h in wallets.prefix(10) {
            guard let p = vm.analyses[h.owner]?.position else { continue }
            if let d = p.delayMin, d >= 0, d <= 10 { earlyPct += h.pct ?? 0; earlyN += 1 }
            let b = p.buys ?? 0
            let s = p.sells ?? 0
            let held = p.qtyHeld ?? 0
            if s >= 2 && (p.realizedUsd ?? 0) > 0 { selling += 1 }
            else if b > s && held > 0 { accumulating += 1 }
            else if held > 0 { holding += 1 }
        }
        if earlyN >= 1 {
            rows.append(Finding(level: earlyPct >= 15 ? "risk" : "warn", text: String(earlyN) + " 个大户在池子创建 10 分钟内入场，合计持有 " + String(format: "%.1f%%", earlyPct), basis: "拆解里的首次买入时间 − 池子创建时间；早期大额筹码常是庄家或内部"))
        }
        if selling + accumulating + holding > 0 {
            let lvl = selling > accumulating + holding ? "risk" : "info"
            rows.append(Finding(level: lvl, text: "已拆解大户动向：出货 " + String(selling) + " 个 · 加仓 " + String(accumulating) + " 个 · 持仓不动 " + String(holding) + " 个", basis: "出货 = 卖出 ≥2 笔且已兑现盈利；加仓 = 买入笔数多于卖出且仍持仓"))
        }
        if let cs = links?.clusters {
            for c in cs {
                let set = Set(c.owners.map { $0.lowercased() })
                let share = vm.holders.filter { set.contains($0.owner.lowercased()) }.reduce(0.0) { $0 + ($1.pct ?? 0) }
                rows.append(Finding(level: share >= 15 ? "risk" : "warn", text: String(c.owners.count) + " 个大户由同一地址出资，合计持有 " + String(format: "%.1f%%", share) + "，疑似同一控制人", basis: "出资地址 " + Addr.short(c.funder) + (c.name.map { "（" + $0 + "）" } ?? "")))
            }
        }
        return rows
    }

    // 交易复盘：每个已拆解大户在这个币上的买点位置、买后回撤、卖后是否卖飞（用本地 K 线缓存）
    static func review(_ vm: UTokenVM) -> [Finding] {
        guard let pair = vm.main?.pairAddress else { return [] }
        var cs = KLineCache.load(vm.chain.rawValue + ":" + pair + ":" + TF.m15.rawValue)
        if cs.count < 20 { cs = KLineCache.load(vm.chain.rawValue + ":" + pair + ":" + TF.h1.rawValue) }
        guard cs.count >= 20, let lo = cs.map({ $0.l }).min(), let hi = cs.map({ $0.h }).max(), hi > lo else {
            return [Finding(level: "info", text: "K 线缓存不足，先在上面的图表里加载一会儿再来复盘", basis: "复盘需要该币的历史价格")]
        }
        var rows: [Finding] = []
        for h in vm.holders.filter({ $0.kind == "wallet" }).prefix(10) {
            guard let an = vm.analyses[h.owner], let ts = an.trades, !ts.isEmpty else { continue }
            var buyPos: [Double] = []
            var dd: [Double] = []
            var missed: [Double] = []
            for t in ts {
                guard let q = t.qty, let u = t.usd, q > 0, u > 0 else { continue }
                let px = u / q
                let after = cs.filter { $0.t >= t.t }
                if t.side == "buy" {
                    buyPos.append((px - lo) / (hi - lo))
                    if let mn = after.map({ $0.l }).min() { dd.append(mn / px - 1) }
                } else if let mx = after.map({ $0.h }).max() {
                    missed.append(mx / px - 1)
                }
            }
            if buyPos.isEmpty && missed.isEmpty { continue }
            var line = "#" + String(h.rank) + " " + Addr.short(h.owner) + "："
            if !buyPos.isEmpty {
                let avg = buyPos.reduce(0, +) / Double(buyPos.count)
                let tag = avg <= 0.25 ? "抄底型" : (avg >= 0.7 ? "追高型" : "中位入场")
                line += "买点在区间 " + String(format: "%.0f%%", avg * 100) + " 位置（" + tag + "）"
                if let w = dd.min() { line += "，买后最大回撤 " + String(format: "%.0f%%", w * 100) }
            }
            if !missed.isEmpty {
                let avgM = missed.reduce(0, +) / Double(missed.count)
                line += "；卖出后平均还涨 " + String(format: "%.0f%%", avgM * 100) + (avgM >= 0.5 ? "（卖飞）" : "")
            }
            rows.append(Finding(level: "info", text: line, basis: "区间 = 已缓存 K 线的最低到最高价；买入价 = 成交额 ÷ 数量"))
            if rows.count >= 6 { break }
        }
        if rows.isEmpty { rows.append(Finding(level: "info", text: "已拆解的大户里没有带数量和金额的成交记录可复盘", basis: "先在「筹码」页等大户拆解完成")) }
        return rows
    }
}

struct IntelTab: View {
    @ObservedObject var vm: UTokenVM
    @State private var links: LinksResp?
    @State private var linksBusy = false
    @State private var linksErr: String?

    var body: some View {
        VStack(spacing: 14) {
            whaleCard
            washCard
            botCard
            smartCard
            linkCard
            reviewCard
            DeFadeCard(vm: vm)
        }
    }

    private var whaleCard: some View {
        let rows = Intel.whale(vm, links)
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("庄家 / 控盘画像", systemImage: "person.3.fill").font(.headline)
                if rows.isEmpty { Text("持有人还在加载，或这个币没有可分析的普通钱包").font(.footnote).foregroundStyle(.secondary) }
                ForEach(rows) { FindingRow(f: $0) }
                Text("画像来自持有人榜单与大户拆解；「同一控制人」需要先点下方「钱包关联」查询。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var washCard: some View {
        let r = Intel.wash(vm.trades)
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("洗盘 / 刷量检测", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                    Spacer()
                    if vm.trades.count >= 20 { Pill(text: "嫌疑 " + String(r.0) + "/100", color: r.0 >= 50 ? Color.red : (r.0 >= 25 ? Color.orange : Color.green)) }
                }
                ForEach(r.1) { FindingRow(f: $0) }
            }
        }
    }

    private var botCard: some View {
        let list = Intel.bots(vm.trades, vm)
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("机器人识别", systemImage: "cpu").font(.headline)
                if list.isEmpty { Text("最近成交里没有识别出高频或节奏规整的地址").font(.footnote).foregroundStyle(.secondary) }
                ForEach(Array(list.prefix(8).enumerated()), id: \.offset) { _, b in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Addr.short(b.0)).font(.caption.monospaced())
                        Text(b.1).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("判据：成交 ≥6 笔且间隔中位数 ≤6 秒，或间隔离散度 <0.3；链上无法区分套利机器人与对敲，只给线索。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var smartCard: some View {
        let list = Intel.smart(vm)
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("聪明钱", systemImage: "brain.head.profile").font(.headline)
                if list.isEmpty { Text("已拆解的大户里暂时没有「胜率 ≥60% 且已兑现 ≥5 个币」的钱包").font(.footnote).foregroundStyle(.secondary) }
                ForEach(Array(list.prefix(6).enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Addr.short(s.0)).font(.caption.monospaced())
                        Text(s.1).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var linkCard: some View {
        let wallets = vm.holders.filter { $0.kind == "wallet" }.prefix(12).map { $0.owner }
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("钱包关联（资金同源）", systemImage: "link").font(.headline)
                if let l = links { linkBody(l) }
                else if let e = linksErr { Text(e).font(.footnote).foregroundStyle(Color.orange) }
                Button {
                    Task { await loadLinks(wallets) }
                } label: {
                    HStack(spacing: 6) {
                        if linksBusy { ProgressView() }
                        Text(links == nil ? "查询前 " + String(wallets.count) + " 个大户的出资来源" : "重新查询")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(linksBusy || wallets.count < 2)
                Text("原理：查每个大户钱包收到的第一笔原生币来自谁，多个大户共享同一出资地址 = 很可能同一人控制。交易所热钱包会让不相干的人撞车，出资地址是合约时只能当线索。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func linkBody(_ l: LinksResp) -> some View {
        let cs = l.clusters ?? []
        if cs.isEmpty {
            Text("查了 " + String((l.links ?? []).count) + " 个大户，没有发现共享出资地址").font(.footnote)
        }
        ForEach(cs) { c in
            VStack(alignment: .leading, spacing: 2) {
                Text(String(c.owners.count) + " 个大户同源 ← " + Addr.short(c.funder) + (c.name.map { "（" + $0 + "）" } ?? "")).font(.footnote.weight(.semibold)).foregroundStyle(Color.orange)
                Text(c.owners.map { Addr.short($0) }.joined(separator: "、")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func loadLinks(_ owners: [String]) async {
        linksBusy = true
        linksErr = nil
        defer { linksBusy = false }
        do {
            let r: LinksResp = try await Engine.get("/e/v2/links", ["chain": vm.chain.rawValue, "owners": owners.joined(separator: ",")])
            if let e = r.error { linksErr = e + (r.detail.map { "：" + $0 } ?? "") } else { links = r }
        } catch {
            linksErr = Net.message(error)
        }
    }

    private var reviewCard: some View {
        let rows = Intel.review(vm)
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("交易复盘", systemImage: "clock.arrow.circlepath").font(.headline)
                ForEach(rows) { FindingRow(f: $0) }
            }
        }
    }
}

// MARK: - DeFade 取证（可选）：粘贴 defade.org/developers 的免费 df_ 密钥；MCP 接口 https://api.defade.org/mcp
enum DeFadeKit {
    static var key: String {
        get { Cfg.defaults.string(forKey: "defadeKey") ?? "" }
        set { Cfg.defaults.set(newValue, forKey: "defadeKey") }
    }

    private static func post(_ url: URL, _ body: [String: Any], session: String?) async throws -> (String, String?) {
        var req = URLRequest(url: url, timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let s = session { req.setValue(s, forHTTPHeaderField: "Mcp-Session-Id") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let r = try await Net.fetch(req)
        let text = String(data: r.0, encoding: .utf8) ?? ""
        let sid = (r.1 as? HTTPURLResponse)?.value(forHTTPHeaderField: "Mcp-Session-Id")
        return (text, sid)
    }

    private static func payload(_ text: String) -> [String: Any]? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.hasPrefix("{") {
            let lines = raw.split(separator: "\n").map { String($0) }.filter { $0.hasPrefix("data:") }
            guard let l = lines.last else { return nil }
            raw = String(l.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        }
        guard let d = raw.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    static func run(tool: String, address: String, chain: String) async throws -> String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, let url = URL(string: "https://api.defade.org/mcp?api_key=" + k) else { return "还没有填 DeFade 密钥" }
        let ini: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-03-26", "capabilities": [String: Any](), "clientInfo": ["name": "TSTZ-M", "version": "1.0"]]]
        let (_, sid) = try await post(url, ini, session: nil)
        let note: [String: Any] = ["jsonrpc": "2.0", "method": "notifications/initialized"]
        _ = try? await post(url, note, session: sid)
        let call: [String: Any] = ["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": tool, "arguments": ["address": address, "chain": chain]]]
        let (text, _) = try await post(url, call, session: sid)
        guard let o = payload(text) else { return "DeFade 返回的不是 JSON：" + String(text.prefix(200)) }
        if let e = o["error"] as? [String: Any] { return "DeFade 报错：" + ((e["message"] as? String) ?? "未知") }
        if let r = o["result"] as? [String: Any], let c = r["content"] as? [[String: Any]] {
            let t = c.compactMap { $0["text"] as? String }.joined(separator: "\n")
            return t.isEmpty ? "DeFade 返回为空" : t
        }
        return String(text.prefix(1500))
    }
}

struct DeFadeCard: View {
    @ObservedObject var vm: UTokenVM
    @State private var key = DeFadeKit.key
    @State private var out = ""
    @State private var busy = ""

    private let tools: [(String, String)] = [("get_token_scan", "全面扫描"), ("get_whales", "庄家/大户"), ("get_wallet_links", "钱包关联"), ("get_smart_money", "聪明钱"), ("get_launch_bundles", "捆绑/狙击"), ("get_lookalike_clusters", "洗盘协同"), ("get_dev_tracker", "开发者")]

    private var chainName: String { vm.chain == .eth ? "ethereum" : vm.chain.rawValue }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("DeFade 取证（可选）", systemImage: "shield.lefthalf.filled").font(.headline)
                Text("DeFade 是开源 SDK + 托管 API：捆绑/狙击/发币者追踪/资金来源/聪明钱。到 defade.org/developers 领 df_ 密钥填在这里；Solana 可用免费档，EVM 链需其 All-Chains 套餐（付费，未填密钥时本功能不工作，不影响其它分析）。")
                    .font(.caption2).foregroundStyle(.secondary)
                SecureField("粘贴 df_ 密钥", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: key) { _, v in DeFadeKit.key = v }
                if !key.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(tools, id: \.0) { t in
                            Button { Task { await run(t) } } label: {
                                Text(busy == t.0 ? "查询中…" : t.1).font(.footnote.weight(.semibold)).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(!busy.isEmpty)
                        }
                    }
                }
                if !out.isEmpty {
                    Text(out).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
            }
        }
    }

    private func run(_ t: (String, String)) async {
        busy = t.0
        out = ""
        defer { busy = "" }
        do {
            let s = try await DeFadeKit.run(tool: t.0, address: vm.address, chain: chainName)
            out = t.1 + "：\n" + String(s.prefix(2500))
        } catch {
            out = "DeFade 查询失败：" + Net.message(error)
        }
    }
}
