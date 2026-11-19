import SwiftUI
import UIKit

extension Notification.Name {
    static let gxAppsChanged = Notification.Name("gxAppsChanged")
}

struct GXLink: Identifiable {
    let app: GXApp
    let url: URL
    let copy: String?
    var id: String { app.rawValue }
}

// 可一键跳转的 App / 网站；设置 → 跳转 App 里逐个开关
enum GXApp: String, CaseIterable, Identifiable {
    case gmgn, ave, okx, binance, gate, kraken, fomo, birdeye, dexscreener, cielo, debank, scan, bubblemaps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gmgn: return "GMGN"
        case .ave: return "AVE"
        case .okx: return "欧易 OKX"
        case .binance: return "币安"
        case .gate: return "Gate"
        case .kraken: return "海妖 Kraken"
        case .fomo: return "FOMO"
        case .birdeye: return "Birdeye"
        case .dexscreener: return "Dexscreener"
        case .cielo: return "Cielo"
        case .debank: return "DeBank"
        case .scan: return "区块浏览器"
        case .bubblemaps: return "Bubblemaps"
        }
    }

    var note: String {
        switch self {
        case .gate, .kraken, .fomo: return "没有公开的代币页链接：点击先复制地址再打开官网 / App，到里面粘贴搜索"
        case .okx, .binance, .ave: return "按官网公开的链接格式拼接，个别链打不开请反馈"
        default: return ""
        }
    }

    func brand(_ chain: Chain) -> String {
        if self == .scan {
            switch chain {
            case .solana: return "solscan"
            case .bsc: return "bscscan"
            case .base: return "basescan"
            default: return "etherscan"
            }
        }
        return rawValue
    }

    var key: String { "gxApp." + rawValue }
    var enabled: Bool { (Cfg.defaults.object(forKey: key) as? Bool) ?? true }

    static func okxSlug(_ c: Chain) -> String? {
        switch c {
        case .solana: return "solana"
        case .eth: return "ethereum"
        case .bsc: return "bsc"
        case .base: return "base"
        case .arbitrum: return "arbitrum"
        case .optimism: return "optimism"
        case .polygon: return "polygon"
        case .xlayer: return "xlayer"
        default: return nil
        }
    }

    static func binSlug(_ c: Chain) -> String? {
        switch c {
        case .solana: return "sol"
        case .eth: return "eth"
        case .bsc: return "bsc"
        case .base: return "base"
        default: return nil
        }
    }

    static func bubbleSlug(_ c: Chain) -> String? {
        switch c {
        case .solana: return "sol"
        case .eth: return "eth"
        case .bsc: return "bsc"
        case .base: return "base"
        default: return nil
        }
    }

    static func aveChain(_ c: Chain) -> String { c == .eth ? "eth" : c.rawValue }

    static func tokenLinks(chain: Chain, addr: String, pair: String?, all: Bool = false) -> [GXLink] {
        var out: [GXLink] = []
        func add(_ a: GXApp, _ s: String, copy: Bool = false) {
            if !all && !a.enabled { return }
            if let u = URL(string: s) { out.append(GXLink(app: a, url: u, copy: copy ? addr : nil)) }
        }
        if let g = GMGNApi.code(chain) { add(.gmgn, "https://gmgn.ai/" + g + "/token/" + addr) }
        add(.ave, "https://ave.ai/token/" + addr + "-" + aveChain(chain))
        if let o = okxSlug(chain) { add(.okx, "https://web3.okx.com/token/" + o + "/" + addr) }
        if let b = binSlug(chain) { add(.binance, "https://web3.binance.com/zh-CN/token/" + b + "/" + addr) }
        add(.gate, "https://www.gate.com/web3", copy: true)
        add(.kraken, "https://www.kraken.com", copy: true)
        add(.fomo, "https://fomo.family", copy: true)
        add(.birdeye, "https://birdeye.so/token/" + addr + "?chain=" + chain.dexId)
        if let p = pair, !p.isEmpty { add(.dexscreener, "https://dexscreener.com/" + chain.dexId + "/" + p) }
        add(.scan, GFMap.es(chain) + "/token/" + addr)
        if let bm = bubbleSlug(chain) { add(.bubblemaps, "https://app.bubblemaps.io/" + bm + "/token/" + addr) }
        return out
    }

    static func walletLinks(chain: Chain, addr: String, all: Bool = false) -> [GXLink] {
        var out: [GXLink] = []
        func add(_ a: GXApp, _ s: String, copy: Bool = false) {
            if !all && !a.enabled { return }
            if let u = URL(string: s) { out.append(GXLink(app: a, url: u, copy: copy ? addr : nil)) }
        }
        if let g = GMGNApi.code(chain) { add(.gmgn, "https://gmgn.ai/" + g + "/address/" + addr) }
        add(.ave, "https://ave.ai/address/" + addr + "-" + aveChain(chain))
        if okxSlug(chain) != nil { add(.okx, "https://web3.okx.com/portfolio/" + addr) }
        add(.binance, "https://web3.binance.com/zh-CN", copy: true)
        add(.gate, "https://www.gate.com/web3", copy: true)
        add(.kraken, "https://www.kraken.com", copy: true)
        add(.fomo, "https://fomo.family", copy: true)
        if chain == .solana { add(.birdeye, "https://birdeye.so/profile/" + addr + "?chain=solana") }
        add(.cielo, "https://app.cielo.finance/profile/" + addr)
        if chain != .solana { add(.debank, "https://debank.com/profile/" + addr) }
        add(.scan, chain == .solana ? "https://solscan.io/account/" + addr : GFMap.es(chain) + "/address/" + addr)
        return out
    }

    @MainActor
    static func open(_ l: GXLink) {
        if let c = l.copy {
            UIPasteboard.general.string = c
            GXClip.shared.mute()
        }
        UIApplication.shared.open(l.url)
    }

    // 本地打包的图标（CI 从官方站点抓取）；没有就返回 nil
    static func localIcon(_ key: String) -> UIImage? { GMLogoFiles.bundle("gmb_" + key) }

    // 菜单里的小图标：原色，不被系统染成单色
    static func menuIcon(_ key: String) -> Image {
        guard let ui = localIcon(key) else { return Image(systemName: "arrow.up.right.square") }
        let s = CGSize(width: 24, height: 24)
        let r = UIGraphicsImageRenderer(size: s)
        let out: UIImage = r.image { _ in ui.draw(in: CGRect(origin: CGPoint.zero, size: s)) }.withRenderingMode(.alwaysOriginal)
        return Image(uiImage: out)
    }
}

