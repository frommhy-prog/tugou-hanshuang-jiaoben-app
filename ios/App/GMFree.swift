import SwiftUI
import UIKit
import CryptoKit

// MARK: - 头部菜单 → 代币页的通知（顶栏按钮并进头部后，由 UnifiedTokenRoot 接收）
extension Notification.Name {
    static let gmOpenSearch = Notification.Name("gmOpenSearch")
    static let gmOpenDash = Notification.Name("gmOpenDash")
    static let gmShare = Notification.Name("gmShare")
    static let gmAlert = Notification.Name("gmAlert")
    static let gmOpenTools = Notification.Name("gmOpenTools")
}

private func gfNum(_ x: Any?) -> Double? {
    if let n = x as? NSNumber { return n.doubleValue }
    if let s = x as? String {
        let t: String = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : Double(t)
    }
    return nil
}

private func gfArr(_ x: Any?) -> [[String: Any]] {
    return (x as? [[String: Any]]) ?? []
}

struct GFWallet: Identifiable {
    let addr: String
    let pct: Double
    let tag: String?
    var isContract: Bool = false
    var id: String { addr }
}

struct GFPart {
    var name: String
    var nums: [String: Double] = [:]
    var texts: [String: String] = [:]
    var wallets: [GFWallet] = []
}

// MARK: - 各个免费来源（手机直连；全部失败也不影响页面，缺的显示「—」）
enum GFSrc {
    static func json(_ s: String, headers: [String: String] = [:]) async -> Any? {
        guard let url = URL(string: s) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        guard let r = try? await Net.fetch(req) else { return nil }
        let code: Int = (r.1 as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) { return nil }
        return try? JSONSerialization.jsonObject(with: r.0)
    }

    // 币安 Web3 公共接口（不需要 Key）：持有者数 + 前十占比，只支持 ETH / BSC / Base / Solana
    static func binance(_ chain: Chain, _ addr: String) async -> GFPart? {
        let ids: [Chain: String] = [.eth: "1", .bsc: "56", .base: "8453", .solana: "CT_501"]
        guard let cid = ids[chain] else { return nil }
        let u: String = "https://web3.binance.com/bapi/defi/v4/public/wallet-direct/buw/wallet/market/token/dynamic/info?chainId=" + cid + "&contractAddress=" + addr
        guard let o = await json(u, headers: ["User-Agent": "binance-web3/1.1 (Skill)"]),
              let top = o as? [String: Any], let d = top["data"] as? [String: Any] else { return nil }
        var p = GFPart(name: "币安 Web3")
        if let h = gfNum(d["holders"]) { p.nums["holders"] = h }
        if let t = gfNum(d["top10HoldersPercentage"]) ?? gfNum(d["holdersTop10Percent"]) { p.nums["top10"] = t }
        return p.nums.isEmpty ? nil : p
    }

    // GoPlus（免费）
    static let gpIds: [Chain: String] = [.eth: "1", .bsc: "56", .base: "8453", .arbitrum: "42161", .optimism: "10", .polygon: "137", .xlayer: "196", .okc: "66", .robinhood: "4663"]

    static func goplus(_ chain: Chain, _ addr: String) async -> GFPart? {
        if chain == .solana { return await goplusSol(addr) }
        guard let cid = gpIds[chain] else { return nil }
        await DataGate.shared.wait("api.gopluslabs.io")
        let low: String = addr.lowercased()
        let u: String = "https://api.gopluslabs.io/api/v1/token_security/" + cid + "?contract_addresses=" + low
        guard let o = await json(u), let top = o as? [String: Any], let res = top["result"] as? [String: Any] else { return nil }
        var dOpt: [String: Any]? = res[low] as? [String: Any]
        if dOpt == nil { dOpt = res.values.first as? [String: Any] }
        guard let d = dOpt else { return nil }
        var p = GFPart(name: "GoPlus")
        if let h = gfNum(d["holder_count"]) { p.nums["holders"] = h }
        let hs: [[String: Any]] = gfArr(d["holders"])
        if !hs.isEmpty {
            var raw: Double = 0
            for h in hs.prefix(10) { raw += gfNum(h["percent"]) ?? 0 }
            let k: Double = raw <= 1.0001 ? 100 : 1
            var sum: Double = 0
            var ws: [GFWallet] = []
            for h in hs.prefix(10) {
                let pc: Double = (gfNum(h["percent"]) ?? 0) * k
                let isC: Bool = (gfNum(h["is_contract"]) ?? 0) > 0
                if let a = h["address"] as? String { ws.append(GFWallet(addr: a, pct: pc, tag: h["tag"] as? String, isContract: isC)) }
                if !isC { sum += pc }
            }
            p.nums["top10"] = sum
            p.wallets = ws
            p.texts["top10note"] = "只统计榜单里的普通钱包，已剔除合约/池子"
        }
        if let c = gfNum(d["creator_percent"]) { p.nums["dev"] = c * 100 }
        if let b = gfNum(d["buy_tax"]) { p.nums["buyTax"] = b * 100 }
        if let s = gfNum(d["sell_tax"]) { p.nums["sellTax"] = s * 100 }
        if let h = gfNum(d["is_honeypot"]) { p.nums["honeypot"] = h }
        let lps: [[String: Any]] = gfArr(d["lp_holders"])
        if !lps.isEmpty {
            var rawL: Double = 0
            for l in lps { rawL += gfNum(l["percent"]) ?? 0 }
            let kl: Double = rawL <= 1.0001 ? 100 : 1
            var safe: Double = 0
            for l in lps {
                let a: String = ((l["address"] as? String) ?? "").lowercased()
                let locked: Bool = (gfNum(l["is_locked"]) ?? 0) > 0 || a.contains("dead") || a == "0x0000000000000000000000000000000000000000"
                if locked { safe += (gfNum(l["percent"]) ?? 0) * kl }
            }
            p.nums["lpSafe"] = min(100, safe)
        }
        return p.nums.isEmpty ? nil : p
    }

