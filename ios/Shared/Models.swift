import Foundation
import ActivityKit

// MARK: - 旧 Worker 响应（字段全部可选：缺字段不解码失败，界面显示「未知」）
struct Price: Codable {
    var name: String?
    var symbol: String?
    var priceUsd: Double?
    var liquidityUsd: Double?
    var volume24hUsd: Double?
    var priceChange24hPct: Double?
    var pairAddress: String?
    var dexId: String?
}

struct TradeLinks: Codable {
    var ave: String?
    var gmgn: String?
    var dexscreener: String?
    var xSearch: String?
}

struct TopHolder: Codable {
    var address: String?
    var sharePct: Double?
    var isContract: Bool?
}

struct TradeFlowPeriod: Codable {
    var buys: Int?
    var sells: Int?
}

struct TradeFlow: Codable {
    var m5: TradeFlowPeriod?
    var h1: TradeFlowPeriod?
    var h24: TradeFlowPeriod?
}

struct SolanaAuthorities: Codable {
    var mintRenounced: Bool?
    var freezeRenounced: Bool?
}

struct Txns: Codable {
    var buys: Int?
    var sells: Int?
}

struct TokenResponse: Codable {
    var chain: String?
    var address: String?
    var error: String?
    var price: Price?
    var holders: Int?
    var realHolders: Int?
    var topHoldersPct: Double?
    var buyTax: Double?
    var sellTax: Double?
    var honeypot: Bool?
    var renounced: Bool?
    var mintable: Bool?
    var blacklist: Bool?
    var lpLocked: Bool?
    var lpBurnPct: Double?
    var poolAge: Double?
    var marketCapUsd: Double?
    var txns24h: Txns?
    var risk: String?
    var riskSource: String?
    var topHolders: [TopHolder]?
    var tradeFlow: TradeFlow?
    var solanaAuthorities: SolanaAuthorities?
    var tradeLinks: TradeLinks?
}

struct DeepHolderAnalysis: Codable {
    var wallet: String?
    var style: String?
    var truncated: Bool?
}

struct DeepResponse: Codable {
    var chain: String?
    var address: String?
    var error: String?
    var holderAnalyses: [DeepHolderAnalysis]?
}

struct PortfolioHolding: Codable {
    var kind: String?
    var chain: String?
    var address: String?
    var symbol: String?
    var name: String?
    var amount: Double?
    var priceUsd: Double?
    var usd: Double?
    var priceChange24hPct: Double?
    var spamLikely: Bool?
}

struct PortfolioWallet: Codable {
    var chain: String?
    var address: String?
    var holdings: [PortfolioHolding]?
    var totalUsd: Double?
    var pricedCount: Int?
    var unpricedCount: Int?
}

struct Brain: Codable {
    var conclusion: String?
    var topSymbol: String?
    var topSharePct: Double?
    var analyzedCount: Int?
    var totalNonNative: Int?
    var watch: [String]?
    var disclaimer: String?
}

struct InvalidWallet: Codable {
    var chain: String?
    var address: String?
    var reason: String?
}

struct PortfolioResponse: Codable {
    var mode: String?
    var wallets: [PortfolioWallet]?
    var merged: PortfolioWallet?
    var invalid: [InvalidWallet]?
    var brain: Brain?
    var note: String?
    var error: String?
    var fetchedAt: Int?
}

struct FxResponse: Codable {
    var base: String?
    var rates: [String: Double]?
    var source: String?
    var rateDate: String?
}

struct WosCode: Codable, Identifiable {
    var code: String?
    var status: String?
    var rewards: String?
    var note: String?
    var id: String { code ?? UUID().uuidString }
    enum CodingKeys: String, CodingKey { case code, status, rewards, note }
}

struct WosPlayer: Codable {
    var name: String?
    var id: String?
    var kingdom: String?
    var initialKingdom: String?
    var alliance: String?
    var redeemUrl: String?
}

struct WosCodesResponse: Codable {
    var player: WosPlayer?
    var redeemUrl: String?
    var source: String?
    var codes: [WosCode]?
    var note: String?
}

struct FeedbackResponse: Codable {
    var stored: Bool?
    var id: String?
    var error: String?
    var note: String?
}

struct QuotaItem: Codable, Identifiable {
    var id: String
    var name: String?
    var keyPresent: Bool?
    var window: String?
    var limit: Int?
    var limitUnit: String?
    var usedToday: String?
    var remaining: Int?
    var remainingText: String?
    var limited: Bool?
    var resetsInSec: Int?
    var resetsText: String?
    var note: String?
}

// MARK: - 新网关响应
struct AnalyzeResponse: Codable {
    var analysis: Analysis?
    var model: String?
    var error: String?
    var detail: String?

    struct Analysis: Codable {
        var verdict: String?
        var score: Double?
        var headline: String?
        var bullets: [Bullet]?
        var watch: [String]?
    }
    struct Bullet: Codable {
        var tag: String?
        var text: String?
    }
}

struct QuotasV: Codable {
    var day: String?
    var groq: GroqQ?
    var usage: [Usage]?
    var legacy: Legacy?

    struct GroqQ: Codable {
        var keyPresent: Bool?
        var called: Bool?
        var at: Double?
        var status: Int?
        var model: String?
        var limitRequests: Double?
        var remainingRequests: Double?
        var resetRequestsAtMs: Double?
        var limitTokens: Double?
        var remainingTokens: Double?
        var resetTokensAtMs: Double?
        var limited: Bool?
        var retryAtMs: Double?
    }
    struct Usage: Codable, Identifiable {
        var ep: String
        var n: Int
        var id: String { ep }
    }
    struct Legacy: Codable {
        var items: [QuotaItem]?
    }
}

struct KeyInfo: Codable, Identifiable {
    var id: String
    var present: Bool
    var last4: String?
}

struct KeysResponse: Codable {
    var providers: [KeyInfo]
}

struct AlertRule: Codable, Identifiable {
    var id: Int
    var kind: String
    var chain: String?
    var address: String?
    var symbol: String?
    var value: Double?
    var ref: Double?
    var active: Int?
    var cooldown: Int?
    var lastFired: Double?

    enum CodingKeys: String, CodingKey {
        case id, kind, chain, address, symbol, value, ref, active
        case cooldown = "cooldown_min"
        case lastFired = "last_fired"
    }
}

struct AlertsResponse: Codable {
    var alerts: [AlertRule]
}

struct AlertDraft: Codable {
    var kind: String
    var chain: String
    var address: String
    var symbol: String
    var value: Double
    var ref: Double?
    var cooldownMin: Int
}

struct ProfileResponse: Codable {
    var profile: WosPlayer?
}

struct Ping: Codable {
    var ok: Bool?
    var lastEval: LastEval?
    struct LastEval: Codable {
        var at: Double?
        var alerts: Int?
        var fired: Int?
    }
}

// MARK: - 灵动岛
struct WatchAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var price: Double
        var change24h: Double?
        var liquidity: Double?
        var updated: Date
    }
    var symbol: String
    var chain: String
}
