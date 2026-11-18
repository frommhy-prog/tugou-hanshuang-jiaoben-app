import SwiftUI

// MARK: - 官方额度表：每一项都来自官方文档（source）；官方没公布具体次数的写「未公布」，不编数字
struct GMQuota: Identifiable {
    let id: String
    let name: String
    let brand: String?
    let perMin: Double?
    let perDay: Double?
    let perMonth: Double?
    let unit: String
    let source: String
    let note: String
}

enum GMQuotaCatalog {
    // 手机直连（本机统计真实发出的请求）
    static let phone: [GMQuota] = [
        GMQuota(id: "gecko", name: "GeckoTerminal", brand: "gecko", perMin: 30, perDay: nil, perMonth: nil, unit: "次", source: "https://apiguide.geckoterminal.com/faq", note: "免费公共接口：官方限每分钟 30 次，没有日 / 月上限（K 线、热门池子、成交都走它）"),
        GMQuota(id: "dexscreener", name: "Dexscreener", brand: "dexscreener", perMin: 300, perDay: nil, perMonth: nil, unit: "次", source: "https://docs.dexscreener.com/api/reference", note: "池子 / 代币 / 搜索接口每分钟 300 次；资料、置顶、广告、热门叙事接口每分钟 60 次；没有日 / 月上限"),
        GMQuota(id: "goplus", name: "GoPlus 合约安全", brand: "goplus", perMin: 150, perDay: 30_000, perMonth: 150_000, unit: "CU", source: "https://gopluslabs.io/security-api", note: "免费档：每月 15 万 CU、每日 3 万 CU、每分钟 150 CU；官网没列单次消耗，这里按每次 1 CU 估算"),
        GMQuota(id: "rugcheck", name: "RugCheck", brand: "rugcheck", perMin: nil, perDay: nil, perMonth: nil, unit: "次", source: "https://fluxbeam.gitbook.io/fluxrpc-docs/rugcheck-api/introduction", note: "官方未公布免费档的具体次数（免费档返回缓存报告并限频），只统计已用次数"),
        GMQuota(id: "jupiter", name: "Jupiter", brand: "jupiter", perMin: 30, perDay: nil, perMonth: nil, unit: "次", source: "https://developers.jup.ag/docs/portal/rate-limits", note: "无密钥 0.5 次/秒（每分钟 30 次），lite-api 将逐步下线；免费密钥 1 次/秒"),
        GMQuota(id: "coingecko", name: "CoinGecko（无密钥）", brand: nil, perMin: 10, perDay: nil, perMonth: nil, unit: "次", source: "https://docs.coingecko.com/docs/keyless-public-api", note: "无密钥公共池约 10–30 次/分钟且随负载浮动，这里按 10 次保守估算"),
        GMQuota(id: "gmgn", name: "GMGN", brand: "gmgn", perMin: 300, perDay: nil, perMonth: nil, unit: "权重点", source: "https://github.com/gmgnai/gmgn-skills", note: "免费档漏桶 5/5（速率/容量，每秒 5 个权重点），各接口权重 1–5；官方未公布日 / 月上限。这里按每次 1 点统计"),
        GMQuota(id: "okx", name: "OKX Web3 / Onchain OS", brand: "okx", perMin: 60, perDay: nil, perMonth: nil, unit: "次", source: "https://web3.okx.com/onchainos/dev-docs/home/api-fee", note: "试用档默认 1 次/秒（审核后可到 5 次/秒），试用期 60 天；官方未公布日 / 月上限"),
        GMQuota(id: "cf_workers", name: "Cloudflare Workers（手机→你的服务）", brand: nil, perMin: nil, perDay: 100_000, perMonth: nil, unit: "次", source: "https://developers.cloudflare.com/workers/platform/pricing/", note: "免费档每日 10 万次，UTC 0 点重置；引擎每次请求另占 1 次 Durable Objects 请求（同样每日 10 万）。这里只统计本机发出的部分"),
    ]

