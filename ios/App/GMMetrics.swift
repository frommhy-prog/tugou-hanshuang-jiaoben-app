import SwiftUI
import UIKit

enum GMMarketKind {
    // 内盘 = 还在发射台的曲线里；外盘 = 已经毕业到公开 DEX 池
    static func text(dex: String?, pad: GMLaunchpad?) -> String? {
        let d: String = (dex ?? "").lowercased()
        let inner: [String] = ["pumpfun", "fourmeme", "moonshot", "launchlab", "letsbonk", "bonkfun", "believe", "flap", "virtuals"]
        for k in inner where d.contains(k) { return "内盘" }
        if pad != nil { return "外盘" }
        return nil
    }
}

struct GMVal {
    var text: String
    var color: Color
    var icon: String? = nil
    var rows: [(String, String)] = []
}

struct GMMetricDef {
    let id: String
    let title: String
    let desc: String
}

struct GMSheetID: Identifiable {
    let id: String
}

enum GMMetricCatalog {
    static let all: [GMMetricDef] = [
        GMMetricDef(id: "top10", title: "前十占比", desc: "持币最多的 10 个钱包（不含池子）合计占总供应量的比例，越高越容易被少数人砍盘。低于 20% 较分散，高于 50% 很危险。"),
        GMMetricDef(id: "holders", title: "持有者", desc: "目前持有这个币的不同钱包总数。越多越分散，但要和前十占比、新钱包占比一起看。"),
        GMMetricDef(id: "dexpaid", title: "Dex付费", desc: "项目方是否在 Dexscreener 付费更新资料页，或已由社区接管（CTO）。付费不等于安全，只说明有人愿意花钱做展示。"),
        GMMetricDef(id: "devhold", title: "Dev持仓", desc: "币的创建者（Dev）现在还拿着多少。Dev 仍大量持有意味着随时可能砍盘；已清仓不等于安全，要到「筹码」里查资金去向。"),
        GMMetricDef(id: "sniper", title: "狙击者", desc: "开盘第一时间就买入的钱包（多为机器人）。显示它们目前还持有的占比，没有持仓数据时显示个数。"),
        GMMetricDef(id: "bundler", title: "捆绑交易", desc: "开盘时被机器人打包批量买入的成交占比，高于 30% 说明价格可能被操纵。"),
        GMMetricDef(id: "rat", title: "老鼠仓", desc: "疑似内幕 / 偏门钱包提前拿货的占比。越高越容易被提前布局的人抽走流动性。"),
        GMMetricDef(id: "phishing", title: "钓鱼钱包", desc: "被标记为「钓鱼 / 诱导」的钱包成交占比，用来判断项目方是否在钓跟风者。"),
        GMMetricDef(id: "tax", title: "买/卖税", desc: "买入税 / 卖出税，总税率 = 两者之和。卖税超过 10% 基本不值得碰。"),
        GMMetricDef(id: "fresh", title: "新钱包", desc: "持有者里刚创建不久的钱包占比，偏高常见于分散模拟散户的老鼠仓。"),
        GMMetricDef(id: "rug", title: "跑路风险", desc: "GMGN 的跑路概率评分（0–100%），高于 30% 为高风险，只能参考，不是结论。"),
        GMMetricDef(id: "mint", title: "增发/冻结", desc: "Solana：是否已放弃增发权限和冻结权限；EVM：合约所有权是否已放弃。没放弃 = 开发者还能增发或冻结你的钱包。"),
        GMMetricDef(id: "honeypot", title: "蜜罐", desc: "能买不能卖的合约（仅 BSC / Base / ETH 可检测，Solana 不适用）。"),
        GMMetricDef(id: "lp", title: "烧池/锁池", desc: "流动性池的 LP 是否已烧毁或锁定，没烧没锁就可能被一键撒池。"),
        GMMetricDef(id: "smart", title: "聪明钱/KOL", desc: "目前持有这个币的 GMGN 标记「聪明钱」和「知名 KOL」钱包数。"),
        GMMetricDef(id: "bluechip", title: "蓝筹指数", desc: "持有者里「蓝筹钱包」（长期持有主流资产的老钱包）的占比。"),
        GMMetricDef(id: "curve", title: "内盘/外盘", desc: "内盘 = 还在发射台曲线里交易；外盘 = 已经毕业进入公开 DEX 池。"),
    ]