    static func goplusSol(_ mint: String) async -> GFPart? {
        await DataGate.shared.wait("api.gopluslabs.io")
        let u: String = "https://api.gopluslabs.io/api/v1/solana/token_security?contract_addresses=" + mint
        guard let o = await json(u), let top = o as? [String: Any], let res = top["result"] as? [String: Any], let d = res[mint] as? [String: Any] else { return nil }
        var p = GFPart(name: "GoPlus")
        if let h = gfNum(d["holder_count"]) { p.nums["holders"] = h }
        let hs: [[String: Any]] = gfArr(d["holders"])
        if !hs.isEmpty {
            var raw: Double = 0
            for h in hs.prefix(10) { raw += gfNum(h["percent"]) ?? 0 }
            let k: Double = raw <= 1.0001 ? 100 : 1
            var sum: Double = 0
            var ws: [GFWallet] = []
            for h in hs.prefix(10) {
                let pc: Double = (gfNum(h["percent"]) ?? 0) * k
                sum += pc
                let a: String = (h["account"] as? String) ?? (h["address"] as? String) ?? ""
                if !a.isEmpty { ws.append(GFWallet(addr: a, pct: pc, tag: h["tag"] as? String)) }
            }
            p.nums["top10"] = sum
            p.wallets = ws
            p.texts["top10note"] = "榜单前 10 名合计，可能含池子"
        }
        return p.nums.isEmpty ? nil : p
    }

    // RugCheck（Solana，免费）
    static func rugcheck(_ chain: Chain, _ mint: String) async -> GFPart? {
        if chain != .solana { return nil }
        guard let o = await json("https://api.rugcheck.xyz/v1/tokens/" + mint + "/report"), let d = o as? [String: Any] else { return nil }
        var p = GFPart(name: "RugCheck")
        if let h = gfNum(d["totalHolders"]) { p.nums["holders"] = h }
        let th: [[String: Any]] = gfArr(d["topHolders"])
        if !th.isEmpty {
            var s10: Double = 0
            var ins: Double = 0
            var hasFlag = false
            var ws: [GFWallet] = []
            let creator: String = (d["creator"] as? String) ?? ""
            var devPct: Double? = nil
            for (i, h) in th.enumerated() {
                let pc: Double = gfNum(h["pct"]) ?? 0
                let owner: String = (h["owner"] as? String) ?? (h["address"] as? String) ?? ""
                if i < 10 { s10 += pc }
                if let f = h["insider"] as? Bool {
                    hasFlag = true
                    if f { ins += pc }
                }
                if !creator.isEmpty && owner == creator { devPct = pc }
                if i < 20 && !owner.isEmpty { ws.append(GFWallet(addr: owner, pct: pc, tag: nil)) }
            }
            p.nums["top10"] = s10
            p.texts["top10note"] = "榜单前 10 名合计，可能含池子"
            if hasFlag { p.nums["insider"] = ins }
            if let dv = devPct { p.nums["dev"] = dv }
            else if let cb = gfNum(d["creatorBalance"]), cb == 0 { p.nums["dev"] = 0 }
            p.wallets = ws
        }
        return p.nums.isEmpty ? nil : p
    }

    // Jupiter lite-api（Solana，不带 Key；官方可能改成需要 Key，失败就忽略）
    static func jupiter(_ chain: Chain, _ mint: String) async -> GFPart? {
        if chain != .solana { return nil }
        guard let o = await json("https://lite-api.jup.ag/tokens/v2/search?query=" + mint), let arr = o as? [[String: Any]] else { return nil }
        var hit: [String: Any]? = arr.first(where: { ($0["id"] as? String) == mint })
        if hit == nil { hit = arr.first }
        guard let d = hit else { return nil }
        var p = GFPart(name: "Jupiter")
        if let h = gfNum(d["holderCount"]) { p.nums["holders"] = h }
        if let a = d["audit"] as? [String: Any] {
            if let t = gfNum(a["topHoldersPercentage"]) { p.nums["top10"] = t }
            if let dv = gfNum(a["devBalancePercentage"]) { p.nums["dev"] = dv }
        }
        return p.nums.isEmpty ? nil : p
    }

    // Honeypot.is（EVM：蜜罐 + 实测买卖税）
    static func honeypot(_ chain: Chain, _ addr: String) async -> GFPart? {
        let ids: [Chain: String] = [.eth: "1", .bsc: "56", .base: "8453"]
        guard let cid = ids[chain] else { return nil }
        guard let o = await json("https://api.honeypot.is/v2/IsHoneypot?address=" + addr + "&chainID=" + cid), let d = o as? [String: Any] else { return nil }
        var p = GFPart(name: "Honeypot.is")
        if let hr = d["honeypotResult"] as? [String: Any], let h = hr["isHoneypot"] as? Bool { p.nums["honeypot"] = h ? 1 : 0 }
        if let sr = d["simulationResult"] as? [String: Any] {
            if let b = gfNum(sr["buyTax"]) { p.nums["buyTax"] = b }
            if let s = gfNum(sr["sellTax"]) { p.nums["sellTax"] = s }
        }
        return p.nums.isEmpty ? nil : p
    }