    // 服务端（你的引擎 Worker 调用上游的次数，由引擎记录）
    static let server: [GMQuota] = [
        GMQuota(id: "alchemy", name: "Alchemy（EVM 链上数据）", brand: nil, perMin: nil, perDay: nil, perMonth: 30_000_000, unit: "CU", source: "https://support.alchemy.com/articles/5827006872-what-is-included-in-the-free-tier", note: "免费档每月 3000 万 CU（约 25 次/秒）。CU 按官方各方法消耗表估算（如 eth_getLogs 60、eth_call 26），以 Alchemy 后台为准"),
        GMQuota(id: "helius", name: "Helius（Solana）", brand: nil, perMin: nil, perDay: nil, perMonth: 1_000_000, unit: "credits", source: "https://www.helius.dev/docs/billing/credits", note: "免费档每月 100 万 credits（10 次/秒，DAS 2 次/秒）。标准 RPC 1 credit、DAS 10 credits、Enhanced Transactions 每次 100 credits（钱包分析每翻一页就是 100），以 Helius 后台为准"),
        GMQuota(id: "groq", name: "Groq（AI 研判）", brand: nil, perMin: 30, perDay: nil, perMonth: nil, unit: "次", source: "https://console.groq.com/docs/rate-limits", note: "免费档每分钟 30 次，每日次数和令牌按模型不同（以响应头实测为准）"),
    ]

    static let serverNames: [String: String] = [
        "cerebras": "Cerebras（AI）", "gemini": "Gemini（AI）", "openrouter": "OpenRouter（AI）", "mistral": "Mistral（AI）",
        "dexscreener": "Dexscreener（服务端）", "geckoterminal": "GeckoTerminal（服务端）", "rugcheck": "RugCheck（服务端）",
        "goplus": "GoPlus（服务端）", "coingecko": "CoinGecko（服务端）", "jupiter": "Jupiter（服务端）", "dexpaprika": "DexPaprika（服务端）",
        "publicnode": "PublicNode RPC", "binance": "币安（服务端）", "okx": "欧易（服务端）", "gate": "Gate（服务端）", "pumpfun": "pump.fun（服务端）",
    ]
}

