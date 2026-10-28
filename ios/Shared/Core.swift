import Foundation
import SwiftUI

// MARK: - 配置（App 与小组件通过 App Group 共享）
enum Cfg {
    static let fallbackGroup = "group.com.Hao-Yi-Miao.TSTZ-M"
    static let defaultBase = "https://tstzm-api.from-mhy.workers.dev"

    // 侧载工具重签名时可能改写 App Group，优先读 Info.plist 里登记的那一个
    static var group: String {
        if let arr = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String], let g = arr.first { return g }
        return fallbackGroup
    }
    static let defaults: UserDefaults = UserDefaults(suiteName: Cfg.group) ?? UserDefaults.standard

    static var base: String {
        get { defaults.string(forKey: "base") ?? defaultBase }
        set { defaults.set(newValue, forKey: "base") }
    }
    static var token: String {
        get { defaults.string(forKey: "token") ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "token") }
    }
    static var wallets: [Wallet] {
        get {
            guard let d = defaults.data(forKey: "wallets"), let w = try? JSONDecoder().decode([Wallet].self, from: d) else { return [] }
            return w
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "wallets") }
    }
    static var snapshot: Snapshot? {
        get {
            guard let d = defaults.data(forKey: "snapshot") else { return nil }
            return try? JSONDecoder().decode(Snapshot.self, from: d)
        }
        set {
            if let v = newValue { defaults.set(try? JSONEncoder().encode(v), forKey: "snapshot") }
        }
    }
}

// MARK: - 钱包与链
struct Wallet: Codable, Identifiable, Hashable {
    var id = UUID()
    var address: String
    var label: String
    var chains: [String]   // Chain.rawValue
}

enum Chain: String, CaseIterable, Codable, Identifiable {
    case bsc, eth, base, solana, robinhood, arbitrum, optimism, polygon, okc, xlayer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bsc: return "BSC"
        case .eth: return "ETH"
        case .base: return "Base"
        case .solana: return "Solana"
        case .robinhood: return "Robinhood"
        case .arbitrum: return "Arbitrum"
        case .optimism: return "Optimism"
        case .polygon: return "Polygon"
        case .okc: return "OKTC"
        case .xlayer: return "X Layer"
        }
    }
    var isEVM: Bool { self != .solana }
    // 代币体检：Worker 已适配的链；OKTC、X Layer 目前只做钱包
    var tokenSupported: Bool { self != .okc && self != .xlayer }
    static let evmDefault: [Chain] = [.eth, .bsc, .base, .arbitrum, .optimism, .polygon, .robinhood, .okc, .xlayer]
    static func fromDex(_ id: String) -> Chain? {
        switch id.lowercased() {
        case "bsc": return .bsc
        case "ethereum": return .eth
        case "base": return .base
        case "solana": return .solana
        case "robinhood": return .robinhood
        case "arbitrum": return .arbitrum
        case "optimism": return .optimism
        case "polygon": return .polygon
        case "okc": return .okc
        case "xlayer": return .xlayer
        default: return nil
        }
    }
}

enum Addr {
    static func isEVM(_ s: String) -> Bool { s.range(of: "^0x[0-9a-fA-F]{40}$", options: .regularExpression) != nil }
    static func isSolana(_ s: String) -> Bool { s.range(of: "^[1-9A-HJ-NP-Za-km-z]{32,44}$", options: .regularExpression) != nil }
    static func short(_ s: String) -> String {
        s.count > 14 ? String(s.prefix(6)) + "…" + String(s.suffix(4)) : s
    }
}

// MARK: - 计价货币（金额一律从美元换算；汇率缺失回落美元，绝不贴错符号）
struct CurrencyInfo: Identifiable, Hashable {
    let code: String
    let name: String
    let symbol: String
    let decimals: Int
    var id: String { code }
}