    // Blockscout 区块浏览器接口（各链官方浏览器自带，免费不需要 Key）：持有者数、前十普通钱包占比、Dev 持仓
    static let bsHosts: [Chain: String] = [.robinhood: "robinhoodchain.blockscout.com", .eth: "eth.blockscout.com", .base: "base.blockscout.com", .optimism: "optimism.blockscout.com", .arbitrum: "arbitrum.blockscout.com", .polygon: "polygon.blockscout.com"]

    static func blockscout(_ chain: Chain, _ addr: String) async -> GFPart? {
        guard let host = bsHosts[chain] else { return nil }
        let base: String = "https://" + host + "/api/v2"
        let low: String = addr.lowercased()
        let tkO: Any? = await json(base + "/tokens/" + addr)
        guard let tkD = tkO as? [String: Any] else { return nil }
        let hlO: Any? = await json(base + "/tokens/" + addr + "/holders")
        let adO: Any? = await json(base + "/addresses/" + addr)
        var p = GFPart(name: "Blockscout")
        if let hc = gfNum(tkD["holders_count"]) ?? gfNum(tkD["holders"]) { p.nums["holders"] = hc }
        let supply: Double = gfNum(tkD["total_supply"]) ?? 0
        var creator: String? = nil
        if let ad = adO as? [String: Any], let c = ad["creator_address_hash"] as? String { creator = c.lowercased() }
        var devPct: Double? = nil
        if supply > 0, let hd = hlO as? [String: Any], let items = hd["items"] as? [[String: Any]] {
            var sum10: Double = 0
            var cnt: Int = 0
            var ws: [GFWallet] = []
            for it in items {
                let a: [String: Any] = (it["address"] as? [String: Any]) ?? [:]
                let hash: String = (a["hash"] as? String) ?? ""
                if hash.isEmpty { continue }
                let hl: String = hash.lowercased()
                let burn: Bool = hl.hasSuffix("dead") || hl == "0x0000000000000000000000000000000000000000"
                let isC: Bool = ((a["is_contract"] as? Bool) ?? false) || burn
                let pc: Double = (gfNum(it["value"]) ?? 0) / supply * 100
                if ws.count < 30 {
                    var tag: String? = a["name"] as? String
                    if burn { tag = "销毁地址" }
                    ws.append(GFWallet(addr: hash, pct: pc, tag: tag, isContract: isC))
                }
                if !isC && cnt < 10 {
                    sum10 += pc
                    cnt += 1
                }
                if let c = creator, hl == c { devPct = pc }
            }
            if cnt > 0 {
                p.nums["top10"] = sum10
                p.texts["top10note"] = cnt >= 10 ? "前 10 个普通钱包合计，已剔除合约/池子/销毁地址" : "只统计到前 " + String(cnt) + " 个普通钱包（已剔除合约/池子/销毁地址）"
            }
            p.wallets = ws
        }
        if devPct == nil, let c = creator, supply > 0 {
            let tbO: Any? = await json(base + "/addresses/" + c + "/token-balances")
            if let tb = tbO as? [[String: Any]] {
                var found: Double? = nil
                for it in tb {
                    let tkn: [String: Any] = (it["token"] as? [String: Any]) ?? [:]
                    let th: String = ((tkn["address_hash"] as? String) ?? (tkn["address"] as? String) ?? "").lowercased()
                    if th == low { found = (gfNum(it["value"]) ?? 0) / supply * 100 }
                }
                if let f = found { devPct = f }
                else if tb.count < 50 { devPct = 0 }
            }
        }
        if let dv = devPct { p.nums["dev"] = dv }
        return p.nums.isEmpty ? nil : p
    }

