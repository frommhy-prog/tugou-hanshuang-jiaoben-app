import SwiftUI
import UIKit

// MARK: - 链徽标：所有支持的链都有颜色和字符（没有各链官方 logo 资源，用自绘徽标）
extension Chain {
    var avColor: Color {
        switch self {
        case .solana: return Color(red: 0.55, green: 0.36, blue: 0.96)
        case .eth: return Color(red: 0.38, green: 0.49, blue: 0.92)
        case .bsc: return Color(red: 0.95, green: 0.73, blue: 0.07)
        case .base: return Color(red: 0.0, green: 0.32, blue: 1.0)
        case .arbitrum: return Color(red: 0.16, green: 0.63, blue: 0.93)
        case .optimism: return Color(red: 1.0, green: 0.02, blue: 0.13)
        case .polygon: return Color(red: 0.51, green: 0.28, blue: 0.9)
        case .robinhood: return Color(red: 0.0, green: 0.7, blue: 0.2)
        case .okc: return Color(red: 0.15, green: 0.15, blue: 0.18)
        case .xlayer: return Color(red: 0.25, green: 0.25, blue: 0.3)
        }
    }

    var avGlyph: String {
        switch self {
        case .solana: return "S"
        case .eth: return "Ξ"
        case .bsc: return "B"
        case .base: return "b"
        case .arbitrum: return "A"
        case .optimism: return "O"
        case .polygon: return "P"
        case .robinhood: return "R"
        case .okc: return "K"
        case .xlayer: return "X"
        }
    }
}

enum AvPalette {
    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    static func color(_ h: UInt64, _ shift: UInt64) -> Color {
        let hue = Double((h >> shift) % 360) / 360.0
        return Color(hue: hue, saturation: 0.62, brightness: 0.86)
    }

    static func pair(_ s: String) -> (Color, Color) {
        let h = hash(s.lowercased())
        return (color(h, 0), color(h, 17))
    }
}

// MARK: - 币头像：多来源兜底 + 内存/磁盘缓存（Dexscreener 资料 → Dexscreener 图床 → GeckoTerminal 代币信息）
@MainActor
final class AvLogoStore {
    static let shared = AvLogoStore()
    private let mem = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private var dead: [String: Date] = [:]

    private var dir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("AvLogos", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func file(_ key: String) -> URL { dir.appendingPathComponent(String(AvPalette.hash(key), radix: 16)) }

    func tokenImage(key: String, chain: Chain?, address: String, hint: String?) async -> UIImage? {
        if let i = mem.object(forKey: key as NSString) { return i }
        if let d = try? Data(contentsOf: file(key)), let i = UIImage(data: d) {
            mem.setObject(i, forKey: key as NSString)
            return i
        }
        if let t = dead[key], Date().timeIntervalSince(t) < 600 { return nil }
        if let t = inflight[key] { return await t.value }
        let task = Task { await self.fetchToken(key: key, chain: chain, address: address, hint: hint) }
        inflight[key] = task
        let r = await task.value
        inflight[key] = nil
        if let img = r { mem.setObject(img, forKey: key as NSString) } else { dead[key] = Date() }
        return r
    }

    private func fetchToken(key: String, chain: Chain?, address: String, hint: String?) async -> UIImage? {
        var first: [String] = []
        if let h = hint, h.hasPrefix("http") { first.append(h) }
        let isEvm = chain?.isEVM ?? false
        let a = isEvm ? address.lowercased() : address
        let cid = chain?.dexId ?? "solana"
        first.append("https://dd.dexscreener.com/ds-data/tokens/" + cid + "/" + a + ".png")
        if let r = await download(first) {
            save(key, r.1)
            return r.0
        }
        if let c = chain, let u = await geckoLogo(c, address), let r = await download([u]) {
            save(key, r.1)
            return r.0
        }
        return nil
    }

    private func geckoLogo(_ chain: Chain, _ address: String) async -> String? {
        guard let url = URL(string: "https://api.geckoterminal.com/api/v2/networks/" + chain.geckoId + "/tokens/" + address + "/info") else { return nil }
        guard let r = try? await URLSession.shared.data(from: url) else { return nil }
        guard let o = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any] else { return nil }
        let data = o["data"] as? [String: Any]
        let attrs = data?["attributes"] as? [String: Any]
        guard let u = attrs?["image_url"] as? String, u.hasPrefix("http"), !u.contains("missing") else { return nil }
        return u
    }

    private func download(_ urls: [String]) async -> (UIImage, Data)? {
        for s in urls {
            guard let u = URL(string: s) else { continue }
            var req = URLRequest(url: u, timeoutInterval: 10)
            req.setValue("image/*", forHTTPHeaderField: "Accept")
            guard let r = try? await URLSession.shared.data(for: req) else { continue }
            let code = (r.1 as? HTTPURLResponse)?.statusCode ?? 0
            if code != 200 || r.0.count < 64 { continue }
            if let img = UIImage(data: r.0) { return (img, r.0) }
        }
        return nil
    }

    private func save(_ key: String, _ data: Data) { try? data.write(to: file(key)) }
}

