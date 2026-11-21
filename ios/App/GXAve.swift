import SwiftUI
import UIKit

// MARK: - Ave 同款图标：轮廓取自 Ave 截图并矢量化（256×256 网格，偶奇填充），任意字号都清晰，颜色跟随数值红 / 绿
enum GXAveGlyph {
    static let paths: [String: String] = [
        "wallet": "201,132 201,139 204,141 216,141 217,140 219,138 218,132 217,130 214,128 210,129 204,128|118,68 118,72 117,80 118,174 120,178 125,179 238,179 242,178 244,174 244,98 242,93 239,91 225,90 222,89 219,87 218,84 218,69 216,66 214,66 133,66 122,66|130,106 132,104 136,104 228,104 230,104 232,106 232,158 232,166 230,167 216,168 141,168 132,166 130,163 129,158|130,82 132,79 134,78 202,78 204,78 206,82 206,86 204,90 202,90 136,90 130,88 130,86",
        "person": "154,180 153,185 154,194 160,221 162,232 164,236 169,238 176,240 202,240 207,238 214,238 219,235 220,232 221,222 226,206 228,190 228,186 228,182 228,180 224,179 222,179 216,184 212,184 208,182 196,171 194,170 191,169 186,170 174,183 166,183 160,178 156,178|170,140 163,138 156,138 147,138 132,137 124,135 95,138 72,138 60,138 55,140 44,148 38,154 34,160 30,165 26,172 24,188 24,222 26,234 28,237 32,238 44,240 114,238 130,240 132,238 136,234 136,224 135,214 130,198 128,183 128,166 129,163 134,156 138,153 146,150 150,148 158,150 166,150 168,148 170,144|116,18 112,20 94,26 80,40 75,50 72,54 70,60 69,66 69,82 71,90 76,98 80,108 92,118 101,125 108,128 117,129 129,129 134,128 149,122 158,116 167,107 176,90 176,83 176,64 174,56 170,46 156,30 136,20 125,18",
        "chef": "208,218 206,212 203,209 198,207 188,207 176,206 64,206 57,208 54,211 52,216 51,222 53,230 56,235 66,242 71,244 184,244 192,242 202,237 204,234 208,224|26,78 20,90 18,94 16,106 17,118 20,126 24,132 30,144 37,152 42,156 49,166 50,169 50,182 52,187 55,190 60,192 152,193 188,192 200,192 205,187 208,182 209,168 212,161 216,156 221,153 226,148 235,136 238,128 241,123 243,116 244,103 242,98 238,90 234,80 228,72 219,64 214,60 204,58 196,54 185,52 182,51 172,42 168,36 161,30 152,25 147,22 141,19 124,18 118,19 112,21 96,32 88,39 84,46 80,50 72,52 61,54 42,62 38,64 34,68",
        "rat": "228,68 223,64 220,62 216,62 208,62 202,64 198,68 190,72 188,72 185,67 184,58 182,55 174,42 166,34 159,32 142,32 135,34 126,42 123,48 120,64 121,74 119,76 110,78 94,84 80,86 70,91 54,96 33,109 20,124 16,131 10,148 10,161 12,166 20,187 24,192 30,194 38,201 50,214 60,221 66,224 76,224 84,227 90,228 101,228 116,226 154,224 162,222 165,221 165,220 164,218 156,216 136,216 104,219 90,218 68,214 65,213 64,210 66,208 94,198 98,195 108,190 114,185 120,182 125,178 132,174 134,172 144,168 152,163 166,159 175,155 187,153 199,148 227,146 233,142 237,138 238,135 239,130 238,125 232,120 230,114 230,104 234,90 234,86 230,72",
        "fish": "228,75 223,70 211,66 204,61 192,58 183,54 168,52 151,52 138,54 115,60 94,70 84,76 79,82 76,84 62,99 60,102 58,105 34,105 29,106 24,108 14,116 12,120 11,126 14,134 18,142 26,150 30,152 33,156 34,158 34,162 28,179 28,188 31,199 34,202 38,204 50,204 64,202 71,196 78,194 88,193 98,196 111,198 117,200 141,200 159,196 167,196 176,192 182,192 195,184 209,174 223,160 230,152 240,132 241,126 240,122 232,116 228,111 225,109 221,104 221,100 226,86 228,82 228,77|176,108 178,108 182,110 186,113 188,116 188,122 186,125 184,127 179,129 172,128 168,124 167,121 167,116 168,114 171,111",
        "layers": "16,131 16,135 20,144 30,154 36,156 42,162 52,165 58,172 66,174 72,179 82,184 88,189 97,192 102,198 110,202 112,204 112,206 110,208 109,208 104,208 100,206 92,200 86,198 81,194 68,188 62,183 54,179 48,174 40,171 35,166 26,162 23,162 21,163 18,166 18,172 18,178 20,182 30,190 36,192 40,196 50,202 56,206 70,212 76,216 84,220 90,224 98,228 102,234 112,238 118,242 122,244 132,244 137,242 145,237 153,234 160,228 168,224 176,218 182,214 184,212 200,206 207,200 214,198 221,192 230,188 240,178 242,174 242,166 240,162 236,162 225,165 220,167 216,172 208,175 196,183 189,188 180,192 171,200 164,203 160,206 152,209 147,210 145,209 143,207 144,203 146,202 154,198 160,193 170,190 175,184 182,180 187,176 197,172 202,166 210,162 216,157 226,153 231,148 235,145 238,142 242,136 242,130 241,128 238,126 235,126 221,129 219,130 217,133 214,136 202,139 196,146 187,148 180,154 174,155 168,162 158,166 154,170 145,174 140,178 136,179 130,180 120,180 114,178 110,174 102,170 98,166 90,162 84,156 73,152 65,146 58,142 54,138 44,134 39,128 32,128 25,125 19,128|120,212 123,210 135,211 137,212 137,214 132,216 125,216 121,214 120,213|125,19 120,20 116,22 112,26 102,29 96,36 88,38 82,44 74,48 65,54 58,57 52,61 40,67 35,70 24,76 20,80 18,86 17,90 17,99 19,106 22,110 30,118 38,122 41,127 54,130 60,135 70,140 74,144 84,149 90,154 100,158 106,163 116,167 120,171 125,173 132,174 136,172 140,167 154,163 158,157 170,153 174,148 181,144 186,139 195,136 201,131 213,126 218,122 227,116 240,104 242,100 242,90 240,86 230,76 222,72 216,66 206,62 200,57 186,52 176,46 170,39 163,36 154,30 146,26 141,22 134,20",
        "angry": "124,24 112,26 104,30 94,33 90,37 85,40 74,52 69,59 63,66 54,85 48,90 40,94 28,104 26,108 18,123 15,142 16,146 20,148 22,150 28,150 35,154 42,156 46,158 50,166 50,178 52,188 54,191 58,194 66,198 76,199 83,202 92,208 95,214 99,216 103,222 108,224 121,230 132,230 138,228 150,222 156,216 160,212 164,205 168,202 180,198 188,198 198,192 200,190 202,188 203,166 206,161 212,156 226,152 235,148 239,144 240,140 238,136 238,128 237,124 233,119 228,108 216,94 206,90 197,82 195,79 193,72 187,64 183,56 168,40 164,38 158,33 151,30 138,26|103,149 104,146 108,142 112,140 121,138 130,138 140,140 146,142 148,144 150,150 150,157 148,160 144,164 140,167 134,168 120,168 112,166 104,158 103,155|170,104 171,108 169,114 165,118 160,120 150,122 146,122 140,122 136,121 135,120 135,115 136,112 150,102 158,100 165,100 168,102|84,104 88,100 100,100 107,102 112,106 116,111 118,114 116,120 114,123 108,123 97,122 88,118 85,114 84,110 83,106",
        "cross": "122,14 118,16 115,18 112,32 110,36 106,38 88,44 74,52 58,66 42,88 38,103 33,111 28,116 22,116 16,118 14,120 12,124 12,131 13,134 16,137 20,138 29,140 33,143 38,152 40,160 42,166 47,173 48,178 52,182 62,193 67,196 72,201 78,204 84,209 108,217 112,220 113,224 114,237 120,240 128,240 132,239 134,238 136,225 137,222 140,218 150,214 165,208 168,205 176,202 182,196 188,193 191,190 204,174 206,168 210,156 215,144 218,140 222,139 234,138 238,134 238,125 236,120 234,118 232,117 227,117 220,116 216,112 204,82 200,76 197,71 190,64 184,60 180,56 170,50 166,46 148,40 140,36 137,31 136,20 134,18 131,15|114,108 118,106 130,106 138,110 142,113 145,122 146,131 144,136 142,140 136,146 130,148 116,148 112,145 105,137 103,128 104,119 106,115",
    ]

