import SwiftUI

// MARK: - 代币叙事：这个币讲什么故事 + 同类叙事代币现状（只用真实资料与真实搜索结果，资料不足就写「信息不足」）
struct NarrAnalysis: Codable {
    var narrative: String?
    var themes: [String]?
    var keywords: [String]?
    var evidence: [String]?
    var risks: [String]?
    var unknown: [String]?
    var confidence: String?
}

struct NarrResult: Codable {
    var analysis: NarrAnalysis?
    var model: String?
    var cached: Bool?
    var error: String?
    var detail: String?
}

struct NarrPayload: Encodable {
    var name: String
    var symbol: String
    var chain: String
    var description: String
    var categories: [String]
    var socials: [String]
    var websites: [String]
    var fresh: Bool?
}

struct SimilarToken: Identifiable {
    let id: String
    let sym: String
    let name: String
    let chain: String
    let liq: Double
    let mc: Double?
    let vol24: Double?
    let change24: Double?
    let ageDays: Double?
    var status: String { liq < 1_000 ? "基本归零" : (liq < 20_000 ? "衰退/低迷" : "仍有流动性") }
    var statusColor: Color { liq < 1_000 ? Color.red : (liq < 20_000 ? Color.orange : Color.green) }
}

@MainActor
final class NarrativeVM: ObservableObject {
    @Published var desc = ""
    @Published var categories: [String] = []
    @Published var result: NarrAnalysis?
    @Published var similar: [SimilarToken] = []
    @Published var loading = false
    @Published var note: String?
    @Published var simNote: String?
    private var key = ""

    func load(chain: Chain, address: String, main: DexPair?) async {
        let k = chain.rawValue + address.lowercased()
        if k == key && result != nil { return }
        key = k
        loading = true
        note = nil
        simNote = nil
        result = nil
        similar = []
        defer { loading = false }
        // 1. 公开简介（GeckoTerminal 代币信息）
        var description = ""
        var cats: [String] = []
        var socials: [String] = []
        var webs: [String] = []
        if let o = try? await MarketAPI.json("https://api.geckoterminal.com/api/v2/networks/\(chain.geckoId)/tokens/\(address)/info"),
           let a = ((o as? [String: Any])?["data"] as? [String: Any])?["attributes"] as? [String: Any] {
            description = (a["description"] as? String) ?? ""
            cats = (a["categories"] as? [String]) ?? []
            if let t = a["twitter_handle"] as? String, !t.isEmpty { socials.append("https://x.com/" + t) }
            if let t = a["telegram_handle"] as? String, !t.isEmpty { socials.append("https://t.me/" + t) }
            webs = (a["websites"] as? [String]) ?? []
        }
        for s in main?.info?.socials ?? [] { if let u = s.url { socials.append(u) } }
        for w in main?.info?.websites ?? [] { if let u = w.url { webs.append(u) } }
        desc = description
        categories = cats
        // 2. 叙事归纳（只依据上面的资料，资料太少会如实说信息不足）
        let payload = NarrPayload(name: main?.baseToken?.name ?? "", symbol: main?.baseToken?.symbol ?? "", chain: chain.title, description: description, categories: cats, socials: Array(Set(socials)), websites: Array(Set(webs)), fresh: nil)
        var words: [String] = []
        do {
            let r: NarrResult = try await Engine.post("/e/v2/narrative", payload)
            if let e = r.error {
                note = e == "no_groq_key" ? "未绑定 Groq 密钥，无法归纳叙事" : "叙事归纳暂时不可用（" + e + "）"
            } else {
                result = r.analysis
                words = r.analysis?.keywords ?? []
            }
        } catch {
            note = "叙事归纳暂时不可用（" + Net.message(error) + "）"
        }
        // 3. 同类叙事代币：用名称和关键词在 Dexscreener 搜索，统计它们现在的状态
        var qs: [String] = []
        let nm = main?.baseToken?.name ?? ""
        let sym = main?.baseToken?.symbol ?? ""
        for w in words + [nm] + (sym.count >= 4 ? [sym] : []) {
            let t = w.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count >= 3 && !qs.contains(where: { $0.lowercased() == t.lowercased() }) { qs.append(t) }
        }
        await findSimilar(qs: Array(qs.prefix(3)), selfAddr: address)
    }

