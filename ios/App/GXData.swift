import SwiftUI
import UIKit

// MARK: - 项目资料：描述 / X / Telegram / 最新动态（全部免费公开接口，没有 Key）
struct GXXProfile {
    var handle: String = ""
    var name: String = ""
    var bio: String = ""
    var followers: Int = 0
    var following: Int = 0
    var tweets: Int = 0
    var joined: String = ""
}

struct GXTweet: Identifiable {
    let id: String
    let text: String
    let time: String
    let likes: Int
    let rts: Int
}

struct GXMeta {
    var desc: String?
    var x: String?
    var tg: String?
    var web: String?
    var created: Date?
}

enum GXNet {
    static func get(_ s: String, headers: [String: String] = [:], timeout: TimeInterval = 10) async -> Data? {
        guard let url = URL(string: s) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard let r = try? await URLSession.shared.data(for: req) else { return nil }
        let code: Int = (r.1 as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) { return nil }
        return r.0
    }

    static func json(_ s: String, headers: [String: String] = [:], timeout: TimeInterval = 10) async -> Any? {
        guard let d = await get(s, headers: headers, timeout: timeout) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    static func urls(in v: Any) -> [String] {
        var out: [String] = []
        if let s = v as? String {
            if s.hasPrefix("http") { out.append(s) }
        } else if let a = v as? [Any] {
            for x in a { out += urls(in: x) }
        } else if let d = v as? [String: Any] {
            for (_, x) in d { out += urls(in: x) }
        }
        return out
    }

    static let uaMobile: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
}

enum GXSrc {
    static func xHandle(_ s: String) -> String? {
        guard let u = URL(string: s), let h = u.host?.lowercased() else { return nil }
        if !(h.hasSuffix("twitter.com") || h.hasSuffix("x.com")) { return nil }
        let parts: [String] = u.pathComponents.filter { $0 != "/" }
        guard let f = parts.first else { return nil }
        let bad: Set<String> = ["i", "search", "home", "intent", "hashtag", "share", "explore", "communities", "status"]
        if bad.contains(f.lowercased()) { return nil }
        return f
    }

    static func tgHandle(_ s: String) -> String? {
        guard let u = URL(string: s), let h = u.host?.lowercased(), h == "t.me" || h == "telegram.me" else { return nil }
        let parts: [String] = u.pathComponents.filter { $0 != "/" }
        guard let f = parts.first else { return nil }
        if f.hasPrefix("+") || f == "joinchat" { return nil }
        return f
    }

    // 币安 Web3 公共接口：项目描述、社交链接、创建时间
    static func binanceMeta(_ chain: Chain, _ addr: String) async -> GXMeta? {
        let ids: [Chain: String] = [.eth: "1", .bsc: "56", .base: "8453", .solana: "CT_501"]
        guard let cid = ids[chain] else { return nil }
        let u: String = "https://web3.binance.com/bapi/defi/v1/public/wallet-direct/buw/wallet/dex/market/token/meta/info?chainId=" + cid + "&contractAddress=" + addr
        guard let o = await GXNet.json(u, headers: ["User-Agent": "binance-web3/1.1 (Skill)"]) as? [String: Any], let d = o["data"] as? [String: Any] else { return nil }
        var m = GXMeta()
        if let s = d["description"] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { m.desc = s }
        if let t = gmNum(d["createTime"]), t > 0 { m.created = Date(timeIntervalSince1970: t / 1000) }
        for s in GXNet.urls(in: d) {
            if m.x == nil, let h = xHandle(s) { m.x = h; continue }
            if m.tg == nil, let h = tgHandle(s) { m.tg = h; continue }
            if m.web == nil, xHandle(s) == nil, tgHandle(s) == nil, !s.contains("bnbstatic.com") { m.web = s }
        }
        return (m.desc == nil && m.x == nil && m.tg == nil && m.web == nil && m.created == nil) ? nil : m
    }