enum Money {
    static let all: [CurrencyInfo] = [
        CurrencyInfo(code: "USD", name: "美元", symbol: "$", decimals: 2),
        CurrencyInfo(code: "CNY", name: "人民币", symbol: "¥", decimals: 2),
        CurrencyInfo(code: "EUR", name: "欧元", symbol: "€", decimals: 2),
        CurrencyInfo(code: "GBP", name: "英镑", symbol: "£", decimals: 2),
        CurrencyInfo(code: "JPY", name: "日元", symbol: "¥", decimals: 0),
        CurrencyInfo(code: "KRW", name: "韩元", symbol: "₩", decimals: 0),
        CurrencyInfo(code: "CAD", name: "加元", symbol: "C$", decimals: 2),
        CurrencyInfo(code: "AUD", name: "澳元", symbol: "A$", decimals: 2),
        CurrencyInfo(code: "HKD", name: "港元", symbol: "HK$", decimals: 2),
        CurrencyInfo(code: "TWD", name: "新台币", symbol: "NT$", decimals: 2),
        CurrencyInfo(code: "SGD", name: "新加坡元", symbol: "S$", decimals: 2),
        CurrencyInfo(code: "CHF", name: "瑞郎", symbol: "CHF ", decimals: 2),
        CurrencyInfo(code: "NZD", name: "新西兰元", symbol: "NZ$", decimals: 2),
        CurrencyInfo(code: "INR", name: "印度卢比", symbol: "₹", decimals: 2),
        CurrencyInfo(code: "BRL", name: "巴西雷亚尔", symbol: "R$", decimals: 2),
        CurrencyInfo(code: "MXN", name: "墨西哥比索", symbol: "MX$", decimals: 2),
        CurrencyInfo(code: "THB", name: "泰铢", symbol: "฿", decimals: 2),
        CurrencyInfo(code: "MYR", name: "马来西亚林吉特", symbol: "RM ", decimals: 2),
        CurrencyInfo(code: "IDR", name: "印尼盾", symbol: "Rp ", decimals: 0),
        CurrencyInfo(code: "PHP", name: "菲律宾比索", symbol: "₱", decimals: 2),
        CurrencyInfo(code: "VND", name: "越南盾", symbol: "₫", decimals: 0),
        CurrencyInfo(code: "AED", name: "阿联酋迪拉姆", symbol: "AED ", decimals: 2),
        CurrencyInfo(code: "SAR", name: "沙特里亚尔", symbol: "SAR ", decimals: 2),
        CurrencyInfo(code: "PLN", name: "波兰兹罗提", symbol: "zł ", decimals: 2),
        CurrencyInfo(code: "SEK", name: "瑞典克朗", symbol: "kr ", decimals: 2),
        CurrencyInfo(code: "NOK", name: "挪威克朗", symbol: "kr ", decimals: 2),
        CurrencyInfo(code: "DKK", name: "丹麦克朗", symbol: "kr ", decimals: 2),
        CurrencyInfo(code: "CZK", name: "捷克克朗", symbol: "Kč ", decimals: 2),
        CurrencyInfo(code: "HUF", name: "匈牙利福林", symbol: "Ft ", decimals: 0),
        CurrencyInfo(code: "ILS", name: "以色列谢克尔", symbol: "₪ ", decimals: 2),
        CurrencyInfo(code: "ZAR", name: "南非兰特", symbol: "R ", decimals: 2),
        CurrencyInfo(code: "TRY", name: "土耳其里拉", symbol: "₺ ", decimals: 2),
        CurrencyInfo(code: "RUB", name: "俄罗斯卢布", symbol: "₽ ", decimals: 2),
        CurrencyInfo(code: "UAH", name: "乌克兰格里夫纳", symbol: "₴ ", decimals: 2),
        CurrencyInfo(code: "NGN", name: "尼日利亚奈拉", symbol: "₦ ", decimals: 0),
        CurrencyInfo(code: "EGP", name: "埃及镑", symbol: "E£ ", decimals: 2),
        CurrencyInfo(code: "PKR", name: "巴基斯坦卢比", symbol: "Rs ", decimals: 0),
    ]

    static var code: String {
        get { Cfg.defaults.string(forKey: "currency") ?? "USD" }
        set { Cfg.defaults.set(newValue, forKey: "currency") }
    }
    static var rates: [String: Double] {
        get {
            guard let d = Cfg.defaults.data(forKey: "fx"), let m = try? JSONDecoder().decode([String: Double].self, from: d) else { return [:] }
            return m
        }
        set { Cfg.defaults.set(try? JSONEncoder().encode(newValue), forKey: "fx") }
    }

    static func resolved() -> (CurrencyInfo, Double) {
        let c = code
        let info = all.first { $0.code == c } ?? all[0]
        if info.code == "USD" { return (info, 1) }
        if let r = rates[info.code], r > 0 { return (info, r) }
        return (all[0], 1)
    }

    static func format(_ usd: Double?) -> String {
        guard let usd = usd else { return "未知" }
        let (i, r) = resolved()
        return abbreviate(usd * r, symbol: i.symbol, decimals: i.decimals)
    }

    static func abbreviate(_ v: Double, symbol: String, decimals: Int) -> String {
        let a = abs(v)
        let sign = v < 0 ? "-" : ""
        if a >= 1_000_000_000 { return sign + symbol + String(format: "%.2fB", a / 1_000_000_000) }
        if a >= 1_000_000 { return sign + symbol + String(format: "%.2fM", a / 1_000_000) }
        if a >= 10_000 { return sign + symbol + String(format: "%.1fK", a / 1_000) }
        return sign + symbol + String(format: "%.\(decimals)f", a)
    }