    // OKX Web3（OnchainOS，免费 Key，每月有免费额度）：前十 / Dev / 捆绑 / 狙击 / 可疑地址占比
    static func okxSign(_ ts: String, _ method: String, _ path: String, _ secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data((ts + method + path).utf8), using: key)
        return Data(mac).base64EncodedString()
    }

    static func okxCall(_ path: String) async -> (Any?, String) {
        let d: UserDefaults = Cfg.defaults
        let k: String = d.string(forKey: "okxWebKey") ?? ""
        let sec: String = d.string(forKey: "okxWebSecret") ?? ""
        let pass: String = d.string(forKey: "okxWebPass") ?? ""
        let proj: String = d.string(forKey: "okxWebProject") ?? ""
        if k.isEmpty || sec.isEmpty || pass.isEmpty { return (nil, "没填 OKX Web3 的 Key / Secret / 口令") }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts: String = f.string(from: Date())
        guard let url = URL(string: "https://web3.okx.com" + path) else { return (nil, "地址无效") }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue(k, forHTTPHeaderField: "OK-ACCESS-KEY")
        req.setValue(okxSign(ts, "GET", path, sec), forHTTPHeaderField: "OK-ACCESS-SIGN")
        req.setValue(ts, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
        req.setValue(pass, forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
        if !proj.isEmpty { req.setValue(proj, forHTTPHeaderField: "OK-ACCESS-PROJECT") }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let r = try? await Net.fetch(req) else { return (nil, "网络失败") }
        let code: Int = (r.1 as? HTTPURLResponse)?.statusCode ?? 0
        let o: Any? = try? JSONSerialization.jsonObject(with: r.0)
        if let dd = o as? [String: Any], let c = dd["code"] as? String, c != "0" {
            return (nil, "OKX 返回 " + c + "：" + ((dd["msg"] as? String) ?? ""))
        }
        if !(200..<300).contains(code) { return (nil, "HTTP " + String(code)) }
        return (o, "")
    }

    static func okx(_ chain: Chain, _ addr: String) async -> GFPart? {
        let ids: [Chain: String] = [.eth: "1", .bsc: "56", .base: "8453", .arbitrum: "42161", .optimism: "10", .polygon: "137", .solana: "501", .xlayer: "196"]
        guard let ci = ids[chain] else { return nil }
        let r = await okxCall("/api/v6/dex/market/token/advanced-info?chainIndex=" + ci + "&tokenContractAddress=" + addr)
        guard let top = r.0 as? [String: Any] else { return nil }
        var dd: [String: Any]? = top["data"] as? [String: Any]
        if dd == nil, let arr = top["data"] as? [[String: Any]] { dd = arr.first }
        guard let d = dd else { return nil }
        var p = GFPart(name: "OKX Web3")
        if let x = gfNum(d["top10HoldPercent"]) { p.nums["top10"] = x }
        if let x = gfNum(d["devHoldingPercent"]) { p.nums["dev"] = x }
        if let x = gfNum(d["bundleHoldingPercent"]) { p.nums["bundle"] = x }
        if let x = gfNum(d["suspiciousHoldingPercent"]) { p.nums["insider"] = x }
        if let x = gfNum(d["sniperHoldingPercent"]) { p.nums["sniper"] = x }
        if let x = gfNum(d["snipersTotal"]) { p.nums["sniperN"] = x }
        if let x = gfNum(d["lpBurnedPercent"]) { p.nums["lpSafe"] = x }
        if let x = d["riskControlLevel"] as? String, !x.isEmpty { p.texts["okxRisk"] = x }
        return p.nums.isEmpty ? nil : p
    }
}

// MARK: - 汇总：GMGN 没有时，代币页顶部数据条回落到这里
@MainActor
final class GMFreeStore: ObservableObject {
    static let shared = GMFreeStore()
    @Published var v: [String: Double] = [:]
    @Published var t: [String: String] = [:]
    @Published var src: [String: String] = [:]
    @Published var wallets: [GFWallet] = []
    @Published var used: [String] = []
    @Published var loading = false
    private var key = ""
    private var at = Date.distantPast

    func load(chain: Chain, address: String, force: Bool = false) async {
        if address.isEmpty { return }
        let k: String = chain.rawValue + ":" + address.lowercased()
        if k == key && !force && Date().timeIntervalSince(at) < 90 { return }
        if k != key {
            v = [:]
            t = [:]
            src = [:]
            wallets = []
            used = []
        }
        key = k
        at = Date()
        loading = true
        let parts: [GFPart] = await withTaskGroup(of: (Int, GFPart?).self) { g in
            g.addTask { return (0, await GFSrc.okx(chain, address)) }
            g.addTask { return (1, await GFSrc.binance(chain, address)) }
            g.addTask { return (2, await GFSrc.blockscout(chain, address)) }
            g.addTask { return (3, await GFSrc.goplus(chain, address)) }
            g.addTask { return (4, await GFSrc.rugcheck(chain, address)) }
            g.addTask { return (5, await GFSrc.jupiter(chain, address)) }
            g.addTask { return (6, await GFSrc.honeypot(chain, address)) }
            var tmp: [(Int, GFPart?)] = []
            for await r in g { tmp.append(r) }
            tmp.sort { $0.0 < $1.0 }
            return tmp.compactMap { $0.1 }
        }
        if k != key {
            loading = false
            return
        }
        var nv: [String: Double] = [:]
        var ns: [String: String] = [:]
        var nt: [String: String] = [:]
        var nw: [GFWallet] = []
        for p in parts {
            for (a, b) in p.nums where nv[a] == nil {
                nv[a] = b
                ns[a] = p.name
            }
            if nw.isEmpty && !p.wallets.isEmpty { nw = p.wallets }
            if let r = p.texts["okxRisk"] { nt["okxRisk"] = r }
        }
        if let s = ns["top10"], let part = parts.first(where: { $0.name == s }), let note = part.texts["top10note"] { nt["top10note"] = note }
        v = nv
        t = nt
        src = ns
        wallets = nw
        used = parts.map { $0.name }
        loading = false
    }

    func okxTest() async -> String {
        let r = await GFSrc.okxCall("/api/v6/dex/market/token/advanced-info?chainIndex=1&tokenContractAddress=0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        if r.0 != nil { return "OKX Web3 连接正常，代币页顶部会自动补上 狙击 / 捆绑 / 老鼠仓 / Dev 持仓 / 前十占比" }
        return r.1.isEmpty ? "OKX 没有返回数据" : r.1
    }

    // 数据条里「百分比」类项目：GMGN 优先，其次免费来源
    static func pctVal(_ g: Double?, _ key: String, _ lo: Double, _ hi: Double, _ none: GMVal) -> GMVal {
        var val: Double? = g
        var s: String = "GMGN"
        if val == nil, let x = shared.v[key] {
            val = x
            s = shared.src[key] ?? "免费数据源"
        }
        guard let x = val else { return none }
        return GMVal(text: String(format: "%.1f%%", x), color: GMMetricCatalog.pctColor(x, lo, hi), rows: [("占比", String(format: "%.2f%%", x)), ("数据来源", s)])
    }
}

// MARK: - 没有 GMGN 钱包列表时，用免费来源的榜单顶上
struct GMFreeWalletsCard: View {
    let chain: Chain
    let id: String
    @ObservedObject private var fr = GMFreeStore.shared

    var body: some View {
        if fr.wallets.isEmpty || !["top10", "holders", "devhold"].contains(id) {
            EmptyView()
        } else {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("持仓榜单（" + (fr.src["top10"] ?? "免费数据源") + "，点钱包 → 跳转 GMGN / 区块浏览器 / DeBank / Cielo）").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(fr.wallets) { w in
                        Menu {
                            GMWalletMenuContent(chain: chain, addr: w.addr)
                        } label: {
                            HStack(spacing: 8) {
                                Text(Addr.short(w.addr)).font(.caption.monospaced()).foregroundStyle(Color.primary)
                                if let tg = w.tag, !tg.isEmpty { Text(tg).font(.caption2).foregroundStyle(Color.orange).lineLimit(1) }
                                else if w.isContract { Text("合约/池子").font(.caption2).foregroundStyle(Color.orange) }
                                Spacer()
                                Text(String(format: "%.2f%%", w.pct)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Color.primary)
                                Image(systemName: "arrow.up.right.square").font(.caption).foregroundStyle(Color.accentColor)
                            }
                        }
                        Divider()
                    }
                }
            }
        }
    }
}

