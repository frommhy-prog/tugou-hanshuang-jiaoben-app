import SwiftUI

// 叙事分析（规则引擎，不依赖 AI）：这个币讲什么故事 → 同类叙事有哪些币 → 叙事级别 → 热度。
// 数据全部来自公开接口（GeckoTerminal 简介 + Dexscreener 搜索），样本有限，缺什么就说缺什么，不编造「社交热度」。
struct NarrTheme {
    let title: String
    let words: [String]
    let terms: [String]
}

struct NarrHit: Identifiable {
    let id = UUID()
    var title: String
    var words: [String]
    var terms: [String]
}

struct SimTok: Identifiable {
    var id: String
    var sym: String
    var name: String
    var chainId: String
    var address: String
    var mc: Double
    var liq: Double
    var vol: Double
    var ch24: Double?
    var created: Double?
    var buys: Int
    var sells: Int
}

struct NarrReport {
    var hits: [NarrHit]
    var keywords: [String]
    var summary: String
    var level: String
    var levelBasis: String
    var position: String
    var positionBasis: String
    var heat: String
    var heatBasis: String
    var heatItems: [[String]]
    var similar: [SimTok]
    var notes: [String]
    var at: Date
}

enum NarrLex {
    static let themes: [NarrTheme] = [
        NarrTheme(title: "狗币 / 柴犬", words: ["dog", "doge", "inu", "shib", "puppy", "wif", "bonk", "woof", "hound", "pup", "shiba", "pooch"], terms: ["dog", "doge", "inu"]),
        NarrTheme(title: "猫咪", words: ["cat", "kitty", "kitten", "meow", "popcat", "neko", "mog", "nyan", "purr"], terms: ["cat", "meow"]),
        NarrTheme(title: "青蛙 / Pepe", words: ["pepe", "frog", "kek", "toad", "ribbit"], terms: ["pepe", "frog"]),
        NarrTheme(title: "AI / 智能体", words: ["ai", "agent", "gpt", "bot", "neural", "llm", "agi", "grok", "deepseek", "openai", "virtual", "robot"], terms: ["ai", "agent"]),
        NarrTheme(title: "政治 / 名人", words: ["trump", "maga", "elon", "musk", "biden", "harris", "melania", "vance", "kamala", "putin", "obama", "kanye", "snoop", "drake"], terms: ["trump", "elon"]),
        NarrTheme(title: "二次元 / 动漫", words: ["anime", "waifu", "senpai", "kawaii", "chan", "sama", "naruto", "pokemon", "manga", "otaku"], terms: ["anime", "waifu"]),
        NarrTheme(title: "食物", words: ["pizza", "burger", "taco", "sushi", "banana", "cheese", "coffee", "beer", "noodle", "cookie", "egg", "bread", "chicken"], terms: ["pizza", "burger"]),
        NarrTheme(title: "宗教 / 神话", words: ["god", "jesus", "allah", "buddha", "zeus", "thor", "satan", "angel", "devil", "holy", "pray"], terms: ["god", "jesus"]),
        NarrTheme(title: "太空 / 外星", words: ["moon", "mars", "space", "rocket", "alien", "ufo", "galaxy", "cosmic", "saturn"], terms: ["moon", "alien"]),
        NarrTheme(title: "猿猴 / 熊牛", words: ["ape", "monkey", "gorilla", "bear", "bull", "chimp", "kong", "banana"], terms: ["ape", "monkey"]),
        NarrTheme(title: "海洋 / 动物园", words: ["whale", "fish", "shark", "dolphin", "penguin", "duck", "goose", "hippo", "panda", "turtle", "squid", "octopus"], terms: ["whale", "penguin"]),
        NarrTheme(title: "游戏 / NFT", words: ["game", "play", "pixel", "arcade", "gamer", "nft", "quest", "level"], terms: ["game", "pixel"]),
        NarrTheme(title: "金融 / 实用", words: ["defi", "swap", "rwa", "dao", "vault", "staking", "yield", "bank", "finance", "protocol"], terms: ["defi", "rwa"]),
        NarrTheme(title: "财富 / 暴富", words: ["rich", "money", "cash", "gold", "dollar", "billion", "million", "bucks", "wealth", "lambo"], terms: ["rich", "lambo"]),
        NarrTheme(title: "Degen 文化", words: ["degen", "gm", "wagmi", "ngmi", "based", "chad", "wen", "lfg", "bro", "fomo", "higher", "pump", "send"], terms: ["degen", "based"]),
    ]

