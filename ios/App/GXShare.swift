import SwiftUI
import UIKit

// MARK: - 分享：分享那一刻的全部最新数据 + 分析 → 折叠分类网页链接（也可发固定尺寸摘要卡），设置里可选分享哪些内容
enum GXShareKey: String, CaseIterable, Identifiable {
    case basic, metrics, narr, verdict, risk, holders, wallets, links
    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: return "基础行情（价格 / 市值 / 流动性 / 涨跌）"
        case .metrics: return "顶部数据条（前十 / Dev / 狙击 / 捆绑 / 老鼠仓 …）"
        case .narr: return "具体叙事与项目资料"
        case .verdict: return "综合研判（安全分 / 利空 / 利好 / 盯盘线）"
        case .risk: return "合约安全"
        case .holders: return "持仓集中度与前十大户"
        case .wallets: return "大户情报（狙击 / 聪明钱 / 机器人 / 新钱包）"
        case .links: return "跳转链接（GMGN / AVE / 币安 / 欧易 …）"
        }
    }

    var on: Bool { (Cfg.defaults.object(forKey: "gxShare." + rawValue) as? Bool) ?? true }
}

struct GXShareToggleRow: View {
    let k: GXShareKey
    @AppStorage private var on: Bool

    init(k: GXShareKey) {
        self.k = k
        _on = AppStorage(wrappedValue: true, "gxShare." + k.rawValue, store: Cfg.defaults)
    }

    var body: some View {
        Toggle(k.title, isOn: $on).font(.subheadline)
    }
}

@MainActor
enum GXShareBuilder {
    static let endpoint = "https://tstzm-share.from-mhy.workers.dev"

