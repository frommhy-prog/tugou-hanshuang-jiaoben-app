import SwiftUI
import UIKit

// MARK: - 品牌图标注册表（key -> 显示名, 官网域名）。真实图标由 CI 抓进包内 gmb_<key>.png（清单见 ios/tools/brands.txt，两处保持一致）
enum GMBrand {
    static let table: [String: (String, String)] = [
        "x": ("X", "x.com"),
        "telegram": ("Telegram", "telegram.org"),
        "discord": ("Discord", "discord.com"),
        "youtube": ("YouTube", "youtube.com"),
        "tiktok": ("TikTok", "tiktok.com"),
        "reddit": ("Reddit", "reddit.com"),
        "github": ("GitHub", "github.com"),
        "website": ("官网", ""),
        "dexscreener": ("Dexscreener", "dexscreener.com"),
        "gmgn": ("GMGN", "gmgn.ai"),
        "ave": ("Ave", "ave.ai"),
        "birdeye": ("Birdeye", "birdeye.so"),
        "dextools": ("DEXTools", "dextools.io"),
        "gecko": ("GeckoTerminal", "geckoterminal.com"),
        "bubblemaps": ("Bubblemaps", "bubblemaps.io"),
        "rugcheck": ("RugCheck", "rugcheck.xyz"),
        "goplus": ("GoPlus", "gopluslabs.io"),
        "solscan": ("Solscan", "solscan.io"),
        "etherscan": ("Etherscan", "etherscan.io"),
        "bscscan": ("BscScan", "bscscan.com"),
        "basescan": ("BaseScan", "basescan.org"),
        "debank": ("DeBank", "debank.com"),
        "cielo": ("Cielo", "cielo.finance"),
        "arkham": ("Arkham", "arkm.com"),
        "jupiter": ("Jupiter", "jup.ag"),
        "photon": ("Photon", "photon-sol.tinyastro.io"),
        "bullx": ("BullX", "bullx.io"),
        "axiom": ("Axiom", "axiom.trade"),
        "bonkbot": ("BonkBot", "bonkbot.io"),
        "bananagun": ("Banana Gun", "bananagun.io"),
        "maestro": ("Maestro", "maestrobots.com"),
        "phantom": ("Phantom", "phantom.com"),
        "metamask": ("MetaMask", "metamask.io"),
        "okxwallet": ("OKX Wallet", "web3.okx.com"),
        "trust": ("Trust Wallet", "trustwallet.com"),
        "rabby": ("Rabby", "rabby.io"),
        "solflare": ("Solflare", "solflare.com"),
        "backpack": ("Backpack", "backpack.app"),
        "bitgetwallet": ("Bitget Wallet", "web3.bitget.com"),
        "tokenpocket": ("TokenPocket", "tokenpocket.pro"),
        "imtoken": ("imToken", "token.im"),
        "safepal": ("SafePal", "safepal.com"),
        "ledger": ("Ledger", "ledger.com"),
        "trezor": ("Trezor", "trezor.io"),
        "binance": ("Binance", "binance.com"),
        "okx": ("OKX", "okx.com"),
        "bybit": ("Bybit", "bybit.com"),
        "gate": ("Gate", "gate.io"),
        "bitget": ("Bitget", "bitget.com"),
        "kucoin": ("KuCoin", "kucoin.com"),
        "kraken": ("Kraken", "kraken.com"),
        "htx": ("HTX", "htx.com"),
        "mexc": ("MEXC", "mexc.com"),
        "coinbase": ("Coinbase", "coinbase.com"),
        "bingx": ("BingX", "bingx.com"),
        "upbit": ("Upbit", "upbit.com"),
    ]

    static func domain(_ key: String) -> String? {
        guard let d = table[key]?.1, !d.isEmpty else { return nil }
        return d
    }

    static func title(_ key: String) -> String { table[key]?.0 ?? key }

    // 代币社交链接名（GMHeader.socials 产生的 X / TG / 官网 / Discord ...）-> 品牌 key
    static func socialKey(_ name: String) -> String? {
        let n: String = name.lowercased()
        switch n {
        case "x", "twitter": return "x"
        case "tg", "telegram": return "telegram"
        case "官网", "website": return "website"
        default: return table[n] != nil ? n : nil
        }
    }

    // 外部行情链接名 -> 品牌 key
    static func externalKey(_ name: String) -> String? {
        switch name {
        case "Dexscreener": return "dexscreener"
        case "GMGN": return "gmgn"
        case "Ave": return "ave"
        case "Birdeye": return "birdeye"
        case "X 搜索": return "x"
        default: return nil
        }
    }