    private func findSimilar(qs: [String], selfAddr: String) async {
        if qs.isEmpty { simNote = "没有可用于搜索同类代币的关键词"; return }
        var seen = Set<String>()
        var out: [SimilarToken] = []
        for q in qs {
            guard let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let o = try? await MarketAPI.json("https://api.dexscreener.com/latest/dex/search?q=" + enc), let pairs = (o as? [String: Any])?["pairs"] as? [[String: Any]] else { continue }
            let ql = q.lowercased()
            for p in pairs {
                guard let b = p["baseToken"] as? [String: Any], let addr = b["address"] as? String, addr.lowercased() != selfAddr.lowercased() else { continue }
                let n = (b["name"] as? String) ?? ""
                let s = (b["symbol"] as? String) ?? ""
                if !(n.lowercased().contains(ql) || s.lowercased().contains(ql)) { continue }
                let cid = (p["chainId"] as? String) ?? ""
                let key = cid + addr.lowercased()
                if seen.contains(key) { continue }
                let liq = (((p["liquidity"] as? [String: Any])?["usd"]) as? NSNumber)?.doubleValue ?? 0
                let mc = ((p["marketCap"] as? NSNumber) ?? (p["fdv"] as? NSNumber))?.doubleValue
                let vol = (((p["volume"] as? [String: Any])?["h24"]) as? NSNumber)?.doubleValue
                let ch = (((p["priceChange"] as? [String: Any])?["h24"]) as? NSNumber)?.doubleValue
                var age: Double?
                if let c = (p["pairCreatedAt"] as? NSNumber)?.doubleValue { age = (Date().timeIntervalSince1970 * 1000 - c) / 86_400_000 }
                seen.insert(key)
                out.append(SimilarToken(id: key, sym: s, name: n, chain: Chain.fromDex(cid)?.title ?? cid, liq: liq, mc: mc, vol24: vol, change24: ch, ageDays: age))
            }
        }
        similar = Array(out.sorted { $0.liq > $1.liq }.prefix(14))
        if similar.isEmpty { simNote = "没有搜到名称或关键词相同的代币" }
    }
}

struct NarrativeCard: View {
    let chain: Chain
    let address: String
    let main: DexPair?
    @StateObject private var vm = NarrativeVM()

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("代币叙事", systemImage: "text.book.closed").font(.headline)
                    Spacer()
                    if vm.loading { ProgressView() }
                }
                if let n = vm.result {
                    HStack(alignment: .top, spacing: 8) {
                        if let c = n.confidence, !c.isEmpty { Pill(text: "把握 " + c, color: c == "高" ? Color.green : (c == "中" ? Color.orange : Color.gray)) }
                        Text(n.narrative ?? "信息不足").font(.subheadline.weight(.semibold))
                    }
                    if let t = n.themes, !t.isEmpty {
                        HStack(spacing: 6) { ForEach(t, id: \.self) { Pill(text: $0, color: Color.indigo) } }
                    }
                    ForEach(Array((n.evidence ?? []).enumerated()), id: \.offset) { _, e in
                        Text("依据：" + e).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let r = n.risks, !r.isEmpty {
                        Text("叙事层面的风险").font(.caption.weight(.semibold)).foregroundStyle(Color.orange)
                        ForEach(Array(r.enumerated()), id: \.offset) { _, s in Text("· " + s).font(.footnote) }
                    }
                    if let u = n.unknown, !u.isEmpty {
                        Text("资料里没有、无法判断").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(u.enumerated()), id: \.offset) { _, s in Text("· " + s).font(.caption2).foregroundStyle(.secondary) }
                    }
                    if vm.desc.isEmpty { Text("公开资料里没有这个币的简介，叙事只能依据名称与社交链接推断，参考价值有限。").font(.caption2).foregroundStyle(.secondary) }
                } else if let n = vm.note {
                    Text(n).font(.footnote).foregroundStyle(.secondary)
                } else if vm.loading {
                    Text("读取公开资料并归纳…").font(.footnote).foregroundStyle(.secondary)
                } else if !AIMode.auto {
                    Button { Task { await vm.load(chain: chain, address: address, main: main) } } label: { Label("生成叙事与同类对比（手动）", systemImage: "sparkles") }.buttonStyle(.bordered)
                }
                Divider()
                Text("历史相似叙事：同名/同主题代币现在怎么样").font(.subheadline.weight(.semibold))
                if vm.similar.isEmpty {
                    Text(vm.simNote ?? (vm.loading ? "搜索中…" : "暂无")).font(.footnote).foregroundStyle(.secondary)
                } else {
                    summary
                    ForEach(vm.similar.prefix(8)) { s in row(s) }
                    Text("只统计 Dexscreener 当前还能搜到的代币，已下架或被清理的看不到，所以存活比例会被高估；这里没有历史最高价，不能据此推算峰值收益。").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: chain.rawValue + address) { if AIMode.auto { await vm.load(chain: chain, address: address, main: main) } }
    }

    private var summary: some View {
        let n = vm.similar.count
        let dead = vm.similar.filter { $0.liq < 1_000 }.count
        let alive = vm.similar.filter { $0.liq >= 20_000 }.count
        let ages = vm.similar.compactMap { $0.ageDays }.sorted()
        let med = ages.isEmpty ? nil : ages[ages.count / 2]
        let tail = med.map { String(format: "，池龄中位数 %.0f 天", $0) } ?? ""
        return Text("找到 \(n) 个相似代币：\(dead) 个流动性低于 $1,000（基本归零），\(alive) 个仍有 $20,000 以上流动性" + tail)
            .font(.footnote)
    }

    private func row(_ s: SimilarToken) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(s.sym).font(.subheadline.weight(.semibold))
                    Pill(text: s.chain, color: Color.blue)
                }
                Text(s.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("流动性 " + Fmt2.usd(s.liq)).font(.caption.monospacedDigit())
                HStack(spacing: 6) {
                    if let a = s.ageDays { Text(a < 2 ? String(format: "%.0f 小时", a * 24) : String(format: "%.0f 天", a)).font(.caption2).foregroundStyle(.secondary) }
                    Pill(text: s.status, color: s.statusColor)
                }
            }
        }
    }
}
