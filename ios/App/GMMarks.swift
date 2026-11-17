import SwiftUI
import UIKit

// MARK: - 公链徽标：矢量绘制，不依赖网络
private struct GMSolBar: Shape {
    var row: Int
    func path(in r: CGRect) -> Path {
        let h: CGFloat = r.height * 0.24
        let gap: CGFloat = (r.height - 3 * h) / 2
        let y: CGFloat = r.minY + CGFloat(row) * (h + gap)
        let k: CGFloat = r.width * 0.18
        var p = Path()
        if row == 1 {
            p.move(to: CGPoint(x: r.minX, y: y))
            p.addLine(to: CGPoint(x: r.maxX - k, y: y))
            p.addLine(to: CGPoint(x: r.maxX, y: y + h))
            p.addLine(to: CGPoint(x: r.minX + k, y: y + h))
        } else {
            p.move(to: CGPoint(x: r.minX + k, y: y))
            p.addLine(to: CGPoint(x: r.maxX, y: y))
            p.addLine(to: CGPoint(x: r.maxX - k, y: y + h))
            p.addLine(to: CGPoint(x: r.minX, y: y + h))
        }
        p.closeSubpath()
        return p
    }
}

private struct GMEthShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w: CGFloat = r.width
        let h: CGFloat = r.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * w, y: r.minY + y * h) }
        p.move(to: pt(0.5, 0))
        p.addLine(to: pt(1, 0.52))
        p.addLine(to: pt(0.5, 0.72))
        p.addLine(to: pt(0, 0.52))
        p.closeSubpath()
        p.move(to: pt(0.5, 1))
        p.addLine(to: pt(1, 0.62))
        p.addLine(to: pt(0.5, 0.82))
        p.addLine(to: pt(0, 0.62))
        p.closeSubpath()
        return p
    }
}

private struct GMDiamond: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

private struct GMBnbMark: View {
    var s: CGFloat
    var body: some View {
        ZStack {
            GMDiamond().fill(Color.white).frame(width: s * 0.2, height: s * 0.2)
            GMDiamond().fill(Color.white).frame(width: s * 0.17, height: s * 0.17).offset(y: -s * 0.28)
            GMDiamond().fill(Color.white).frame(width: s * 0.17, height: s * 0.17).offset(y: s * 0.28)
            GMDiamond().fill(Color.white).frame(width: s * 0.17, height: s * 0.17).offset(x: -s * 0.28)
            GMDiamond().fill(Color.white).frame(width: s * 0.17, height: s * 0.17).offset(x: s * 0.28)
        }
        .frame(width: s, height: s)
    }
}

// 链徽标里的图形（叠在链颜色渐变圆上）
struct GMChainGlyph: View {
    let chain: Chain
    var size: CGFloat

    var body: some View {
        switch chain {
        case .solana:
            ZStack {
                GMSolBar(row: 0).fill(Color.white)
                GMSolBar(row: 1).fill(Color.white)
                GMSolBar(row: 2).fill(Color.white)
            }
            .frame(width: size * 0.58, height: size * 0.5)
        case .eth:
            GMEthShape().fill(Color.white).frame(width: size * 0.38, height: size * 0.6)
        case .bsc:
            GMBnbMark(s: size * 0.64)
        case .base:
            ZStack {
                Circle().fill(Color.white)
                Rectangle().fill(Color(red: 0.0, green: 0.32, blue: 1.0)).frame(width: size * 0.3, height: size * 0.1).offset(x: size * 0.12)
            }
            .frame(width: size * 0.54, height: size * 0.54)
        case .polygon:
            Image(systemName: "hexagon.fill").font(.system(size: size * 0.56)).foregroundStyle(Color.white)
        case .robinhood:
            Image(systemName: "leaf.fill").font(.system(size: size * 0.52)).foregroundStyle(Color.white)
        case .optimism:
            Text("OP").font(.system(size: size * 0.4, weight: .heavy, design: .rounded)).foregroundStyle(Color.white)
        default:
            Text(chain.avMark).font(.system(size: size * 0.58, weight: .heavy, design: .rounded)).foregroundStyle(Color.white)
        }
    }
}

// MARK: - 发射台 / 内盘平台
enum GMLaunchpad {
    case pump, bonk, fourMeme, flap, moonshot, clanker, virtuals, bags, believe, boop, heaven, launchLab, jupStudio, daos, zora

    var title: String {
        switch self {
        case .pump: return "pump.fun"
        case .bonk: return "bonk.fun"
        case .fourMeme: return "four.meme"
        case .flap: return "flap.sh"
        case .moonshot: return "Moonshot"
        case .clanker: return "Clanker"
        case .virtuals: return "Virtuals"
        case .bags: return "Bags"
        case .believe: return "Believe"
        case .boop: return "Boop"
        case .heaven: return "Heaven"
        case .launchLab: return "LaunchLab"
        case .jupStudio: return "Jupiter Studio"
        case .daos: return "DAOS.FUN"
        case .zora: return "Zora"
        }
    }