struct AvChainBadge: View {
    let chain: Chain
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().fill(chain.avColor)
            Text(chain.avGlyph)
                .font(.system(size: size * 0.58, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.card, lineWidth: 1.5))
    }
}

struct AvTokenLogo: View {
    var chain: Chain?
    var address: String
    var symbol: String
    var hint: String? = nil
    var size: CGFloat = 40
    var badge: Bool = true
    @State private var img: UIImage?

    private var taskKey: String { (chain?.rawValue ?? "") + ":" + address + ":" + (hint ?? "") }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatar
                .frame(width: size, height: size)
                .clipShape(Circle())
            if badge, let c = chain {
                AvChainBadge(chain: c, size: max(13, size * 0.38))
                    .offset(x: size * 0.1, y: size * 0.1)
            }
        }
        .frame(width: size, height: size)
        .task(id: taskKey) { await load() }
    }

    @ViewBuilder
    private var avatar: some View {
        if let i = img {
            Image(uiImage: i).resizable().scaledToFill()
        } else {
            fallback
        }
    }

    private var fallback: some View {
        let g = AvPalette.pair(address.isEmpty ? symbol : address)
        return ZStack {
            LinearGradient(colors: [g.0, g.1], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(String(symbol.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
        }
    }

    private func load() async {
        if address.isEmpty { return }
        let k = (chain?.rawValue ?? "x") + ":" + address.lowercased()
        img = await AvLogoStore.shared.tokenImage(key: k, chain: chain, address: address, hint: hint)
    }
}

// 钱包没有官方头像：按地址生成固定的渐变 + 对称方块图案，同一地址永远是同一个头像
struct AvBlocks: View {
    let seed: String
    let size: CGFloat

    private func on(_ r: Int, _ c: Int) -> Bool {
        let h = AvPalette.hash(seed.lowercased())
        let cc = c < 3 ? c : 4 - c
        let shift = UInt64(r * 3 + cc)
        return ((h >> shift) & 1) == 1
    }

    var body: some View {
        let cell = size * 0.15
        return VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { c in
                        Rectangle()
                            .fill(on(r, c) ? Color.white.opacity(0.85) : Color.clear)
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }
}

struct AvWalletIcon: View {
    var address: String
    var chain: Chain? = nil
    var size: CGFloat = 36

    private var badgeChain: Chain { chain ?? (Addr.isEVM(address) ? Chain.eth : Chain.solana) }

    var body: some View {
        let g = AvPalette.pair(address)
        return ZStack(alignment: .bottomTrailing) {
            ZStack {
                LinearGradient(colors: [g.0, g.1], startPoint: .topLeading, endPoint: .bottomTrailing)
                AvBlocks(seed: address, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            AvChainBadge(chain: badgeChain, size: max(12, size * 0.36))
                .offset(x: size * 0.1, y: size * 0.1)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 查询记录：币用币头像，钱包用钱包头像
struct AvHistoryIcon: View {
    let h: HistoryItem
    var size: CGFloat = 40

    var body: some View {
        if h.kind == "wallet" {
            AvWalletIcon(address: h.address, chain: nil, size: size)
        } else {
            AvTokenLogo(chain: Chain(rawValue: h.chain), address: h.address, symbol: h.title, hint: h.logo, size: size)
        }
    }
}

// 横向一行头像条：占一行高度，替代原来的长列表
struct AvRecentStrip: View {
    let items: [HistoryItem]
    let onPick: (HistoryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近查询").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(items) { h in
                        Button { onPick(h) } label: {
                            VStack(spacing: 4) {
                                AvHistoryIcon(h: h, size: 44)
                                Text(h.title).font(.caption2).lineLimit(1).frame(width: 56)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// 完整记录弹层：可搜索、左滑删除、一键清空
struct AvHistorySheet: View {
    let kind: String
    let onPick: (HistoryItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [HistoryItem] = []
    @State private var q = ""

    private var shown: [HistoryItem] {
        if q.isEmpty { return items }
        let k = q.lowercased()
        return items.filter { ($0.title + " " + $0.address).lowercased().contains(k) }
    }

    private func reload() { items = QueryHistory.items.filter { $0.kind == kind } }

    private func row(_ h: HistoryItem) -> some View {
        HStack(spacing: 12) {
            AvHistoryIcon(h: h, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(h.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                Text(Addr.short(h.address)).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            Text(TZ.short(h.at)).font(.caption2).foregroundStyle(.secondary)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if shown.isEmpty { Text("没有记录").foregroundStyle(.secondary) }
                ForEach(shown) { h in
                    Button {
                        dismiss()
                        onPick(h)
                    } label: { row(h) }
                }
                .onDelete { idx in
                    let ids = idx.map { shown[$0].id }
                    for id in ids { QueryHistory.remove(id) }
                    reload()
                }
            }
            .searchable(text: $q, prompt: "搜索符号或地址")
            .navigationTitle("查询记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    if !items.isEmpty { Button("清空", role: .destructive) { QueryHistory.clear(kind: kind); reload() } }
                }
            }
            .onAppear { reload() }
        }
    }
}
