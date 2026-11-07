import SwiftUI

// 代币页头部：参考主流土狗终端（GMGN / Photon / Ave / Dexscreener）的信息密度——价格、涨跌、市值/FDV/流动性/成交、买卖笔数、池龄、安全标签、官方链接、外部查看。
struct TerminalHeader: View {
    @ObservedObject var vm: UTokenVM
    @State private var copied = false
    @State private var showHolders = false

    private func col(_ v: Double?) -> Color {
        guard let v = v else { return .secondary }
        return v >= 0 ? .green : .red
    }

    private func pct(_ v: Double?) -> String {
        guard let v = v else { return "—" }
        return String(format: "%+.1f%%", v)
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 3).background(c.opacity(0.15), in: Capsule()).foregroundStyle(c)
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
            Circle().fill(Color.secondary.opacity(0.2)).overlay(Text(String((m.baseToken?.symbol ?? "?").prefix(1))).font(.headline))
        }
        .frame(width: 46, height: 46)
        .clipShape(Circle())
    }

    private func liqRatio(_ m: DexPair) -> String {
        let mc: Double = m.marketCap ?? m.fdv ?? 0
        if mc <= 0 || m.liq <= 0 { return "—" }
        return String(format: "%.1f%%", m.liq / mc * 100)
    }

    private func dexName(_ m: DexPair) -> String? {
        let d: String? = m.dexId
        return d
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

    @ViewBuilder
    private func content(_ m: DexPair) -> some View {
        let h24 = m.priceChange?["h24"]
        let tx = m.txns?["h24"]
        let created = m.pairCreatedAt
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    logo(m)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.baseToken?.symbol ?? vm.symbol).font(.title3.bold())
                        Text(m.baseToken?.name ?? "").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        chip((m.chainId ?? "").uppercased(), Color.blue)
                        if let d = dexName(m) { chip(d, Color.gray) }
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(m.price.map { Money.price($0) } ?? "—").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(col(h24)).minimumScaleFactor(0.6).lineLimit(1)
                }
                HStack(spacing: 8) {
                    ForEach([("5分", "m5"), ("1时", "h1"), ("6时", "h6"), ("24时", "h24")], id: \.1) { it in
                        let v = m.priceChange?[it.1]
                        VStack(spacing: 2) {
                            Text(it.0).font(.caption2).foregroundStyle(.secondary)
                            Text(pct(v)).font(.footnote.bold()).foregroundStyle(col(v))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    stat("市值", Fmt2.usd(m.marketCap))
                    stat("FDV", Fmt2.usd(m.fdv))
                    stat("流动性", Fmt2.usd(m.liq))
                    stat("24h 成交", Fmt2.usd(m.volume?["h24"]))
                    stat("24h 买/卖", cat(String(tx?.buys ?? 0), "/", String(tx?.sells ?? 0)))
                    stat("池龄", created.map { Fmt2.dur(Date().timeIntervalSince1970 - $0 / 1000) } ?? "—")
                    stat("池子数", String(vm.pairs.count))
                    stat("流动性/市值", liqRatio(m))
                }
                let chips = safetyChips()
                if !chips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) { ForEach(chips.indices, id: \.self) { i in chip(chips[i].0, chips[i].1) } }
                    }
                }
                let ls = links(m) + externals(m)
                if !ls.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(ls.indices, id: \.self) { i in
                                Link(destination: ls[i].1) { Text(ls[i].0).font(.footnote.weight(.semibold)) }
                            }
                        }
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
                    if vm.chain == .solana {
                        Button { showHolders = true } label: { Label("大户情报", systemImage: "person.3.sequence").font(.caption.weight(.semibold)) }
                    }
                }
            }
        }
        .sheet(isPresented: $showHolders) { HoldersIntelView() }
    }

    var body: some View {
        Group {
            if let m = vm.main { content(m) }
        }
    }
}

// 持有人一键全查（从代币页进入；钱包页里的「查询地址」负责单个钱包）
struct HoldersIntelView: View {
    @ObservedObject private var vm = IntelVM.shared
    @ObservedObject private var tok = UTokenVM.shared
    @State private var picked: PickedReport?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(cat(tok.symbol, " 的前 20 个普通钱包")).font(.headline)
                            Button { Task { await vm.runBatch(holders: tok.holders) } } label: {
                                HStack { Text(vm.batchBusy ? cat("查询中 ", String(vm.batchDone), "/", String(vm.batchTotal)) : "重新全查"); if vm.batchBusy { ProgressView() } }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(vm.batchBusy || tok.holders.isEmpty)
                        }
                    }
                    let c = vm.cohort()
                    if !c.lines.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("大户整体画像").font(.headline)
                                ForEach(c.lines) { l in
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(l.text).font(.subheadline)
                                        Text(cat("依据：", l.basis)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if !vm.rows.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("逐个钱包").font(.headline)
                                ForEach(vm.rows) { r in
                                    Button { picked = r.report.map { PickedReport(r: $0) } } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack {
                                                Text(Addr.short(r.owner)).font(.system(.footnote, design: .monospaced))
                                                if let p = r.pct { Text(String(format: "%.2f%%", p)).font(.caption).foregroundStyle(.secondary) }
                                                Spacer()
                                                if let s = r.report?.score { Text(cat("分 ", String(s))).font(.caption.bold()) }
                                            }
                                            if let rep = r.report {
                                                Text(rep.labels.map { $0.name }.joined(separator: "、")).font(.caption2).foregroundStyle(.secondary)
                                            } else if let e = r.err {
                                                Text(e).font(.caption2).foregroundStyle(Color.orange)
                                            } else {
                                                Text("排队中…").font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("大户情报")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $picked) { p in
                NavigationStack { ScrollView { IntelReportView(r: p.r).padding() }.navigationTitle("钱包情报") }
            }
            .task { if vm.rows.isEmpty { await vm.runBatch(holders: tok.holders) } }
        }
    }
}

// 单个 Solana 钱包情报页（从「钱包 → 查询地址」的结果页右上角进入）
struct SolIntelPage: View {
    let address: String
    @ObservedObject private var vm = IntelVM.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if vm.loading { Card { HStack(spacing: 10) { ProgressView(); Text("正在读取并计算…").font(.subheadline) } } }
                if let e = vm.error { Card { Text(e).font(.footnote).foregroundStyle(Color.orange) } }
                if let r = vm.report, r.address == address { IntelReportView(r: r) }
            }
            .padding()
        }
        .navigationTitle("钱包情报")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.query(address) }
    }
}
