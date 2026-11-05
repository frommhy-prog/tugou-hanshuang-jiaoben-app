import SwiftUI

// 土狗全生命周期 + 社交与官方信息。全部是规则计算 + 公开数据，缺什么就标「未知」，不拿假数凑。

// MARK: - 生命周期（发射 → 拉升 → 顶部 → 回落 → 现状）
struct LifePhase: Identifiable {
    let id = UUID()
    var title: String
    var text: String
    var basis: String
    var level: String
}

struct LifeReport {
    var phases: [LifePhase]
    var stage: String
    var stageBasis: String
    var n: Int
    var tfTitle: String
}

enum LifeEngine {
    static func analyze(_ cs: [Candle], tf: TF, createdMs: Double?, liq: Double) -> LifeReport? {
        guard cs.count >= 5, let first = cs.first, let last = cs.last else { return nil }
        let sec = tf.sec
        let p0: Double = first.o > 0 ? first.o : first.c
        guard p0 > 0, let ath = cs.max(by: { $0.h < $1.h }) else { return nil }
        let perDay = max(1, Int(86_400 / sec))
        var total = 0.0
        for c in cs { total += c.v }
        var day1 = 0.0
        for c in cs.prefix(perDay) { day1 += c.v }
        var peak24 = 0.0
        var run = 0.0
        for i in 0..<cs.count {
            run += cs[i].v
            if i >= perDay { run -= cs[i - perDay].v }
            if i >= perDay - 1 { peak24 = max(peak24, run) }
        }
        var last24 = 0.0
        for c in cs.suffix(perDay) { last24 += c.v }
        let dd: Double = ath.h > 0 ? last.c / ath.h - 1 : 0
        let mult: Double = ath.h / p0
        let athIdx = cs.firstIndex(where: { $0.t == ath.t }) ?? 0
        var halfAfter: Double? = nil
        for c in cs[athIdx...] where c.c <= ath.h * 0.5 {
            halfAfter = c.t - ath.t
            break
        }
        let avgV = total / Double(cs.count)
        let basis = cat("GeckoTerminal ", tf.title, " K 线，共 ", String(cs.count), " 根")
        var phases: [LifePhase] = []

        var launch = cat("首根 K 线 ", TZ.short(first.date), "，开盘 ", Money.price(p0))
        if total > 0 { launch += String(format: "；首 24 小时成交额占已加载累计的 %.0f%%", day1 / total * 100) }
        var lb = basis
        if let cm = createdMs, cm / 1000 < first.t - sec * 2 { lb = cat(basis, "；最早一根晚于建池时间，更早的数据未取到") }
        phases.append(LifePhase(title: "发射", text: launch, basis: lb, level: "info"))

        if athIdx > 0 {
            let t = cat("从开盘涨到最高点 ", String(format: "%.1f", mult), " 倍，用时 ", Fmt2.dur(ath.t - first.t))
            phases.append(LifePhase(title: "拉升", text: t, basis: cat("最高价 ÷ 首根开盘价（", Money.price(ath.h), " ÷ ", Money.price(p0), "）"), level: mult >= 20 ? "warn" : "info"))
        }
        var top = cat("最高价 ", Money.price(ath.h), " 出现在 ", TZ.short(ath.date))
        if avgV > 0 { top += String(format: "；那一根成交额是均值的 %.1f 倍", ath.v / avgV) }
        phases.append(LifePhase(title: "顶部", text: top, basis: "已加载范围内最高价", level: "info"))

        if athIdx < cs.count - 1 {
            var t = cat("自最高点至今 ", String(format: "%+.0f%%", dd * 100))
            if let h = halfAfter { t += cat("；最高点后 ", Fmt2.dur(h), " 就跌去一半") } else { t += "；还没有从最高点跌去一半" }
            phases.append(LifePhase(title: "回落", text: t, basis: cat("现价 ", Money.price(last.c), " ÷ 最高价"), level: dd <= -0.7 ? "risk" : (dd <= -0.4 ? "warn" : "info")))
        }

        var stage = "横盘整理期"
        var sb = cat("距最高点 ", String(format: "%+.0f%%", dd * 100))
        let ratio: Double = peak24 > 0 ? last24 / peak24 : 0
        if peak24 > 0 { sb += String(format: "；最近 24 小时成交额只有峰值 24 小时的 %.0f%%", ratio * 100) }
        let ageH = (last.t - first.t) / 3600
        if liq > 0 && liq < 1_000 { stage = "已归零 / 无流动性"; sb = cat("流动性只有 ", Fmt2.usd(liq), "；", sb) }
        else if dd <= -0.9 && ratio < 0.05 { stage = "死亡期（量能枯竭）" }
        else if dd <= -0.9 { stage = "崩盘后残局" }
        else if dd <= -0.7 { stage = "派发后期" }
        else if dd <= -0.4 { stage = "回落期" }
        else if dd >= -0.15 && last.t - ath.t <= 86_400 * 2 { stage = "顶部区（新高附近）" }
        else if ageH < 6 { stage = "发射期" }
        phases.append(LifePhase(title: "现状", text: stage, basis: sb, level: dd <= -0.7 ? "risk" : (dd <= -0.4 ? "warn" : "info")))
        return LifeReport(phases: phases, stage: stage, stageBasis: sb, n: cs.count, tfTitle: tf.title)
    }
}