    static func def(_ id: String) -> GMMetricDef? { all.first { $0.id == id } }

    static func pctColor(_ v: Double, _ lo: Double, _ hi: Double) -> Color {
        v < lo ? Color.green : (v < hi ? Color.orange : Color.red)
    }

    static func compact(_ n: Double) -> String {
        if n >= 1_000_000 { return String(format: "%.2fM", n / 1_000_000) }
        if n >= 1000 { return String(format: "%.1fK", n / 1000) }
        return String(format: "%.0f", n)
    }

    @MainActor
    static func eval(_ id: String, vm: UTokenVM, gm: GMGNStore, paid: GMPaid?) -> GMVal {
        let hint: String = gm.hasKey ? "GMGN 暂未返回这一项" : "免费来源（币安 Web3、Blockscout、GoPlus、RugCheck 等）暂时没有这一项；填 GMGN 或 OKX Web3 Key 可补全（设置）"
        let none = GMVal(text: "—", color: Color.secondary, rows: [("说明", hint)])

        func pct(_ x: Double?, _ lo: Double, _ hi: Double, _ extra: [(String, String)]) -> GMVal {
            guard let v = x else { return none }
            return GMVal(text: String(format: "%.1f%%", v), color: pctColor(v, lo, hi), rows: [("占比", String(format: "%.2f%%", v))] + extra + [("数据来源", "GMGN")])
        }

        switch id {
        case "top10":
            var v: Double? = gm.num("top_10_holder_rate", "stat.top_10_holder_rate").map { $0 * 100 }
            var src = "GMGN"
            if v == nil, let w = vm.conc?.wallets10 ?? vm.conc?.top10 {
                v = Double(w)
                src = "链上榜单（已剔除池子和合约）"
            }
            if v == nil, let fx = GMFreeStore.shared.v["top10"] {
                v = fx
                src = (GMFreeStore.shared.src["top10"] ?? "免费数据源") + (GMFreeStore.shared.t["top10note"].map { "（" + $0 + "）" } ?? "")
            }
            guard let x = v else { return none }
            return GMVal(text: String(format: "%.1f%%", x), color: pctColor(x, 20, 50), rows: [("前十持仓占比", String(format: "%.2f%%", x)), ("数据来源", src)])
        case "holders":
            let gmN: Double? = gm.num("holder_count", "stat.holder_count")
            guard let n = gmN ?? GMFreeStore.shared.v["holders"] else { return none }
            return GMVal(text: compact(n), color: Color.primary, rows: [("持有钱包数", String(Int(n))), ("数据来源", gmN != nil ? "GMGN" : (GMFreeStore.shared.src["holders"] ?? "免费数据源"))])
        case "dexpaid":
            guard let p = paid else { return GMVal(text: "—", color: Color.secondary, icon: "dollarsign.circle", rows: [("说明", "查询 Dexscreener 付费状态中或暂无结果")]) }
            return GMVal(text: p.text, color: p.paid ? Color.green : Color.secondary, icon: p.paid ? "dollarsign.circle.fill" : "dollarsign.circle", rows: [("资料页付费", p.profile ? "已付" : "未付"), ("社区接管 CTO", p.cto ? "是" : "否"), ("广告位", p.ad ? "有" : "无"), ("数据来源", "Dexscreener")])
        case "devhold":
            let fs = GMFreeStore.shared
            let gmDev: Double? = gm.num("creator_balance_rate", "stat.creator_hold_rate").map { $0 * 100 }
            let r: Double? = gmDev ?? fs.v["dev"]
            let st: String? = gm.str("creator_token_status")
            if r == nil && st == nil { return none }
            let stText: String = st == "creator_hold" ? "仍持有" : (st == "creator_close" ? "已清仓" : "未知")
            var rows: [(String, String)] = []
            if st != nil { rows.append(("创建者状态", stText)) }
            if let x = r { rows.append(("创建者持仓占比", String(format: "%.2f%%", x))) }
            if let t = gm.num("dev_team_hold_rate", "stat.dev_team_hold_rate") { rows.append(("Dev 团队持仓", String(format: "%.2f%%", t * 100))) }
            let devFromGM: Bool = gmDev != nil || st != nil
            rows.append(("数据来源", devFromGM ? "GMGN" : (fs.src["dev"] ?? "免费数据源")))
            let col: Color = st == "creator_close" ? Color.green : ((r ?? 0) > 5 ? Color.red : Color.orange)
            return GMVal(text: r.map { String(format: "%.1f%%", $0) } ?? stText, color: col, rows: rows)
        case "sniper":
            let fs = GMFreeStore.shared
            let cnt: Double? = gm.num("sniper_count", "wallet_tags_stat.sniper_wallets") ?? fs.v["sniperN"]
            let gmHold: Double? = gm.sniperHold()
            let hold: Double? = gmHold ?? fs.v["sniper"]
            if cnt == nil && hold == nil { return none }
            var rows: [(String, String)] = []
            if let c = cnt { rows.append(("狙击钱包数", String(Int(c)))) }
            if let h = hold { rows.append(("狙击者当前持仓", String(format: "%.2f%%", h))) }
            let fromFree: Bool = gmHold == nil && fs.v["sniper"] != nil
            rows.append(("数据来源", fromFree ? (fs.src["sniper"] ?? "免费数据源") : "GMGN"))
            if let h = hold { return GMVal(text: String(format: "%.2f%%", h), color: pctColor(h, 3, 10), rows: rows) }
            let c = cnt ?? 0
            return GMVal(text: String(Int(c)) + " 个", color: c < 5 ? Color.green : (c <= 20 ? Color.orange : Color.red), rows: rows)
        case "bundler":
            return GMFreeStore.pctVal(gm.num("bundler_trader_amount_rate", "stat.top_bundler_trader_percentage").map { $0 * 100 }, "bundle", 5, 15, none)
        case "rat":
            return GMFreeStore.pctVal(gm.num("suspected_insider_hold_rate", "rat_trader_amount_rate", "stat.top_rat_trader_percentage").map { $0 * 100 }, "insider", 5, 15, none)
        case "phishing":
            return pct(gm.num("stat.top_entrapment_trader_percentage").map { $0 * 100 }, 3, 10, [])
        case "fresh":
            return pct(gm.num("stat.fresh_wallet_rate").map { $0 * 100 }, 20, 50, [])
        case "tax":
            var b: Double? = gm.num("buy_tax").map { $0 * 100 }
            var s: Double? = gm.num("sell_tax").map { $0 * 100 }
            var src = "GMGN"
            if b == nil && s == nil, let sc = vm.security {
                b = sc.buyTax
                s = sc.sellTax
                src = "合约扫描"
            }
            if b == nil && s == nil, let fb = GMFreeStore.shared.v["buyTax"] ?? GMFreeStore.shared.v["sellTax"] {
                _ = fb
                b = GMFreeStore.shared.v["buyTax"]
                s = GMFreeStore.shared.v["sellTax"]
                src = GMFreeStore.shared.src["buyTax"] ?? GMFreeStore.shared.src["sellTax"] ?? "免费数据源"
            }
            if b == nil && s == nil { return none }
            let bb: Double = b ?? 0
            let ss: Double = s ?? 0
            let mx: Double = max(bb, ss)
            let col: Color = mx >= 10 ? Color.red : (mx > 0 ? Color.orange : Color.green)
            return GMVal(text: String(format: "%.0f/%.0f%%", bb, ss), color: col, rows: [("买入税", String(format: "%.1f%%", bb)), ("卖出税", String(format: "%.1f%%", ss)), ("总税率", String(format: "%.1f%%", bb + ss)), ("数据来源", src)])
        case "rug":
            return pct(gm.num("rug_ratio").map { $0 * 100 }, 10, 30, [])
        case "mint":
            if vm.chain == .solana {
                var m: Bool? = nil
                var f: Bool? = nil
                if let x = gmPath(gm.sec, "renounced_mint") as? Bool { m = x }
                if let x = gmPath(gm.sec, "renounced_freeze_account") as? Bool { f = x }
                var src = "GMGN"
                if m == nil, let au = vm.authorities {
                    m = (au.mint ?? "").isEmpty
                    f = (au.freeze ?? "").isEmpty
                    src = "链上权限读取"
                }
                guard let mm = m else { return none }
                let ff: Bool = f ?? false
                let ok: Bool = mm && ff
                return GMVal(text: ok ? "已弃" : "未弃", color: ok ? Color.green : Color.red, rows: [("增发权限", mm ? "已放弃" : "未放弃"), ("冻结权限", ff ? "已放弃" : "未放弃"), ("数据来源", src)])
            }
            if let o = gm.str("owner_renounced") {
                let ok: Bool = o == "yes"
                return GMVal(text: ok ? "已弃权" : (o == "no" ? "未弃权" : "未知"), color: ok ? Color.green : Color.orange, rows: [("合约所有权", o), ("数据来源", "GMGN")])
            }
            if let r = vm.security?.renounced {
                return GMVal(text: r ? "已弃权" : "未弃权", color: r ? Color.green : Color.orange, rows: [("数据来源", "合约扫描")])
            }
            return none
        case "honeypot":
            if vm.chain != .solana, gm.str("is_honeypot") == nil, vm.security?.honeypot == nil, let hv = GMFreeStore.shared.v["honeypot"] {
                let yes: Bool = hv > 0
                return GMVal(text: yes ? "是" : "否", color: yes ? Color.red : Color.green, rows: [("数据来源", GMFreeStore.shared.src["honeypot"] ?? "免费数据源")])
            }
            if vm.chain == .solana { return GMVal(text: "不适用", color: Color.secondary, rows: [("说明", "Solana 没有蜜罐这个概念")]) }
            if let h = gm.str("is_honeypot") {
                return GMVal(text: h == "yes" ? "是" : "否", color: h == "yes" ? Color.red : Color.green, rows: [("数据来源", "GMGN")])
            }
            if let h = vm.security?.honeypot {
                return GMVal(text: h ? "是" : "否", color: h ? Color.red : Color.green, rows: [("数据来源", "合约扫描")])
            }
            return none
        case "lp":
            if gm.str("burn_status") == nil, gmPath(gm.sec, "burn_status") == nil, vm.security?.lpLocked == nil, let lv = GMFreeStore.shared.v["lpSafe"] {
                return GMVal(text: String(format: "%.0f%%", lv), color: lv >= 90 ? Color.green : (lv >= 50 ? Color.orange : Color.red), rows: [("LP 已锁定/烧毁占比", String(format: "%.1f%%", lv)), ("数据来源", GMFreeStore.shared.src["lpSafe"] ?? "免费数据源")])
            }
            if let b = gm.str("burn_status") {
                let burned: Bool = b == "burn"
                return GMVal(text: burned ? "已烧" : b, color: burned ? Color.green : Color.orange, rows: [("LP 烧毁状态", b), ("数据来源", "GMGN")])
            }
            if gmPath(gm.sec, "burn_status") != nil {
                return GMVal(text: "未烧", color: Color.orange, rows: [("LP 烧毁状态", "未烧"), ("数据来源", "GMGN")])
            }
            if let l = vm.security?.lpLocked {
                return GMVal(text: l ? "已锁" : "未锁", color: l ? Color.green : Color.orange, rows: [("数据来源", "合约扫描")])
            }
            return none
        case "smart":
            let s: Double? = gm.num("wallet_tags_stat.smart_wallets")
            let k: Double? = gm.num("wallet_tags_stat.renowned_wallets")
            if s == nil && k == nil { return none }
            let ss: Int = Int(s ?? 0)
            let kk: Int = Int(k ?? 0)
            return GMVal(text: String(ss) + "/" + String(kk), color: ss > 0 ? Color.green : Color.secondary, rows: [("聪明钱钱包", String(ss)), ("KOL 钱包", String(kk)), ("数据来源", "GMGN")])
        case "bluechip":
            guard let b = gm.num("stat.bluechip_owner_percentage") else { return none }
            return GMVal(text: String(format: "%.1f%%", b * 100), color: Color.blue, rows: [("蓝筹钱包占比", String(format: "%.2f%%", b * 100)), ("数据来源", "GMGN")])
        case "curve":
            let d: String? = vm.main?.dexId
            let pad: GMLaunchpad? = GMLaunchpad.detect(chain: vm.chain, address: vm.address, dex: d)
            guard let t = GMMarketKind.text(dex: d, pad: pad) else {
                return GMVal(text: "—", color: Color.secondary, rows: [("说明", "不是发射台发的币，没有内外盘之分")])
            }
            return GMVal(text: t, color: t == "内盘" ? Color.orange : Color.green, rows: [("当前交易所", d ?? "未知"), ("发射台", pad?.title ?? "未识别")])
        default:
            return none
        }
    }
}

