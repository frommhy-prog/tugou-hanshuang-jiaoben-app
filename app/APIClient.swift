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
    }

    struct TokenResponse: Codable {
        var chain: String
        var address: String
        var price: Price?
        var risk: String?
        var riskSource: String?
        var tradeLinks: TradeLinks?
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

    static func fetchHoldings(wallets: [WalletAccount]) async throws -> HoldingsResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/holdings"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(HoldingsRequest(wallets: wallets))
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(HoldingsResponse.self, from: data)
    }
}
