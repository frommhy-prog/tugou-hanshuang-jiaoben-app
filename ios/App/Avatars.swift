import SwiftUI
import UIKit

// MARK: - 头像体系：代币头像（多来源兜底 + 本地缓存 + 链徽章）、钱包头像（按地址生成）、查询记录条与记录面板

extension Chain {
    // 链徽章里的单字符标记
    var avMark: String {
        switch self {
        case .solana: return "◎"
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

    var avColors: [Color] {
        switch self {
        case .solana: return [Color(red: 0.60, green: 0.27, blue: 1.0), Color(red: 0.10, green: 0.80, blue: 0.60)]
        case .eth: return [Color(red: 0.42, green: 0.52, blue: 0.95), Color(red: 0.25, green: 0.30, blue: 0.62)]
        case .bsc: return [Color(red: 0.96, green: 0.74, blue: 0.06), Color(red: 0.80, green: 0.58, blue: 0.0)]
        case .base: return [Color(red: 0.10, green: 0.38, blue: 1.0), Color(red: 0.0, green: 0.22, blue: 0.80)]
        case .arbitrum: return [Color(red: 0.20, green: 0.58, blue: 0.88), Color(red: 0.10, green: 0.26, blue: 0.46)]
        case .optimism: return [Color(red: 1.0, green: 0.10, blue: 0.20), Color(red: 0.75, green: 0.0, blue: 0.10)]
        case .polygon: return [Color(red: 0.55, green: 0.32, blue: 0.92), Color(red: 0.35, green: 0.15, blue: 0.70)]
        case .robinhood: return [Color(red: 0.0, green: 0.78, blue: 0.25), Color(red: 0.0, green: 0.55, blue: 0.15)]
        case .okc: return [Color(red: 0.30, green: 0.30, blue: 0.32), Color(red: 0.08, green: 0.08, blue: 0.10)]
        case .xlayer: return [Color(red: 0.30, green: 0.30, blue: 0.34), Color(red: 0.0, green: 0.0, blue: 0.0)]
        }
    }
}

func avFNV(_ s: String) -> UInt64 {
    var h: UInt64 = 1469598103934665603
    for b in s.utf8 {
        h ^= UInt64(b)
        h = h &* 1099511628211
    }
    return h
}

// 钱包地址对应的链（EVM 取已勾选的第一条链，没有就用 ETH）
func avWalletChain(_ address: String, _ chains: [String]) -> Chain {
    if Addr.isSolana(address) && !Addr.isEVM(address) { return .solana }
    if let f = chains.first, let c = Chain(rawValue: f), c != .solana { return c }
    return .eth
}

struct AvChainBadge: View {
    let chain: Chain
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: chain.avColors, startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(chain.avMark)
                .font(.system(size: size * 0.58, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.card, lineWidth: 1.5))
    }
}

// 没有图片时的字母头像：颜色由地址决定，同一个币永远是同一个颜色
struct AvLetterDot: View {
    let text: String
    let seed: String
    var size: CGFloat = 40

    var body: some View {
        let hv = avFNV(seed.isEmpty ? text : seed)
        let hue1 = Double(hv % 360) / 360.0
        let hue2 = Double((hv / 360) % 360) / 360.0
        let c1 = Color(hue: hue1, saturation: 0.55, brightness: 0.85)
        let c2 = Color(hue: hue2, saturation: 0.60, brightness: 0.60)
        ZStack {
            Circle().fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(String(text.prefix(1)).uppercased())
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
    }
}

// GeckoTerminal 免费 30 次/分钟：头像兜底查询串行并拉开间隔
actor AvGeckoGate {
    static let shared = AvGeckoGate()
    private var next = Date.distantPast

    func slot() async {
        let now = Date()
        let at = max(now, next)
        next = at.addingTimeInterval(2.3)
        let wait = at.timeIntervalSince(now)
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
    }
}

// 头像缓存：内存 + 磁盘（Caches），失败 5 分钟内不重复请求
final class AvLogoStore: @unchecked Sendable {
    static let shared = AvLogoStore()
    private let mem = NSCache<NSString, UIImage>()
    private var failed: [String: Date] = [:]
    private let lock = NSLock()
    private let dir: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        dir = base.appendingPathComponent("avlogos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        mem.countLimit = 300
    }