enum GMMetricPrefs {
    static let defaultOrder: [String] = ["top10", "holders", "dexpaid", "devhold", "sniper", "bundler", "rat", "phishing", "tax", "fresh", "rug", "mint", "honeypot", "lp", "smart", "bluechip", "curve"]

    static func order(_ s: String) -> [String] {
        var out: [String] = s.split(separator: ",").map { String($0) }.filter { GMMetricCatalog.def($0) != nil }
        for id in defaultOrder where !out.contains(id) { out.append(id) }
        return out
    }

    static func hidden(_ s: String) -> Set<String> { Set(s.split(separator: ",").map { String($0) }) }
}

// MARK: - 代币页顶部的横向数据条（点每一项看详情 / 钱包 / 一键跳转交易平台）
struct GMMetricStrip: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var gm = GMGNStore.shared
    @AppStorage("gmOrder", store: Cfg.defaults) private var orderStr = ""
    @AppStorage("gmHidden", store: Cfg.defaults) private var hiddenStr = ""
    @State private var paid: GMPaid?
    @State private var sheet: GMSheetID?
    @ObservedObject private var fr = GMFreeStore.shared
    @State private var showEditor = false

    private var ids: [String] {
        let h = GMMetricPrefs.hidden(hiddenStr)
        return GMMetricPrefs.order(orderStr).filter { !h.contains($0) }
    }

    private func cell(_ id: String) -> some View {
        let title: String = GMMetricCatalog.def(id)?.title ?? id
        let v = GMMetricCatalog.eval(id, vm: vm, gm: gm, paid: paid)
        return Button { sheet = GMSheetID(id: id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title).underline(true, pattern: .dot, color: Color.secondary).font(.system(size: 9.5)).foregroundStyle(Color.secondary)
                HStack(spacing: 3) {
                    if let ic = v.icon { Image(systemName: ic).font(.caption2).foregroundStyle(v.color) }
                    Text(v.text).font(.system(size: 11.5, weight: .bold)).foregroundStyle(v.color).lineLimit(1)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, -2.5)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ids, id: \.self) { id in cell(id) }
                Button { showEditor = true } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "slider.horizontal.3").font(.footnote)
                        Text("调").font(.caption2)
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: vm.chain.rawValue + ":" + vm.address) {
            paid = nil
            Task { await fr.load(chain: vm.chain, address: vm.address) }
            await gm.load(chain: vm.chain, address: vm.address)
            paid = await GMPaidApi.fetch(chainId: vm.main?.chainId ?? vm.chain.dexId, address: vm.address)
        }
        .onChange(of: vm.refreshToken) { _, _ in
            Task { await fr.load(chain: vm.chain, address: vm.address, force: true) }
            Task { await gm.load(chain: vm.chain, address: vm.address) }
        }
        .sheet(item: $sheet) { s in GMMetricSheet(id: s.id, vm: vm, paid: paid) }
        .sheet(isPresented: $showEditor) { GMMetricEditor() }
    }
}

