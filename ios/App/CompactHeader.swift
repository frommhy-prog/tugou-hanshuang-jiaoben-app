import SwiftUI

// 交易所风格头部：头像（带链徽章）+ 代币 / 报价币 + 叙事标签；价格与涨跌；核心 4 项数据。
// 更多数据（FDV、买卖笔数、池子数、安全标签、地址）点「更多数据」展开，默认收起。
struct CompactHeader: View {
    @ObservedObject var vm: UTokenVM
    var embedded: Bool = false
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

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(c.opacity(0.15), in: Capsule()).foregroundStyle(c)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoJV(_ m: DexPair) -> JV? {
        guard let info = m.info, let d = try? JSONEncoder().encode(info) else { return nil }
        return try? JSONDecoder().decode(JV.self, from: d)
    }

    private func links(_ m: DexPair) -> [(String, URL)] {
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
        let cid = m.chainId ?? ""
        let a = vm.address
        let pa: String? = m.pairAddress
        if let p = pa, let u = URL(string: cat("https://dexscreener.com/", cid, "/", p)) { out.append(("Dexscreener", u)) }
        let gm: [String: String] = ["solana": "sol", "bsc": "bsc", "ethereum": "eth", "base": "base", "tron": "tron"]
        if let s = gm[cid], let u = URL(string: cat("https://gmgn.ai/", s, "/token/", a)) { out.append(("GMGN", u)) }
        if let u = URL(string: cat("https://ave.ai/token/", a, "-", vm.chain == .eth ? "eth" : vm.chain.rawValue)) { out.append(("Ave", u)) }
        if let u = URL(string: cat("https://x.com/search?q=", a)) { out.append(("X 搜索", u)) }
        let bd: Set<String> = ["solana", "ethereum", "bsc", "base", "arbitrum", "optimism", "polygon", "avalanche"]
        if bd.contains(cid), let u = URL(string: cat("https://birdeye.so/token/", a, "?chain=", cid)) { out.append(("Birdeye", u)) }
        return out
    }

    private func logo(_ m: DexPair) -> some View {
        AvTokenLogo(chain: vm.chain, address: vm.address, symbol: m.baseToken?.symbol ?? vm.symbol, hint: m.info?.imageUrl, size: 52)
    }

    private func safetyChips() -> [(String, Color)] {
        var out: [(String, Color)] = []
        if vm.chain == .solana {
            if let au = vm.authorities {
                let mintOn = !(au.mint ?? "").isEmpty
                let freezeOn = !(au.freeze ?? "").isEmpty
                out.append((mintOn ? "可增发" : "增发已弃", mintOn ? Color.red : Color.green))
                out.append((freezeOn ? "可冻结" : "冻结已弃", freezeOn ? Color.red : Color.green))
            }
        } else if let s = vm.security {
            if s.honeypot == true { out.append(("蜜罐", Color.red)) }
            if let t = s.sellTax { out.append((String(format: "卖税 %.0f%%", Double(t)), t >= 10 ? Color.red : Color.green)) }
            if let t = s.buyTax { out.append((String(format: "买税 %.0f%%", Double(t)), t >= 10 ? Color.orange : Color.green)) }
            if s.mintable == true { out.append(("可增发", Color.orange)) }
        }
        if let w = vm.conc?.wallets10 {
            let v = Double(w)
            out.append((String(format: "前10 %.1f%%", v), v >= 30 ? Color.red : (v >= 15 ? Color.orange : Color.green)))
        }
        let a = vm.agg
        if a.snipers + a.early > 0 { out.append((cat("狙击/早买 ", String(a.snipers + a.early)), Color.orange)) }
        if a.withPos >= 2 { out.append((cat("大户盈利 ", String(a.profit), "/", String(a.withPos)), Color.blue)) }
        return out
    }

    private func liqRatio(_ m: DexPair) -> String {
        let mc: Double = m.marketCap ?? m.fdv ?? 0
        if mc <= 0 || m.liq <= 0 { return "—" }
        return String(format: "%.1f%%", m.liq / mc * 100)
    }

    // MARK: 叙事标签（紧挨头像）：主题词命中 + 热度；点一下跳到「叙事」页
    private var nKey: String { cat(vm.chain.rawValue, ":", vm.address, "#", String(vm.refreshToken)) }

