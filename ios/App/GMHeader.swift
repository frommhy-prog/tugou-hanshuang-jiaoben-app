import SwiftUI
import UIKit

// GMGN 风格紧凑代币头：首屏就能看完「基础信息 + 完整 K 线」，不用滑动。
// 价格/市值开关和 K 线共用 kMcap：切换后头部大字、右侧数据、导航标题、K 线、收藏页同步变化。
struct GMHeader: View {
    @ObservedObject var vm: UTokenVM
    @AppStorage("kMcap", store: Cfg.defaults) private var mcapMode = false
    @State private var copied = false
    @State private var narr: NarrReport?

    private func col(_ v: Double?) -> Color {
        guard let v = v else { return .secondary }
        return v >= 0 ? .green : .red
    }

    private func pct(_ v: Double?) -> String {
        guard let v = v else { return "—" }
        return String(format: "%+.1f%%", v)
    }

    private func infoJV(_ m: DexPair) -> JV? {
        guard let info = m.info, let d = try? JSONEncoder().encode(info) else { return nil }
        return try? JSONDecoder().decode(JV.self, from: d)
    }

    private func socials(_ m: DexPair) -> [(String, URL)] {
        var out: [(String, URL)] = []
        if let j = infoJV(m) {
            for s in j.at("socials")?.array ?? [] {
                if let t = s.at("type")?.text, let u = s.at("url")?.text, let url = URL(string: u) {
                    let name = t.lowercased() == "twitter" ? "X" : (t.lowercased() == "telegram" ? "TG" : t.capitalized)
                    out.append((name, url))
                }
            }
            for w in (j.at("websites")?.array ?? []).prefix(1) {
                if let u = w.at("url")?.text, let url = URL(string: u) { out.append(("官网", url)) }
            }
        }
        return out
    }

    private func externals(_ m: DexPair) -> [(String, URL)] {
        var out: [(String, URL)] = []
        let cid: String = m.chainId ?? ""
        let a: String = vm.address
        let pa: String? = m.pairAddress
        if let p = pa, let u = URL(string: "https://dexscreener.com/" + cid + "/" + p) { out.append(("Dexscreener", u)) }
        let gm: [String: String] = ["solana": "sol", "bsc": "bsc", "ethereum": "eth", "base": "base", "tron": "tron"]
        if let s = gm[cid], let u = URL(string: "https://gmgn.ai/" + s + "/token/" + a) { out.append(("GMGN", u)) }
        let aveChain: String = vm.chain == .eth ? "eth" : vm.chain.rawValue
        if let u = URL(string: "https://ave.ai/token/" + a + "-" + aveChain) { out.append(("Ave", u)) }
        if let u = URL(string: "https://x.com/search?q=" + a) { out.append(("X 搜索", u)) }
        let bd: Set<String> = ["solana", "ethereum", "bsc", "base", "arbitrum", "optimism", "polygon", "avalanche"]
        if bd.contains(cid), let u = URL(string: "https://birdeye.so/token/" + a + "?chain=" + cid) { out.append(("Birdeye", u)) }
        return out
    }

    // MARK: 叙事标签
    private var nKey: String { vm.chain.rawValue + ":" + vm.address + "#" + String(vm.refreshToken) }

    private func narrText(_ m: DexPair) -> (String, Color) {
        let rep: NarrReport? = NarrativeRulesCard.store[nKey] ?? narr
        if let r = rep {
            let theme: String = r.hits.first?.title ?? "无命中主题词"
            var heat: String = r.heat
            if let i = heat.firstIndex(of: "（") { heat = String(heat[heat.startIndex..<i]) }
            let tail: String = (heat.isEmpty || heat.hasPrefix("样本")) ? "" : " · " + heat
            return ("叙事 · " + theme + tail, r.hits.isEmpty ? Color.gray : Color.purple)
        }
        let ws = NarrLex.words((m.baseToken?.name ?? "") + " " + (m.baseToken?.symbol ?? ""))
        if let h = NarrLex.match(ws).first { return ("叙事 · " + h.title, Color.purple) }
        return ("叙事 · 分析中", Color.gray)
    }

    private func narrChip(_ m: DexPair) -> some View {
        let t = narrText(m)
        return Button {
            NotificationCenter.default.post(name: .tstzmOpenPage, object: 4)
        } label: {
            Text(t.0)
                .font(.caption2.bold())
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(t.1.opacity(0.16), in: Capsule())
                .foregroundStyle(t.1)
        }
        .buttonStyle(.plain)
    }

    private func loadNarr() async {
        guard let p = vm.main, !vm.address.isEmpty else { return }
        let k = nKey
        if NarrativeRulesCard.store[k] != nil { return }
        let r = await NarrEngine.run(pair: p, chain: vm.chain, address: vm.address)
        NarrativeRulesCard.store[k] = r
        narr = r
    }