// MARK: - 单项详情（说明、明细、相关钱包、一键跳转）
struct GMMetricSheet: View {
    let id: String
    @ObservedObject var vm: UTokenVM
    let paid: GMPaid?
    @ObservedObject private var gm = GMGNStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showBuyers = false
    @ObservedObject private var fr = GMFreeStore.shared

    private func wallets() -> [GMWallet] {
        let all = gm.wallets()
        let people = all.filter { !$0.isPool }
        switch id {
        case "top10": return Array(people.prefix(10))
        case "holders": return Array(people.prefix(20))
        case "sniper": return all.filter { $0.tags.contains("sniper") }
        case "bundler": return all.filter { $0.tags.contains("bundler") }
        case "rat": return all.filter { $0.tags.contains("rat_trader") }
        case "smart": return all.filter { w in w.tags.contains("smart_degen") || w.tags.contains("renowned") || w.tags.contains("kol") }
        case "devhold": return all.filter { w in w.tags.contains { t in t.contains("creator") || t.contains("dev") } }
        case "fresh": return all.filter { $0.isNew }
        default: return []
        }
    }

    private func kv(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }

    private func walletRow(_ w: GMWallet) -> some View {
        let pc: Color = (w.profit ?? 0) >= 0 ? Color.green : Color.red
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(w.name ?? Addr.short(w.addr)).font(.caption.monospaced()).foregroundStyle(Color.primary)
                if !w.tags.isEmpty {
                    Text(w.tags.prefix(3).joined(separator: " · ")).font(.caption2).foregroundStyle(Color.orange).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(w.pct.map { String(format: "%.2f%%", $0) } ?? "—").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Color.primary)
                if let p = w.profit { Text(GMPx.fiat(p, signed: true)).font(.caption2.monospacedDigit()).foregroundStyle(pc) }
            }
            Image(systemName: "arrow.up.right.square").font(.caption).foregroundStyle(Color.accentColor)
        }
    }

    private func walletsCard(_ ws: [GMWallet]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("相关钱包（点钱包 → 跳转 GMGN / 区块浏览器 / DeBank / Cielo 查看详情）").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(ws.prefix(30))) { w in
                    Menu { GMWalletMenuContent(chain: vm.chain, addr: w.addr) } label: { walletRow(w) }
                    Divider()
                }
            }
        }
    }

    private var tokenLinks: [(String, String)] {
        var out: [(String, String)] = []
        let gmc: String = GMGNApi.code(vm.chain) ?? vm.chain.rawValue
        out.append(("GMGN 代币", "https://gmgn.ai/" + gmc + "/token/" + vm.address))
        if let pa = vm.main?.pairAddress { out.append(("Dexscreener", "https://dexscreener.com/" + vm.chain.dexId + "/" + pa)) }
        let bubble: [String: String] = ["solana": "sol", "bsc": "bsc", "base": "base", "ethereum": "eth"]
        if ["top10", "holders", "bundler", "rat", "sniper", "fresh", "devhold"].contains(id), let b = bubble[vm.chain.dexId] {
            out.append(("Bubblemaps 关联图", "https://app.bubblemaps.io/" + b + "/token/" + vm.address))
        }
        if vm.chain == .solana { out.append(("RugCheck", "https://rugcheck.xyz/tokens/" + vm.address)) }
        else { out.append(("GoPlus 安全", "https://gopluslabs.io/token-security/" + vm.address)) }
        return out
    }

    var body: some View {
        let def = GMMetricCatalog.def(id)
        let v = GMMetricCatalog.eval(id, vm: vm, gm: gm, paid: paid)
        let ws = wallets()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        if let ic = v.icon { Image(systemName: ic).font(.title).foregroundStyle(v.color) }
                        Text(v.text).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(v.color)
                    }
                    Text(def?.desc ?? "").font(.subheadline).foregroundStyle(.secondary)
                    if !v.rows.isEmpty {
                        Card {
                            VStack(spacing: 8) {
                                ForEach(v.rows.indices, id: \.self) { i in kv(v.rows[i].0, v.rows[i].1) }
                            }
                        }
                    }
                    if !gm.hasKey {
                        Card {
                            Text("填入 GMGN API Key（设置 → GMGN 数据，免费）后，这里会显示 GMGN 的完整数据和相关钱包。").font(.footnote).foregroundStyle(.secondary)
                        }
                    } else if !gm.status.isEmpty {
                        Text(gm.status).font(.footnote).foregroundStyle(Color.orange)
                    }
                    if !ws.isEmpty { walletsCard(ws) }
                    if ws.isEmpty { GMFreeWalletsCard(chain: vm.chain, id: id) }
                    if ["top10", "holders", "sniper"].contains(id) {
                        Button { showBuyers = true } label: {
                            Label("前 70 买家状态（持仓不变 / 加仓 / 卖出 / 转走）", systemImage: "circle.grid.3x3.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!gm.hasKey)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("一键跳转查看").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            FlowLayoutLinks(items: tokenLinks)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.page)
            .navigationTitle(def?.title ?? "详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .sheet(isPresented: $showBuyers) { GMBuyersSheet(chain: vm.chain, address: vm.address) }
    }
}

// MARK: - 前 70 买家状态图（和 GMGN 同款：绿 = 持仓不变，蓝 = 加仓，半红 = 卖出部分，空心红 = 全部卖出，黄三角 = 转走）
private struct GMTri: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY + 2))
        p.addLine(to: CGPoint(x: r.maxX - 2, y: r.maxY - 2))
        p.addLine(to: CGPoint(x: r.minX + 2, y: r.maxY - 2))
        p.closeSubpath()
        return p
    }
}