    // GeckoTerminal 代币资料
    static func geckoInfo(_ chain: Chain, _ addr: String) async -> GXMeta? {
        let u: String = "https://api.geckoterminal.com/api/v2/networks/" + chain.geckoId + "/tokens/" + addr + "/info"
        guard let o = await GXNet.json(u) as? [String: Any], let d = o["data"] as? [String: Any], let a = d["attributes"] as? [String: Any] else { return nil }
        var m = GXMeta()
        if let s = a["description"] as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { m.desc = s }
        if let t = a["twitter_handle"] as? String, !t.isEmpty { m.x = t }
        if let t = a["telegram_handle"] as? String, !t.isEmpty { m.tg = t }
        if let w = a["websites"] as? [String], let f = w.first { m.web = f }
        return (m.desc == nil && m.x == nil && m.tg == nil && m.web == nil) ? nil : m
    }

    // X 资料（FixTweet 公共接口）
    static func xProfile(_ h: String) async -> GXXProfile? {
        guard let o = await GXNet.json("https://api.fxtwitter.com/" + h) as? [String: Any], let u = o["user"] as? [String: Any] else { return nil }
        var p = GXXProfile()
        p.handle = (u["screen_name"] as? String) ?? h
        p.name = (u["name"] as? String) ?? ""
        p.bio = (u["description"] as? String) ?? ""
        p.followers = Int(gmNum(u["followers"]) ?? 0)
        p.following = Int(gmNum(u["following"]) ?? 0)
        p.tweets = Int(gmNum(u["tweets"]) ?? 0)
        p.joined = (u["joined"] as? String) ?? ""
        return p
    }

    static func tweetTime(_ s: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        if let d = f.date(from: s) { return TZ.short(d) }
        return s
    }

    // X 最新动态（X 官方嵌入时间线；X 随时可能限制匿名读取，读不到就返回空）
    static func tweets(_ h: String) async -> [GXTweet] {
        let u: String = "https://syndication.twitter.com/srv/timeline-profile/screen-name/" + h + "?dnt=true&showReplies=false"
        guard let d = await GXNet.get(u, headers: ["User-Agent": GXNet.uaMobile], timeout: 12), let html = String(data: d, encoding: .utf8) else { return [] }
        guard let a = html.range(of: "<script id=\"__NEXT_DATA__\" type=\"application/json\">"), let b = html.range(of: "</script>", range: a.upperBound..<html.endIndex) else { return [] }
        let js: String = String(html[a.upperBound..<b.lowerBound])
        guard let data = js.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let pp: [String: Any]? = (o["props"] as? [String: Any])?["pageProps"] as? [String: Any]
        let entries: [[String: Any]] = ((pp?["timeline"] as? [String: Any])?["entries"] as? [[String: Any]]) ?? []
        var out: [GXTweet] = []
        for e in entries {
            guard let t = (e["content"] as? [String: Any])?["tweet"] as? [String: Any] else { continue }
            let text: String = (t["full_text"] as? String) ?? (t["text"] as? String) ?? ""
            if text.isEmpty { continue }
            let id: String = (t["id_str"] as? String) ?? UUID().uuidString
            let time: String = tweetTime((t["created_at"] as? String) ?? "")
            out.append(GXTweet(id: id, text: text, time: time, likes: Int(gmNum(t["favorite_count"]) ?? 0), rts: Int(gmNum(t["retweet_count"]) ?? 0)))
            if out.count >= 6 { break }
        }
        return out
    }