// MARK: - 本机计数（按 UTC 自然日，和 Cloudflare / Groq 的重置时间一致；线程安全）
final class GMUsage: @unchecked Sendable {
    static let shared = GMUsage()
    private let lock = NSLock()
    private var days: [String: [String: Int]] = [:]
    private var recent: [String: [Double]] = [:]
    private var scout: [String: Int] = [:]
    private var scoutDay: String = ""
    private var saving: Bool = false
    private static let key = "gmUsageV1"

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ d: Date = Date()) -> String { fmt.string(from: d) }

    private init() {
        if let d = Cfg.defaults.data(forKey: GMUsage.key), let v = try? JSONDecoder().decode([String: [String: Int]].self, from: d) { days = v }
    }

    // host -> 供应商 id（认不出的域名不计数）
    static func provider(host h0: String) -> String? {
        let h: String = h0.lowercased()
        if h == "api.geckoterminal.com" { return "gecko" }
        if h == "api.dexscreener.com" { return "dexscreener" }
        if h == "api.gopluslabs.io" { return "goplus" }
        if h == "api.rugcheck.xyz" { return "rugcheck" }
        if h.hasSuffix("jup.ag") { return "jupiter" }
        if h == "api.coingecko.com" { return "coingecko" }
        if h == "api.honeypot.is" { return "honeypot" }
        if h.hasSuffix("blockscout.com") { return "blockscout" }
        if h.hasSuffix("gmgn.ai") { return "gmgn" }
        if h.hasSuffix("okx.com") { return "okx" }
        if h.hasSuffix("workers.dev") { return "cf_workers" }
        return nil
    }

    func hit(_ prov: String, _ n: Int = 1) {
        let now: Double = Date().timeIntervalSince1970
        let dk: String = GMUsage.dayKey()
        lock.lock()
        days[dk, default: [:]][prov, default: 0] += n
        var r: [Double] = recent[prov] ?? []
        r.append(now)
        r.removeAll { now - $0 > 60 }
        recent[prov] = r
        let need: Bool = !saving
        saving = true
        lock.unlock()
        if need { DispatchQueue.global().asyncAfter(deadline: .now() + 5) { self.save() } }
    }

    private func save() {
        lock.lock()
        let keys: [String] = days.keys.sorted()
        if keys.count > 62 { for k in keys.prefix(keys.count - 62) { days.removeValue(forKey: k) } }
        let snap = days
        saving = false
        lock.unlock()
        if let d = try? JSONEncoder().encode(snap) { Cfg.defaults.set(d, forKey: GMUsage.key) }
    }

    func today(_ prov: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return days[GMUsage.dayKey()]?[prov] ?? 0
    }

    func month(_ prov: String) -> Int {
        let pre: String = String(GMUsage.dayKey().prefix(7))
        lock.lock()
        defer { lock.unlock() }
        var s: Int = 0
        for (k, v) in days where k.hasPrefix(pre) { s += v[prov] ?? 0 }
        return s
    }

    func lastMinute(_ prov: String) -> Int {
        let now: Double = Date().timeIntervalSince1970
        lock.lock()
        defer { lock.unlock() }
        return (recent[prov] ?? []).filter { now - $0 <= 60 }.count
    }

    // 本月出现过的供应商 id（表里没有的也会列出来）
    func seen() -> [String] {
        let pre: String = String(GMUsage.dayKey().prefix(7))
        lock.lock()
        defer { lock.unlock() }
        var out: Set<String> = []
        for (k, v) in days where k.hasPrefix(pre) { for p in v.keys { out.insert(p) } }
        return out.sorted()
    }

    // 今日雷达自己用掉的次数（有每日预算，不会把额度花完）
    func scoutHit(_ prov: String) {
        let dk: String = GMUsage.dayKey()
        lock.lock()
        if scoutDay != dk {
            scoutDay = dk
            scout = [:]
        }
        scout[prov, default: 0] += 1
        lock.unlock()
    }

    func scoutToday(_ prov: String) -> Int {
        let dk: String = GMUsage.dayKey()
        lock.lock()
        defer { lock.unlock() }
        return scoutDay == dk ? (scout[prov] ?? 0) : 0
    }

    func canScout(_ prov: String, daily: Int) -> Bool {
        return scoutToday(prov) < daily
    }

    // 最近 1 分钟没怎么用到限流额度，且雷达今日预算没花完 → 才算「API 空余」
    func hasHeadroom() -> Bool {
        if lastMinute("gecko") > 8 { return false }
        if lastMinute("dexscreener") > 100 { return false }
        if scoutToday("gecko") >= 400 { return false }
        return true
    }
}

// MARK: - 额度计算
struct GMQuotaState {
    var headline: String
    var lines: [String]
    var ratio: Double?
}

enum GMQuotaMath {
    static func fmt(_ v: Double) -> String {
        let a: Double = max(0, v)
        return a >= 10_000 ? CNUnit.short(a, 2) : String(format: "%.0f", a)
    }