struct GMBuyersSheet: View {
    let chain: Chain
    let address: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var gm = GMGNStore.shared
    @State private var rows: [BRow] = []
    @State private var msg: String?
    @State private var loading = true

    struct BRow: Identifiable {
        let id: Int
        let addr: String
        let state: Int
        let pct: Double
        let sniper: Bool
    }

    private static func classify(_ d: [String: Any]) -> Int {
        let bal: Double = gmNum(d["balance"]) ?? gmNum(d["amount_cur"]) ?? 0
        let sellPct: Double = gmNum(d["sell_amount_percentage"]) ?? 0
        let buyTx: Double = gmNum(d["buy_tx_count_cur"]) ?? 1
        let outAmt: Double = (gmNum(d["current_transfer_out_amount"]) ?? 0) + (gmNum(d["history_transfer_out_amount"]) ?? 0)
        if outAmt > 0 && sellPct < 0.5 && bal <= 0 { return 4 }
        if bal <= 0 || sellPct >= 0.99 { return 3 }
        if sellPct > 0.01 { return 2 }
        if buyTx >= 2 { return 1 }
        return 0
    }

    private func count(_ s: Int) -> Int { rows.filter { $0.state == s }.count }

    @ViewBuilder
    private func mark(_ s: Int) -> some View {
        switch s {
        case 0: Circle().fill(Color.green)
        case 1: Circle().fill(Color.blue)
        case 2:
            ZStack {
                Circle().stroke(Color(red: 0.9, green: 0.2, blue: 0.3), lineWidth: 3)
                Circle().trim(from: 0, to: 0.5).fill(Color(red: 0.9, green: 0.2, blue: 0.3))
            }
        case 3: Circle().stroke(Color(red: 0.9, green: 0.2, blue: 0.3), lineWidth: 3)
        default: GMTri().stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
        }
    }