    private func file(_ key: String) -> URL {
        var safe = ""
        for ch in key.prefix(120) { safe += (ch.isLetter || ch.isNumber) ? String(ch) : "_" }
        return dir.appendingPathComponent(safe + ".img")
    }

    func cached(_ key: String) -> UIImage? {
        if let i = mem.object(forKey: key as NSString) { return i }
        if let d = try? Data(contentsOf: file(key)), let i = UIImage(data: d) {
            mem.setObject(i, forKey: key as NSString)
            return i
        }
        return nil
    }

    private func recentlyFailed(_ k: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let t = failed[k] { return Date().timeIntervalSince(t) < 300 }
        return false
    }

    private func markFailed(_ k: String) {
        lock.lock()
        failed[k] = Date()
        lock.unlock()
    }

    private func save(_ key: String, _ data: Data, _ img: UIImage) {
        mem.setObject(img, forKey: key as NSString)
        try? data.write(to: file(key), options: .atomic)
    }

    private func fetch(_ s: String) async -> (UIImage, Data)? {
        guard let url = URL(string: s) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let r = try? await URLSession.shared.data(for: req) else { return nil }
        let code = (r.1 as? HTTPURLResponse)?.statusCode ?? 0
        if code != 200 || r.0.count < 100 { return nil }
        guard let img = UIImage(data: r.0) else { return nil }
        return (img, r.0)
    }

    private func geckoImage(_ c: Chain, _ addr: String) async -> String? {
        await AvGeckoGate.shared.slot()
        let u = "https://api.geckoterminal.com/api/v2/networks/" + c.geckoId + "/tokens/" + addr + "/info"
        guard let o = try? await MarketAPI.json(u) else { return nil }
        let data = (o as? [String: Any])?["data"] as? [String: Any]
        guard let a = data?["attributes"] as? [String: Any] else { return nil }
        guard let s = a["image_url"] as? String, s.hasPrefix("http"), !s.contains("missing") else { return nil }
        return s
    }

    // 来源顺序：已知链接 → Dexscreener 图片库 → GeckoTerminal 代币资料
    func load(key: String, chain: Chain?, address: String, hint: String?) async -> UIImage? {
        if let i = cached(key) { return i }
        let fk = key + "|" + (hint ?? "")
        if recentlyFailed(fk) { return nil }
        var urls: [String] = []
        if let h = hint, h.hasPrefix("http") { urls.append(h) }
        let cid = chain?.dexId ?? "solana"
        let path = (chain?.isEVM ?? false) ? address.lowercased() : address
        urls.append("https://dd.dexscreener.com/ds-data/tokens/" + cid + "/" + path + ".png")
        for u in urls {
            if let r = await fetch(u) {
                save(key, r.1, r.0)
                return r.0
            }
        }
        if let c = chain, let g = await geckoImage(c, address), let r = await fetch(g) {
            save(key, r.1, r.0)
            return r.0
        }
        markFailed(fk)
        return nil
    }
}

// 代币头像：真实图片优先，加载失败退回字母头像；右下角是链徽章
struct AvTokenLogo: View {
    let chain: Chain?
    let address: String
    let symbol: String
    var hint: String? = nil
    var size: CGFloat = 40
    var badge: Bool = true
    @State private var img: UIImage?

    private var key: String { (chain?.rawValue ?? "?") + ":" + address.lowercased() }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatar
            if badge, let c = chain {
                AvChainBadge(chain: c, size: max(12, size * 0.38))
                    .offset(x: size * 0.08, y: size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .task(id: key + "|" + (hint ?? "")) { await resolve() }
    }

    @ViewBuilder
    private var avatar: some View {
        if let i = img {
            Image(uiImage: i)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            AvLetterDot(text: symbol, seed: address, size: size)
        }
    }

    private func resolve() async {
        if let c = AvLogoStore.shared.cached(key) {
            img = c
            return
        }
        let r = await AvLogoStore.shared.load(key: key, chain: chain, address: address, hint: hint)
        if let r = r { img = r }
    }
}

// 钱包头像：按地址生成的 5×5 对称像素图，同一个地址永远是同一个头像
struct AvWalletIcon: View {
    let address: String
    var chain: Chain? = nil
    var size: CGFloat = 40

    private func cells(_ hv: UInt64) -> [Bool] {
        var out = [Bool](repeating: false, count: 25)
        for r in 0..<5 {
            for c in 0..<3 {
                let bit = (hv >> UInt64(r * 3 + c + 8)) & 1
                let on = bit == 1
                out[r * 5 + c] = on
                out[r * 5 + (4 - c)] = on
            }
        }
        return out
    }

