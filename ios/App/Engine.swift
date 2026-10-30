import SwiftUI
import UIKit

// MARK: - 引擎客户端（Solana 钱包 / 代币 / 持有人 / 池子 分析，数据全部来自链上原始记录）
enum Engine {
    static var base: String {
        Cfg.defaults.string(forKey: "engineBase") ?? "https://tstzm-engine.from-mhy.workers.dev"
    }

    static func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        try await send(path, query: query, method: "GET", body: nil)
    }

    static func post<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await send(path, query: [:], method: "POST", body: data)
    }

    static func send<T: Decodable>(_ path: String, query: [String: String], method: String, body: Data?) async throws -> T {
        guard !Cfg.token.isEmpty else { throw APIError.noToken }
        guard var comps = URLComponents(string: base + path) else { throw APIError.network("地址无效") }
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = comps.url else { throw APIError.network("地址无效") }
        var req = URLRequest(url: url, timeoutInterval: 120)
        req.httpMethod = method
        req.setValue("Bearer " + Cfg.token, forHTTPHeaderField: "Authorization")
        if let body = body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let result: (Data, URLResponse)
        do { result = try await URLSession.shared.data(for: req) }
        catch { throw APIError.network(error.localizedDescription) }
        let code = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw APIError.unauthorized }
        if !(200..<300).contains(code) {
            let txt = String((String(data: result.0, encoding: .utf8) ?? "").prefix(200))
            throw APIError.http(code, txt)
        }
        do { return try JSONDecoder().decode(T.self, from: result.0) }
        catch { throw APIError.decode(error.localizedDescription) }
    }
}

// MARK: - 模型
struct SolStats: Codable {
    var swapTx: Int?
    var pages: Int?
    var complete: Bool?
    var tradeN: Int?
    var multiSkipped: Int?
    var feesSol: Double?
    var from: Double?
    var to: Double?
    var spanDays: Double?
    var tokensTraded: Int?
    var realizedN: Int?
    var winN: Int?
    var winRate: Double?
    var realizedSol: Double?
    var closedN: Int?
    var medHoldSec: Double?
    var medBuySol: Double?
    var perDay: Double?
    var uncoveredTokens: Int?
    var usdQuoteTrades: Int?
}

struct SolEv: Codable {
    var mint: String?
    var sym: String?
    var text: String?
}

struct SolTag: Codable, Identifiable {
    var tag: String
    var basis: String?
    var ev: [SolEv]?
    var id: String { tag }
}

struct SolPosition: Codable, Identifiable {
    var mint: String
    var sym: String?
    var q: String?
    var buys: Int?
    var sells: Int?
    var bought: Double?
    var sold: Double?
    var boughtAmt: Double?
    var soldAmt: Double?
    var realized: Double?
    var remainingQty: Double?
    var remainingCost: Double?
    var unrealized: Double?
    var firstBuy: Double?
    var lastSell: Double?
    var firstTrade: Double?
    var lastTrade: Double?
    var uncovQty: Double?
    var bestSig: String?
    var worstSig: String?
    var liqUsd: Double?
    var id: String { mint + (q ?? "") }
}

struct SolTrade: Codable, Identifiable {
    var sig: String
    var t: Double
    var mint: String
    var side: String
    var qty: Double?
    var amt: Double?
    var q: String?
    var src: String?
    var sym: String?
    var id: String { sig + mint }
}

struct SolWallet: Codable {
    var address: String?
    var stats: SolStats?
    var tags: [SolTag]?
    var notes: [String]?
    var sample: String?
    var positions: [SolPosition]?
    var trades: [SolTrade]?
    var error: String?
    var detail: String?
}

struct Finding: Codable, Identifiable {
    var level: String
    var text: String
    var basis: String?
    var id: String { text }
    var color: Color {
        switch level {
        case "risk": return Color.red
        case "warn": return Color.orange
        case "ok": return Color.green
        default: return Color.gray
        }
    }
    var icon: String {
        switch level {
        case "risk": return "xmark.octagon.fill"
        case "warn": return "exclamationmark.triangle.fill"
        case "ok": return "checkmark.circle.fill"
        default: return "info.circle.fill"
        }
    }
}

struct TokHolder: Codable, Identifiable {
    var rank: Int
    var owner: String
    var kind: String
    var program: String?
    var amount: Double?
    var pct: Double?
    var id: String { owner }
    var kindText: String {
        switch kind {
        case "wallet": return "普通钱包"
        case "pda": return "池子金库/派生地址"
        case "contract": return "合约持有账户"
        case "program": return "程序账户"
        default: return "未知"
        }
    }
}