    private func legend(_ s: Int, _ t: String) -> some View {
        HStack(spacing: 6) {
            mark(s).frame(width: 14, height: 14)
            Text(t + "：" + String(count(s))).font(.subheadline)
            Spacer()
        }
    }

    private func load() async {
        guard let cc = GMGNApi.code(chain) else { msg = "GMGN 暂不支持这条链"; loading = false; return }
        let r = await GMGNApi.fetch("/v1/market/token_top_traders", ["chain": cc, "address": address, "limit": "70", "order_by": "buy_volume_cur", "direction": "desc"])
        switch r {
        case .success(let v):
            var l: [[String: Any]] = []
            if let dd = v as? [String: Any], let x = dd["list"] as? [[String: Any]] { l = x }
            else if let x = v as? [[String: Any]] { l = x }
            var out: [BRow] = []
            for (i, d) in l.enumerated() {
                let tags: [String] = ((d["tags"] as? [String]) ?? []) + ((d["maker_token_tags"] as? [String]) ?? [])
                out.append(BRow(id: i, addr: gmStr(d["address"]) ?? "", state: Self.classify(d), pct: (gmNum(d["amount_percentage"]) ?? 0) * 100, sniper: tags.contains("sniper")))
            }
            rows = out
            if out.isEmpty { msg = "GMGN 没有返回买家列表" }
        case .failure(let e):
            msg = e.localizedDescription
        }
        loading = false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if loading { ProgressView("读取买家…") }
                    if let m = msg { Text(m).font(.footnote).foregroundStyle(Color.orange) }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 10), spacing: 12) {
                        ForEach(rows) { r in
                            Menu { GMWalletMenuContent(chain: chain, addr: r.addr) } label: {
                                mark(r.state).frame(width: 24, height: 24)
                            }
                        }
                    }
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { legend(0, "持仓不变"); legend(1, "加仓") }
                            HStack { legend(2, "卖出部分"); legend(3, "全部卖出") }
                            HStack { legend(4, "转走"); Spacer() }
                            Divider()
                            let sn: Double = rows.filter { $0.sniper }.reduce(0) { $0 + $1.pct }
                            let cur: Double = rows.reduce(0) { $0 + $1.pct }
                            Text("狙击持仓：" + String(format: "%.4f%%", sn)).font(.subheadline)
                            Text("当前持仓：" + String(format: "%.2f%%", cur)).font(.subheadline)
                            if let t = gm.num("top_10_holder_rate", "stat.top_10_holder_rate") {
                                Text("前10持仓大户：" + String(format: "%.2f%%", t * 100)).font(.subheadline)
                            }
                            Text("点任意一个图标 → 跳转 GMGN / 区块浏览器查看该钱包。状态由 GMGN 返回的买卖、转账数据推算，结果和 GMGN App 可能有细微差别。").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.page)
            .navigationTitle("前 70 买家")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .task { await load() }
        }
        .presentationDetents([.large])
    }
}