    private func narrText(_ m: DexPair) -> (String, Color) {
        let rep: NarrReport? = NarrativeRulesCard.store[nKey] ?? narr
        if let r = rep {
            let theme: String = r.hits.first?.title ?? "无命中主题词"
            var heat: String = r.heat
            if let i = heat.firstIndex(of: "（") { heat = String(heat[heat.startIndex..<i]) }
            let tail: String = (heat.isEmpty || heat.hasPrefix("样本")) ? "" : " · " + heat
            return ("叙事 · " + theme + tail, r.hits.isEmpty ? Color.gray : Color.purple)
        }
        let ws = NarrLex.words(cat(m.baseToken?.name ?? "", " ", m.baseToken?.symbol ?? ""))
        if let h = NarrLex.match(ws).first { return ("叙事 · " + h.title, Color.purple) }
        return ("叙事 · 分析中", Color.gray)
    }

    private func narrChip(_ m: DexPair) -> some View {
        let t = narrText(m)
        return Button {
            Cfg.defaults.set(4, forKey: "tokTab")
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

    // MARK: 布局
    @ViewBuilder
    private func wrap<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        if embedded { c() } else { Card { c() } }
    }

    private func titleRow(_ m: DexPair, _ ls: [(String, URL)]) -> some View {
        let quote: String = m.quoteToken?.symbol ?? ""
        let sub: String = cat(vm.chain.title, " · ", m.dexId ?? "?", " · ", m.baseToken?.name ?? "")
        return HStack(alignment: .center, spacing: 12) {
            logo(m)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(m.baseToken?.symbol ?? vm.symbol).font(.title3.bold()).lineLimit(1)
                    if !quote.isEmpty { Text("/" + quote).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                }
                narrChip(m)
                Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
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

    private func priceRow(_ m: DexPair, _ h24: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(m.price.map { Money.price($0) } ?? "—")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(col(h24))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(pct(h24)).font(.headline).foregroundStyle(col(h24))
            Spacer()
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

    private func statGrid(_ m: DexPair) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        let age: String = m.pairCreatedAt.map { Fmt2.dur(Date().timeIntervalSince1970 - $0 / 1000) } ?? "—"
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            stat("市值", Fmt2.usd(m.marketCap))
            stat("流动性", Fmt2.usd(m.liq))
            stat("24h 成交", Fmt2.usd(m.volume?["h24"]))
            stat("池龄", age)
        }
    }

    private func moreBlock(_ m: DexPair, _ tx: DexTx?) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        let chips = safetyChips()
        return VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                stat("FDV", Fmt2.usd(m.fdv))
                stat("24h 买/卖", cat(String(tx?.buys ?? 0), "/", String(tx?.sells ?? 0)))
                stat("池子数", String(vm.pairs.count))
                stat("流动性/市值", liqRatio(m))
            }
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(chips.indices, id: \.self) { i in chip(chips[i].0, chips[i].1) } }
                }
            }
            HStack {
                Text(Addr.short(vm.address)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                Button {
                    UIPasteboard.general.string = vm.address
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.caption)
                }
                Spacer()
                Text("每 20 秒自动刷新").font(.caption2).foregroundStyle(.secondary)
            }
        }
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
        let ls = links(m) + externals(m)
        wrap {
            VStack(alignment: .leading, spacing: 10) {
                titleRow(m, ls)
                priceRow(m, h24)
                changeRow(m)
                statGrid(m)
                if expanded { moreBlock(m, tx) }
                toggleButton
            }
        }
    }

    var body: some View {
        Group {
            if let m = vm.main { content(m) }
        }
        .task(id: nKey) { await loadNarr() }
    }
}

// 「大户情报」入口：Solana 代币一键全查前 20 个大户
struct HoldersIntelButton: View {
    @ObservedObject var vm: UTokenVM
    @State private var show = false
    var body: some View {
        if vm.chain == .solana && !vm.holders.isEmpty {
            Button { show = true } label: {
                Label("一键查询全部大户情报（标签 + 行为信号）", systemImage: "person.3.sequence").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $show) { HoldersIntelView() }
        }
    }
}