    static func daysLeftInMonthUTC() -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        let now = Date()
        let total: Int = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let day: Int = cal.component(.day, from: now)
        return max(1, total - day + 1)
    }

    static func state(_ q: GMQuota, today: Double, month: Double, minute: Int?) -> GMQuotaState {
        var lines: [String] = []
        lines.append("今日已用 " + fmt(today) + " " + q.unit + " · 本月已用 " + fmt(month) + " " + q.unit)
        var head: String = "仅统计已用"
        var ratio: Double? = nil
        if let d = q.perDay {
            head = "今日剩余 " + fmt(d - today)
            ratio = d > 0 ? today / d : nil
            lines.append("每日上限 " + fmt(d) + "（UTC 0 点 = 北京时间 8:00 重置）")
        }
        if let m = q.perMonth {
            let rem: Double = max(0, m - month)
            if q.perDay == nil {
                head = "本月剩余 " + fmt(rem)
                ratio = m > 0 ? month / m : nil
            }
            let left: Double = Double(daysLeftInMonthUTC())
            lines.append("每月上限 " + fmt(m) + "，本月剩余 " + fmt(rem) + "，折合每天约 " + fmt(rem / left))
        }
        if let p = q.perMin {
            var s: String = "每分钟上限 " + fmt(p)
            if let mu = minute { s += "，近 60 秒已用 " + String(mu) }
            lines.append(s)
            if q.perDay == nil && q.perMonth == nil {
                head = "不设日 / 月上限"
                if let mu = minute {
                    ratio = p > 0 ? Double(mu) / p : nil
                    head = "本分钟剩 " + fmt(p - Double(mu)) + " / " + fmt(p)
                }
            }
        }
        if q.perDay == nil && q.perMonth == nil && q.perMin == nil { lines.append("官方未公布具体次数，只统计已用") }
        return GMQuotaState(headline: head, lines: lines, ratio: ratio)
    }
}

// MARK: - 服务端用量（引擎 /e/usage）
struct GMServerUsage: Decodable {
    struct Row: Decodable {
        var provider: String
        var calls: Double?
        var units: Double?
    }
    struct GroqU: Decodable {
        var hdr: [String: JV]?
        var at: Double?
    }
    var day: String?
    var today: [Row]?
    var month: [Row]?
    var groq: GroqU?
}

@MainActor
final class GMUsageVM: ObservableObject {
    @Published var server: GMServerUsage?
    @Published var err: String?
    @Published var loading: Bool = false

    func load() async {
        loading = true
        defer { loading = false }
        do {
            let s: GMServerUsage = try await Engine.get("/e/usage")
            server = s
            err = nil
        } catch {
            err = error.localizedDescription
        }
    }

    // CU / credits 类取估算消耗，其余取次数
    func use(_ id: String, today: Bool) -> Double {
        let rows: [GMServerUsage.Row] = (today ? server?.today : server?.month) ?? []
        guard let r = rows.first(where: { $0.provider == id }) else { return 0 }
        if id == "alchemy" || id == "helius" { return r.units ?? 0 }
        return r.calls ?? 0
    }

    func ids() -> [String] {
        var s: Set<String> = []
        for r in (server?.today ?? []) { s.insert(r.provider) }
        for r in (server?.month ?? []) { s.insert(r.provider) }
        return s.sorted()
    }
}