struct LifecycleCard: View {
    @ObservedObject var vm: UTokenVM
    @State private var report: LifeReport?
    @State private var at: Date?
    @State private var err: String?
    @State private var loading = false
    private static var store: [String: (LifeReport, Date)] = [:]

    private var key: String { cat(vm.chain.rawValue, ":", vm.main?.pairAddress ?? "") }

    private func col(_ l: String) -> Color { l == "risk" ? .red : (l == "warn" ? .orange : .blue) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("全生命周期", systemImage: "hourglass").font(.headline)
                    Spacer()
                    if let a = at { Text(cat("计算于 ", a.formatted(date: .omitted, time: .standard))).font(.caption2).foregroundStyle(.secondary) }
                }
                if loading { HStack(spacing: 8) { ProgressView(); Text("读取全程 K 线…").font(.footnote).foregroundStyle(.secondary) } }
                if let r = report {
                    ForEach(r.phases) { p in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .top, spacing: 6) {
                                Circle().fill(col(p.level)).frame(width: 7, height: 7).padding(.top, 6)
                                Text(cat(p.title, "：", p.text)).font(.subheadline)
                            }
                            Text(cat("依据：", p.basis)).font(.caption2).foregroundStyle(.secondary).padding(.leading, 13)
                        }
                    }
                }
                if let e = err { Text(e).font(.caption).foregroundStyle(Color.orange) }
                Text("时间线由 K 线按规则算出：池子只加载到最近 1000 根（小时线约 41 天，更老的币用日线），超出部分不在内。").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task(id: key) { await load() }
    }

    private func load() async {
        guard let pair = vm.main?.pairAddress, !pair.isEmpty else { return }
        if let c = Self.store[key] { report = c.0; at = c.1 }
        loading = report == nil
        err = nil
        var ageH = 9999.0
        if let cm = vm.main?.pairCreatedAt { ageH = (Date().timeIntervalSince1970 * 1000 - cm) / 3_600_000 }
        let tf: TF = ageH <= 950 ? .h1 : .d1
        do {
            let cs = try await MarketAPI.candlesPage(vm.chain, pair, tf, before: nil, limit: 1000)
            if let r = LifeEngine.analyze(cs, tf: tf, createdMs: vm.main?.pairCreatedAt, liq: vm.main?.liq ?? 0) {
                report = r
                at = Date()
                Self.store[key] = (r, Date())
            } else {
                err = "K 线不足 5 根，无法判断生命周期"
            }
        } catch {
            err = report == nil ? Net.message(error) : cat("刷新失败，显示的是旧数据：", Net.message(error))
        }
        loading = false
    }
}

// MARK: - 社交与官方信息（Dexscreener 登记 + X + Telegram + 域名年龄 + GeckoTerminal 资料）
struct SocialItem: Identifiable {
    let id = UUID()
    var level: String
    var text: String
    var basis: String
}

struct SocialReport {
    var items: [SocialItem]
    var facts: [[String]]
    var unknown: [String]
    var at: Date
}

enum SocialEngine {
    static func get(_ urlStr: String) async -> Data? {
        guard let u = URL(string: urlStr) else { return nil }
        var r = URLRequest(url: u, timeoutInterval: 12)
        r.setValue("application/json, text/html", forHTTPHeaderField: "Accept")
        r.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        guard let res = try? await Net.fetch(r), let code = (res.1 as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return nil }
        return res.0
    }

    static func handle(_ url: String, hosts: [String]) -> String? {
        guard let u = URL(string: url), let h = u.host?.lowercased(), hosts.contains(where: { h == $0 || h.hasSuffix("." + $0) }) else { return nil }
        let first = u.pathComponents.filter { $0 != "/" }.first ?? ""
        if first.isEmpty || first == "i" || first == "home" || first == "share" { return nil }
        return first
    }

