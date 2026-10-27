import Foundation

// Worker 统一网关：App 和小组件只读这里，不直连上游。
// 交易所 Key 跳过阶段：交易所持仓接口不在这里调，持仓页只显示钱包聚合结果。
enum APIClient {
    static let baseURL = URL(string: "https://tugou-hanshuang-jiaoben-app.from-mhy.workers.dev")!

    struct Price: Codable {
        var name: String?
        var symbol: String?
        var priceUsd: Double?
        var liquidityUsd: Double?
        var volume24hUsd: Double?
        var priceChange24hPct: Double?
        var pairAddress: String?
        var dexId: String?
        var source: String?
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
        var buySharePct: Double?
        var buySellRatio: Double?
    }

    struct TradeFlow: Codable {
        var m5: TradeFlowPeriod?
        var h1: TradeFlowPeriod?
        var h24: TradeFlowPeriod?
        var source: String?
        var moneyFlowNote: String?
    }

    struct SolanaAuthorities: Codable {
        var mintAuthority: String?
        var freezeAuthority: String?
        var mintRenounced: Bool?
        var freezeRenounced: Bool?
        var source: String?
    }

    struct CreatorHistory: Codable {
        var creatorAddress: String?
        var creationTxHash: String?
        var creationTimestamp: Int?
    }

    struct TokenResponse: Codable {
        var chain: String
        var address: String
        var price: Price?
        var holders: Int?
        var topHoldersPct: Double?
        var buyTax: Double?
        var sellTax: Double?
        var honeypot: Bool?
        var renounced: Bool?
        var mintable: Bool?
        var blacklist: Bool?
        var lpLocked: Bool?
        var lpBurnPct: Double?
        var lpTopHolder: String?
        var lpTopHolderPct: Double?
        var poolAge: Double?
        var creatorHistory: CreatorHistory?
        var marketCapUsd: Double?
        var realHolders: Int?
        var txns24h: Txns?
        var queryTimeMs: Int?
        var cached: Bool?
        var fast: Bool?
        var risk: String?
        var riskSource: String?
        var topHolders: [TopHolder]?
        var holdersSource: String?
        var tradeFlow: TradeFlow?
        var solanaAuthorities: SolanaAuthorities?
        var tradeLinks: TradeLinks?
        var fetchedAt: Int?
        var cacheTtlSec: Int?
        var minPollIntervalSec: Int?
    }

    struct Txns: Codable {
        var buys: Int?
        var sells: Int?
    }

    struct HoldingsResponse: Codable {
        var wallets: [WalletAccount]
        var invalid: [InvalidWallet]
        var totalUsd: Double?
        var balanceSource: String?
        var note: String?

        struct InvalidWallet: Codable {
            var chain: String?
            var address: String?
            var reason: String?
        }
    }

    struct HoldingsRequest: Codable {
        var wallets: [WalletAccount]
    }