// MARK: - 调整显示项和顺序
struct GMMetricEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("gmOrder", store: Cfg.defaults) private var orderStr = ""
    @AppStorage("gmHidden", store: Cfg.defaults) private var hiddenStr = ""
    @State private var order: [String] = []
    @State private var hidden: Set<String> = []

    private func save() {
        orderStr = order.joined(separator: ",")
        hiddenStr = hidden.sorted().joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order, id: \.self) { id in
                        Toggle(isOn: Binding(get: { !hidden.contains(id) }, set: { on in
                            if on { hidden.remove(id) } else { hidden.insert(id) }
                            save()
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(GMMetricCatalog.def(id)?.title ?? id).font(.subheadline.weight(.semibold))
                                Text(GMMetricCatalog.def(id)?.desc ?? "").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                    .onMove { from, to in
                        order.move(fromOffsets: from, toOffset: to)
                        save()
                    }
                } footer: {
                    Text("拖动右侧手柄调整顺序；关掉开关就不在代币页顶部显示。每一项都能点进去看详细数据和相关钱包。")
                }
                Section {
                    Button("恢复默认") {
                        order = GMMetricPrefs.defaultOrder
                        hidden = []
                        save()
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("顶部数据显示")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .onAppear {
                order = GMMetricPrefs.order(orderStr)
                hidden = GMMetricPrefs.hidden(hiddenStr)
            }
        }
    }
}