    static func snapshot(_ vm: UTokenVM) -> [String: Any] {
        var sections: [[String: Any]] = []
        func sec(_ title: String, rows: [[String]] = [], lines: [String] = []) {
            if rows.isEmpty && lines.isEmpty { return }
            sections.append(["title": title, "rows": rows, "lines": lines])
        }
        let m: DexPair? = vm.main
        let sym: String = m?.baseToken?.symbol ?? vm.symbol
        let gm = GMGNStore.shared

        if GXShareKey.basic.on, let m = m {
            var r: [[String]] = []
            r.append(["价格", GMPx.tp(m.price)])
            r.append(["市值", GMPx.cap(m.marketCap ?? m.fdv)])
            r.append(["流动性", GMPx.cap(m.liq)])
            r.append(["24h 成交额", GMPx.cap(m.volume?["h24"])])
            for (n, k) in [("5分", "m5"), ("1时", "h1"), ("6时", "h6"), ("24时", "h24")] {
                if let c = m.priceChange?[k] { r.append(["涨跌 " + n, String(format: "%+.1f%%", c)]) }
            }
            if let c = m.pairCreatedAt { r.append(["池龄", Fmt2.dur(Date().timeIntervalSince1970 - c / 1000)]) }
            r.append(["公链 / 交易所", vm.chain.title + " / " + (m.dexId ?? "未知")])
            if let pad = GMLaunchpad.detect(chain: vm.chain, address: vm.address, dex: m.dexId) {
                r.append(["发射台", pad.title + (GMMarketKind.text(dex: m.dexId, pad: pad).map { "（" + $0 + "）" } ?? "")])
            }
            r.append(["合约", vm.address])
            sec("基础行情", rows: r)
        }
        if GXShareKey.metrics.on {
            var r: [[String]] = []
            for id in GMMetricPrefs.defaultOrder {
                let v: GMVal = GMMetricCatalog.eval(id, vm: vm, gm: gm, paid: nil)
                r.append([GMMetricCatalog.def(id)?.title ?? id, v.text])
            }
            sec("数据条", rows: r)
        }
        if GXShareKey.narr.on {
            let info = GXInfoStore.shared
            var l: [String] = []
            if info.key == GXInfoStore.k(vm), !info.desc.isEmpty {
                l.append("具体叙事：" + (info.descZh.isEmpty ? info.desc : info.descZh) + "（来源 " + info.descSrc + "）")
            } else {
                l.append("项目方没有公开描述，仅凭名称无法判断具体叙事")
            }
            let key: String = vm.chain.rawValue + ":" + vm.address + "#" + String(vm.refreshToken)
            if let r = NarrativeRulesCard.store[key], let h = r.hits.first {
                l.append("规则归类：" + h.title + " · " + r.position + " · " + r.heat)
            }
            if let p = GXInfoStore.shared.xProfile, info.key == GXInfoStore.k(vm) {
                l.append("X：@" + p.handle + "，粉丝 " + String(p.followers) + "，关注 " + String(p.following))
                if !p.bio.isEmpty { l.append("X 简介：" + p.bio) }
            }
            for t in GXInfoStore.shared.tweets.prefix(3) where info.key == GXInfoStore.k(vm) { l.append("推文 " + t.time + "：" + String(t.text.prefix(140))) }
            sec("叙事与项目资料", lines: l)
        }
        if GXShareKey.verdict.on {
            let v: TokenVerdict = VerdictEngine.build(vm)
            var l: [String] = []
            l.append(v.grade + (v.score.map { "（安全分 " + String($0) + "）" } ?? "") + "：" + v.headline)
            for x in v.risks { l.append("利空：" + x.text + "（依据 " + x.basis + "）") }
            for x in v.goods { l.append("利好：" + x.text + "（依据 " + x.basis + "）") }
            for w in v.watch { l.append("盯盘：" + w) }
            for d in v.deltas { l.append(v.deltaTitle + "：" + d.text) }
            l.append(v.completeness)
            sec("综合研判", lines: l)
        }
        if GXShareKey.risk.on {
            var r: [[String]] = []
            if vm.chain == .solana {
                if let au = vm.authorities {
                    r.append(["放弃增发权限", (au.mint ?? "").isEmpty ? "是" : "否"])
                    r.append(["放弃冻结权限", (au.freeze ?? "").isEmpty ? "是" : "否"])
                }
            } else if let s = vm.security {
                r.append(["蜜罐", s.honeypot == nil ? "未知" : (s.honeypot == true ? "是" : "否")])
                r.append(["买入税", s.buyTax.map { String(format: "%.1f%%", $0) } ?? "未知"])
                r.append(["卖出税", s.sellTax.map { String(format: "%.1f%%", $0) } ?? "未知"])
                r.append(["可增发", s.mintable == nil ? "未知" : (s.mintable == true ? "是" : "否")])
                r.append(["已放弃所有权", s.renounced == nil ? "未知" : (s.renounced == true ? "是" : "否")])
                r.append(["LP 已锁定", s.lpLocked == nil ? "未知" : (s.lpLocked == true ? "是" : "否")])
            }
            sec("合约安全", rows: r)
        }
        if GXShareKey.holders.on {
            var r: [[String]] = []
            if let c = vm.conc {
                r.append(["第 1 大", String(format: "%.1f%%", c.top1 ?? 0)])
                r.append(["前 5 大", String(format: "%.1f%%", c.top5 ?? 0)])
                r.append(["前 10 大", String(format: "%.1f%%", c.top10 ?? 0)])
                if let w = c.wallets10 { r.append(["前 10 普通钱包", String(format: "%.1f%%", Double(w))]) }
            }
            for h in vm.holders.filter({ $0.kind == "wallet" }).prefix(10) {
                r.append(["#" + String(h.rank) + " " + Addr.short(h.owner), h.pct.map { String(format: "%.2f%%", $0) } ?? "—"])
            }
            sec("持仓与前十大户", rows: r)
        }
        if GXShareKey.wallets.on {
            let d: GXDerivedVals = GXHoldersStore.shared.derived
            var l: [String] = []
            if d.scanned > 0 { l.append("1 分钟内入场的大户合计持有 " + String(format: "%.2f%%", d.sniperPct) + "（" + String(d.sniperN) + " 个）；10 分钟内入场 " + String(format: "%.2f%%", d.earlyPct)) }
            if d.intelN > 0 {
                l.append("已查询 " + String(d.intelN) + " 个大户：聪明钱 " + String(d.smartN) + " 个，机器人/狙击手 " + String(d.botN) + " 个（" + String(format: "%.1f%%", d.botPct) + "），新钱包 " + String(d.freshN) + " 个（" + String(format: "%.1f%%", d.freshPct) + "）")
            }
            sec("大户情报", lines: l)
        }
        var links: [[String]] = []
        if GXShareKey.links.on {
            for l in GXApp.tokenLinks(chain: vm.chain, addr: vm.address, pair: m?.pairAddress, all: true) where l.copy == nil {
                links.append([l.app.title, l.url.absoluteString])
            }
        }
        let df = ISO8601DateFormatter()
        return [
            "v": 1,
            "title": sym,
            "subtitle": vm.chain.title + " · " + Addr.short(vm.address),
            "at": TZ.format(Date()),
            "sections": sections,
            "links": links,
        ]
        _ = df
    }