    var body: some View {
        let hv = avFNV(address.lowercased())
        let hue = Double(hv % 360) / 360.0
        let fg = Color(hue: hue, saturation: 0.65, brightness: 0.92)
        let bg = Color(hue: hue, saturation: 0.30, brightness: 0.28)
        let cs = cells(hv)
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(bg)
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<5, id: \.self) { c in
                                Rectangle().fill(cs[r * 5 + c] ? fg : Color.clear)
                            }
                        }
                    }
                }
                .frame(width: size * 0.6, height: size * 0.6)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            if let c = chain {
                AvChainBadge(chain: c, size: max(12, size * 0.38))
                    .offset(x: size * 0.08, y: size * 0.08)
            }
        }
        .frame(width: size, height: size)
    }
}

struct AvHistoryAvatar: View {
    let item: HistoryItem
    var size: CGFloat = 40

    var body: some View {
        if item.kind == "token" {
            AvTokenLogo(chain: Chain(rawValue: item.chain), address: item.address, symbol: item.title, hint: item.logo, size: size)
        } else {
            AvWalletIcon(address: item.address, chain: item.chain == "solana" ? Chain.solana : Chain.eth, size: size)
        }
    }
}

// 横向一行头像条：只占约 70pt 高，替代原来的长列表
struct AvRecentStrip: View {
    let items: [HistoryItem]
    var showTitle: Bool = true
    let onPick: (HistoryItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showTitle { Text("最近查询").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(items) { h in
                        Button { onPick(h) } label: {
                            VStack(spacing: 4) {
                                AvHistoryAvatar(item: h, size: 42)
                                Text(h.title)
                                    .font(.caption2)
                                    .foregroundStyle(Color.primary)
                                    .lineLimit(1)
                                    .frame(width: 58)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 6)
            }
        }
    }
}

// 完整记录面板：搜索、点选、左滑删除、清空
struct AvHistorySheet: View {
    let kind: String
    let onPick: (HistoryItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [HistoryItem] = []
    @State private var q = ""

    private var shown: [HistoryItem] {
        let k = q.trimmingCharacters(in: .whitespaces).lowercased()
        if k.isEmpty { return items }
        return items.filter { $0.title.lowercased().contains(k) || $0.address.lowercased().contains(k) }
    }

    var body: some View {
        NavigationStack {
            List {
                if shown.isEmpty { Text("还没有查询记录").foregroundStyle(.secondary) }
                ForEach(shown) { h in
                    Button {
                        onPick(h)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            AvHistoryAvatar(item: h, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(h.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                                Text(Addr.short(h.address)).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(TZ.short(h.at)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    let ids = idx.map { shown[$0].id }
                    for id in ids { QueryHistory.remove(id) }
                    reload()
                }
            }
            .searchable(text: $q, prompt: "搜索币名或地址")
            .navigationTitle(kind == "token" ? "代币记录" : "地址记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("清空", role: .destructive) {
                        QueryHistory.clear(kind: kind)
                        reload()
                    }
                    .disabled(items.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .onAppear { reload() }
        }
        .presentationDetents([.medium, .large])
    }

    private func reload() { items = QueryHistory.items.filter { $0.kind == kind } }
}

// 代币页顶部：一行搜索栏（粘贴 / 清除 / 记录），不再占两行卡片
struct AvSearchBar: View {
    @ObservedObject var vm: UTokenVM
    @Binding var hist: [HistoryItem]
    @State private var showHist = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("粘贴代币合约（Solana / EVM 自动识别）", text: $vm.input)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.subheadline, design: .monospaced))
                .submitLabel(.search)
                .onSubmit { vm.start(vm.input) }
                .onChange(of: vm.input) { _, _ in vm.inputChanged() }
            if vm.input.isEmpty {
                Button {
                    if let s = UIPasteboard.general.string { vm.input = s }
                } label: {
                    Image(systemName: "doc.on.clipboard").foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Button { vm.input = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button {
                hist = QueryHistory.items.filter { $0.kind == "token" }
                showHist = true
            } label: {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .sheet(isPresented: $showHist) {
            AvHistorySheet(kind: "token") { h in vm.start(h.address) }
        }
    }
}