    // 指标 id → Ave 图标（Ave 上有的：前十 / Dev / 老鼠仓 / 钓鱼 / 捆绑 / 狙击；聪明钱 / 风险用同套风格）
    static func name(_ id: String) -> String? {
        switch id {
        case "top10": return "wallet"
        case "smart": return "person"
        case "devhold": return "chef"
        case "rat": return "rat"
        case "phishing": return "fish"
        case "bundler": return "layers"
        case "rug": return "angry"
        case "sniper": return "cross"
        default: return nil
        }
    }

    static func has(_ id: String) -> Bool { name(id) != nil }

    private static var cache: [String: [[CGPoint]]] = [:]

    static func polys(_ n: String) -> [[CGPoint]] {
        if let c = cache[n] { return c }
        guard let s = paths[n] else { return [] }
        var out: [[CGPoint]] = []
        for part in s.split(separator: "|") {
            var pts: [CGPoint] = []
            for pt in part.split(separator: " ") {
                let xy = pt.split(separator: ",")
                if xy.count == 2, let x = Double(xy[0]), let y = Double(xy[1]) { pts.append(CGPoint(x: x / 256.0, y: y / 256.0)) }
            }
            if pts.count > 2 { out.append(pts) }
        }
        cache[n] = out
        return out
    }
}

