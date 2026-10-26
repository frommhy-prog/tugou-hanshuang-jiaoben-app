import Foundation

// 链：首批 BSC / ETH / Base / Solana / Robinhood，不按链重做一套。
enum Chain: String, CaseIterable, Codable, Identifiable {
    case bsc, eth, base, solana, robinhood
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .bsc: return "BSC"
        case .eth: return "ETH"
        case .base: return "Base"
        case .solana: return "Solana"
        case .robinhood: return "Robinhood"
        }
    }
    var isEVM: Bool { self != .solana }
    var chainId: Int? { self == .robinhood ? 4663 : nil }
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