    static let stop: Set<String> = ["the", "of", "and", "coin", "token", "on", "in", "to", "a", "for", "by", "is", "it", "sol", "solana", "base", "bsc", "eth", "usd", "usdt", "official", "protocol", "finance", "network", "fun"]

    static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { String($0) }
    }

    // 短词（≤3 个字符）必须整词相等；长词允许包含（dogwifhat 命中 dog、wif）
    static func hit(_ w: String, _ lex: String) -> Bool {
        if lex.count <= 3 { return w == lex }
        return w == lex || w.contains(lex)
    }

    static func match(_ ws: [String]) -> [NarrHit] {
        var out: [NarrHit] = []
        for t in themes {
            var found: [String] = []
            for w in ws {
                for l in t.words where hit(w, l) {
                    if !found.contains(l) { found.append(l) }
                }
            }
            if !found.isEmpty { out.append(NarrHit(title: t.title, words: found, terms: t.terms)) }
        }
        out.sort { $0.words.count > $1.words.count }
        return out
    }
}

enum NarrEngine {
    static func search(_ q: String) async -> [DexPair] {
        guard let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        guard let d = await SocialEngine.get("https://api.dexscreener.com/latest/dex/search?q=" + enc) else { return [] }
        struct Resp: Decodable { var pairs: [DexPair]? }
        return (try? JSONDecoder().decode(Resp.self, from: d))?.pairs ?? []
    }

    static func tok(_ p: DexPair) -> SimTok? {
        guard let b = p.baseToken, let a = b.address, !a.isEmpty else { return nil }
        let mc = p.marketCap ?? p.fdv ?? 0
        let tx = p.txns?["h24"]
        return SimTok(id: (p.chainId ?? "") + ":" + a, sym: b.symbol ?? "?", name: b.name ?? "", chainId: p.chainId ?? "", address: a, mc: mc, liq: p.liq, vol: p.volume?["h24"] ?? 0, ch24: p.priceChange?["h24"], created: p.pairCreatedAt, buys: tx?.buys ?? 0, sells: tx?.sells ?? 0)
    }

    static func med(_ a: [Double]) -> Double? {
        if a.isEmpty { return nil }
        let s = a.sorted()
        let m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }

