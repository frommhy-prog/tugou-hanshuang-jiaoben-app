import SwiftUI
import UIKit

// MARK: - GMGN OpenAPI（免费档、只读，用你自己的 API Key）
enum GMGNApiError: LocalizedError {
    case noKey
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .noKey: return "还没填 GMGN API Key"
        case .http(let c, let m):
            var s = "GMGN 返回 " + String(c)
            if !m.isEmpty { s += "：" + m }
            if c == 401 || c == 403 { s += "（Key 不对，或手机网络走了 IPv6，GMGN 只支持 IPv4，可切换 Wi-Fi 或关掉蜂窝的 IPv6 再试）" }
            if c == 429 { s += "（请求太频繁，稍等几分钟）" }
            return s
        }
    }
}

enum GMGNApi {
    static var apiKey: String { (Cfg.defaults.string(forKey: "gmgnKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    static func code(_ c: Chain) -> String? {
        switch c {
        case .solana: return "sol"
        case .bsc: return "bsc"
        case .base: return "base"
        case .eth: return "eth"
        default: return nil
        }
    }

    static func get(_ path: String, _ q: [String: String]) async throws -> Any {
        let key = apiKey
        if key.isEmpty { throw GMGNApiError.noKey }
        guard var comps = URLComponents(string: "https://openapi.gmgn.ai" + path) else { throw GMGNApiError.http(0, "地址错误") }
        var items: [URLQueryItem] = q.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970))))
        items.append(URLQueryItem(name: "client_id", value: UUID().uuidString))
        comps.queryItems = items
        guard let url = comps.url else { throw GMGNApiError.http(0, "地址错误") }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(key, forHTTPHeaderField: "X-APIKEY")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (d, r) = try await URLSession.shared.data(for: req)
        let code: Int = (r as? HTTPURLResponse)?.statusCode ?? 0
        let obj = try? JSONSerialization.jsonObject(with: d)
        var msg = ""
        if let o = obj as? [String: Any] {
            msg = (o["message"] as? String) ?? (o["msg"] as? String) ?? (o["error"] as? String) ?? ""
        }
        if code != 200 { throw GMGNApiError.http(code, msg) }
        guard let o = obj else { throw GMGNApiError.http(code, "返回内容不是 JSON") }
        if let dict = o as? [String: Any] {
            if let c = dict["code"] as? Int, c != 0 { throw GMGNApiError.http(c, msg) }
            if let dd = dict["data"] { return dd }
        }
        return o
    }

    static func fetch(_ path: String, _ q: [String: String]) async -> Result<Any, Error> {
        do { return .success(try await get(path, q)) } catch { return .failure(error) }
    }
}

func gmPath(_ d: [String: Any], _ path: String) -> Any? {
    var cur: Any? = d
    for k in path.split(separator: ".") {
        cur = (cur as? [String: Any])?[String(k)]
        if cur == nil { return nil }
    }
    return cur
}