// MARK: - API 用量控制台
struct GMUsageView: View {
    @StateObject private var vm = GMUsageVM()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 4)) { _ in
            List {
                Section {
                    Text("按 UTC 自然日 / 自然月统计（北京时间每天 8:00 换日）。「已用」是真实发出的请求，命中缓存、合并的重复请求不算。额度来自各家官方文档，点「官方文档」可核对；官方没公布的我们不编数字。").font(.caption).foregroundStyle(.secondary)
                }
                Section("手机直连（本机统计）") {
                    ForEach(GMQuotaCatalog.phone) { q in
                        row(q, today: Double(GMUsage.shared.today(q.id)), month: Double(GMUsage.shared.month(q.id)), minute: GMUsage.shared.lastMinute(q.id), extra: [])
                    }
                    ForEach(phoneExtras(), id: \.self) { id in
                        row(extraQuota(id, GMQuotaCatalog.serverNames[id] ?? id), today: Double(GMUsage.shared.today(id)), month: Double(GMUsage.shared.month(id)), minute: GMUsage.shared.lastMinute(id), extra: [])
                    }
                }
                serverSection
                Section("今日雷达自动扫描预算（用完就停，不会把额度花完）") {
                    Text(budgetText()).font(.footnote.monospacedDigit())
                }
                Section {
                    NavigationLink("API 密钥与额度（Groq 实测、绑定密钥）") { KeysView() }
                }
            }
            .refreshable { await vm.load() }
        }
        .navigationTitle("API 用量控制台")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }

    private func phoneExtras() -> [String] {
        let known: Set<String> = Set(GMQuotaCatalog.phone.map { $0.id })
        return GMUsage.shared.seen().filter { !known.contains($0) }
    }

    private func extraQuota(_ id: String, _ name: String) -> GMQuota {
        return GMQuota(id: id, name: name, brand: nil, perMin: nil, perDay: nil, perMonth: nil, unit: "次", source: "", note: "没有查到官方公开的具体次数，只统计已用")
    }

    private func budgetText() -> String {
        let g: Int = GMUsage.shared.scoutToday("gecko")
        let d: Int = GMUsage.shared.scoutToday("dexscreener")
        let p: Int = GMUsage.shared.scoutToday("goplus")
        let r: Int = GMUsage.shared.scoutToday("rugcheck")
        return "GeckoTerminal " + String(g) + " / 400 · Dexscreener " + String(d) + " / 600 · GoPlus " + String(p) + " / 120 · RugCheck " + String(r) + " / 120"
    }

    @ViewBuilder
    private var serverSection: some View {
        Section("你的 Worker 服务端（引擎记录；Alchemy / Helius 按官方价目估算）") {
            if let e = vm.err {
                Text(e + "（引擎刚更新过的话要等第一次请求后才有数据）").font(.footnote).foregroundStyle(Color.orange)
            }
            ForEach(GMQuotaCatalog.server) { q in
                row(q, today: vm.use(q.id, today: true), month: vm.use(q.id, today: false), minute: nil, extra: groqExtra(q.id))
            }
            ForEach(serverExtras(), id: \.self) { id in
                row(extraQuota(id, GMQuotaCatalog.serverNames[id] ?? id), today: vm.use(id, today: true), month: vm.use(id, today: false), minute: nil, extra: [])
            }
        }
    }

    private func serverExtras() -> [String] {
        let known: Set<String> = Set(GMQuotaCatalog.server.map { $0.id })
        return vm.ids().filter { !known.contains($0) }
    }

    private func groqExtra(_ id: String) -> [String] {
        guard id == "groq", let h = vm.server?.groq?.hdr else { return [] }
        var out: [String] = []
        let rem: String = h["x-ratelimit-remaining-requests"]?.text ?? ""
        let lim: String = h["x-ratelimit-limit-requests"]?.text ?? ""
        if !rem.isEmpty { out.append("实测今日剩余请求 " + rem + (lim.isEmpty ? "" : " / " + lim) + "（来自 Groq 响应头）") }
        let tr: String = h["x-ratelimit-remaining-tokens"]?.text ?? ""
        if !tr.isEmpty { out.append("本分钟剩余令牌 " + tr) }
        return out
    }

    private func row(_ q: GMQuota, today: Double, month: Double, minute: Int?, extra: [String]) -> some View {
        let st: GMQuotaState = GMQuotaMath.state(q, today: today, month: month, minute: minute)
        let hot: Bool = (st.ratio ?? 0) > 0.8
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if let b = q.brand { GMBrandIcon(key: b, size: 18) }
                Text(q.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(st.headline).font(.footnote.weight(.bold).monospacedDigit()).foregroundStyle(hot ? Color.orange : Color.primary)
            }
            if let r = st.ratio { ProgressView(value: min(1, max(0, r))).tint(hot ? Color.orange : Color.accentColor) }
            ForEach(st.lines, id: \.self) { l in Text(l).font(.caption).foregroundStyle(.secondary) }
            ForEach(extra, id: \.self) { l in Text(l).font(.caption).foregroundStyle(Color.green) }
            Text(q.note).font(.caption2).foregroundStyle(.secondary)
            if let u = URL(string: q.source), !q.source.isEmpty {
                Link("官方文档", destination: u).font(.caption2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct GMUsageLink: View {
    var body: some View {
        NavigationLink {
            GMUsageView()
        } label: {
            Card {
                HStack {
                    Label("API 用量控制台：今日剩余 / 本月已用", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.subheadline)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