    static func joinedDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return f.date(from: s)
    }

    static func isoDate(_ s: String) -> Date? {
        let a = ISO8601DateFormatter()
        a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = a.date(from: s) { return d }
        let b = ISO8601DateFormatter()
        b.formatOptions = [.withInternetDateTime]
        return b.date(from: s)
    }

    static func digits(_ s: String) -> Double? {
        let d = s.filter { $0.isNumber }
        return d.isEmpty ? nil : Double(d)
    }

    static func tgMembers(_ html: String) -> (Double, String)? {
        guard let re = try? NSRegularExpression(pattern: "([0-9][0-9 \u{00a0},]*)\\s*(members|subscribers)", options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        guard let m = re.firstMatch(in: html, options: [], range: NSRange(location: 0, length: ns.length)), m.numberOfRanges >= 3 else { return nil }
        let num = ns.substring(with: m.range(at: 1))
        let kind = ns.substring(with: m.range(at: 2))
        guard let v = digits(num) else { return nil }
        return (v, kind.lowercased())
    }

    static func run(pair: DexPair, chain: Chain, address: String) async -> SocialReport {
        var items: [SocialItem] = []
        var facts: [[String]] = []
        var unknown: [String] = []

        var socials: [(String, String)] = []
        var webs: [String] = []
        if let info = pair.info, let d = try? JSONEncoder().encode(info), let j = try? JSONDecoder().decode(JV.self, from: d) {
            for s in j.at("socials")?.array ?? [] {
                if let t = s.at("type")?.text, let u = s.at("url")?.text { socials.append((t.lowercased(), u)) }
            }
            for w in j.at("websites")?.array ?? [] {
                if let u = w.at("url")?.text { webs.append(u) }
            }
        }

        // 并行：X、Telegram、GeckoTerminal 资料
        var xHandle = socials.compactMap { handle($0.1, hosts: ["x.com", "twitter.com"]) }.first
        var tgHandle = socials.compactMap { handle($0.1, hosts: ["t.me", "telegram.me"]) }.first
        let gk = await get(cat("https://api.geckoterminal.com/api/v2/networks/", chain.geckoId, "/tokens/", address, "/info"))
        var gtScore: Double? = nil
        var gtHolders: Double? = nil
        if let d = gk, let j = try? JSONDecoder().decode(JV.self, from: d), let a = j.at("data")?.at("attributes") {
            gtScore = a.at("gt_score")?.number
            gtHolders = a.at("holders")?.at("count")?.number
            if xHandle == nil, let h = a.at("twitter_handle")?.text { xHandle = h }
            if tgHandle == nil, let h = a.at("telegram_handle")?.text { tgHandle = h }
            for w in a.at("websites")?.strings ?? [] where !webs.contains(w) { webs.append(w) }
        } else {
            unknown.append("GeckoTerminal 代币资料未取到")
        }

        let linkCount = socials.count + webs.count
        let types = socials.map { $0.0 }.joined(separator: "、")
        if linkCount == 0 && xHandle == nil && tgHandle == nil {
            items.append(SocialItem(level: "warn", text: "没有登记任何官方社交或网站链接", basis: "Dexscreener 与 GeckoTerminal 均无记录"))
        } else {
            facts.append(["官方链接", cat(types.isEmpty ? "无社交" : types, "；", webs.isEmpty ? "无官网" : cat(String(webs.count), " 个网站"))])
        }
        if let s = gtScore { facts.append(["GeckoTerminal 评分", String(format: "%.1f / 100", s)]) }
        if let h = gtHolders { facts.append(["GeckoTerminal 持有人数", String(Int(h))]) }

        if let h = xHandle {
            if let d = await get(cat("https://api.fxtwitter.com/", h)), let j = try? JSONDecoder().decode(JV.self, from: d), let u = j.at("user") {
                let fo = u.at("followers")?.number
                let tw = u.at("tweets")?.number
                var ageD: Double? = nil
                if let js = u.at("joined")?.text, let jd = joinedDate(js) { ageD = Date().timeIntervalSince(jd) / 86_400 }
                var line = cat("@", h)
                if let f = fo { line += cat("，粉丝 ", String(Int(f))) }
                if let t = tw { line += cat("，推文 ", String(Int(t))) }
                if let a = ageD { line += cat("，账号 ", String(Int(a)), " 天") }
                facts.append(["X 账号", line])
                let basis = "fxtwitter 公开接口（第三方，可能延迟）"
                if let f = fo, f < 100 { items.append(SocialItem(level: "warn", text: cat("X 粉丝只有 ", String(Int(f))), basis: basis)) }
                if let a = ageD, a < 30 { items.append(SocialItem(level: "warn", text: cat("X 账号只创建了 ", String(Int(a)), " 天"), basis: basis)) }
                if let a = ageD, let f = fo, a < 30, f > 5_000 { items.append(SocialItem(level: "info", text: "账号很新但粉丝很多，可能买过粉（只是提示，无法证明）", basis: cat(String(Int(f)), " 粉丝 / ", String(Int(a)), " 天"))) }
                if let t = tw, t < 20 { items.append(SocialItem(level: "info", text: cat("X 推文只有 ", String(Int(t)), " 条"), basis: basis)) }
            } else {
                unknown.append(cat("X 账号 @", h, " 的粉丝与年龄未取到（接口无响应）"))
            }
        } else {
            unknown.append("没有找到 X 账号")
        }

        if let h = tgHandle {
            if let d = await get(cat("https://t.me/", h)), let html = String(data: d, encoding: .utf8), let m = tgMembers(html) {
                facts.append(["Telegram", cat("t.me/", h, "，", String(Int(m.0)), " ", m.1 == "subscribers" ? "订阅" : "成员")])
                if m.0 < 200 { items.append(SocialItem(level: "warn", text: cat("Telegram 只有 ", String(Int(m.0)), " 人"), basis: "t.me 公开页")) }
            } else {
                unknown.append(cat("Telegram ", h, " 的人数未取到"))
            }
        } else {
            unknown.append("没有找到 Telegram")
        }

        let skip = ["x.com", "twitter.com", "t.me", "telegram.org", "discord.gg", "discord.com", "linktr.ee", "medium.com", "github.com", "youtube.com"]
        if let w = webs.first, let host = URL(string: w)?.host?.lowercased(), !skip.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            let dom = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if let d = await get(cat("https://rdap.org/domain/", dom)), let j = try? JSONDecoder().decode(JV.self, from: d) {
                var reg: Date? = nil
                for e in j.at("events")?.array ?? [] where (e.at("eventAction")?.text ?? "") == "registration" {
                    if let s = e.at("eventDate")?.text { reg = isoDate(s) }
                }
                if let r = reg {
                    let days = Date().timeIntervalSince(r) / 86_400
                    facts.append(["官网域名", cat(dom, "，注册 ", String(Int(days)), " 天")])
                    if days < 14 { items.append(SocialItem(level: "warn", text: cat("官网域名 ", dom, " 只注册了 ", String(Int(days)), " 天"), basis: "RDAP 注册记录")) }
                    else if days < 30 { items.append(SocialItem(level: "info", text: cat("官网域名注册不到 30 天（", String(Int(days)), " 天）"), basis: "RDAP 注册记录")) }
                } else {
                    unknown.append(cat("域名 ", dom, " 的注册时间未取到"))
                }
            } else {
                unknown.append(cat("域名 ", dom, " 的注册信息未取到"))
            }
        }
        if items.isEmpty && !facts.isEmpty { items.append(SocialItem(level: "ok", text: "已查到的官方信息没有触发明显风险项", basis: "只说明链接存在且基本数据正常，不代表项目可信；链上没有「社交热度」的免费公开数据，这里不编造")) }
        return SocialReport(items: items, facts: facts, unknown: unknown, at: Date())
    }
}