    private static let subs = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"]
    private static func sub(_ n: Int) -> String {
        String(n).compactMap { Int(String($0)) }.map { subs[$0] }.joined()
    }

    // 币价：小额币不缩写，极小价格用 0.0₅1234 写法，避免被显示成 0
    static func price(_ usd: Double?) -> String {
        guard let usd = usd else { return "未知" }
        let (i, r) = resolved()
        let v = usd * r
        let s = i.symbol
        if v == 0 { return s + "0" }
        let a = abs(v)
        let sign = v < 0 ? "-" : ""
        if a >= 1000 { return sign + s + String(format: "%.2f", a) }
        if a >= 1 { return sign + s + String(format: "%.4f", a) }
        if a >= 0.0001 { return sign + s + String(format: "%.6f", a) }
        let zeros = max(1, Int(-floor(log10(a))) - 1)
        let sig = a * pow(10, Double(zeros + 1))
        let digits = String(format: "%.3f", sig).replacingOccurrences(of: ".", with: "")
        return sign + s + "0.0" + sub(zeros) + digits
    }
}

enum FX {
    static func refresh() async {
        if let r: FxResponse = try? await API.get("/api/fx"), let m = r.rates, !m.isEmpty { Money.rates = m }
    }
}

// MARK: - 小组件快照
struct SnapItem: Codable, Hashable {
    var symbol: String
    var usd: Double
    var chain: String
}

struct Snapshot: Codable {
    var totalUsd: Double?
    var items: [SnapItem]
    var at: Date

    static let sample = Snapshot(totalUsd: 12345, items: [
        SnapItem(symbol: "SOL", usd: 5200, chain: "solana"),
        SnapItem(symbol: "ETH", usd: 4100, chain: "eth"),
        SnapItem(symbol: "BNB", usd: 3045, chain: "bsc"),
    ], at: Date())

    static func build(_ rs: [PortfolioResponse]) -> Snapshot {
        var total = 0.0
        var agg: [String: SnapItem] = [:]
        for r in rs {
            total += r.merged?.totalUsd ?? 0
            for h in r.merged?.holdings ?? [] {
                if h.spamLikely == true { continue }
                guard let usd = h.usd, usd > 0 else { continue }
                let key = (h.symbol ?? "?") + "|" + (h.chain ?? "")
                if var e = agg[key] { e.usd += usd; agg[key] = e }
                else { agg[key] = SnapItem(symbol: h.symbol ?? "?", usd: usd, chain: h.chain ?? "") }
            }
        }
        let items = Array(agg.values.sorted { $0.usd > $1.usd }.prefix(8))
        return Snapshot(totalUsd: total, items: items, at: Date())
    }
}

// MARK: - 网络
enum APIError: LocalizedError {
    case noToken, unauthorized, http(Int, String), decode(String), network(String)
    var errorDescription: String? {
        switch self {
        case .noToken: return "还没连接服务：到「设置 → 连接」填入令牌"
        case .unauthorized: return "令牌无效或已更换：到「设置 → 连接」重新填入"
        case .http(let c, let m): return "服务返回 \(c)：\(m)"
        case .decode(let m): return "数据格式异常：\(m)"
        case .network(let m): return "网络失败：\(m)"
        }
    }
}

enum API {
    struct Empty: Decodable {}

    static func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        try await send(path, query: query, method: "GET", body: nil)
    }

    static func post<T: Decodable, B: Encodable>(_ path: String, _ body: B, method: String = "POST", query: [String: String] = [:]) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await send(path, query: query, method: method, body: data)
    }

    static func send<T: Decodable>(_ path: String, query: [String: String], method: String, body: Data?) async throws -> T {
        guard !Cfg.token.isEmpty else { throw APIError.noToken }
        guard var comps = URLComponents(string: Cfg.base + path) else { throw APIError.network("地址无效") }
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = comps.url else { throw APIError.network("地址无效") }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = method
        req.setValue("Bearer " + Cfg.token, forHTTPHeaderField: "Authorization")
        if let body = body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let result: (Data, URLResponse)
        do { result = try await URLSession.shared.data(for: req) }
        catch { throw APIError.network(error.localizedDescription) }
        let data = result.0
        let code = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw APIError.unauthorized }
        if !(200..<300).contains(code) {
            throw APIError.http(code, String((String(data: data, encoding: .utf8) ?? "").prefix(160)))
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.decode(error.localizedDescription) }
    }
}
