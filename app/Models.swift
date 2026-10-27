import Foundation

// 链：与 Worker CHAINS 对齐的 8 条链，不按链重做一套。
enum Chain: String, CaseIterable, Codable, Identifiable {
    case bsc, eth, base, solana, robinhood, arbitrum, optimism, polygon, okc, xlayer
    var id: String { rawValue }
    var displayName: String {
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
    var chainId: Int? { switch self { case .robinhood: return 4663; case .arbitrum: return 42161; case .optimism: return 10; case .polygon: return 137; case .okc: return 66; case .xlayer: return 196; default: return nil } }
}

// 钱包：只存公开地址 + 链 + 备注名，绝不存私钥。
// 钱包经常换，所以是用户在 App 内随时增删改的列表，不是写死的配置。
struct WalletAccount: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var chain: Chain
    var address: String
    var label: String
}

struct TokenCheck: Codable {
    var chain: String
    var address: String
    var priceUsd: Double?
    var liquidityUsd: Double?
    var volume24hUsd: Double?
    var priceChange24hPct: Double?
    var risk: String?
    var riskSource: String?
}