struct SocialCard: View {
    @ObservedObject var vm: UTokenVM
    @State private var report: SocialReport?
    @State private var loading = false
    private static var store: [String: SocialReport] = [:]

    private var key: String { cat(vm.chain.rawValue, ":", vm.address) }
    private func col(_ l: String) -> Color { l == "risk" ? .red : (l == "warn" ? .orange : (l == "ok" ? .green : .blue)) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("社交与官方信息", systemImage: "bubble.left.and.bubble.right").font(.headline)
                    Spacer()
                    if let r = report { Text(cat("查询于 ", r.at.formatted(date: .omitted, time: .standard))).font(.caption2).foregroundStyle(.secondary) }
                    Button("刷新") { Task { await load(force: true) } }.font(.caption)
                }
                if loading { HStack(spacing: 8) { ProgressView(); Text("读取 X / Telegram / 域名…").font(.footnote).foregroundStyle(.secondary) } }
                if let r = report {
                    ForEach(r.facts, id: \.self) { f in
                        HStack(alignment: .top) {
                            Text(f[0]).font(.caption).foregroundStyle(.secondary).frame(width: 96, alignment: .leading)
                            Text(f[1]).font(.footnote)
                            Spacer(minLength: 0)
                        }
                    }
                    ForEach(r.items) { i in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .top, spacing: 6) {
                                Circle().fill(col(i.level)).frame(width: 7, height: 7).padding(.top, 6)
                                Text(i.text).font(.subheadline)
                            }
                            Text(cat("依据：", i.basis)).font(.caption2).foregroundStyle(.secondary).padding(.leading, 13)
                        }
                    }
                    if !r.unknown.isEmpty {
                        Text("未知（没取到，不参与判断）").font(.caption).foregroundStyle(.secondary)
                        ForEach(r.unknown, id: \.self) { u in Text(cat("· ", u)).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .task(id: key) { await load(force: false) }
    }

    private func load(force: Bool) async {
        guard let p = vm.main, !vm.address.isEmpty else { return }
        if !force, let c = Self.store[key] { report = c; return }
        loading = true
        let r = await SocialEngine.run(pair: p, chain: vm.chain, address: vm.address)
        Self.store[key] = r
        report = r
        loading = false
    }
}