struct TokMarket: Codable {
    var sym: String?
    var name: String?
    var liq: Double?
    var priceUsd: Double?
    var priceNative: Double?
    var quote: String?
    var pair: String?
    var dex: String?
    var createdAt: Double?
    var b24: Int?
    var s24: Int?
    var vol24: Double?
    var mc: Double?
}

struct Conc: Codable {
    var top1: Double?
    var top5: Double?
    var top10: Double?
    var top20: Double?
    var wallets10: Double?
    var nonWallet: Double?
    var listed: Int?
}

struct TokAuth: Codable {
    var mint: String?
    var freeze: String?
}

struct SolToken: Codable {
    var mint: String?
    var decimals: Int?
    var supply: Double?
    var authorities: TokAuth?
    var market: TokMarket?
    var holders: [TokHolder]?
    var concentration: Conc?
    var findings: [Finding]?
    var notes: [String]?
    var error: String?
    var detail: String?
}

struct HolderPos: Codable {
    var q: String?
    var buys: Int?
    var sells: Int?
    var bought: Double?
    var sold: Double?
    var boughtAmt: Double?
    var soldAmt: Double?
    var realized: Double?
    var remainingQty: Double?
    var remainingCost: Double?
    var firstBuy: Double?
    var lastSell: Double?
    var uncovQty: Double?
    var avgBuyPrice: Double?
}

struct SolHolder: Codable {
    var owner: String?
    var mint: String?
    var tokenPositions: [HolderPos]?
    var tradesThis: [SolTrade]?
    var finding: String?
    var stats: SolStats?
    var tags: [SolTag]?
    var notes: [String]?
    var sample: String?
    var error: String?
    var detail: String?
}

struct PoolWindow: Codable {
    var swapTx: Int?
    var from: Double?
    var to: Double?
    var complete: Bool?
    var pages: Int?
}

struct PoolTotals: Codable {
    var buySol: Double?
    var sellSol: Double?
    var nb: Int?
    var ns: Int?
    var traders: Int?
    var netInSol: Double?
}

struct PoolTrader: Codable, Identifiable {
    var w: String
    var buySol: Double?
    var sellSol: Double?
    var nb: Int?
    var ns: Int?
    var id: String { w }
}

struct SolPool: Codable {
    var pair: String?
    var window: PoolWindow?
    var totals: PoolTotals?
    var topBuyers: [PoolTrader]?
    var topSellers: [PoolTrader]?
    var wash: [PoolTrader]?
    var findings: [Finding]?
    var notes: [String]?
    var attributed: Int?
    var error: String?
    var detail: String?
}

struct AIPoint: Codable {
    var claim: String?
    var basis: String?
}

struct AIAnalysis: Codable {
    var summary: String?
    var judgement: String?
    var points: [AIPoint]?
    var unknown: [String]?
}

struct AIResult: Codable {
    var analysis: AIAnalysis?
    var model: String?
    var error: String?
    var detail: String?
}

struct AIPayload<F: Encodable>: Encodable {
    var kind: String
    var facts: F
}

struct WalletFacts: Encodable {
    var address: String
    var stats: SolStats?
    var tags: [SolTag]
    var notes: [String]
    var sample: String?
    var topPositions: [SolPosition]
}

struct TokenFacts: Encodable {
    var mint: String
    var symbol: String?
    var liquidityUsd: Double?
    var priceUsd: Double?
    var poolCreatedAtMs: Double?
    var authorities: TokAuth?
    var concentration: Conc?
    var findings: [Finding]
    var holders: [HolderFact]
    var pool: PoolFact?
}

struct HolderFact: Encodable {
    var rank: Int
    var owner: String
    var kind: String
    var pct: Double?
    var finding: String?
    var stats: SolStats?
    var tags: [SolTag]?
    var thisToken: [HolderPos]?
}

struct PoolFact: Encodable {
    var totals: PoolTotals?
    var findings: [Finding]?
}

// MARK: - 格式化与链接
enum Fmt2 {
    static func time(_ ts: Double?) -> String {
        guard let ts = ts else { return "未知" }
        return Date(timeIntervalSince1970: ts).formatted(date: .abbreviated, time: .shortened)
    }
    static func dur(_ s: Double?) -> String {
        guard let s = s else { return "未知" }
        if s < 90 { return String(format: "%.0f 秒", s) }
        if s < 5400 { return String(format: "%.1f 分钟", s / 60) }
        if s < 172800 { return String(format: "%.1f 小时", s / 3600) }
        return String(format: "%.1f 天", s / 86400)
    }
    static func sol(_ v: Double?) -> String {
        guard let v = v else { return "未知" }
        return String(format: "%+.4f SOL", v)
    }
    static func solPlain(_ v: Double?) -> String {
        guard let v = v else { return "未知" }
        return String(format: "%.4f SOL", v)
    }
    static func qty(_ v: Double?) -> String {
        guard let v = v else { return "未知" }
        let a = abs(v)
        if a >= 1_000_000_000 { return String(format: "%.2fB", v / 1_000_000_000) }
        if a >= 1_000_000 { return String(format: "%.2fM", v / 1_000_000) }
        if a >= 1_000 { return String(format: "%.1fK", v / 1_000) }
        return String(format: "%.2f", v)
    }
    static func buySell(_ b: Int?, _ s: Int?) -> String {
        let bs = b.map { "\($0)" } ?? "未知"
        let ss = s.map { "\($0)" } ?? "未知"
        return bs + " / " + ss
    }
}