    static func upload(_ snap: [String: Any]) async -> (URL?, String) {
        guard let url = URL(string: endpoint + "/s"), let body = try? JSONSerialization.data(withJSONObject: snap) else { return (nil, "快照生成失败") }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        guard let r = try? await URLSession.shared.data(for: req) else { return (nil, "网络失败，稍后再试") }
        let code: Int = (r.1 as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200, let o = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any], let s = o["url"] as? String, let u = URL(string: s) else { return (nil, "分享服务返回 " + String(code)) }
        return (u, "")
    }

    static func summaryText(_ vm: UTokenVM) -> String {
        let m: DexPair? = vm.main
        var s: String = (m?.baseToken?.symbol ?? vm.symbol) + "（" + vm.chain.title + "） " + GMPx.tp(m?.price)
        if let c = m?.priceChange?["h24"] { s += " 24h " + String(format: "%+.1f%%", c) }
        s += " 市值 " + GMPx.cap(m?.marketCap ?? m?.fdv) + " 流动性 " + GMPx.cap(m?.liq)
        let v: TokenVerdict = VerdictEngine.build(vm)
        s += "\n" + v.grade + (v.score.map { " 安全分 " + String($0) } ?? "")
        return s
    }
}

// 固定尺寸的摘要卡（不是长图）
struct GXShareCard: View {
    let vm: UTokenVM

    var body: some View {
        let m: DexPair? = vm.main
        let v: TokenVerdict = VerdictEngine.build(vm)
        let gm = GMGNStore.shared
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AvTokenLogo(chain: vm.chain, address: vm.address, symbol: m?.baseToken?.symbol ?? vm.symbol, hint: m?.info?.imageUrl, size: 44, dex: m?.dexId)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m?.baseToken?.symbol ?? vm.symbol).font(.title3.bold())
                    Text(vm.chain.title + " · " + Addr.short(vm.address)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(v.grade).font(.subheadline.bold()).foregroundStyle(v.color)
            }
            Text(GMPx.tp(m?.price)).font(.system(size: 30, weight: .bold, design: .rounded))
            HStack {
                ForEach(["top10", "devhold", "sniper", "bundler", "rat"], id: \.self) { id in
                    let r: GMVal = GMMetricCatalog.eval(id, vm: vm, gm: gm, paid: nil)
                    VStack(spacing: 2) {
                        Text(GMMetricCatalog.def(id)?.title ?? id).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(r.text).font(.system(size: 13, weight: .bold)).foregroundStyle(r.color)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text(v.headline).font(.footnote).lineLimit(3)
            Text("TSTZ-M · " + TZ.format(Date())).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(width: 360)
        .background(Color(red: 0.97, green: 0.97, blue: 0.98))
        .environment(\.colorScheme, .light)
    }
}

struct GXShareSheet: View {
    @ObservedObject var vm: UTokenVM
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var link: URL?
    @State private var msg: String?
    @State private var items: [Any] = []
    @State private var showSys = false

    var body: some View {
        NavigationStack {
            List {
                Section("分享哪些内容（和 设置 → 分享 同步）") {
                    ForEach(GXShareKey.allCases) { k in GXShareToggleRow(k: k) }
                }
                Section {
                    Button {
                        Task {
                            busy = true
                            msg = nil
                            let snap: [String: Any] = GXShareBuilder.snapshot(vm)
                            let r = await GXShareBuilder.upload(snap)
                            link = r.0
                            if let u = r.0 {
                                items = [GXShareBuilder.summaryText(vm) + "\n" + u.absoluteString]
                                showSys = true
                            } else {
                                msg = r.1
                            }
                            busy = false
                        }
                    } label: {
                        HStack { Label("生成分享链接（折叠分类网页）", systemImage: "link"); if busy { Spacer(); ProgressView() } }
                    }
                    .disabled(busy)
                    if let u = link {
                        Text(u.absoluteString).font(.caption.monospaced()).textSelection(.enabled)
                        Button("复制链接") { UIPasteboard.general.string = u.absoluteString }
                    }
                    Button {
                        let r = ImageRenderer(content: GXShareCard(vm: vm))
                        r.scale = 3
                        if let img = r.uiImage {
                            items = [img]
                            showSys = true
                        }
                    } label: { Label("分享摘要卡（固定尺寸图片）", systemImage: "rectangle.on.rectangle") }
                    if let m = msg { Text(m).font(.footnote).foregroundStyle(Color.orange) }
                } footer: {
                    Text("链接里的数据是点击那一刻的快照：基础行情、数据条、叙事、研判、安全、持仓、大户情报都按上面的开关带上，网页里按类别折叠，不是长图。链接 30 天后失效。")
                }
            }
            .navigationTitle("分享 " + vm.symbol)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .sheet(isPresented: $showSys) { ShareSheet(items: items) }
        }
        .presentationDetents([.large])
    }
}
