import SwiftUI

// 交易所风格的紧凑头部：一屏内看到 代币 + 价格 + 涨跌 + 核心 4 项数据，紧接着就是 K 线。
// 更多数据（FDV、买卖笔数、池子数、安全标签、链接、地址）点「更多数据」展开，默认收起，页面不再拖得很长。
struct CompactHeader: View {
    @ObservedObject var vm: UTokenVM
    var embedded: Bool = false
    @State private var expanded = false
    @State private var copied = false

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
        let url = infoJV(m)?.at("imageUrl")?.text.flatMap { URL(string: $0) }
        return AsyncImage(url: url) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(Color.secondary.opacity(0.2)).overlay(Text(String((m.baseToken?.symbol ?? "?").prefix(1))).font(.subheadline))
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
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

    @ViewBuilder
    private func wrap<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        if embedded { c() } else { Card { c() } }
    }

    @ViewBuilder
    private func content(_ m: DexPair) -> some View {
        let h24 = m.priceChange?["h24"]
        let tx = m.txns?["h24"]
        let dex: String? = m.dexId
        let ls = links(m) + externals(m)
        wrap {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    logo(m)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(m.baseToken?.symbol ?? vm.symbol).font(.headline).lineLimit(1)
                            chip((m.chainId ?? "").uppercased(), Color.blue)
                            if let d = dex { chip(d, Color.gray) }
                        }
                        Text(m.baseToken?.name ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Menu {
                        ForEach(ls.indices, id: \.self) { i in
                            Link(ls[i].0, destination: ls[i].1)
                        }
                        Button("复制合约地址") { UIPasteboard.general.string = vm.address }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(m.price.map { Money.price($0) } ?? "—").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(col(h24)).minimumScaleFactor(0.6).lineLimit(1)
                    Text(pct(h24)).font(.headline).foregroundStyle(col(h24))
                    Spacer()
                }
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
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    stat("市值", Fmt2.usd(m.marketCap))
                    stat("流动性", Fmt2.usd(m.liq))
                    stat("24h 成交", Fmt2.usd(m.volume?["h24"]))
                    stat("池龄", m.pairCreatedAt.map { Fmt2.dur(Date().timeIntervalSince1970 - $0 / 1000) } ?? "—")
                }
                if expanded {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        stat("FDV", Fmt2.usd(m.fdv))
                        stat("24h 买/卖", cat(String(tx?.buys ?? 0), "/", String(tx?.sells ?? 0)))
                        stat("池子数", String(vm.pairs.count))
                        stat("流动性/市值", liqRatio(m))
                    }
                    let chips = safetyChips()
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
                Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                    HStack(spacing: 4) {
                        Text(expanded ? "收起" : "更多数据").font(.caption)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    var body: some View {
        Group {
            if let m = vm.main { content(m) }
        }
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