// App 图标：FOMO 这类新加入的优先读本地文件，缺图时用字母头像；其余沿用统一的品牌图标
struct GXAppLogo: View {
    let app: GXApp
    let chain: Chain
    var size: CGFloat = 22

    var body: some View {
        if app == .fomo {
            if let ui = GXApp.localIcon("fomo") {
                Image(uiImage: ui).resizable().scaledToFit().frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                AvLetterDot(text: "F", seed: "fomo", size: size)
            }
        } else {
            GMBrandIcon(key: app.brand(chain), size: size)
        }
    }
}

// 一排 App 图标（代币头部 / 剪贴板卡片 / 钱包卡片）
struct GXAppIcons: View {
    let chain: Chain
    let addr: String
    var pair: String? = nil
    var wallet: Bool = false
    var size: CGFloat = 22
    @State private var tick = 0

    var body: some View {
        let ls: [GXLink] = wallet ? GXApp.walletLinks(chain: chain, addr: addr) : GXApp.tokenLinks(chain: chain, addr: addr, pair: pair)
        HStack(spacing: 9) {
            ForEach(ls) { l in
                Button { GXApp.open(l) } label: {
                    GXAppLogo(app: l.app, chain: chain, size: size)
                }
                .buttonStyle(.plain)
            }
        }
        .id(tick)
        .onReceive(NotificationCenter.default.publisher(for: .gxAppsChanged)) { _ in tick += 1 }
    }
}

// 钱包地址的跳转菜单：每项带 App 图标（由补丁替换掉 GMGNApi.swift 里原来的同名文字菜单）
struct GXWalletMenuBody: View {
    let chain: Chain
    let addr: String

    var body: some View {
        let ls: [GXLink] = GXApp.walletLinks(chain: chain, addr: addr)
        ForEach(ls) { l in
            Button { GXApp.open(l) } label: {
                Label {
                    Text(l.copy != nil ? l.app.title + "（复制地址后打开）" : l.app.title)
                } icon: {
                    GXApp.menuIcon(l.app.brand(chain))
                }
            }
        }
        Button("复制地址") { UIPasteboard.general.string = addr }
    }
}

// 设置里的单个开关行
struct GXAppToggleRow: View {
    let app: GXApp
    @AppStorage private var on: Bool

    init(app: GXApp) {
        self.app = app
        _on = AppStorage(wrappedValue: true, app.key, store: Cfg.defaults)
    }

    var body: some View {
        Toggle(isOn: $on) {
            HStack(spacing: 10) {
                GXAppLogo(app: app, chain: .solana, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.title).font(.subheadline.weight(.semibold))
                    if !app.note.isEmpty { Text(app.note).font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
        .onChange(of: on) { _, _ in NotificationCenter.default.post(name: .gxAppsChanged, object: nil) }
    }
}
