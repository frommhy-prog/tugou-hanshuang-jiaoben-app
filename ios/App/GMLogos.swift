import SwiftUI
import UIKit

// 真实品牌图标：构建时由 CI 从官方源抱进 App（gmc_链 / gml_发射台），抱不到的运行时再走网络，都没有才用矢量兜底
enum GMLogoFiles {
    private static var cache: [String: UIImage] = [:]

    static func bundle(_ name: String) -> UIImage? {
        if let c = cache[name] { return c }
        guard let p = Bundle.main.path(forResource: name, ofType: "png"), let i = UIImage(contentsOfFile: p) else { return nil }
        cache[name] = i
        return i
    }

    static func chainName(_ c: Chain) -> String { "gmc_" + c.dexId }
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
        }
    }
}

@MainActor
enum GMRemoteLogos {
    private static var cache: [String: UIImage] = [:]
    private static var failed: Set<String> = []

    static func load(_ urls: [String]) async -> UIImage? {
        for s in urls {
            if let c = cache[s] { return c }
            if failed.contains(s) { continue }
            guard let u = URL(string: s) else { continue }
            if let r = try? await URLSession.shared.data(from: u), (r.1 as? HTTPURLResponse)?.statusCode == 200, r.0.count > 200, let img = UIImage(data: r.0) {
                cache[s] = img
                return img
            }
            failed.insert(s)
        }
        return nil
    }
}

struct GMChainLogo: View {
    let chain: Chain
    var size: CGFloat
    @State private var img: UIImage?

    var body: some View {
        Group {
            if let i = GMLogoFiles.bundle(GMLogoFiles.chainName(chain)) ?? img {
                Image(uiImage: i).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
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

struct GMLaunchLogo: View {
    let pad: GMLaunchpad
    var size: CGFloat
    @State private var img: UIImage?

    var body: some View {
        Group {
            if let i = GMLogoFiles.bundle("gml_" + pad.fileKey) ?? img {
                Image(uiImage: i).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle())
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
