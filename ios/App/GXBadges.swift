import SwiftUI

// MARK: - OG 判定：同链同名代币里最早创建、且有真实流动性的那一个
@MainActor
final class GXOG: ObservableObject {
    static let shared = GXOG()
    @Published var result: [String: Bool] = [:]
    @Published var note: [String: String] = [:]
    private var running: Set<String> = []

    static func key(_ chain: Chain, _ address: String) -> String { chain.rawValue + ":" + address.lowercased() }

    func check(chain: Chain, address: String, symbol: String) async {
        let k: String = Self.key(chain, address)
        if result[k] != nil || running.contains(k) || symbol.count < 2 { return }
        running.insert(k)
        defer { running.remove(k) }
        guard let q = symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return }
        guard let o = await GXNet.json("https://api.dexscreener.com/latest/dex/search?q=" + q) as? [String: Any], let pairs = o["pairs"] as? [[String: Any]] else { return }
        var created: [String: Double] = [:]
        var liq: [String: Double] = [:]
        for p in pairs {
            guard (p["chainId"] as? String) == chain.dexId, let bt = p["baseToken"] as? [String: Any], let sym = bt["symbol"] as? String, sym.lowercased() == symbol.lowercased(), let a = bt["address"] as? String else { continue }
            let id: String = a.lowercased()
            let c: Double = gmNum(p["pairCreatedAt"]) ?? Double.greatestFiniteMagnitude
            let l: Double = gmNum((p["liquidity"] as? [String: Any])?["usd"]) ?? 0
            created[id] = min(created[id] ?? Double.greatestFiniteMagnitude, c)
            liq[id] = max(liq[id] ?? 0, l)
        }
        let me: String = address.lowercased()
        guard let mine = created[me] else { return }
        let cands: [String] = created.keys.filter { $0 == me || (liq[$0] ?? 0) >= 2000 }
        let earliest: Double = cands.compactMap { created[$0] }.min() ?? mine
        let og: Bool = cands.count >= 3 && mine <= earliest && (liq[me] ?? 0) >= 2000
        result[k] = og
        note[k] = "同链同名 " + String(created.count) + " 个代币，这个创建最早"
    }
}

// MARK: - 股票币：xStocks（SPCXx / TSLAx …）和 Ondo 代币化股票（TSLAon …）
enum GXStock {
    static func isStock(_ s: String) -> Bool {
        if s.count < 3 || s.count > 9 { return false }
        for suf in ["x", "on"] where s.hasSuffix(suf) {
            let body: Substring = s.dropLast(suf.count)
            if body.count >= 2 && body.allSatisfy({ $0.isUppercase || $0.isNumber }) { return true }
        }
        return false
    }
}

struct GXBadgeRow: View {
    @ObservedObject var vm: UTokenVM
    let pair: DexPair
    @ObservedObject private var og = GXOG.shared

    private var key: String { GXOG.key(vm.chain, vm.address) }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t)
            .font(.system(size: 10, weight: .heavy))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(c.opacity(0.2), in: Capsule())
            .foregroundStyle(c)
    }

    var body: some View {
        let quote: String = pair.quoteToken?.symbol ?? ""
        let base: String = pair.baseToken?.symbol ?? vm.symbol
        HStack(spacing: 4) {
            if og.result[key] == true { chip("OG", Color.yellow) }
            if GXStock.isStock(quote) { chip("📈 股票对", Color.blue) }
            else if GXStock.isStock(base) { chip("📈 股票币", Color.blue) }
        }
        .task(id: key) { await og.check(chain: vm.chain, address: vm.address, symbol: base) }
    }
}

// MARK: - 顶部数据条的单个格子：紧凑图标版（和 Ave 一样一屏 7 个半）/ 文字版
struct GXChipView: View {
    let id: String
    let title: String
    let v: GMVal
    let compact: Bool

    private var shortText: String {
        switch id {
        case "dexpaid":
            if v.text == "已付费" { return "已付" }
            if v.text == "未付费" { return "未付" }
            return v.text
        default:
            return v.text
        }
    }

    var body: some View {
        if compact && v.text == "—" {
            EmptyView()
        } else if compact {
            HStack(spacing: 2) {
                if id == "dexpaid" {
                    GMBrandIcon(key: "dexscreener", size: 12)
                } else if GXAveGlyph.has(id) {
                    GXAveIcon(id: id, color: v.color, size: 13)
                } else if let em = GMTagIcon.metric(id) {
                    Text(em).font(.system(size: 11))
                } else {
                    Text(String(title.prefix(1))).font(.system(size: 10, weight: .bold)).foregroundStyle(Color.secondary)
                }
                Text(shortText)
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(v.color)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if id == "dexpaid" {
                    GMBrandIcon(key: "dexscreener", size: 12)
                } else if GXAveGlyph.has(id) {
                    GXAveIcon(id: id, color: v.color, size: 12)
                } else if let em = GMTagIcon.metric(id) {
                    Text(em).font(.system(size: 10))
                }
                Text(title).font(.system(size: 9.5)).foregroundStyle(Color.secondary)
                Text(v.text).font(.system(size: 11.5, weight: .bold)).foregroundStyle(v.color).lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

// MARK: - 头部下方的「具体叙事」一行（点开看完整项目资料）
struct GXNarrLine: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var info = GXInfoStore.shared
    @State private var open = false

    var body: some View {
        let t: String = info.line(vm: vm)
        Button { open = true } label: {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "text.quote")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.purple)
                    .padding(.top, 2)
                Text(t)
                    .font(.caption)
                    .foregroundStyle(Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) { GXTokenSheet(vm: vm) }
    }
}