struct GXAveShape: Shape {
    let name: String

    func path(in r: CGRect) -> Path {
        var p = Path()
        let s: CGFloat = min(r.width, r.height)
        let ox: CGFloat = r.minX + (r.width - s) / 2
        let oy: CGFloat = r.minY + (r.height - s) / 2
        for poly in GXAveGlyph.polys(name) {
            guard let f = poly.first else { continue }
            p.move(to: CGPoint(x: ox + f.x * s, y: oy + f.y * s))
            for q in poly.dropFirst() { p.addLine(to: CGPoint(x: ox + q.x * s, y: oy + q.y * s)) }
            p.closeSubpath()
        }
        return p
    }
}

struct GXAveIcon: View {
    let id: String
    var color: Color
    var size: CGFloat = 12

    var body: some View {
        if let n = GXAveGlyph.name(id) {
            GXAveShape(name: n)
                .fill(color, style: FillStyle(eoFill: true))
                .frame(width: size, height: size)
        }
    }
}

// MARK: - 内置图标（包内没有文件时的兜底）：Pons 发射台（取自 Ave 的同款蓝色 P 图标）
enum GXEmbedded {
    private static var cache: [String: UIImage] = [:]

    static let ponsB64: String = "iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAMAAADVRocKAAAAeFBMVEX///////3+///+//74///+/v79/v/9/f79/fv5/f7s/f71+vvm+f7m9fzl7/Xb9v3S9/7V8/7S7vvR5PC98v655/eb6P6L3fyy0+muyNp31Pt6xe9Zy/pCyPxNwfg+v/6Ir89esuY0tPsvrvd4pMUuo+5TmMs+hLgdet4bAAAEJklEQVR42u2Z6XKjMBCEwRFgcdrCXJbNZTDv/4bbI+Er+w+Rrd0tuhKcOK7+NDNikBTL2rRp06ZNm/427RzSbvfPDHi/t216dd2dyyyXBfGsgLsqHs9z3S97bzuLAfu9x13OGPPjNE2rh/AzKK7SF31qOcDjQcBYCPuSlL4URwECAcBxPHeZvwcAhu+r0adCiGOSREkUhmEURX4UxVEUuBwQZ2HVOUdyuB9i8CJ8k68VkDjJXQhwkfsgioVIRRImL+cHAH9VYpwvA6C0PnKNxGj9FgUCwMSKfMaXTSPmh6Iqk5co97PCR5L8SJQxWxgBsl+VInnXi0CFJoVpVfrLIvDLti2P4Wx9PP5GUWEcM9wXy4og2mGg+aPctT5joVKEoszKKljS2KwUgColwPG7kuOz7qkZQEcw24rvGFK2HIAUUQ1C8j8cBL7EiS4kej2QTjk6iAkg8QFQTuJweinTL4dTcc7LyjgC8n9XlmU5vk+nvJBnaQYQGvAwzp8q6CLl+SLNUkQA5f8wL56S57OUl9o8gqOA/cP7/NJFqe5MAclB+b+bw1bpUl8ufWeaokT7vw1a219Jl+vNGIAAtP/s3TTN9U23uyEAGcrI/+k+6wEYjQEPf+Xek94BjTGAAlD+19l+VcBAABVA/bTvmx8AwB/ON2gmvIq8CuCiALebJnzU2LjIGQAqgNuH/wzAjdZ1xgBk6PoKoGnq5+jhj3aUGQKy4vyWoEY3ifqqWgUARX4iwM4U8LR/NAsyh+BftWsB4K9c0aSVfaH79zRUfPksymgSaUDf1+RayE5LEkC2w9TGrhEAk0iVoG+opEXR3u/THRraIpfDhAAWLR01oFCAOUPj2HUtRvzUMAz4LiO2WwPQ96MaNt59U1vBf9HqWi+8PgB9101D6sdqc0MK6OIH3LMMAVSC8dbXHd6JsS9RmzPsfvbYonD8YgCQBKjJfxz7WsqhjViwV+LqAnmO55gACgKMJMzMFlNS2WOH7Ni2sydvzySCkgC3GSAVAEO3bNdzHWxg9zb5mwDyE+6zJ6BSADjrT1iWjSgW7mIxTQcC4EZuPgAW3zmWPmMwOhb5AIw/A2jvBMAsHT8B7noAamiYRB+AHQAgrBUBAW5PQPkDgOI7gFLkrZKidJju3wCFjsBbBxC30ySxKKpn/7qTuQbgTlAEw9M7Vk5TSQ+0uchNLbM5gjVmkWXxoBpKWrXUo0pSfylybGYAcNcBBAFLq+qEXqEADRZZ2PkHLvdWigDNmKWlyHLZ1dSsz/I+VSEqgAbtrAPwOPPDNCukXgdJPH8ZEkTdbh0Auj5j2EMVEk9jWj6UMaO7YLdOimwAHDoYDEWplhJ4Hrueuo/XET1QoC+ujrWwgEgDTkxnLYI6CYefPvr1QzqJBXI9wB8/2t/+vbFp06ZN/7F+Abx/xz9iqEdbAAAAAElFTkSuQmCC"