// MARK: - 设置页：免费数据源（OKX Web3 Key 可选）
struct GMFreeSettings: View {
    @AppStorage("okxWebKey", store: Cfg.defaults) private var key = ""
    @AppStorage("okxWebSecret", store: Cfg.defaults) private var sec = ""
    @AppStorage("okxWebPass", store: Cfg.defaults) private var pass = ""
    @AppStorage("okxWebProject", store: Cfg.defaults) private var proj = ""
    @State private var msg: String?
    @State private var testing = false

    var body: some View {
        Section("免费数据源（代币页顶部数据条）") {
            Text("已默认启用，不需要任何 Key：币安 Web3、Blockscout（Robinhood / ETH / Base / OP / Arbitrum / Polygon）、GoPlus、RugCheck、Honeypot.is、Jupiter。币安、欧易交易所的 API 密钥只管账户资产，不含链上持仓数据。").font(.caption).foregroundStyle(.secondary)
            SecureField(key.isEmpty ? "OKX Web3 API Key（选填）" : "API Key 已保存（粘贴新的可替换）", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(sec.isEmpty ? "OKX Web3 Secret Key" : "Secret 已保存", text: $sec)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(pass.isEmpty ? "OKX Web3 口令（Passphrase）" : "口令已保存", text: $pass)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField(proj.isEmpty ? "Project ID（没有就留空）" : "Project ID 已保存", text: $proj)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                Button("测试 OKX 连接") {
                    Task {
                        testing = true
                        msg = await GMFreeStore.shared.okxTest()
                        testing = false
                    }
                }
                .disabled(testing || key.isEmpty || sec.isEmpty || pass.isEmpty)
                if testing { Spacer(); ProgressView() }
            }
            if let m = msg { Text(m).font(.footnote).foregroundStyle(.secondary) }
            Text("OKX Web3 Key 是另一套免费 Key（不是交易所 API）：web3.okx.com → OnchainOS → Dev Portal 创建，每月有免费额度。填上后会补齐 狙击者、捆绑交易、老鼠仓、Dev 持仓、前十占比。").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 工具箱：用户给的整份清单，按当前代币生成一键跳转
struct GFTool: Identifiable {
    let name: String
    let url: String
    let note: String
    let only: String   // "" 全部；"sol" 只 Solana；"evm" 只 EVM
    var id: String { name + url }
    init(_ name: String, _ url: String, _ note: String = "", _ only: String = "") {
        self.name = name
        self.url = url
        self.note = note
        self.only = only
    }
}

struct GFGroup: Identifiable {
    let id: String
    let items: [GFTool]
    init(_ title: String, _ items: [GFTool]) {
        self.id = title
        self.items = items
    }
}

enum GFMap {
    static func gm(_ c: Chain) -> String {
        switch c {
        case .solana: return "sol"
        case .eth: return "eth"
        default: return c.rawValue
        }
    }
    static func dt(_ c: Chain) -> String {
        switch c {
        case .eth: return "ether"
        case .bsc: return "bnb"
        default: return c.rawValue
        }
    }
    static func ave(_ c: Chain) -> String { return c == .eth ? "eth" : c.rawValue }
    static func bm(_ c: Chain) -> String {
        switch c {
        case .solana: return "sol"
        case .eth: return "eth"
        default: return c.rawValue
        }
    }
    static func es(_ c: Chain) -> String {
        switch c {
        case .solana: return "https://solscan.io"
        case .eth: return "https://etherscan.io"
        case .bsc: return "https://bscscan.com"
        case .base: return "https://basescan.org"
        case .arbitrum: return "https://arbiscan.io"
        case .optimism: return "https://optimistic.etherscan.io"
        case .polygon: return "https://polygonscan.com"
        case .robinhood: return "https://robinhoodchain.blockscout.com"
        case .xlayer: return "https://www.oklink.com/x-layer"
        case .okc: return "https://www.oklink.com/oktc"
        }
    }
    static func cid(_ c: Chain) -> String {
        switch c {
        case .eth: return "1"
        case .bsc: return "56"
        case .base: return "8453"
        case .arbitrum: return "42161"
        case .optimism: return "10"
        case .polygon: return "137"
        case .robinhood: return "4663"
        case .xlayer: return "196"
        case .okc: return "66"
        case .solana: return "501"
        }
    }
    static func hp(_ c: Chain) -> String { return c == .eth ? "ethereum" : c.rawValue }
    static func ts(_ c: Chain) -> String { return c.rawValue }
}

enum GFTools {
    static let live: [GFTool] = [
        GFTool("Dexscreener", "https://dexscreener.com/{ds}/{p}", "已接入：行情、池子、Dex 付费"),
        GFTool("GeckoTerminal", "https://www.geckoterminal.com/{gt}/pools/{p}", "已接入：K 线、成交"),
        GFTool("DEXTools", "https://www.dextools.io/app/en/{dt}/pair-explorer/{p}", "DEXT"),
        GFTool("Birdeye", "https://birdeye.so/token/{a}?chain={ds}", "代币 / 钱包 PnL"),
        GFTool("GMGN", "https://gmgn.ai/{gm}/token/{a}", "聪明钱、狙击、捆绑"),
        GFTool("Ave", "https://ave.ai/token/{a}-{ave}", ""),
        GFTool("Bubblemaps", "https://app.bubblemaps.io/{bm}/token/{a}", "持仓关联图"),
        GFTool("Arkham", "https://intel.arkm.com/explorer/token/{a}", "链上实体标签"),
        GFTool("区块浏览器", "{es}/token/{a}", "Solscan / Etherscan 系 / Blockscout"),
        GFTool("Pump.fun", "https://pump.fun/coin/{a}", "发射台页面", "sol"),
        GFTool("Jupiter", "https://jup.ag/swap/SOL-{a}", "买卖", "sol"),
        GFTool("Raydium", "https://raydium.io/swap/?inputMint=sol&outputMint={a}", "买卖", "sol"),
    ]

    static let safety: [GFTool] = [
        GFTool("RugCheck", "https://rugcheck.xyz/tokens/{a}", "已接入数据：持有者、前十、Dev、内部钱包", "sol"),
        GFTool("GoPlus", "https://gopluslabs.io/token-security/{a}", "已接入数据：持有者、前十、税率、蜜罐、LP 锁定"),
        GFTool("Honeypot.is", "https://honeypot.is/{hp}?address={a}", "已接入数据：蜜罐、实测买卖税", "evm"),
        GFTool("Token Sniffer", "https://tokensniffer.com/token/{ts}/{a}", "", "evm"),
        GFTool("De.Fi Scanner", "https://de.fi/scanner/contract/{a}?chainId={cid}", "", "evm"),
        GFTool("Quick Intel", "https://app.quickintel.io/scanner?type=token&chain={ts}&token={a}", "", "evm"),
        GFTool("StaySAFU", "https://staysafu.org", ""),
        GFTool("RugDoc", "https://rugdoc.io", ""),
        GFTool("GhostScan", "https://ghostlabs.asia/ghostscan.html", ""),
        GFTool("RugMunch", "https://docs.cryptorugmunch.com/rmi/api-scanner/", "扫描 API 文档"),
        GFTool("币安 Web3 代币接口", "https://github.com/binance/binance-skills-hub", "已接入数据：持有者、前十（ETH / BSC / Base / Solana）"),
        GFTool("OKX Web3 / OnchainOS", "https://web3.okx.com/onchain-os/dev-portal", "需免费 Web3 Key（设置里填）：狙击、捆绑、Dev、前十"),
        GFTool("Blockscout", "https://docs.blockscout.com/robinhood-api", "已接入数据：Robinhood 等链的持有者、前十、Dev"),
    ]

    static let wallet: [GFTool] = [
        GFTool("Cielo", "https://cielo.finance", "钱包追踪"),
        GFTool("Nansen", "https://nansen.ai", "聪明钱（多为付费）"),
        GFTool("Zerion", "https://zerion.io/api/ethereum", "钱包资产 API"),
        GFTool("Dune", "https://dune.com", "链上看板"),
        GFTool("Flipside", "https://flipsidecrypto.xyz", "链上分析"),
        GFTool("Glassnode", "https://glassnode.com", "链上指标"),
        GFTool("CryptoQuant", "https://cryptoquant.com", "交易所流向"),
        GFTool("DeFiLlama", "https://api-docs.defillama.com/llms.txt", "TVL / 价格 API 文档"),
        GFTool("CoinMarketCal", "https://coinmarketcal.com", "事件日历"),
        GFTool("Birdeye 钱包 PnL", "https://birdeye.so", ""),
        GFTool("SolanaTracker PnL", "https://data.solanatracker.io/pnl/", "钱包盈亏 API"),
        GFTool("Solana Portfolio Tracker", "https://www.niks3089.com/posts/solana-portfolio-tracker/", "文章"),
        GFTool("Shyft", "https://shyft.to", "Solana 数据 API"),
        GFTool("Solscan", "https://solscan.io", "Solana 浏览器"),
    ]

    static let api: [GFTool] = [
        GFTool("GeckoTerminal API", "https://api.geckoterminal.com/api/v2", "已接入"),
        GFTool("DexScreener API", "https://api.dexscreener.com", "已接入"),
        GFTool("CoinGecko（Demo）", "https://www.coingecko.com/en/api", ""),
        GFTool("Binance klines", "https://developers.binance.com/docs/binance-spot-api-docs/rest-api/market-data-endpoints", "GET /api/v3/klines"),
        GFTool("CCXT", "https://github.com/ccxt/ccxt", ""),
        GFTool("Pump.fun frontend-api-v3", "https://github.com/penguin-life/meme-terminal/blob/HEAD/skills/pump-fun/SKILL.md", ""),
        GFTool("PumpPortal", "https://solanacompass.com/projects/pumpportal", ""),
        GFTool("Codex", "https://www.codex.io/blog/pump-fun-api", ""),
        GFTool("Jupiter Price v3", "https://api.jup.ag/price/v3", ""),
        GFTool("Raydium V3", "https://api-v3.raydium.io", ""),
        GFTool("CoinStats", "https://coinstats.app/blog/best-free-crypto-api/", ""),
        GFTool("CoinMarketCap（AI Agent API）", "https://coinmarketcap.com/api/resources/coinmarketcap-api-for-ai-agents/", ""),
        GFTool("Free Crypto News", "https://mcpservers.org/servers/nirholas/free-crypto-news", ""),
        GFTool("PublicNode", "https://publicnode.com", "RPC"),
        GFTool("dRPC", "https://drpc.org", "RPC"),
        GFTool("Ankr", "https://ankr.com", "RPC"),
        GFTool("1RPC", "https://1rpc.io", "RPC"),
    ]

    static let charts: [GFTool] = [
        GFTool("LightweightChartsIOS", "https://deepwiki.com/tradingview/LightweightChartsIOS/1.2-quick-start", "App 现用同一套 TradingView Lightweight Charts"),
        GFTool("KSChart", "https://deepwiki.com/sevtin/KSChart", "原生 K 线（备选）"),
        GFTool("DGCharts", "https://swiftpackageregistry.com/ChartsOrg/Charts", "原生图表（备选）"),
        GFTool("CHKLineChart", "https://deepwiki.com/zhiquan911/CHKLineChart", "原生 K 线（备选）"),
        GFTool("CandleKit", "https://dev.to/lalanachami/candlekit-a-native-swiftui-candlestick-chart-no-webview-1odn", "SwiftUI 原生蜡烛图（备选）"),
        GFTool("SwiftCharts", "https://cocoapods.org/pods/SwiftCharts", "备选"),
    ]

    static let repos: [GFTool] = [
        GFTool("Memcoin-Sniper-Bot", "https://github.com/vineetdev02/memcoin-sniper-bot/blob/HEAD/MEMECOIN_SNIPER_PLAN.md", ""),
        GFTool("MemeBot", "https://github.com/fariz4446/MemeBot/blob/main/README.md", ""),
        GFTool("1ai-nexus", "https://github.com/oyi77/1ai-nexus/blob/HEAD/README.md", ""),
        GFTool("Cabal-Hunter", "https://github.com/paulf280-ui/solana-safe-sniper-mcp-template/blob/HEAD/README.md", ""),
        GFTool("daily-alpha-scanner", "https://github.com/zhuyansen/daily-alpha-scanner/blob/HEAD/SKILL.md", ""),
        GFTool("onchain-alpha-radar", "https://github.com/zhuyansen/onchain-alpha-radar/blob/HEAD/.claude/skills/daily-alpha-scanner/SKILL.md", ""),
        GFTool("OpenTrading 聪明钱", "https://github.com/orangejustin/opentrading/blob/HEAD/docs/SMART_MONEY.md", ""),
        GFTool("mona-vault crypto-smart-money", "https://github.com/priandhi/mona-vault/blob/HEAD/backup/profiles-reset-2026-06-28/profiles/yerin/skills/crypto/crypto-smart-money/SKILL.md", ""),
        GFTool("hyperliquid-whale-tracker", "https://github.com/michalszafron-netizen/autmattrader/blob/HEAD/hyperliquid-whale-tracker/.claude/skills/hyperliquid-whale-tracker/SKILL.md", ""),
        GFTool("solenrich", "https://github.com/0xsardius/solenrich/blob/HEAD/docs/trenches-scope.md", ""),
        GFTool("coin-scout", "https://glama.ai/mcp/servers/dennisyilmaz/coin-scout/tree", ""),
        GFTool("ScamHound", "https://github.com/runtimeadmin/scamhound/blob/HEAD/docs/scamhound_build_planV2.md", ""),
        GFTool("forta-solidus-bot", "https://github.com/forta-network/forta-solidus-bot", ""),
        GFTool("base-trading-bot-starter", "https://github.com/ak10082247-max/base-trading-bot-starter", ""),
        GFTool("CryptoWildfire", "https://github.com/codebytelabs/CryptoWildfire", ""),
        GFTool("sentiment-analysis", "https://github.com/yahmez3/claude-skills/blob/HEAD/skills/trading/sentiment-analysis/SKILL.md", ""),
        GFTool("freqtrade", "https://github.com/freqtrade/freqtrade", ""),
        GFTool("LimpusCrypto", "https://github.com/georgelimpus/LimpusCrypto", ""),
        GFTool("crypto-portfolio-tracker-swiftui", "https://github.com/tri1911/crypto-portfolio-tracker-swiftui/blob/HEAD/README.md", ""),
        GFTool("Bitpal-iOS", "https://github.com/pointwelve/bitpal-ios/blob/HEAD/Bitpal-v2/.specify/memory/constitution.md", ""),
        GFTool("ccxt-pro-swift", "https://medium.com/@samgermain048/build-a-native-crypto-trading-app-for-mac-iphone-using-ccxt-pro-swift-63f9c6129504", ""),
        GFTool("bubblemaps-hackaton", "https://github.com/0ximgh05t/bubblemaps-hackaton", ""),
        GFTool("dex-gem-trading-bot", "https://github.com/pasmars/fxcrypt1/blob/HEAD/docs/SKILL.md", ""),
        GFTool("tckr", "https://github.com/allogenes-labs/tckr/blob/HEAD/CHANGELOG.md", ""),
        GFTool("JINI", "https://github.com/muddassirshadab/jini-hyperliquid-wallet-intelligence-dashboard/blob/HEAD/README.md", ""),
        GFTool("wallet-profiling", "https://github.com/neversight/learn-skills.dev/blob/HEAD/data/skills-md/agiprolabs/claude-trading-skills/wallet-profiling/SKILL.md", ""),
        GFTool("quantstats + vectorbt 回测", "https://www.quantide.io/guides/how-to-backtest-a-trading-strategy-in-python", ""),
        GFTool("HeadlessTracker", "https://github.com/tamasPetki/HeadlessTracker", ""),
    ]

    static var groups: [GFGroup] {
        return [
            GFGroup("按当前代币一键打开", live),
            GFGroup("合约安全 / 持仓数据来源", safety),
            GFGroup("聪明钱 · 钱包追踪 · 链上分析", wallet),
            GFGroup("行情 / 数据 API · RPC", api),
            GFGroup("iOS 图表库", charts),
            GFGroup("开源项目 / Skill 参考", repos),
        ]
    }
}

struct GMToolbox: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var fr = GMFreeStore.shared
    @AppStorage("okxWebKey", store: Cfg.defaults) private var okxKey = ""
    @AppStorage("gmgnKey", store: Cfg.defaults) private var gmgnKey = ""
    @Environment(\.dismiss) private var dismiss

    private func fill(_ s: String) -> String {
        var o: String = s
        let ch: Chain = vm.chain
        let pairs: [(String, String)] = [
            ("{a}", vm.address),
            ("{p}", vm.main?.pairAddress ?? ""),
            ("{ds}", ch.dexId),
            ("{gt}", ch.geckoId),
            ("{gm}", GFMap.gm(ch)),
            ("{dt}", GFMap.dt(ch)),
            ("{ave}", GFMap.ave(ch)),
            ("{bm}", GFMap.bm(ch)),
            ("{es}", GFMap.es(ch)),
            ("{cid}", GFMap.cid(ch)),
            ("{hp}", GFMap.hp(ch)),
            ("{ts}", GFMap.ts(ch)),
        ]
        for r in pairs { o = o.replacingOccurrences(of: r.0, with: r.1) }
        return o
    }

    private func visible(_ t: GFTool) -> Bool {
        if t.only == "sol" && vm.chain != .solana { return false }
        if t.only == "evm" && vm.chain == .solana { return false }
        if t.url.contains("{p}") && (vm.main?.pairAddress ?? "").isEmpty { return false }
        if t.url.contains("{a}") && vm.address.isEmpty { return false }
        return true
    }

    private func row(_ t: GFTool) -> some View {
        let s: String = fill(t.url)
        return Group {
            if let u = URL(string: s) {
                Link(destination: u) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                            if !t.note.isEmpty { Text(t.note).font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("本币数据来源") {
                    if fr.loading {
                        Text("读取中…").font(.footnote).foregroundStyle(.secondary)
                    } else if fr.used.isEmpty {
                        Text("免费来源暂时都没有这个币的持仓数据（新币，或该链没有覆盖）").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("已返回：" + fr.used.joined(separator: "、")).font(.footnote)
                    }
                    Text("GMGN Key：" + (gmgnKey.isEmpty ? "未填" : "已填") + "　OKX Web3 Key：" + (okxKey.isEmpty ? "未填" : "已填")).font(.caption).foregroundStyle(.secondary)
                    if let r = fr.t["okxRisk"] { Text("OKX 风控等级：" + r + "（数字越大越危险）").font(.caption).foregroundStyle(.secondary) }
                }
                ForEach(GFTools.groups) { g in
                    let items: [GFTool] = g.items.filter { visible($0) }
                    if !items.isEmpty {
                        Section(g.id) {
                            ForEach(items) { t in row(t) }
                        }
                    }
                }
            }
            .navigationTitle("工具箱")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}
