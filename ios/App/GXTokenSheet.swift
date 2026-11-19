import SwiftUI
import UIKit

// MARK: - 点代币头像弹出：代币 / 社媒 / 数据 三页（仿 Ave 的代币详情面板）
struct GXTokenSheet: View {
    @ObservedObject var vm: UTokenVM
    @ObservedObject private var info = GXInfoStore.shared
    @ObservedObject private var gm = GMGNStore.shared
    @ObservedObject private var fr = GMFreeStore.shared
    @ObservedObject private var hs = GXHoldersStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    private func kv(_ k: String, _ v: String, _ c: Color = Color.primary) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(v).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(c).multilineTextAlignment(.trailing)
        }
    }

    private func themeText() -> String? {
        let key: String = vm.chain.rawValue + ":" + vm.address + "#" + String(vm.refreshToken)
        guard let r = NarrativeRulesCard.store[key], let h = r.hits.first else { return nil }
        var s: String = h.title
        if !r.position.isEmpty { s += " · " + r.position }
        if !r.heat.isEmpty { s += " · " + r.heat }
        return s
    }

    // MARK: 代币页
    @ViewBuilder
    private var tokenTab: some View {
        if let m = vm.main {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        AvTokenLogo(chain: vm.chain, address: vm.address, symbol: m.baseToken?.symbol ?? vm.symbol, hint: m.info?.imageUrl, size: 56, dex: m.dexId)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.baseToken?.name ?? vm.symbol).font(.title3.bold()).lineLimit(2)
                            Text(m.baseToken?.symbol ?? vm.symbol).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    GXBadgeRow(vm: vm, pair: m)
                    if let c = m.pairCreatedAt { kv("池子创建", TZ.format(Date(timeIntervalSince1970: c / 1000))) }
                    if let c = info.created { kv("代币创建", TZ.format(c)) }
                    kv("公链", vm.chain.title)
                    kv("交易所", m.dexId ?? "未知")
                    if let pad = GMLaunchpad.detect(chain: vm.chain, address: vm.address, dex: m.dexId) {
                        kv("发射台", pad.title + (GMMarketKind.text(dex: m.dexId, pad: pad).map { "（" + $0 + "）" } ?? ""))
                    }
                    kv("合约", Addr.short(vm.address))
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("具体叙事").font(.headline)
                    if info.desc.isEmpty {
                        Text("币安 Web3 / GeckoTerminal / X 简介都没有这个币的公开描述。名称是「" + (m.baseToken?.name ?? vm.symbol) + "」，仅凭名称无法判断具体叙事，不编造。").font(.subheadline)
                    } else {
                        Text(info.descZh.isEmpty ? info.desc : info.descZh).font(.subheadline)
                        if !info.descZh.isEmpty {
                            Text("原文：" + info.desc).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("来源：" + info.descSrc + (info.descZh.isEmpty ? "" : "（机器翻译）")).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let t = themeText() { kv("规则归类", t) }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("一键跳转").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    GXAppIcons(chain: vm.chain, addr: vm.address, pair: m.pairAddress, size: 30)
                    Text("要显示 / 隐藏哪些 App：设置 → 跳转 App").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: 社媒页
    @ViewBuilder
    private var xCard: some View {
        if let h = info.xHandle {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("X 账号", systemImage: "person.crop.circle").font(.headline)
                        Spacer()
                        if info.loading { ProgressView() }
                    }
                    if let p = info.xProfile {
                        Text(p.name.isEmpty ? "@" + h : p.name).font(.title3.bold())
                        Text("@" + p.handle).font(.subheadline).foregroundStyle(.secondary)
                        HStack(spacing: 18) {
                            VStack { Text(CNUnit.wrap("", Double(p.followers), 2, "")).font(.headline); Text("粉丝").font(.caption2).foregroundStyle(.secondary) }
                            VStack { Text(CNUnit.wrap("", Double(p.following), 2, "")).font(.headline); Text("关注").font(.caption2).foregroundStyle(.secondary) }
                            VStack { Text(CNUnit.wrap("", Double(p.tweets), 2, "")).font(.headline); Text("推文").font(.caption2).foregroundStyle(.secondary) }
                        }
                        if !p.bio.isEmpty { Text(p.bio).font(.subheadline) }
                        if !p.joined.isEmpty { Text("注册：" + p.joined).font(.caption2).foregroundStyle(.secondary) }
                    } else {
                        Text("@" + h).font(.title3.bold())
                        Text(info.loading ? "读取中…" : "X 资料暂时读不到（X 限制匿名读取）").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let u = URL(string: "https://x.com/" + h) {
                        Link(destination: u) { Label("在 X 打开", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("X 最新内容").font(.headline)
                    if info.tweets.isEmpty {
                        Text(info.loading ? "读取中…" : "没有读到最新推文：X 官方嵌入接口对匿名访问有限制，可点上面「在 X 打开」直接看。").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(info.tweets) { t in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(t.text).font(.subheadline)
                            Text(t.time + " · ♥ " + String(t.likes) + " · ↻ " + String(t.rts)).font(.caption2).foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }
            }
        } else {
            Card { Text("没有找到这个币的官方 X 账号（Dexscreener / 币安 / GeckoTerminal 都没登记）。").font(.footnote).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder
    private var socialTab: some View {
        xCard
        if let tg = info.tgHandle {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Telegram：" + tg, systemImage: "paperplane").font(.headline)
                    if info.tgPosts.isEmpty { Text(info.loading ? "读取中…" : "没有读到频道最新消息（可能是群组，或未开放公开预览）").font(.footnote).foregroundStyle(.secondary) }
                    ForEach(Array(info.tgPosts.enumerated()), id: \.offset) { _, t in
                        Text(t).font(.subheadline)
                        Divider()
                    }
                    if let u = URL(string: "https://t.me/" + tg) {
                        Link(destination: u) { Label("在 Telegram 打开", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                    }
                }
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("更多").font(.headline)
                if let w = info.website, let u = URL(string: w) { Link(destination: u) { Label("官网：" + (u.host ?? w), systemImage: "globe") } }
                if let u = URL(string: "https://x.com/search?q=" + vm.address) { Link(destination: u) { Label("在 X 搜索合约", systemImage: "magnifyingglass") } }
                if let u = URL(string: "https://x.com/search?q=" + (vm.main?.baseToken?.symbol ?? vm.symbol)) { Link(destination: u) { Label("在 X 搜索代币名", systemImage: "magnifyingglass") } }
            }
        }
    }

    // MARK: 数据页
    private func cell(_ id: String) -> some View {
        let v: GMVal = GMMetricCatalog.eval(id, vm: vm, gm: gm, paid: nil)
        return VStack(spacing: 3) {
            Text(GMMetricCatalog.def(id)?.title ?? id).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Text(v.text).font(.system(size: 14, weight: .bold)).foregroundStyle(v.color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private func winRow(_ m: DexPair, _ k: String, _ t: String) -> some View {
        let b: Int = m.txns?[k]?.buys ?? 0
        let s: Int = m.txns?[k]?.sells ?? 0
        let ch: Double? = m.priceChange?[k]
        return HStack {
            Text(t).font(.caption.weight(.semibold)).frame(width: 34, alignment: .leading)
            Text(ch.map { String(format: "%+.1f%%", $0) } ?? "—").font(.caption.monospacedDigit()).foregroundStyle((ch ?? 0) >= 0 ? Color.green : Color.red).frame(width: 62, alignment: .leading)
            Text("成交 " + GMPx.fiat(m.volume?[k])).font(.caption.monospacedDigit())
            Spacer()
            Text("买 " + String(b)).font(.caption.monospacedDigit()).foregroundStyle(Color.green)
            Text("卖 " + String(s)).font(.caption.monospacedDigit()).foregroundStyle(Color.red)
        }
    }

    @ViewBuilder
    private var dataTab: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("核心指标").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(GMMetricPrefs.defaultOrder, id: \.self) { id in cell(id) }
                }
                Text("没有 GMGN / OKX Key 时，缺的项目会尽量用币安 Web3、GoPlus、RugCheck 和本机链上推算补；仍然拿不到的显示 —，不编数。").font(.caption2).foregroundStyle(.secondary)
            }
        }
        if let m = vm.main {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("最近交易").font(.headline)
                    winRow(m, "m5", "5分")
                    winRow(m, "h1", "1时")
                    winRow(m, "h6", "6时")
                    winRow(m, "h24", "24时")
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("基础数据").font(.headline)
                    kv("流动性（最深池）", GMPx.fiat(m.liq))
                    kv("市值 / FDV", GMPx.fiat(m.marketCap ?? m.fdv))
                    kv("24h 成交额", GMPx.fiat(m.volume?["h24"]))
                    if let h = fr.v["holders"] { kv("持有者", String(Int(h))) }
                    kv("池子数量", String(vm.pairs.count) + " 个")
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("安全检测").font(.headline)
                    if vm.chain == .solana {
                        if let au = vm.authorities {
                            kv("放弃增发权限", (au.mint ?? "").isEmpty ? "是" : "否", (au.mint ?? "").isEmpty ? Color.green : Color.red)
                            kv("放弃冻结权限", (au.freeze ?? "").isEmpty ? "是" : "否", (au.freeze ?? "").isEmpty ? Color.green : Color.red)
                        } else { Text("读取中或暂无数据").font(.footnote).foregroundStyle(.secondary) }
                    } else if let s = vm.security {
                        kv("蜜罐", s.honeypot == nil ? "未知" : (s.honeypot == true ? "是" : "否"))
                        kv("买入税 / 卖出税", (s.buyTax.map { String(format: "%.1f%%", $0) } ?? "—") + " / " + (s.sellTax.map { String(format: "%.1f%%", $0) } ?? "—"))
                        kv("可增发", s.mintable == nil ? "未知" : (s.mintable == true ? "是" : "否"))
                        kv("已放弃所有权", s.renounced == nil ? "未知" : (s.renounced == true ? "是" : "否"))
                    } else { Text("读取中或该链暂无合约扫描数据").font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("代币").tag(0)
                    Text("社媒").tag(1)
                    Text("数据").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                ScrollView {
                    VStack(spacing: 14) {
                        switch tab {
                        case 0: tokenTab
                        case 1: socialTab
                        default: dataTab
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color.page)
            .navigationTitle(vm.symbol)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task { await info.load(vm: vm) }
    }
}
