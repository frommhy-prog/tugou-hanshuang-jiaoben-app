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

// 刷新提示规则（用户定：解决了就不显示）：
// - 手动触发：剩余秒数 > 0 才弹确认框，剩余 = 0 直接查，不弹框。
// - 自动显示：数据新鲜（10 秒内）不显示；过期/旧价才显示“几秒前的数据，几秒后刷新”。
// - 时间戳是毫秒级（Worker fetchedAt 为毫秒时间戳），年龄显示到毫秒后 3 位小数，即 12.345 秒这种精度。
enum RefreshInfo {
    static func remainingSec(lastFetchAt: Date?, minIntervalSec: Int, now: Date = Date()) -> Int {
        guard let last = lastFetchAt else { return 0 }
        let elapsed = Int(now.timeIntervalSince(last))
        return max(0, minIntervalSec - elapsed)
    }

    static func ageText(fetchedAtMs: Int?, cacheTtlSec: Int?, now: Date = Date()) -> String? {
        guard let ms = fetchedAtMs else { return nil }
        let ageMs = now.timeIntervalSince1970 * 1000 - Double(ms)
        if ageMs < 10000 { return nil }
        let ageSec = ageMs / 1000
        let ageStr = String(format: "%.3f", ageSec)
        guard let ttl = cacheTtlSec else { return "当前显示的是 \(ageStr) 秒前的数据" }
        let remaining = ttl - Int(ageSec)
        if remaining <= 0 { return "当前显示的是 \(ageStr) 秒前的数据，已过期，点刷新拿新数据" }
        return "当前显示的是 \(ageStr) 秒前的数据，\(remaining) 秒后刷新"
    }

    // 输入自动识别：Solana 是 Base58（32–44 位，不含 0x），EVM 是 0x + 40 位。
    // EVM 合约和钱包在格式上完全一样，单看地址分不出来，只能靠输入框的上下文（体检框 = 合约，钱包框 = 钱包）或链上 code 判断，
    // 所以这里只做链的自动切换（贴 Solana 地址自动切到 Solana），不冒充能区分合约还是钱包。
    static func autoChain(for input: String, current: Chain) -> Chain {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if WalletStore.isValidAddress(chain: .solana, address: t) { return .solana }
        return current
    }
}