enum Scan {
    static func tx(_ sig: String) -> URL? { URL(string: "https://solscan.io/tx/" + sig) }
    static func account(_ a: String) -> URL? { URL(string: "https://solscan.io/account/" + a) }
    static func token(_ m: String) -> URL? { URL(string: "https://solscan.io/token/" + m) }
}

// MARK: - 通用小组件
struct FindingRow: View {
    let f: Finding
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: f.icon).foregroundStyle(f.color).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.text).font(.subheadline)
                if let b = f.basis, !b.isEmpty { Text("依据：" + b).font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
}

struct TagRow: View {
    let t: SolTag
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Pill(text: t.tag, color: Color.indigo)
            if let b = t.basis { Text("依据：" + b).font(.caption2).foregroundStyle(.secondary) }
            ForEach(Array((t.ev ?? []).enumerated()), id: \.offset) { _, e in
                Text("· " + (e.sym ?? Addr.short(e.mint ?? "?")) + " " + (e.text ?? "")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct StatsGrid: View {
    let s: SolStats
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            StatTile(title: "分析窗口", value: (s.swapTx.map { "\($0) 笔 swap" } ?? "未知") + (s.spanDays.map { String(format: " / %.1f 天", $0) } ?? ""))
            StatTile(title: "涉及代币", value: s.tokensTraded.map { "\($0) 个" } ?? "未知")
            StatTile(title: "已兑现盈亏", value: (s.realizedN ?? 0) > 0 ? Fmt2.sol(s.realizedSol) : "样本不足", tint: (s.realizedSol ?? 0) >= 0 ? Color.green : Color.red)
            StatTile(title: "胜率", value: s.winRate.map { String(format: "%.0f%%（%d/%d）", $0 * 100, s.winN ?? 0, s.realizedN ?? 0) } ?? "样本不足")
            StatTile(title: "持仓时间中位数", value: (s.closedN ?? 0) > 0 ? Fmt2.dur(s.medHoldSec) : "样本不足")
            StatTile(title: "单笔买入中位数", value: s.medBuySol.map { String(format: "%.3f SOL", $0) } ?? "未知")
        }
    }
}

struct AIResultCard: View {
    let title: String
    let result: AIResult?
    let loading: Bool
    let message: String?
    var onRun: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(title, systemImage: "sparkles").font(.headline)
                    Spacer()
                    if loading { ProgressView() }
                }
                if let a = result?.analysis {
                    if let j = a.judgement, !j.isEmpty { Text(j).font(.subheadline.weight(.semibold)) }
                    if let s = a.summary, !s.isEmpty { Text(s).font(.footnote) }
                    ForEach(Array((a.points ?? []).enumerated()), id: \.offset) { _, p in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("• " + (p.claim ?? "")).font(.footnote)
                            if let b = p.basis, !b.isEmpty { Text("依据：" + b).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    if let u = a.unknown, !u.isEmpty {
                        Divider()
                        Text("数据无法回答").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(Array(u.enumerated()), id: \.offset) { _, s in Text("· " + s).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Text("AI 只解读上方程序算出的数据，不引入外部信息；不构成投资建议").font(.caption2).foregroundStyle(.secondary)
                } else if let m = message {
                    Text(m).font(.footnote).foregroundStyle(.secondary)
                    Button("重试", action: onRun).font(.footnote.weight(.semibold))
                } else if !loading {
                    Button(action: onRun) { Label("让 AI 解读这份数据", systemImage: "sparkles") }.buttonStyle(.bordered)
                }
            }
        }
    }
}

func aiMessage(_ r: AIResult) -> String? {
    guard let e = r.error else { return nil }
    if e == "no_groq_key" { return "未绑定 Groq 密钥：设置 → API 密钥与额度" }
    if e.hasPrefix("groq_429") { return "Groq 已限额，恢复后再试（设置里有倒计时）" }
    return "AI 解读失败：" + e + (r.detail.map { "（" + $0.prefix(80) + "）" } ?? "")
}