    static func run(pair: DexPair, chain: Chain, address: String) async -> NarrReport {
        var notes: [String] = []
        let sym = pair.baseToken?.symbol ?? ""
        let name = pair.baseToken?.name ?? ""
        var desc = ""
        if let d = await SocialEngine.get(cat("https://api.geckoterminal.com/api/v2/networks/", chain.geckoId, "/tokens/", address, "/info")), let j = try? JSONDecoder().decode(JV.self, from: d), let a = j.at("data")?.at("attributes") {
            desc = a.at("description")?.text ?? ""
        }
        if desc.isEmpty { notes.append("没有取到项目简介（GeckoTerminal 无记录），只能依据名称和符号判断叙事") }

        let ws = NarrLex.words(cat(name, " ", sym, " ", desc))
        let hits = NarrLex.match(ws)
        var keys: [String] = []
        for w in NarrLex.words(cat(sym, " ", name)) where w.count >= 3 && !NarrLex.stop.contains(w) && !keys.contains(w) { keys.append(w) }
        keys = Array(keys.prefix(3))

        // 搜索词：符号 / 名称关键词 / 主题词
        var terms: [String] = []
        for k in keys where !terms.contains(k) { terms.append(k) }
        if let h = hits.first { for t in h.terms where !terms.contains(t) { terms.append(t) } }
        terms = Array(terms.prefix(4))

        var seen: [String: SimTok] = [:]
        let me = (pair.chainId ?? "") + ":" + address
        for t in terms {
            for p in await search(t) {
                guard let s = tok(p), s.liq >= 1_000 else { continue }
                let b = (s.sym + " " + s.name).lowercased()
                if !b.contains(t.lowercased()) { continue }
                if let old = seen[s.id], old.liq >= s.liq { continue }
                seen[s.id] = s
            }
        }
        var others: [SimTok] = []
        for (k, v) in seen where k.lowercased() != me.lowercased() { others.append(v) }
        others.sort { $0.mc > $1.mc }
        let top = Array(others.prefix(12))
        if top.isEmpty { notes.append("Dexscreener 没搜到同名/同主题的其它代币（样本为空，不代表没有）") }

        // 本币
        let myMc = pair.marketCap ?? pair.fdv ?? 0
        let myTx = pair.txns?["h24"]
        let myTok = SimTok(id: me, sym: sym, name: name, chainId: pair.chainId ?? "", address: address, mc: myMc, liq: pair.liq, vol: pair.volume?["h24"] ?? 0, ch24: pair.priceChange?["h24"], created: pair.pairCreatedAt, buys: myTx?.buys ?? 0, sells: myTx?.sells ?? 0)
        var group = others
        group.append(myTok)

        // 级别：叙事规模 + 本币定位
        var groupMc = 0.0
        for g in group { groupMc += g.mc }
        var level = "样本太少，无法判断"
        if group.count >= 3 {
            if groupMc >= 500_000_000 { level = "大叙事" }
            else if groupMc >= 50_000_000 { level = "中型叙事" }
            else if groupMc >= 5_000_000 { level = "小叙事" }
            else { level = "微型 / 刚起步" }
        }
        let levelBasis = cat("已搜到的 ", String(group.count), " 个同类代币市值合计 ", Fmt2.usd(groupMc), "（样本最多每个关键词 30 个池子，实际总规模可能更大）")

        var position = "无法定位"
        var positionBasis = "同类代币太少"
        if !others.isEmpty && myMc > 0 {
            let ranked = group.sorted { $0.mc > $1.mc }
            let rank = (ranked.firstIndex(where: { $0.id == me }) ?? 0) + 1
            let leader = ranked[0]
            let share = leader.mc > 0 ? myMc / leader.mc : 0
            if rank == 1 { position = "龙头（市值第 1）" }
            else if share >= 0.3 { position = "二线（约龙头的 " + String(format: "%.0f%%", share * 100) + "）" }
            else if share >= 0.05 { position = "跟风（约龙头的 " + String(format: "%.0f%%", share * 100) + "）" }
            else { position = "边缘 / 尾部（不到龙头的 5%）" }
            let older = group.filter { ($0.created ?? 0) > 0 && ($0.created ?? 0) < (myTok.created ?? 0) }.count
            let order = older == 0 ? "是已搜到代币里最早建池的" : cat("比它早建池的有 ", String(older), " 个")
            positionBasis = cat("市值排 ", String(rank), " / ", String(group.count), "；龙头 ", leader.sym, " ", Fmt2.usd(leader.mc), "；", order)
            if older >= 1 && rank > 1 { position += " · 后发" }
            if older == 0 { position += " · 先发" }
        }

        // 热度：全部来自样本的真实数据
        let now = Date().timeIntervalSince1970 * 1000
        let new24 = group.filter { ($0.created ?? 0) > 0 && now - ($0.created ?? 0) < 86_400_000 }.count
        let new7 = group.filter { ($0.created ?? 0) > 0 && now - ($0.created ?? 0) < 7 * 86_400_000 }.count
        var vol = 0.0
        var bu = 0
        var se = 0
        for g in group { vol += g.vol; bu += g.buys; se += g.sells }
        let chs = group.compactMap { $0.ch24 }
        let mch = med(chs)
        var items: [[String]] = []
        items.append(["同类代币 24h 成交额合计", Fmt2.usd(vol)])
        items.append(["近 24 小时新建同类池子", cat(String(new24), " 个（7 天内 ", String(new7), " 个）")])
        if let m = mch { items.append(["同类 24h 涨跌中位数", String(format: "%+.1f%%", m)]) }
        if vol > 0 { items.append(["本币占同类成交额", String(format: "%.0f%%", (myTok.vol / vol) * 100)]) }
        if bu + se > 0 { items.append(["同类 24h 买/卖笔数", cat(String(bu), " / ", String(se))]) }
        var heat = "平稳"
        if group.count < 3 { heat = "样本太少，无法判断" }
        else if new24 >= 5 && (mch ?? 0) > 0 { heat = "升温（有人在批量跟风，价格也在涨）" }
        else if new24 >= 5 { heat = "跟风多但价格走弱（容易是尾声）" }
        else if new24 == 0 && vol < 100_000 { heat = "冷（近一天没人新发，成交也很少）" }
        else if (mch ?? 0) <= -20 { heat = "退潮（同类普遍下跌）" }
        let heatBasis = cat("社交热度（推特/电报讨论量）没有免费公开数据，这里只统计链上交易数据，不编造")

        var summary = ""
        if let h = hits.first {
            summary = cat("叙事：", h.title, "（命中词：", h.words.prefix(4).joined(separator: "、"), "）")
            if hits.count > 1 { summary += cat("；同时沾边：", hits.dropFirst().prefix(2).map { $0.title }.joined(separator: "、")) }
        } else {
            summary = cat("没有命中已知主题词；名称关键词：", keys.isEmpty ? "无" : keys.joined(separator: "、"), "。可能是新造梗或纯名字币")
        }
        return NarrReport(hits: hits, keywords: keys, summary: summary, level: level, levelBasis: levelBasis, position: position, positionBasis: positionBasis, heat: heat, heatBasis: heatBasis, heatItems: items, similar: top, notes: notes, at: Date())
    }
}

