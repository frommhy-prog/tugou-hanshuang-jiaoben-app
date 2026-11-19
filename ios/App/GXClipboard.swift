import SwiftUI
import UIKit

// MARK: - 进入 App 自动检测剪贴板里的代币合约 / 钱包地址（和 Ave 一样弹卡片）
struct GXClipCard: Identifiable {
    let id = UUID()
    let addr: String
    var isToken: Bool
    var chain: Chain
    var symbol: String = ""
    var name: String = ""
    var price: Double?
    var change: Double?
    var liq: Double?
    var vol: Double?
    var logo: String?
    var pair: String?
}

@MainActor
final class GXClip: ObservableObject {
    static let shared = GXClip()
    @Published var card: GXClipCard?
    private var lastCount: Int = -1
    private var lastShown: String = ""

    // 本 App 自己复制地址时调用，避免回到前台又弹出来
    func mute() { lastCount = UIPasteboard.general.changeCount }

    static func extract(_ s: String) -> String? {
        let t: String = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.count > 400 { return nil }
        if let r = t.range(of: "0x[0-9a-fA-F]{40}", options: .regularExpression) { return String(t[r]) }
        if let r = t.range(of: "[1-9A-HJ-NP-Za-km-z]{32,44}", options: .regularExpression) {
            let c: String = String(t[r])
            if Addr.isSolana(c) { return c }
        }
        return nil
    }

    static func chainFor(_ dexId: String) -> Chain {
        let all: [Chain] = [.solana, .eth, .bsc, .base, .arbitrum, .optimism, .polygon, .robinhood, .okc, .xlayer]
        return all.first(where: { $0.dexId == dexId }) ?? .eth
    }

    func check() async {
        if (Cfg.defaults.object(forKey: "gxClip") as? Bool) == false { return }
        let pb = UIPasteboard.general
        let cc: Int = pb.changeCount
        if cc == lastCount { return }
        guard pb.hasStrings else { lastCount = cc; return }
        guard let raw = pb.string else { return }
        lastCount = cc
        guard let addr = Self.extract(raw) else { return }
        let low: String = addr.lowercased()
        if low == UTokenVM.shared.address.lowercased() && UTokenVM.shared.main != nil { return }
        if low == lastShown { return }
        guard let c = await lookup(addr) else { return }
        lastShown = low
        card = c
    }

    private func lookup(_ addr: String) async -> GXClipCard? {
        let isEVM: Bool = Addr.isEVM(addr)
        let isSol: Bool = !isEVM && Addr.isSolana(addr)
        if !isEVM && !isSol { return nil }
        let wChain: Chain = isEVM ? .eth : .solana
        if let o = await GXNet.json("https://api.dexscreener.com/latest/dex/tokens/" + addr) as? [String: Any], let ps = o["pairs"] as? [[String: Any]], !ps.isEmpty {
            var best: [String: Any]? = nil
            var bl: Double = -1
            for p in ps {
                let ba: String = ((p["baseToken"] as? [String: Any])?["address"] as? String) ?? ""
                if ba.lowercased() != addr.lowercased() { continue }
                let l: Double = gmNum((p["liquidity"] as? [String: Any])?["usd"]) ?? 0
                if l > bl { bl = l; best = p }
            }
            if let p = best {
                let bt: [String: Any] = (p["baseToken"] as? [String: Any]) ?? [:]
                var c = GXClipCard(addr: addr, isToken: true, chain: Self.chainFor((p["chainId"] as? String) ?? ""))
                c.symbol = (bt["symbol"] as? String) ?? ""
                c.name = (bt["name"] as? String) ?? ""
                c.price = gmNum(p["priceUsd"])
                c.change = gmNum((p["priceChange"] as? [String: Any])?["h24"])
                c.liq = gmNum((p["liquidity"] as? [String: Any])?["usd"])
                c.vol = gmNum((p["volume"] as? [String: Any])?["h24"])
                c.logo = ((p["info"] as? [String: Any])?["imageUrl"] as? String)
                c.pair = p["pairAddress"] as? String
                return c
            }
        }
        return GXClipCard(addr: addr, isToken: false, chain: wChain)
    }
}

struct GXClipSheet: View {
    let card: GXClipCard
    @Environment(\.dismiss) private var dismiss
    @State private var showWallet = false

    private func stat(_ t: String, _ v: String) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.title3.weight(.bold).monospacedDigit())
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var tokenBody: some View {
        HStack(spacing: 12) {
            AvTokenLogo(chain: card.chain, address: card.addr, symbol: card.symbol, hint: card.logo, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(card.symbol).font(.title3.bold())
                    Text(card.chain.title).font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 2).background(Color.blue.opacity(0.15), in: Capsule()).foregroundStyle(Color.blue)
                }
                Text(Addr.short(card.addr)).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(GMPx.tp(card.price)).font(.headline.monospacedDigit())
                if let c = card.change {
                    Text(String(format: "%+.2f%%", c)).font(.caption.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 3)
                        .background((c >= 0 ? Color.green : Color.red).opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(c >= 0 ? Color.green : Color.red)
                }
            }
        }
        HStack {
            stat("流动性", GMPx.fiat(card.liq))
            stat("24h成交额", GMPx.fiat(card.vol))
        }
        Button {
            UTokenVM.shared.start(card.addr)
            AppRouter.shared.tab = 0
            dismiss()
        } label: {
            Text("去分析").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        GXAppIcons(chain: card.chain, addr: card.addr, pair: card.pair, size: 30)
    }

    @ViewBuilder
    private var walletBody: some View {
        HStack(spacing: 12) {
            AvWalletIcon(address: card.addr, chain: card.chain, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("钱包地址").font(.title3.bold())
                Text(Addr.short(card.addr)).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
        }
        Text("没有任何交易对用这个地址当代币，判断为钱包地址。").font(.footnote).foregroundStyle(.secondary)
        Button { showWallet = true } label: {
            Text("查看钱包标签与情报").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        GXAppIcons(chain: card.chain, addr: card.addr, wallet: true, size: 30)
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("检测到剪贴板内容").font(.headline).padding(.top, 18)
            if card.isToken { tokenBody } else { walletBody }
            Button("忽略") { dismiss() }.font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.height(card.isToken ? 380 : 340), .large])
        .sheet(isPresented: $showWallet) { GXWalletSheet(chain: card.chain, addr: card.addr) }
    }
}