    private func chipText(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption2.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 3).background(c.opacity(0.14), in: Capsule()).foregroundStyle(c)
    }

    // MARK: 标题行：头像 + 代币/报价币 + 一行标签（叙事·链·DEX·发射台·内外盘）；右侧 ☆ ⤢ ⋯
    private func tagsRow(_ m: DexPair) -> some View {
        let pad: GMLaunchpad? = GMLaunchpad.detect(chain: vm.chain, address: vm.address, dex: m.dexId)
        let mk: String? = GMMarketKind.text(dex: m.dexId, pad: pad)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                narrChip(m)
                Text(vm.chain.title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                if let d = m.dexId, !d.isEmpty { GMDexChip(dex: d) }
                if let p = pad { Text(p.title).font(.caption2.weight(.semibold)).foregroundStyle(Color.orange).lineLimit(1) }
                if let t = mk { chipText(t, t == "内盘" ? Color.orange : Color.green) }
            }
        }
    }

    private func titleRow(_ m: DexPair) -> some View {
        let quote: String = m.quoteToken?.symbol ?? ""
        let ls: [(String, URL)] = socials(m) + externals(m)
        return HStack(alignment: .center, spacing: 10) {
            AvTokenLogo(chain: vm.chain, address: vm.address, symbol: m.baseToken?.symbol ?? vm.symbol, hint: m.info?.imageUrl, size: 48, dex: m.dexId)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(m.baseToken?.symbol ?? vm.symbol).font(.title3.bold()).lineLimit(1)
                    if !quote.isEmpty { Text("/" + quote).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                }
                tagsRow(m)
            }
            Spacer(minLength: 4)
            FavButton(vm: vm)
            Button { NotificationCenter.default.post(name: .tstzmFullChart, object: nil) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.body)
            }
            .buttonStyle(.plain)
            Menu {
                ForEach(ls.indices, id: \.self) { i in
                    Link(ls[i].0, destination: ls[i].1)
                }
                Button("复制合约地址") { UIPasteboard.general.string = vm.address }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
        }
    }

    // MARK: 合约 + 社交 + 外部行情
    private func contractRow(_ m: DexPair) -> some View {
        let ss: [(String, URL)] = socials(m)
        let ex: [(String, URL)] = externals(m).filter { $0.0 == "GMGN" || $0.0 == "Dexscreener" }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text(Addr.short(vm.address)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                Button {
                    UIPasteboard.general.string = vm.address
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.caption)
                }
                .buttonStyle(.plain)
                ForEach(ss.indices, id: \.self) { i in
                    Link(destination: ss[i].1) { chipText(ss[i].0, Color.accentColor) }
                }
                ForEach(ex.indices, id: \.self) { i in
                    Link(destination: ex[i].1) { chipText(ex[i].0 + " ↗", Color.secondary) }
                }
            }
        }
    }

    // MARK: 价格 / 市值大字 + 右侧关键数据
    private func kvRow(_ k: String, _ v: String) -> some View {
        HStack(spacing: 6) {
            Text(k).font(.caption2).foregroundStyle(.secondary)
            Text(v).font(.caption.weight(.semibold).monospacedDigit())
        }
    }

    private func headline(_ m: DexPair, _ h24: Double?) -> some View {
        let age: String = m.pairCreatedAt.map { Fmt2.dur(Date().timeIntervalSince1970 - $0 / 1000) } ?? "—"
        let big: String = GMPx.headline(m, mcap: mcapMode)
        let other: String = m.price.map { GMPx.usd($0) } ?? "—"
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(big)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(col(h24))
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(pct(h24)).font(.subheadline.weight(.semibold)).foregroundStyle(col(h24))
                    Text("24h").font(.caption2).foregroundStyle(.secondary)
                    GMModeSwitch()
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                if mcapMode { kvRow("价格", other) } else { kvRow("市值", Fmt2.usd(m.marketCap ?? m.fdv)) }
                kvRow("流动性", Fmt2.usd(m.liq))
                kvRow("24h成交", Fmt2.usd(m.volume?["h24"]))
                kvRow("池龄", age)
            }
        }
    }

    private func changeRow(_ m: DexPair) -> some View {
        HStack(spacing: 6) {
            ForEach([("5分", "m5"), ("1时", "h1"), ("6时", "h6"), ("24时", "h24")], id: \.1) { it in
                let v = m.priceChange?[it.1]
                HStack(spacing: 4) {
                    Text(it.0).font(.caption2).foregroundStyle(.secondary)
                    Text(pct(v)).font(.caption.bold()).foregroundStyle(col(v))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    @ViewBuilder
    private func content(_ m: DexPair) -> some View {
        let h24 = m.priceChange?["h24"]
        VStack(alignment: .leading, spacing: 8) {
            titleRow(m)
            contractRow(m)
            headline(m, h24)
            GMMetricStrip(vm: vm)
            changeRow(m)
        }
    }

    var body: some View {
        Group {
            if let m = vm.main { content(m) }
        }
        .task(id: nKey) { await loadNarr() }
    }
}