    // Telegram 公开频道最近几条
    static func tgPosts(_ h: String) async -> [String] {
        guard let d = await GXNet.get("https://t.me/s/" + h, headers: ["User-Agent": GXNet.uaMobile]), let html = String(data: d, encoding: .utf8) else { return [] }
        guard let re = try? NSRegularExpression(pattern: "<div class=\"tgme_widget_message_text[^\"]*\"[^>]*>(.*?)</div>", options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = html as NSString
        let ms = re.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
        var out: [String] = []
        for m in ms.suffix(5).reversed() {
            var t: String = ns.substring(with: m.range(at: 1))
            t = t.replacingOccurrences(of: "<br/>", with: "\n").replacingOccurrences(of: "<br>", with: "\n")
            t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            t = t.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            t = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { out.append(String(t.prefix(300))) }
        }
        return out
    }

    // 英文描述译成中文（MyMemory 免费接口，失败就保留原文）
    static func zh(_ s: String) async -> String? {
        let cjk: Int = s.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        if cjk * 3 >= s.count { return nil }
        let q: String = String(s.prefix(380))
        guard let enc = q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        guard let o = await GXNet.json("https://api.mymemory.translated.net/get?q=" + enc + "&langpair=en%7Czh-CN") as? [String: Any], let rd = o["responseData"] as? [String: Any], let t = rd["translatedText"] as? String else { return nil }
        if t.isEmpty || t.uppercased().contains("MYMEMORY") { return nil }
        return t
    }
}

// MARK: - 当前代币的项目资料（切换代币自动重读）
@MainActor
final class GXInfoStore: ObservableObject {
    static let shared = GXInfoStore()
    @Published var key = ""
    @Published var desc = ""
    @Published var descZh = ""
    @Published var descSrc = ""
    @Published var summary = ""
    @Published var xHandle: String?
    @Published var xProfile: GXXProfile?
    @Published var tweets: [GXTweet] = []
    @Published var tgHandle: String?
    @Published var tgPosts: [String] = []
    @Published var website: String?
    @Published var created: Date?
    @Published var loading = false
    private var at = Date.distantPast

    static func k(_ vm: UTokenVM) -> String { vm.chain.rawValue + ":" + vm.address.lowercased() }

    func line(vm: UTokenVM) -> String {
        if key != Self.k(vm) { return "读取项目资料中…" }
        if !summary.isEmpty { return summary }
        return loading ? "读取项目资料中…" : "项目方没有公开描述（币安 / X / GeckoTerminal 都没有资料），仅凭名称无法判断具体叙事"
    }

    private func short(_ s: String, _ n: Int) -> String {
        let t: String = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > n ? String(t.prefix(n)) + "…" : t
    }

    func load(vm: UTokenVM, force: Bool = false) async {
        if vm.address.isEmpty { return }
        let k: String = Self.k(vm)
        if k == key && !force && (loading || Date().timeIntervalSince(at) < 300) { return }
        if k != key {
            desc = ""; descZh = ""; descSrc = ""; summary = ""
            xHandle = nil; xProfile = nil; tweets = []
            tgHandle = nil; tgPosts = []; website = nil; created = nil
        }
        key = k
        at = Date()
        loading = true
        let chain: Chain = vm.chain
        let addr: String = vm.address
        var x: String? = nil
        var tg: String? = nil
        var web: String? = nil
        for s in vm.main?.info?.socials ?? [] {
            guard let u = s.url else { continue }
            if x == nil, let h = GXSrc.xHandle(u) { x = h }
            if tg == nil, let h = GXSrc.tgHandle(u) { tg = h }
        }
        for w in vm.main?.info?.websites ?? [] {
            if web == nil, let u = w.url { web = u }
        }
        async let bm = GXSrc.binanceMeta(chain, addr)
        async let gk = GXSrc.geckoInfo(chain, addr)
        let b: GXMeta? = await bm
        let g: GXMeta? = await gk
        if k != key { return }
        var text: String = ""
        var src: String = ""
        if let d = b?.desc { text = d; src = "币安 Web3" }
        else if let d = g?.desc { text = d; src = "GeckoTerminal" }
        x = x ?? b?.x ?? g?.x
        tg = tg ?? b?.tg ?? g?.tg
        web = web ?? b?.web ?? g?.web
        var prof: GXXProfile? = nil
        var tws: [GXTweet] = []
        var tgp: [String] = []
        if let h = x {
            async let p = GXSrc.xProfile(h)
            async let t = GXSrc.tweets(h)
            prof = await p
            tws = await t
        }
        if let h = tg { tgp = await GXSrc.tgPosts(h) }
        if k != key { return }
        if text.isEmpty, let p = prof, !p.bio.isEmpty { text = p.bio; src = "X 简介" }
        var zh: String? = nil
        if !text.isEmpty { zh = await GXSrc.zh(text) }
        if k != key { return }
        desc = text
        descZh = zh ?? ""
        descSrc = src
        xHandle = x
        xProfile = prof
        tweets = tws
        tgHandle = tg
        tgPosts = tgp
        website = web
        created = b?.created
        var line: String = short(zh ?? text, 96)
        if !line.isEmpty, !src.isEmpty { line += "（" + src + "）" }
        summary = line
        loading = false
    }
}