    static func fetchToken(chain: Chain, address: String) async throws -> TokenResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "chain", value: chain.rawValue),
            URLQueryItem(name: "address", value: address.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    static func fetchTokenFast(chain: Chain, address: String) async throws -> TokenResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/token-fast"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "chain", value: chain.rawValue),
            URLQueryItem(name: "address", value: address.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    static func fetchHoldings(wallets: [WalletAccount]) async throws -> HoldingsResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/holdings"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(HoldingsRequest(wallets: wallets))
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(HoldingsResponse.self, from: data)
    }

    // 新接口客户端（Worker 已上线，App 旧版只调了 /api/token 与 /api/holdings，导致组合/大脑/总结/深层在 App 里根本用不上）。
    // 字段全部可选：Worker 缺字段时不解码失败，界面显示“未查到”而不是整页报错——这是使用中最常见的崩溃来源。
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
        var liquidityUsd: Double?
        var volume24hUsd: Double?
        var priceStale: Bool?
        var priceFetchedAt: Int?
        var priceSource: String?
        var spamLikely: Bool?
    }

    struct PortfolioWallet: Codable {
        var chain: String?
        var address: String?
        var walletKind: String?
        var holdings: [PortfolioHolding]?
        var totalUsd: Double?
        var pricedCount: Int?
        var unpricedCount: Int?
        var discovery: String?
        var signals: [String]?
    }

    struct Brain: Codable {
        var conclusion: String?
        var topSymbol: String?
        var topSharePct: Double?
        var totalNonNativeUsd: Double?
        var analyzedCount: Int?
        var analyzedLimit: Int?
        var unanalyzedCount: Int?
        var totalNonNative: Int?
        var pricedNonNative: Int?
        var watch: [String]?
        var disclaimer: String?
    }

    struct PortfolioResponse: Codable {
        var mode: String?
        var wallets: [PortfolioWallet]?
        var merged: PortfolioWallet?
        var invalid: [HoldingsResponse.InvalidWallet]?
        var brain: Brain?
        var note: String?
        var error: String?
        var fetchedAt: Int?
        var cacheTtlSec: Int?
        var minPollIntervalSec: Int?
        var cached: Bool?
        var mine: Bool?
        var fresh: Bool?
        var apiCost: CostResponse?
    }

    struct Summary: Codable {
        var verdict: String?
        var conclusion: String?
        var risks: [String]?
        var positives: [String]?
        var unknowns: [String]?
        var notes: [String]?
        var watch: [String]?
        var disclaimer: String?
        var analysis: String?
    }

    struct TokenSummaryResponse: Codable {
        var chain: String?
        var address: String?
        var price: Price?
        var summary: Summary?
        var error: String?
    }

    static func fetchPortfolio(wallets: [WalletAccount], merged: Bool = false, brain: Bool = false, mine: Bool = false, fresh: Bool = false) async throws -> PortfolioResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/wallet-portfolio"), resolvingAgainstBaseURL: false)!
        let walletsParam = wallets.map { "\($0.chain.rawValue):\($0.address)" }.joined(separator: ",")
        var items = [URLQueryItem(name: "wallets", value: walletsParam)]
        if merged { items.append(URLQueryItem(name: "mode", value: "merged")) }
        if brain { items.append(URLQueryItem(name: "brain", value: "1")) }
        // mine=1：我的钱包全量，不走结果缓存、不走旧价、大脑 5 个放宽到 20 个/钱包；fresh=1：本次不走缓存。
        if mine { items.append(URLQueryItem(name: "mine", value: "1")) }
        if fresh { items.append(URLQueryItem(name: "fresh", value: "1")) }
        components.queryItems = items
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(PortfolioResponse.self, from: data)
    }

    static func fetchTokenSummary(chain: Chain, address: String, fresh: Bool = false) async throws -> TokenSummaryResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/token"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "chain", value: chain.rawValue),
            URLQueryItem(name: "address", value: address.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "summary", value: "1"),
        ]
        if fresh { items.append(URLQueryItem(name: "fresh", value: "1")) }
        components.queryItems = items
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(TokenSummaryResponse.self, from: data)
    }

    // 成本与用量：分析按钮点之前先调 /api/cost，先看到预计消耗再点；剩余量上游不返回，Worker 只给当日端点次数，剩余标未知不编数。
    struct CostResponse: Codable {
        var endpoint: String?
        var costText: String?
        var mine: Bool?
        var cached: Bool?
        var actualIfCached: Int?
        var remaining: Int?
        var remainingNote: String?
        var note: String?
    }

    struct UsageResponse: Codable {
        var date: String?
        var counts: [String: Int]?
        var countsNote: String?
        var remaining: Int?
        var remainingNote: String?
    }

    static func fetchCost(endpoint: String, wallets: Int = 1, mine: Bool = false, chain: String? = nil) async throws -> CostResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/cost"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "endpoint", value: endpoint),
            URLQueryItem(name: "wallets", value: String(wallets)),
        ]
        if mine { items.append(URLQueryItem(name: "mine", value: "1")) }
        if let chain { items.append(URLQueryItem(name: "chain", value: chain)) }
        components.queryItems = items
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(CostResponse.self, from: data)
    }

    static func fetchUsage() async throws -> UsageResponse {
        let (data, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("api/usage"))
        return try JSONDecoder().decode(UsageResponse.self, from: data)
    }

    struct FxResponse: Codable {
        var base: String?
        var rates: [String: Double]?
        var source: String?
        var rateDate: String?
        var partial: Bool?
        var cached: Bool?
        var note: String?
    }

    static func fetchFx(fresh: Bool = false) async throws -> FxResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/fx"), resolvingAgainstBaseURL: false)!
        if fresh { components.queryItems = [URLQueryItem(name: "fresh", value: "1")] }
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(FxResponse.self, from: data)
    }

    // 深层分析最小客户端：只解码 App 要显示的字段，其他字段忽略；Solana/OKTC/XLayer 深层不支持，Worker 会报不支持，不编结果。
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
        var apiCost: CostResponse?
    }

    static func fetchTokenDeep(chain: Chain, address: String) async throws -> DeepResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/token-deep"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "chain", value: chain.rawValue),
            URLQueryItem(name: "address", value: address.trimmingCharacters(in: .whitespacesAndNewlines)),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(DeepResponse.self, from: data)
    }

    // 趋势榜（Worker /api/trending）：只给 Dex 付费推广榜与最新资料榜，workerChain 才是 Worker 能查的链名，
    // chainId（ethereum 等）直接拿去调 Worker 会报 unknown_chain；upstreamEmpty = true 时是上游空回，不是没有趋势币，不要显示空榜。
    struct TrendingItem: Codable {
        var chainId: String?
        var workerChain: String?
        var tokenAddress: String?
        var description: String?
        var url: String?
        var icon: String?
    }

    struct TrendingResponse: Codable {
        var boosts: [TrendingItem]?
        var profiles: [TrendingItem]?
        var upstreamEmpty: Bool?
        var fetchedAt: Int?
        var cacheTtlSec: Int?
        var minPollIntervalSec: Int?
        var note: String?
        var cached: Bool?
    }

    static func fetchTrending(limit: Int = 20) async throws -> TrendingResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/trending"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(TrendingResponse.self, from: data)
    }

    // 融合客户端：字段全部可选，Worker 缺字段时不解码失败。
    // 热搜是全局榜、快讯是全局新闻、新池是轮询、筛选是一次性判断；四者都不是推荐、不推送。
    struct TrendingGlobalCoin: Codable {
        var id: String?
        var name: String?
        var symbol: String?
        var marketCapRank: Int?
        var priceBtc: Double?
        var score: Int?
    }

    struct TrendingGlobalResponse: Codable {
        var coins: [TrendingGlobalCoin]?
        var coingeckoStatus: Int?
        var fetchedAt: Int?
        var cacheTtlSec: Int?
        var minPollIntervalSec: Int?
        var cached: Bool?
        var note: String?
    }

    struct NewsItem: Codable {
        var title: String?
        var body: String?
        var publishedOn: Int?
        var categories: [String]?
        var source: String?
        var url: String?
        var sentiment: Double?
    }

    struct NewsResponse: Codable {
        var items: [NewsItem]?
        var cryptocompareStatus: Int?
        var fetchedAt: Int?
        var cached: Bool?
        var note: String?
    }

    struct NewPool: Codable {
        var poolAddress: String?
        var name: String?
        var dex: String?
        var baseTokenAddress: String?
        var createdAt: String?
        var reserveUsd: Double?
        var volume24hUsd: Double?
    }

    struct NewPoolsResponse: Codable {
        var chain: String?
        var pools: [NewPool]?
        var geckoterminalStatus: Int?
        var fetchedAt: Int?
        var cached: Bool?
        var note: String?
    }

    struct ScreenerResponse: Codable {
        var triggered: Bool?
        var volume24hUsd: Double?
        var buys24h: Int?
        var sells24h: Int?
        var buyShare24hPct: Double?
        var liquidityUsd: Double?
        var note: String?
        var error: String?
    }

    static func fetchTrendingGlobal() async throws -> TrendingGlobalResponse {
        let (data, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("api/trending-global"))
        return try JSONDecoder().decode(TrendingGlobalResponse.self, from: data)
    }

    static func fetchNews(limit: Int = 20) async throws -> NewsResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/news"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(NewsResponse.self, from: data)
    }

    static func fetchNewPools(chain: Chain) async throws -> NewPoolsResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/new-pools"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "chain", value: chain.rawValue)]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(NewPoolsResponse.self, from: data)
    }

    static func fetchScreener(chain: Chain, address: String, minVolumeUsd: Double = 50000, minBuySharePct: Double = 65) async throws -> ScreenerResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/screener"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "chain", value: chain.rawValue),
            URLQueryItem(name: "address", value: address.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "minVolumeUsd", value: String(minVolumeUsd)),
            URLQueryItem(name: "minBuySharePct", value: String(minBuySharePct)),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(ScreenerResponse.self, from: data)
    }

    struct MemeScanItem: Codable {
        var chain: String?
        var address: String?
        var name: String?
        var symbol: String?
        var priceUsd: Double?
        var priceChange24hPct: Double?
        var priceChange24hReliable: Bool?
        var volume24hUsd: Double?
        var liquidityUsd: Double?
        var liquidityTier: String?
        var buySharePct: Double?
        var txnSpike: Bool?
        var holders: Int?
        var topHoldersPct: Double?
        var honeypot: Bool?
        var securityRisk: String?
        var washSignal: String?
        var xSearch: String?
    }

    struct MemeScanResponse: Codable {
        var items: [MemeScanItem]?
        var invalid: [String]?
        var note: String?
        var error: String?
    }

    struct TopicItem: Codable {
        var source: String?
        var name: String?
        var symbol: String?
        var chain: String?
        var tokenAddress: String?
        var url: String?
        var description: String?
    }

    struct TopicWatchResponse: Codable {
        var keyword: String?
        var topics: [TopicItem]?
        var note: String?
        var error: String?
    }

    struct RadarResponse: Codable {
        var chain: String?
        var newPools: [NewPool]?
        var geckoStatus: Int?
        var dexStatus: Int?
        var upstreamEmpty: Bool?
        var note: String?
        var error: String?
    }

    struct WalletProfileCounterparty: Codable {
        var counterparty: String?
        var count: Int?
        var entityTag: String?
        var isContract: Bool?
        var assetCount: Int?
    }

    struct WalletProfileResponse: Codable {
        var chain: String?
        var wallet: String?
        var transfersAnalyzed: Int?
        var uniqueCounterparties: Int?
        var uniqueTokens: Int?
        var activityDays: Double?
        var truncated: Bool?
        var topCounterparties: [WalletProfileCounterparty]?
        var note: String?
        var error: String?
    }

    static func fetchMemeScan(tokens: String) async throws -> MemeScanResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/meme-scan"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "tokens", value: tokens), URLQueryItem(name: "fresh", value: "1")]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(MemeScanResponse.self, from: data)
    }

    static func fetchTopicWatch(keyword: String, chain: Chain? = nil) async throws -> TopicWatchResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/topic-watch"), resolvingAgainstBaseURL: false)!
        var qs = [URLQueryItem(name: "keyword", value: keyword)]
        if let c = chain { qs.append(URLQueryItem(name: "chain", value: c.rawValue)) }
        components.queryItems = qs
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(TopicWatchResponse.self, from: data)
    }

    static func fetchMemeRadar(chain: Chain) async throws -> RadarResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/meme-radar"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "chain", value: chain.rawValue)]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(RadarResponse.self, from: data)
    }

    struct WalletAnalysisResponse: Codable {
        var chain: String?
        var wallet: String?
        var transfersAnalyzed: Int?
        var transfersIn: Int?
        var transfersOut: Int?
        var tokensTraded: Int?
        var roundTripTokens: Int?
        var avgHoldingDays: Double?
        var activityDays: Double?
        var score: Int?
        var truncated: Bool?
        var note: String?
        var error: String?
    }

    static func fetchWalletAnalysis(chain: Chain, wallet: String) async throws -> WalletAnalysisResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/wallet-analysis"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "chain", value: chain.rawValue), URLQueryItem(name: "wallet", value: wallet.trimmingCharacters(in: .whitespacesAndNewlines))]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(WalletAnalysisResponse.self, from: data)
    }

    static func fetchWalletProfile(chain: Chain, wallet: String) async throws -> WalletProfileResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/wallet-profile"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "chain", value: chain.rawValue), URLQueryItem(name: "wallet", value: wallet.trimmingCharacters(in: .whitespacesAndNewlines))]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(WalletProfileResponse.self, from: data)
    }

    struct SolActivityItem: Codable {
        var signature: String?
        var blockTime: Int?
        var err: String?
    }

    struct SolActivityResponse: Codable {
        var wallet: String?
        var solBalance: Double?
        var items: [SolActivityItem]?
        var note: String?
        var error: String?
    }

    struct SmartScoreResponse: Codable {
        var score: Int?
        var tokensTraded: Int?
        var roundTripTokens: Int?
        var avgHoldingDays: Double?
        var truncated: Bool?
        var note: String?
        var error: String?
    }

    struct LifecycleResponse: Codable {
        var symbol: String?
        var ageDays: Double?
        var stage: String?
        var dailyReport: String?
        var note: String?
        var error: String?
    }

    struct SocialWatchResponse: Codable {
        var keyword: String?
        var sentiment: Double?
        var note: String?
        var error: String?
    }

    static func fetchSolActivity(wallet: String) async throws -> SolActivityResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/sol-wallet-activity"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "wallet", value: wallet.trimmingCharacters(in: .whitespacesAndNewlines)), URLQueryItem(name: "limit", value: "10")]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(SolActivityResponse.self, from: data)
    }

    static func fetchSmartScore(chain: Chain, wallet: String) async throws -> SmartScoreResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/smart-score"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "chain", value: chain.rawValue), URLQueryItem(name: "wallet", value: wallet.trimmingCharacters(in: .whitespacesAndNewlines))]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(SmartScoreResponse.self, from: data)
    }

    static func fetchLifecycle(chain: Chain, address: String) async throws -> LifecycleResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/token-lifecycle"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "chain", value: chain.rawValue), URLQueryItem(name: "address", value: address.trimmingCharacters(in: .whitespacesAndNewlines))]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(LifecycleResponse.self, from: data)
    }

    struct FeedbackResponse: Codable {
        var stored: Bool?
        var id: String?
        var error: String?
        var note: String?
    }

    struct WosCode: Codable {
        var code: String?
        var status: String?
        var rewards: String?
        var note: String?
    }

    struct WosCodesResponse: Codable {
        var redeemUrl: String?
        var source: String?
        var codes: [WosCode]?
        var note: String?
    }

    static func sendFeedback(type: String, text: String, imageDataUrl: String?) async throws -> FeedbackResponse {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/feedback"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["type": type, "text": text, "platform": "iOS App"]
        if let img = imageDataUrl { body["imageDataUrl"] = img }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(FeedbackResponse.self, from: data)
    }

    static func fetchWosCodes() async throws -> WosCodesResponse {
        let (data, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("api/wos-codes"))
        return try JSONDecoder().decode(WosCodesResponse.self, from: data)
    }

    static func fetchSocialWatch(keyword: String, coin: String? = nil) async throws -> SocialWatchResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/social-watch"), resolvingAgainstBaseURL: false)!
        var qs = [URLQueryItem(name: "keyword", value: keyword)]
        if let c = coin { qs.append(URLQueryItem(name: "coin", value: c)) }
        components.queryItems = qs
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(SocialWatchResponse.self, from: data)
    }

    struct StrategyLabResponse: Codable {
        var chain: String?; var address: String?; var symbol: String?; var priceUsd: Double?; var liquidityUsd: Double?; var volume24hUsd: Double?; var buyShare24hPct: Double?; var poolAgeDays: Double?; var pairCount: Int?
        var rules: [LabRule]?; var grid: [GridLevel]?; var dcaExample: DcaExample?; var backtest: BacktestInfo?; var note: String?; var error: String?
        struct LabRule: Codable { var name: String?; var pass: Bool?; var value: Double?; var threshold: Double? }
        struct GridLevel: Codable { var pct: Int?; var priceUsd: Double? }
        struct DcaExample: Codable { var amountUsd: Double?; var tokensAtCurrentPrice: Double? }
        struct BacktestInfo: Codable { var available: Bool?; var reason: String? }
    }
    struct ArbResponse: Codable { var mode: String?; var symbol: String?; var prices: [String: Double]?; var spreadPct: Double?; var note: String? }
    struct AgentsResponse: Codable {
        var chain: String?; var address: String?; var symbol: String?; var consensus: String?
        var roles: Roles?
        struct Roles: Codable { var technical: Role?; var fundamental: Role?; var risk: Role?
            struct Role: Codable { var conclusion: String?; var note: String? } }
    }
    static func fetchStrategyLab(chain: Chain, address: String) async throws -> StrategyLabResponse {
        var c = URLComponents(url: baseURL.appendingPathComponent("api/strategy-lab"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "chain", value: chain.rawValue), URLQueryItem(name: "address", value: address.trimmingCharacters(in: .whitespacesAndNewlines))]
        let (d, _) = try await URLSession.shared.data(from: c.url!); return try JSONDecoder().decode(StrategyLabResponse.self, from: d)
    }
    static func fetchArb(chain: Chain, address: String) async throws -> ArbResponse {
        var c = URLComponents(url: baseURL.appendingPathComponent("api/arb-check"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "chain", value: chain.rawValue), URLQueryItem(name: "address", value: address.trimmingCharacters(in: .whitespacesAndNewlines))]
        let (d, _) = try await URLSession.shared.data(from: c.url!); return try JSONDecoder().decode(ArbResponse.self, from: d)
    }
    static func fetchArbSymbol(symbol: String) async throws -> ArbResponse {
        var c = URLComponents(url: baseURL.appendingPathComponent("api/arb-check"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "symbol", value: symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())]
        let (d, _) = try await URLSession.shared.data(from: c.url!); return try JSONDecoder().decode(ArbResponse.self, from: d)
    }
    static func fetchAgents(chain: Chain, address: String) async throws -> AgentsResponse {
        var c = URLComponents(url: baseURL.appendingPathComponent("api/agents"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "chain", value: chain.rawValue), URLQueryItem(name: "address", value: address.trimmingCharacters(in: .whitespacesAndNewlines))]
        let (d, _) = try await URLSession.shared.data(from: c.url!); return try JSONDecoder().decode(AgentsResponse.self, from: d)
    }
}