func gmNum(_ v: Any?) -> Double? {
    if let n = v as? Double { return n }
    if let n = v as? Int { return Double(n) }
    if let s = v as? String { return Double(s) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

func gmStr(_ v: Any?) -> String? {
    if let s = v as? String { return s.isEmpty ? nil : s }
    if let n = v as? NSNumber { return n.stringValue }
    return nil
}

struct GMWallet: Identifiable {
    let id: String
    let addr: String
    let pct: Double?
    let tags: [String]
    let name: String?
    let profit: Double?
    let buy: Double?
    let sell: Double?
    let isPool: Bool
    let isNew: Bool

    static func parse(_ d: [String: Any], _ idx: Int) -> GMWallet {
        let a: String = gmStr(d["address"]) ?? ""
        let tags: [String] = ((d["tags"] as? [String]) ?? []) + ((d["maker_token_tags"] as? [String]) ?? [])
        return GMWallet(
            id: a + "#" + String(idx),
            addr: a,
            pct: gmNum(d["amount_percentage"]).map { $0 * 100 },
            tags: tags,
            name: gmStr(d["name"]) ?? gmStr(d["twitter_name"]),
            profit: gmNum(d["profit"]),
            buy: gmNum(d["buy_volume_cur"]),
            sell: gmNum(d["sell_volume_cur"]),
            isPool: (gmNum(d["addr_type"]) ?? 0) == 2,
            isNew: (d["is_new"] as? Bool) == true
        )
    }
}

@MainActor
final class GMGNStore: ObservableObject {
    static let shared = GMGNStore()
    @Published var info: [String: Any] = [:]
    @Published var sec: [String: Any] = [:]
    @Published var list: [[String: Any]] = []
    @Published var status: String = ""
    @Published var loading = false
    private(set) var loadedID = ""
    private var loadedAt: Date?

    var hasKey: Bool { !GMGNApi.apiKey.isEmpty }
    var ready: Bool { !info.isEmpty || !sec.isEmpty }

    func num(_ paths: String...) -> Double? {
        for p in paths {
            if let v = gmNum(gmPath(sec, p) ?? gmPath(info, p)) { return v }
        }
        return nil
    }

    func str(_ paths: String...) -> String? {
        for p in paths {
            if let v = gmStr(gmPath(sec, p) ?? gmPath(info, p)) { return v }
        }
        return nil
    }

    func wallets() -> [GMWallet] {
        var out: [GMWallet] = []
        for (i, d) in list.enumerated() { out.append(GMWallet.parse(d, i)) }
        return out
    }

    func sniperHold() -> Double? {
        if list.isEmpty { return nil }
        var s = 0.0
        for w in wallets() where w.tags.contains("sniper") { s += w.pct ?? 0 }
        return s
    }

    func load(chain: Chain, address: String, force: Bool = false) async {
        guard let cc = GMGNApi.code(chain), !address.isEmpty else {
            info = [:]; sec = [:]; list = []
            status = "GMGN 暂不支持这条链"
            return
        }
        let id = cc + ":" + address
        if !force, id == loadedID, ready, let t = loadedAt, Date().timeIntervalSince(t) < 60 { return }
        if id != loadedID { info = [:]; sec = [:]; list = [] }
        loadedID = id
        if !hasKey { status = "还没填 GMGN API Key"; return }
        loading = true
        status = ""
        async let a = GMGNApi.fetch("/v1/token/info", ["chain": cc, "address": address])
        async let b = GMGNApi.fetch("/v1/token/security", ["chain": cc, "address": address])
        async let c = GMGNApi.fetch("/v1/market/token_top_holders", ["chain": cc, "address": address, "limit": "100", "order_by": "amount_percentage", "direction": "desc"])
        let ra = await a
        let rb = await b
        let rc = await c
        if id != loadedID { loading = false; return }
        var firstErr: String?
        switch ra {
        case .success(let v): info = (v as? [String: Any]) ?? [:]
        case .failure(let e): firstErr = e.localizedDescription
        }
        switch rb {
        case .success(let v): sec = (v as? [String: Any]) ?? [:]
        case .failure(let e): if firstErr == nil { firstErr = e.localizedDescription }
        }
        switch rc {
        case .success(let v):
            if let dd = v as? [String: Any], let l = dd["list"] as? [[String: Any]] { list = l }
            else if let l = v as? [[String: Any]] { list = l }
        case .failure: break
        }
        status = firstErr ?? ""
        loadedAt = Date()
        loading = false
    }
}

// 钱包 → 一键跳转交易平台 / 区块浏览器查看详情
enum GMWalletLinks {
    static func items(_ chain: Chain, _ a: String) -> [(String, URL)] {
        var out: [(String, URL)] = []
        func add(_ n: String, _ s: String) {
            if let u = URL(string: s) { out.append((n, u)) }
        }
        let gm: String = GMGNApi.code(chain) ?? chain.rawValue
        add("GMGN 钱包", "https://gmgn.ai/" + gm + "/address/" + a)
        switch chain {
        case .solana:
            add("Solscan", "https://solscan.io/account/" + a)
            add("Birdeye", "https://birdeye.so/profile/" + a + "?chain=solana")
        case .bsc:
            add("BscScan", "https://bscscan.com/address/" + a)
            add("DeBank", "https://debank.com/profile/" + a)
        case .base:
            add("Basescan", "https://basescan.org/address/" + a)
            add("DeBank", "https://debank.com/profile/" + a)
        case .eth:
            add("Etherscan", "https://etherscan.io/address/" + a)
            add("DeBank", "https://debank.com/profile/" + a)
        default:
            add("DeBank", "https://debank.com/profile/" + a)
        }
        add("Cielo", "https://app.cielo.finance/profile/" + a)
        return out
    }
}

struct GMWalletMenuContent: View {
    let chain: Chain
    let addr: String

    var body: some View {
        let ls = GMWalletLinks.items(chain, addr)
        ForEach(ls.indices, id: \.self) { i in
            Link(ls[i].0, destination: ls[i].1)
        }
        Button("复制地址") { UIPasteboard.general.string = addr }
    }
}

// MARK: - Dexscreener 付费状态（资料页 / CTO / 广告）
struct GMPaid {
    var profile = false
    var cto = false
    var ad = false

    var paid: Bool { profile || cto || ad }

    var text: String {
        if cto { return "CTO" }
        if profile { return "已付费" }
        if ad { return "广告" }
        return "未付费"
    }
}

enum GMPaidApi {
    static func fetch(chainId: String, address: String) async -> GMPaid? {
        if chainId.isEmpty || address.isEmpty { return nil }
        guard let u = URL(string: "https://api.dexscreener.com/orders/v1/" + chainId + "/" + address) else { return nil }
        guard let r = try? await URLSession.shared.data(for: URLRequest(url: u, timeoutInterval: 12)) else { return nil }
        if (r.1 as? HTTPURLResponse)?.statusCode != 200 { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: r.0) else { return nil }
        var arr: [[String: Any]] = []
        if let a = obj as? [[String: Any]] { arr = a }
        else if let d = obj as? [String: Any], let a = d["orders"] as? [[String: Any]] { arr = a }
        var out = GMPaid()
        for o in arr {
            let st: String = (o["status"] as? String) ?? "approved"
            if st != "approved" { continue }
            let t: String = ((o["type"] as? String) ?? "").lowercased()
            if t.contains("takeover") { out.cto = true }
            else if t.contains("profile") { out.profile = true }
            else if t.contains("ad") { out.ad = true }
        }
        return out
    }
}