    private static let matchers: [(String, String)] = [
        ("binance", "binance"), ("okx", "okx"), ("okex", "okx"), ("bybit", "bybit"), ("bitget", "bitget"), ("kucoin", "kucoin"),
        ("kraken", "kraken"), ("coinbase", "coinbase"), ("htx", "htx"), ("huobi", "htx"), ("mexc", "mexc"), ("gate.io", "gate"),
        ("gate io", "gate"), ("bingx", "bingx"), ("upbit", "upbit"),
        ("phantom", "phantom"), ("metamask", "metamask"), ("trust wallet", "trust"), ("rabby", "rabby"), ("solflare", "solflare"),
        ("backpack", "backpack"), ("tokenpocket", "tokenpocket"), ("imtoken", "imtoken"), ("safepal", "safepal"), ("ledger", "ledger"),
        ("trezor", "trezor"),
        ("photon", "photon"), ("bullx", "bullx"), ("axiom", "axiom"), ("bonkbot", "bonkbot"), ("banana", "bananagun"),
        ("maestro", "maestro"), ("gmgn", "gmgn"), ("jupiter", "jupiter"), ("arkham", "arkham"),
    ]

    // 钱包 / 地址标签文字 -> 品牌 key（交易所热钱包、钱包 App、交易机器人）
    static func match(_ label: String) -> String? {
        let l: String = label.lowercased()
        if l.isEmpty { return nil }
        for m in matchers where l.contains(m.0) { return m.1 }
        return nil
    }
}

// 品牌图标：包内真图 → 网络（favicon，缺失返回 404 才会兜底）→ 中性字符兜底（不仿品牌）
struct GMBrandIcon: View {
    let key: String
    var size: CGFloat = 16
    @State private var img: UIImage?

    var body: some View {
        Group {
            if let i = GMLogoFiles.bundle("gmb_" + key) ?? img {
                Image(uiImage: i)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                GMBrandGlyph(key: key, size: size)
            }
        }
        .frame(width: size, height: size)
        .task(id: key) {
            if GMLogoFiles.bundle("gmb_" + key) == nil {
                img = await GMBrandRemote.load(key)
            }
        }
    }
}

struct GMBrandGlyph: View {
    let key: String
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(Color.secondary.opacity(0.25))
            if key == "website" {
                Image(systemName: "globe").font(.system(size: size * 0.62, weight: .semibold)).foregroundStyle(Color.secondary)
            } else {
                Text(String(GMBrand.title(key).prefix(1)).uppercased())
                    .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

@MainActor
enum GMBrandRemote {
    static func load(_ key: String) async -> UIImage? {
        guard let d = GMBrand.domain(key) else { return nil }
        return await GMRemoteLogos.load(["https://t1.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&url=https://" + d + "&size=128"])
    }
}

// 发射台标签：真实图标 + 名称 + 内盘 / 外盘
struct GMLaunchChip: View {
    let pad: GMLaunchpad
    var stage: String?

    var body: some View {
        HStack(spacing: 4) {
            GMLaunchLogo(pad: pad, size: 14)
            Text(pad.title).font(.caption2.weight(.semibold)).lineLimit(1)
            if let s = stage {
                Text(s)
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background((s == "内盘" ? Color.orange : Color.green).opacity(0.22), in: Capsule())
                    .foregroundStyle(s == "内盘" ? Color.orange : Color.green)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.14), in: Capsule())
    }
}

extension GMMarketKind {
    // 头像右上角发射台徽标的外圈颜色：内盘橙、外盘绿、非发射台币保持原样
    static func ring(dex: String?, pad: GMLaunchpad?) -> Color {
        guard let t = text(dex: dex, pad: pad) else { return Color.card }
        return t == "内盘" ? Color.orange : Color.green
    }
}

// 概念类图标（老鼠仓、聪明钱、狙击手、开发者……）：用系统表情，原生渲染，不仿任何品牌
enum GMTagIcon {
    static func metric(_ id: String) -> String? {
        switch id {
        case "top10": return "🔟"
        case "holders": return "👥"
        case "devhold": return "🧑‍💻"
        case "sniper": return "🎯"
        case "bundler": return "📦"
        case "rat": return "🐭"
        case "phishing": return "🎣"
        case "tax": return "🧾"
        case "fresh": return "🌱"
        case "rug": return "🚨"
        case "mint": return "🪙"
        case "honeypot": return "🍯"
        case "lp": return "🔥"
        case "smart": return "🧠"
        case "bluechip": return "💎"
        case "curve": return "📈"
        default: return nil
        }
    }

    // GMGN 钱包标签（英文）-> 图标 + 中文
    static func text(_ tag: String) -> String {
        let l: String = tag.lowercased()
        if l.contains("sniper") { return "🎯 狙击手" }
        if l.contains("rat_trader") || l == "rat" || l.contains("insider") { return "🐭 老鼠仓" }
        if l.contains("smart") { return "🧠 聪明钱" }
        if l.contains("renowned") || l.contains("kol") { return "🌟 KOL" }
        if l.contains("creator") || l == "dev" || l.contains("dev_") { return "🧑‍💻 Dev" }
        if l.contains("bundler") { return "📦 捆绑" }
        if l.contains("entrapment") || l.contains("phishing") { return "🎣 钓鱼" }
        if l.contains("fresh") || l.contains("new_wallet") { return "🌱 新钱包" }
        if l.contains("whale") { return "🐋 巨鲸" }
        return tag
    }
}