    // 先看 Dexscreener 的 dexId，再看合约地址的靠谱特征（地址后缀由各平台的发币合约生成）
    static func detect(chain: Chain?, address: String, dex: String?) -> GMLaunchpad? {
        let d: String = (dex ?? "").lowercased()
        let a: String = address.lowercased()
        if d.contains("pumpfun") || d.contains("pumpswap") || d == "pump" { return .pump }
        if d.contains("fourmeme") { return .fourMeme }
        if d.contains("flap") { return .flap }
        if d.contains("moonshot") { return .moonshot }
        if d.contains("virtuals") { return .virtuals }
        if d.contains("clanker") { return .clanker }
        if d.contains("believe") { return .believe }
        if d.contains("boop") { return .boop }
        if d.contains("heaven") { return .heaven }
        if d.contains("launchlab") { return .launchLab }
        if d.contains("daos") { return .daos }
        if d.contains("zora") { return .zora }
        if d.contains("bonk") { return .bonk }
        let sol: Bool = (chain == .solana) || (chain == nil && !Addr.isEVM(address))
        if sol {
            if a.hasSuffix("pump") { return .pump }
            if a.hasSuffix("bonk") { return .bonk }
            if a.hasSuffix("bags") { return .bags }
        }
        if chain == .bsc {
            if a.hasSuffix("4444") { return .fourMeme }
            if a.hasSuffix("7777") || a.hasSuffix("8888") { return .flap }
        }
        if chain == .base && a.hasSuffix("b07") { return .clanker }
        return nil
    }
}

private struct GMPill: View {
    var body: some View {
        GeometryReader { g in
            let green = Color(red: 0.13, green: 0.82, blue: 0.5)
            ZStack {
                Capsule().fill(Color.white)
                HStack(spacing: 0) {
                    Rectangle().fill(green)
                    Color.clear
                }
                .clipShape(Capsule())
                Capsule().stroke(green, lineWidth: max(1, g.size.height * 0.14))
            }
        }
    }
}

struct GMLaunchMark: View {
    let pad: GMLaunchpad
    var size: CGFloat

    private func disc(_ c1: Color, _ c2: Color, _ t: String, _ fg: Color) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(t).font(.system(size: size * 0.56, weight: .heavy, design: .rounded)).foregroundStyle(fg)
        }
    }

    var body: some View {
        switch pad {
        case .pump:
            ZStack {
                Circle().fill(Color.white)
                GMPill().frame(width: size * 0.64, height: size * 0.3).rotationEffect(.degrees(-45))
            }
        case .bonk:
            disc(Color(red: 1.0, green: 0.55, blue: 0.1), Color(red: 1.0, green: 0.8, blue: 0.2), "B", Color.white)
        case .fourMeme:
            disc(Color(red: 0.05, green: 0.08, blue: 0.05), Color(red: 0.12, green: 0.18, blue: 0.1), "4", Color(red: 0.75, green: 1.0, blue: 0.2))
        case .flap:
            disc(Color(red: 0.25, green: 0.62, blue: 1.0), Color(red: 0.1, green: 0.35, blue: 0.85), "F", Color.white)
        case .moonshot:
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(red: 0.6, green: 0.3, blue: 0.95), Color(red: 0.35, green: 0.15, blue: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "moon.fill").font(.system(size: size * 0.5)).foregroundStyle(Color.white)
            }
        case .clanker:
            disc(Color(red: 0.3, green: 0.3, blue: 0.36), Color(red: 0.1, green: 0.1, blue: 0.14), "C", Color.orange)
        case .virtuals:
            disc(Color(red: 0.1, green: 0.8, blue: 0.75), Color(red: 0.05, green: 0.5, blue: 0.6), "V", Color.white)
        case .bags:
            disc(Color(red: 0.2, green: 0.85, blue: 0.4), Color(red: 0.05, green: 0.55, blue: 0.25), "B", Color.white)
        default:
            disc(Color(red: 0.35, green: 0.35, blue: 0.4), Color(red: 0.12, green: 0.12, blue: 0.16), String(pad.title.prefix(1)).uppercased(), Color.white)
        }
    }
}

// 头像右上角的发射台徽标（和右下角链徽标成对）
struct GMLaunchBadge: View {
    let chain: Chain?
    let address: String
    let dex: String?
    var size: CGFloat

    var body: some View {
        if size >= 30, let p = GMLaunchpad.detect(chain: chain, address: address, dex: dex) {
            let d: CGFloat = max(14, size * 0.36)
            GMLaunchLogo(pad: p, size: d)
                .frame(width: d, height: d)
                .clipShape(Circle())
                .overlay(Circle().stroke(GMMarketKind.ring(dex: dex, pad: p), lineWidth: 1.8))
                .offset(x: size * 0.08, y: -size * 0.08)
        }
    }
}

// MARK: - 交易所（DEX）小图标：先取 Dexscreener 图片库，取不到用颜色点兜底
@MainActor
enum GMDexIcons {
    private static let cache = NSCache<NSString, UIImage>()
    private static var failed: Set<String> = []

    static func load(_ dex: String) async -> UIImage? {
        let k: String = dex.lowercased()
        if let c = cache.object(forKey: k as NSString) { return c }
        if failed.contains(k) { return nil }
        guard let u = URL(string: "https://dd.dexscreener.com/ds-data/dexes/" + k + ".png") else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 10)
        req.setValue("image/*", forHTTPHeaderField: "Accept")
        guard let r = try? await URLSession.shared.data(for: req) else { failed.insert(k); return nil }
        let code: Int = (r.1 as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200, r.0.count > 100, let img = UIImage(data: r.0) else { failed.insert(k); return nil }
        cache.setObject(img, forKey: k as NSString)
        return img
    }
}

struct GMDexChip: View {
    let dex: String
    @State private var img: UIImage?

    private var dot: Color {
        let h: Double = Double(avFNV(dex.lowercased()) % 360) / 360.0
        return Color(hue: h, saturation: 0.6, brightness: 0.85)
    }

    var body: some View {
        HStack(spacing: 4) {
            if let i = img {
                Image(uiImage: i).resizable().scaledToFill().frame(width: 12, height: 12).clipShape(Circle())
            } else {
                Circle().fill(dot).frame(width: 8, height: 8)
            }
            Text(dex).font(.caption2.weight(.semibold)).lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.14), in: Capsule())
        .task(id: dex) { img = await GMDexIcons2.load(dex) }
    }
}
