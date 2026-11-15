import SwiftUI
import UIKit

// GMGN 风格代币头：头像（右下链徽标 + 右上发射台徽标）、代币/报价币、叙事标签、合约 + 社交、价格/市值大字、涨跌条、风控四格。
// 价格/市值开关和 K 线共用 kMcap：切换后头部大字、右侧数据、导航标题、K 线、收藏页同步变化。
struct GMHeader: View {
    @ObservedObject var vm: UTokenVM
    @AppStorage("kMcap", store: Cfg.defaults) private var mcapMode = false
    @State private var expanded = false
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

    // MARK: 标题行：头像 + 代币/报价币 + 叙事 + 链·DEX·发射台；右侧 ☆ ⤢ ⋯
    private func titleRow(_ m: DexPair) -> some View {
        let quote: String = m.quoteToken?.symbol ?? ""
        let ls: [(String, URL)] = socials(m) + externals(m)
        let pad: GMLaunchpad? = GMLaunchpad.detect(chain: vm.chain, address: vm.address, dex: m.dexId)
        return HStack(alignment: .center, spacing: 12) {
            AvTokenLogo(chain: vm.chain, address: vm.address, symbol: m.baseToken?.symbol ?? vm.symbol, hint: m.info?.imageUrl, size: 56, dex: m.dexId)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(m.baseToken?.symbol ?? vm.symbol).font(.title3.bold()).lineLimit(1)
                    if !quote.isEmpty { Text("/" + quote).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                }
                narrChip(m)
                HStack(spacing: 6) {
                    Text(vm.chain.title).font(.caption2).foregroundStyle(.secondary)
                    if let d = m.dexId, !d.isEmpty { GMDexChip(dex: d) }
                    if let p = pad { Text(p.title).font(.caption2.weight(.semibold)).foregroundStyle(Color.orange).lineLimit(1) }
                }
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
    private func linkRow(_ m: DexPair) -> some View {
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

    private func chipText(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption2.weight(.bold)).padding(.horizontal, 7).padding(.vertical, 3).background(c.opacity(0.14), in: Capsule()).foregroundStyle(c)
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
        let other: String = m.price.map { Money.price($0) } ?? "—"
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
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
            VStack(alignment: .trailing, spacing: 3) {
                if mcapMode { kvRow("价格", other) } else { kvRow("市值", Fmt2.usd(m.marketCap)) }
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
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    // MARK: GMGN 风控四格：Top10 / 狙击·早买 / 税或权限 / 池深比（读不到显示 —，不编数）
    private func liqRatio(_ m: DexPair) -> String {
        let mc: Double = m.marketCap ?? m.fdv ?? 0
        if mc <= 0 || m.liq <= 0 { return "—" }
        return String(format: "%.1f%%", m.liq / mc * 100)
    }

    private func riskCells(_ m: DexPair) -> [(String, String, Color)] {
        var out: [(String, String, Color)] = []
        if let w = vm.conc?.wallets10 {
            let v = Double(w)
            out.append(("Top10", String(format: "%.1f%%", v), v >= 30 ? Color.red : (v >= 15 ? Color.orange : Color.green)))
        } else if let w = vm.conc?.top10 {
            let v = Double(w)
            out.append(("Top10", String(format: "%.1f%%", v), v >= 30 ? Color.red : (v >= 15 ? Color.orange : Color.green)))
        } else {
            out.append(("Top10", "—", Color.secondary))
        }
        let a = vm.agg
        if a.withPos >= 1 {
            let n: Int = a.snipers + a.early
            out.append(("狙击/早买", String(n), n > 0 ? Color.orange : Color.green))
        } else {
            out.append(("狙击/早买", "—", Color.secondary))
        }
        if vm.chain == .solana {
            if let au = vm.authorities {
                let on: Bool = !(au.mint ?? "").isEmpty || !(au.freeze ?? "").isEmpty
                out.append(("增发/冻结", on ? "未弃" : "已弃", on ? Color.red : Color.green))
            } else {
                out.append(("增发/冻结", "—", Color.secondary))
            }
        } else if let s = vm.security {
            if s.honeypot == true {
                out.append(("蜜罐", "是", Color.red))
            } else if let t = s.sellTax {
                out.append(("卖税", String(format: "%.0f%%", Double(t)), t >= 10 ? Color.red : Color.green))
            } else {
                out.append(("卖税", "—", Color.secondary))
            }
        } else {
            out.append(("合约", "—", Color.secondary))
        }
        out.append(("池深/市值", liqRatio(m), Color.primary))
        return out
    }

    private func riskRow(_ m: DexPair) -> some View {
        let cells = riskCells(m)
        return HStack(spacing: 6) {
            ForEach(cells.indices, id: \.self) { i in
                VStack(spacing: 2) {
                    Text(cells[i].1).font(.footnote.weight(.bold)).foregroundStyle(cells[i].2).lineLimit(1).minimumScaleFactor(0.7)
                    Text(cells[i].0).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: 更多数据
    private func moreBlock(_ m: DexPair, _ tx: DexTx?) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                stat("FDV", Fmt2.usd(m.fdv))
                stat("24h 买/卖", String(tx?.buys ?? 0) + "/" + String(tx?.sells ?? 0))
                stat("池子数", String(vm.pairs.count))
                stat("池深/市值", liqRatio(m))
            }
            Text("每 20 秒自动刷新").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Text(expanded ? "收起" : "更多数据").font(.caption)
                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func content(_ m: DexPair) -> some View {
        let h24 = m.priceChange?["h24"]
        let tx = m.txns?["h24"]
        VStack(alignment: .leading, spacing: 10) {
            titleRow(m)
            linkRow(m)
            headline(m, h24)
            changeRow(m)
            riskRow(m)
            if expanded { moreBlock(m, tx) }
            toggleButton
        }
    }

    var body: some View {
        Group {
            if let m = vm.main { content(m) }
        }
        .task(id: nKey) { await loadNarr() }
    }
}