struct NarrativeRulesCard: View {
    @ObservedObject var vm: UTokenVM
    @State private var report: NarrReport?
    @State private var loading = false
    private static var store: [String: NarrReport] = [:]

    private var key: String { cat(vm.chain.rawValue, ":", vm.address) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("叙事分析", systemImage: "text.book.closed").font(.headline)
                    Text("不依赖 AI").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(Color.blue.opacity(0.14), in: Capsule()).foregroundStyle(Color.blue)
                    Spacer()
                    Button("刷新") { Task { await load(force: true) } }.font(.caption)
                }
                if loading { HStack(spacing: 8) { ProgressView(); Text("搜索同类叙事代币…").font(.footnote).foregroundStyle(.secondary) } }
                if let r = report {
                    Text(r.summary).font(.subheadline.weight(.semibold))
                    row("叙事级别", r.level, r.levelBasis)
                    row("本币定位", r.position, r.positionBasis)
                    row("热度", r.heat, r.heatBasis)
                    ForEach(r.heatItems, id: \.self) { it in
                        HStack { Text(it[0]).font(.caption).foregroundStyle(.secondary); Spacer(); Text(it[1]).font(.caption.weight(.semibold)) }
                    }
                    if !r.similar.isEmpty {
                        Text("相似叙事代币（点一下切过去查）").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                        ForEach(r.similar) { s in
                            Button { vm.start(s.address) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(s.sym).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                                        Text(cat(s.chainId, " · ", s.created.map { Fmt2.dur(Date().timeIntervalSince1970 - $0 / 1000) } ?? "池龄未知")).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(s.mc > 0 ? Fmt2.usd(s.mc) : "市值未知").font(.footnote.monospacedDigit()).foregroundStyle(Color.primary)
                                        if let c = s.ch24 { Text(String(format: "%+.1f%%", c)).font(.caption2).foregroundStyle(c >= 0 ? Color.green : Color.red) }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ForEach(r.notes, id: \.self) { n in Text(cat("· ", n)).font(.caption2).foregroundStyle(.secondary) }
                    Text(cat("计算于 ", r.at.formatted(date: .omitted, time: .standard), " · 主题词库是内置规则，AI 研判里的叙事是另一条独立轨道")).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: key) { await load(force: false) }
    }

    private func row(_ t: String, _ v: String, _ basis: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top) {
                Text(t).font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                Text(v).font(.subheadline.weight(.semibold))
            }
            Text(cat("依据：", basis)).font(.caption2).foregroundStyle(.secondary).padding(.leading, 70)
        }
    }

    private func load(force: Bool) async {
        guard let p = vm.main, !vm.address.isEmpty else { return }
        if !force, let c = Self.store[key] { report = c; return }
        loading = true
        let r = await NarrEngine.run(pair: p, chain: vm.chain, address: vm.address)
        Self.store[key] = r
        report = r
        loading = false
    }
}
