import SwiftUI
import UIKit

// 真实品牌图标：构建时由 CI 从官方源抓进 App（gmc_链 / gml_发射台 / gmd_DEX / gmb_品牌），抓不到的运行时再走网络，都没有才用矢量 / 字符兜底
enum GMLogoFiles {
    private static var cache: [String: UIImage] = [:]

    static func bundle(_ name: String) -> UIImage? {
        if let c = cache[name] { return c }
        guard let p = Bundle.main.path(forResource: name, ofType: "png"), let i = UIImage(contentsOfFile: p) else { return GXEmbedded.image(name) }
        cache[name] = i
        return i
    }

    static func chainName(_ c: Chain) -> String { "gmc_" + c.dexId }

    // 整圆 / 整块底图（四角不透明，或不透明面积占大半）直接铺满圆；只有图形的透明底图要放进深色圆里，否则会被圆边裁掉
    static func fullBleed(_ img: UIImage) -> Bool {
        guard let cg = img.cgImage else { return true }
        let n: Int = 16
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let ok: Bool = px.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        if !ok { return true }
        let corners: [Int] = [0, n - 1, (n - 1) * n, n * n - 1]
        var cs: Int = 0
        for c in corners { cs += Int(px[c * 4 + 3]) }
        if cs >= 4 * 200 { return true }
        var solid: Int = 0
        for i in 0..<(n * n) where px[i * 4 + 3] > 128 { solid += 1 }
        return Double(solid) / Double(n * n) >= 0.72
    }
}

extension GMLaunchpad {
    var fileKey: String {
        switch self {
        case .pump: return "pumpfun"
        case .bonk: return "letsbonk"
        case .fourMeme: return "fourmeme"
        case .flap: return "flap"
        case .moonshot: return "moonshot"
        case .clanker: return "clanker"
        case .virtuals: return "virtuals"
        case .bags: return "bags"
        case .believe: return "believe"
        case .boop: return "boop"
        case .heaven: return "heaven"
        case .launchLab: return "launchlab"
        case .jupStudio: return "jupstudio"
        case .daos: return "daos"
        case .zora: return "zora"
        case .pons: return "pons"
        }
    }
}

@MainActor
enum GMRemoteLogos {
    private static var cache: [String: UIImage] = [:]
    private static var failed: Set<String> = []
    private static var ph: Data?
    private static var phTried: Bool = false

    // Dexscreener 对不存在的图标也返回 200 的占位图：取一张占位图当指纹，之后一律丢弃
    private static func placeholder() async -> Data? {
        if phTried { return ph }
        phTried = true
        if let u = URL(string: "https://dd.dexscreener.com/ds-data/dexes/zz-not-exist-9.png"),
           let r = try? await URLSession.shared.data(from: u),
           (r.1 as? HTTPURLResponse)?.statusCode == 200 {
            ph = r.0
        }
        return ph
    }

    static func load(_ urls: [String]) async -> UIImage? {
        for s in urls {
            if let c = cache[s] { return c }
            if failed.contains(s) { continue }
            guard let u = URL(string: s) else { continue }
            if let r = try? await URLSession.shared.data(from: u), (r.1 as? HTTPURLResponse)?.statusCode == 200, r.0.count > 200, let img = UIImage(data: r.0) {
                if s.contains("ds-data"), let p = await placeholder(), p == r.0 {
                    failed.insert(s)
                    continue
                }
                cache[s] = img
                return img
            }
            failed.insert(s)
        }
        return nil
    }
}

// 圆形品牌图：整圆底图铺满；只有图形的透明底图放进深色圆里完整显示
struct GMLogoDisc: View {
    let image: UIImage
    var size: CGFloat

    var body: some View {
        if GMLogoFiles.fullBleed(image) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(Color(red: 0.07, green: 0.07, blue: 0.09))
                Image(uiImage: image).resizable().scaledToFit().frame(width: size * 0.64, height: size * 0.64)
            }
            .frame(width: size, height: size)
        }
    }
}

struct GMChainLogo: View {
    let chain: Chain
    var size: CGFloat
    @State private var img: UIImage?

    var body: some View {
        Group {
            if let i = GMLogoFiles.bundle(GMLogoFiles.chainName(chain)) ?? img {
                GMLogoDisc(image: i, size: size)
            } else {
                GMChainGlyph(chain: chain, size: size)
            }
        }
        .task(id: chain.dexId) {
            if GMLogoFiles.bundle(GMLogoFiles.chainName(chain)) == nil {
                img = await GMRemoteLogos.load(["https://dd.dexscreener.com/ds-data/chains/" + chain.dexId + ".png"])
            }
        }
    }
}

// 任意链（Dexscreener 链 id，比如 avalanche / tron / sui）的真实图标；包内没有就走网络，再不行用字母
struct GMChainIdLogo: View {
    let id: String
    var size: CGFloat
    @State private var img: UIImage?

    var body: some View {
        Group {
            if let i = GMLogoFiles.bundle("gmc_" + id.lowercased()) ?? img {
                GMLogoDisc(image: i, size: size)
            } else {
                AvLetterDot(text: id, seed: id, size: size)
            }
        }
        .frame(width: size, height: size)
        .task(id: id) {
            if GMLogoFiles.bundle("gmc_" + id.lowercased()) == nil {
                img = await GMRemoteLogos.load(["https://dd.dexscreener.com/ds-data/chains/" + id.lowercased() + ".png"])
            }
        }
    }
}

struct GMLaunchLogo: View {
    let pad: GMLaunchpad
    var size: CGFloat
    @State private var img: UIImage?

    var body: some View {
        Group {
            if let i = GMLogoFiles.bundle("gml_" + pad.fileKey) ?? img {
                GMLogoDisc(image: i, size: size)
            } else {
                GMLaunchMark(pad: pad, size: size)
            }
        }
        .task(id: pad.fileKey) {
            if GMLogoFiles.bundle("gml_" + pad.fileKey) == nil {
                img = await GMRemoteLogos.load(["https://dd.dexscreener.com/ds-data/dexes/" + pad.fileKey + ".png"])
            }
        }
    }
}

// DEX 小图标：包内（gmd_）→ Dexscreener 图片库（过滤占位图）；都没有返回 nil，由调用方用颜色点兜底
@MainActor
enum GMDexIcons2 {
    static func load(_ dex: String) async -> UIImage? {
        let k: String = dex.lowercased()
        if let b = GMLogoFiles.bundle("gmd_" + k) { return b }
        return await GMRemoteLogos.load(["https://dd.dexscreener.com/ds-data/dexes/" + k + ".png"])
    }
}