    static func image(_ name: String) -> UIImage? {
        if let c = cache[name] { return c }
        guard name == "gml_pons", let d = Data(base64Encoded: ponsB64), let i = UIImage(data: d) else { return nil }
        cache[name] = i
        return i
    }
}

// MARK: - Pons（Robinhood Chain 发射台）识别：直接问 Pons 官方文档公布的两代工厂合约，同时读出是否已毕业（内盘 / 外盘）
final class GXPonsStore: @unchecked Sendable {
    static let shared = GXPonsStore()
    private let lock = NSLock()
    private var set: Set<String> = []
    private var grad: [String: Bool] = [:]

    func has(_ a: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return set.contains(a.lowercased())
    }

    func graduated(_ a: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return grad[a.lowercased()]
    }

    func add(_ a: String, graduated: Bool?) {
        lock.lock()
        set.insert(a.lowercased())
        if let g = graduated { grad[a.lowercased()] = g }
        lock.unlock()
    }
}

@MainActor
final class GXPons: ObservableObject {
    static let shared = GXPons()
    @Published var n: Int = 0
    private var running: Set<String> = []
    private var done: Set<String> = []
    private var tries: [String: Int] = [:]

    // 官方文档：现行工厂 + 旧工厂（Robinhood Chain，chainId 4663）
    static let factories: [String] = ["0xA5aAb3F0c6EeadF30Ef1D3Eb997108E976351feB", "0x0c37a24F5D23A486FA692d1500881d698B1F77a4"]
    static let rpc: String = "https://rpc.mainnet.chain.robinhood.com"

    private func ethCall(_ to: String, _ data: String) async -> String? {
        guard let u = URL(string: GXPons.rpc) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 12)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let call: [String: Any] = ["to": to, "data": data]
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1, "method": "eth_call", "params": [call, "latest"]]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let r = try? await URLSession.shared.data(for: req),
              let o = (try? JSONSerialization.jsonObject(with: r.0)) as? [String: Any],
              let res = o["result"] as? String else { return nil }
        return res
    }

    // 返回值第 i 个 32 字节字是否非零
    private func word(_ hex: String, _ i: Int) -> Bool? {
        let chars: [Character] = Array(hex)
        if chars.count < (i + 1) * 64 { return nil }
        return chars[(i * 64)..<((i + 1) * 64)].contains(where: { $0 != "0" })
    }

    func check(chain: Chain, address: String) async {
        guard chain == .robinhood, address.count == 42 else { return }
        let a: String = address.lowercased()
        if done.contains(a) || running.contains(a) { return }
        running.insert(a)
        defer { running.remove(a) }
        let arg: String = String(repeating: "0", count: 24) + String(a.dropFirst(2))
        for f in GXPons.factories {
            // getLaunchedToken(address)：第 12 个字 exists = 是这个工厂发的币
            guard let res = await ethCall(f, "0x3cf28b5a" + arg) else { continue }
            if word(String(res.dropFirst(2)), 11) != true { continue }
            var g: Bool? = nil
            // graduationStatus(address)：第 3 个字 graduated = 已毕业（外盘）
            if let r2 = await ethCall(f, "0x98d652f1" + arg) { g = word(String(r2.dropFirst(2)), 2) }
            GXPonsStore.shared.add(a, graduated: g)
            done.insert(a)
            n += 1
            return
        }
        let t: Int = (tries[a] ?? 0) + 1
        tries[a] = t
        if t >= 3 { done.insert(a) }
    }
}

// MARK: - 菜单里的品牌小图标（链接名 → 图标）
enum GXIcons {
    static func menuImage(_ name: String) -> Image {
        if name == "官网" { return Image(systemName: "globe") }
        if let k = GMBrand.socialKey(name) ?? GMBrand.externalKey(name) { return GXApp.menuIcon(k) }
        return Image(systemName: "link")
    }
}
