import SwiftUI

// MARK: - 钱包持仓：代币图标 + 链角标；空投垃圾币（名字里带网址 / 领奖词）自动隐藏
enum GXSpam {
    static func looks(_ h: PortfolioHolding) -> Bool {
        if (h.usd ?? 0) >= 100 { return false }
        let s: String = ((h.symbol ?? "") + " " + (h.name ?? "")).lowercased()
        let pat: String = #"[a-z0-9\-]+\.(top|com|net|org|xyz|io|app|vip|cc|me|co|site|fun|club|finance|fi|live|pro|info|online|cfd|today)\b"#
        if s.range(of: pat, options: .regularExpression) != nil { return true }
        for k in ["http", "t.me", "claim", "visit", "voucher", "airdrop", "reward"] where s.contains(k) { return true }
        return false
    }
}

struct GXHoldIcon: View {
    let h: PortfolioHolding

    var body: some View {
        let ch: Chain? = Chain(rawValue: h.chain ?? "")
        let addr: String = h.address ?? ""
        let native: Bool = (h.kind ?? "") == "native" || addr.count < 10
        ZStack(alignment: .bottomTrailing) {
            if let c = ch {
                if native {
                    let base: Chain = (c == .robinhood || c == .base || c == .arbitrum || c == .optimism) ? Chain.eth : c
                    AvChainBadge(chain: base, size: 30)
                } else {
                    AvTokenLogo(chain: c, address: addr, symbol: h.symbol ?? "?", hint: nil, size: 30)
                }
                AvChainBadge(chain: c, size: 13).offset(x: 3, y: 3)
            } else {
                Circle().fill(Color.secondary.opacity(0.2)).frame(width: 30, height: 30)
            }
        }
        .frame(width: 33, height: 33)
    }
}
