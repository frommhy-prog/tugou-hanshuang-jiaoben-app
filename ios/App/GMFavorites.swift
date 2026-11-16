import SwiftUI
import UIKit

extension FavStore {
    private func persist() {
        if let d = try? JSONEncoder().encode(items) { Cfg.defaults.set(d, forKey: "favItems") }
    }

    // 把一份最新行情写进收藏条目（价格、市值、流动性、各周期成交额/笔数/涨跌、池龄、交易所）
    func fill(_ m: DexPair, id: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].price = m.price
        items[i].change24h = m.priceChange?["h24"]
        items[i].change1h = m.priceChange?["h1"]
        items[i].change5m = m.priceChange?["m5"]
        items[i].liq = m.liq
        items[i].mcap = m.marketCap ?? m.fdv
        items[i].vol24h = m.volume?["h24"]
        items[i].dex = m.dexId
        items[i].created = m.pairCreatedAt
        if items[i].logo == nil { items[i].logo = m.info?.imageUrl }
        var chg: [String: Double] = [:]
        var vols: [String: Double] = [:]
        var txs: [String: Int] = [:]
        for k in ["m5", "h1", "h6", "h24"] {
            if let v = m.priceChange?[k] { chg[k] = v }
            if let v = m.volume?[k] { vols[k] = v }
            if let t = m.txns?[k] { txs[k] = (t.buys ?? 0) + (t.sells ?? 0) }
        }
        items[i].chgs = chg
        items[i].vols = vols
        items[i].txs = txs
        persist()
    }

    func setNote(_ id: String, _ note: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let t = note.trimmingCharacters(in: .whitespacesAndNewlines)
        items[i].note = t.isEmpty ? nil : t
        persist()
    }

    func setGroup(_ id: String, _ g: String?) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].group = (g ?? "").isEmpty ? nil : g
        persist()
    }
}

// MARK: - 收藏页（按 GMGN 「收藏」布局：分组、链筛选、周期、排序、筛选规则、备注）
struct GMFavoritesRoot: View {
    @ObservedObject private var store = FavStore.shared
    @AppStorage("kMcap", store: Cfg.defaults) private var mcapMode = false
    @AppStorage("favGroup", store: Cfg.defaults) private var groupSel = "全部"
    @AppStorage("favGroups", store: Cfg.defaults) private var groupsStr = ""
    @AppStorage("favTF", store: Cfg.defaults) private var tf = "m5"
    @AppStorage("favSort", store: Cfg.defaults) private var sort = 0
    @AppStorage("favDesc", store: Cfg.defaults) private var desc = true
    @AppStorage("favChain", store: Cfg.defaults) private var chainSel = ""
    @AppStorage("favFMinMcap", store: Cfg.defaults) private var fMinMcap = ""
    @AppStorage("favFMaxMcap", store: Cfg.defaults) private var fMaxMcap = ""
    @AppStorage("favFMinLiq", store: Cfg.defaults) private var fMinLiq = ""
    @AppStorage("favFMinVol", store: Cfg.defaults) private var fMinVol = ""
    @AppStorage("favFMinChg", store: Cfg.defaults) private var fMinChg = ""
    @AppStorage("favFMaxChg", store: Cfg.defaults) private var fMaxChg = ""
    @State private var showSearch = false
    @State private var showFilter = false
    @State private var showLog = false
    @State private var newGroup = false
    @State private var groupName = ""
    @State private var noteItem: FavItem?
    @State private var busy = false
    @State private var hist: [HistoryItem] = QueryHistory.items.filter { $0.kind == "token" }

    private let tfs: [(String, String)] = [("1m→", "m5"), ("5m", "m5"), ("1h", "h1"), ("6h", "h6"), ("24h", "h24")]
    private let sorts: [String] = ["收藏时间", "涨跌幅", "市值", "成交额", "流动性", "交易笔数", "池龄"]

    private var groups: [String] { groupsStr.split(separator: ",").map { String($0) } }

    private func num(_ s: String) -> Double? { Double(s.trimmingCharacters(in: .whitespaces)) }

    private func chg(_ it: FavItem) -> Double? {
        if let v = it.chgs?[tf] { return v }
        if tf == "h24" { return it.change24h }
        if tf == "h1" { return it.change1h }
        if tf == "m5" { return it.change5m }
        return nil
    }

    private func vol(_ it: FavItem) -> Double? {
        if let v = it.vols?[tf] { return v }
        return tf == "h24" ? it.vol24h : nil
    }

    private func txc(_ it: FavItem) -> Int? { it.txs?[tf] }

    private func passes(_ it: FavItem) -> Bool {
        if groupSel == "默认" && !(it.group ?? "").isEmpty { return false }
        if groupSel != "全部" && groupSel != "默认" && it.group != groupSel { return false }
        if !chainSel.isEmpty && it.chain != chainSel { return false }
        if let v = num(fMinMcap), (it.mcap ?? 0) < v { return false }
        if let v = num(fMaxMcap), (it.mcap ?? 0) > v { return false }
        if let v = num(fMinLiq), (it.liq ?? 0) < v { return false }
        if let v = num(fMinVol), (vol(it) ?? 0) < v { return false }
        if let v = num(fMinChg), (chg(it) ?? -9999) < v { return false }
        if let v = num(fMaxChg), (chg(it) ?? 9999) > v { return false }
        return true
    }

    private func key(_ it: FavItem) -> Double {
        switch sort {
        case 1: return chg(it) ?? -99999
        case 2: return it.mcap ?? 0
        case 3: return vol(it) ?? 0
        case 4: return it.liq ?? 0
        case 5: return Double(txc(it) ?? 0)
        case 6: return it.created ?? 0
        default: return it.addedAt
        }
    }

    private var rows: [FavItem] {
        var a: [FavItem] = store.items.filter { passes($0) }
        a.sort { desc ? key($0) > key($1) : key($0) < key($1) }
        return a
    }

    private var filterOn: Bool {
        !(fMinMcap + fMaxMcap + fMinLiq + fMinVol + fMinChg + fMaxChg).isEmpty
    }

    private func open(_ it: FavItem) {
        UTokenVM.shared.start(it.address)
        AppRouter.shared.tab = 0
    }

    private func refresh() async {
        if busy { return }
        busy = true
        defer { busy = false }
        for it in store.items {
            guard let ch = Chain(rawValue: it.chain) else { continue }
            if let ps = try? await MarketAPI.pairs(ch, it.address), let m = ps.first {
                store.fill(m, id: it.id)
            }
        }
    }

    private func padColor(_ it: FavItem) -> Color {
        let ch: Chain? = Chain(rawValue: it.chain)
        guard let p = GMLaunchpad.detect(chain: ch, address: it.address, dex: it.dex) else { return Color.clear }
        switch p {
        case .pump: return Color(red: 0.2, green: 0.85, blue: 0.5)
        case .bonk: return Color.orange
        case .fourMeme: return Color(red: 0.75, green: 1.0, blue: 0.2)
        case .flap: return Color.blue
        default: return Color.purple
        }
    }

    private func ageText(_ it: FavItem) -> String {
        guard let c = it.created else { return "—" }
        return Fmt2.dur(Date().timeIntervalSince1970 - c / 1000)
    }

    // MARK: 顶部：标题 + 搜索 + 分组 + 筛选行
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("收藏").font(.system(size: 26, weight: .bold))
                Spacer()
                Button { showLog = true } label: { Image(systemName: "bell.badge").font(.title3) }
            }
            Button { showSearch = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    Text("搜索 / 粘贴合约").foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        Button("全部链") { chainSel = "" }
                        ForEach(Chain.allCases.filter { $0.tokenSupported }) { c in
                            Button(c.title) { chainSel = c.rawValue }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                            Text(chainSel.isEmpty ? "全部链" : (Chain(rawValue: chainSel)?.title ?? chainSel))
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.primary)
                    }
                    ForEach(["全部", "默认"] + groups, id: \.self) { g in
                        Button { groupSel = g } label: {
                            Text(g)
                                .font(.footnote.weight(groupSel == g ? .bold : .regular))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(groupSel == g ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: Capsule())
                                .foregroundStyle(groupSel == g ? Color.accentColor : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if g != "全部" && g != "默认" {
                                Button("删除分组", role: .destructive) { removeGroup(g) }
                            }
                        }
                    }
                    Button { groupName = ""; newGroup = true } label: {
                        Image(systemName: "plus")
                            .font(.footnote.weight(.bold))
                            .padding(9)
                            .background(Color.secondary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(Array(tfs.dropFirst().enumerated()), id: \.offset) { _, t in
                        Button(t.0) { tf = t.1 }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(tfs.first { $0.1 == tf && $0.0 != "1m→" }?.0 ?? "5m")
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.primary)
                }
                Menu {
                    ForEach(sorts.indices, id: \.self) { i in
                        Button(sorts[i] + "排序") { sort = i }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: desc ? "arrow.down" : "arrow.up")
                        Text(sorts[min(sort, sorts.count - 1)] + "排序")
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.primary)
                }
                Button { desc.toggle() } label: {
                    Image(systemName: "arrow.up.arrow.down").font(.footnote.weight(.semibold))
                        .padding(9)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                Button { showFilter = true } label: {
                    Image(systemName: filterOn ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.title3)
                        .foregroundStyle(filterOn ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func removeGroup(_ g: String) {
        groupsStr = groups.filter { $0 != g }.joined(separator: ",")
        for it in store.items where it.group == g { store.setGroup(it.id, nil) }
        if groupSel == g { groupSel = "全部" }
    }

    private var tableHeader: some View {
        HStack {
            Text("时间 / 池子").frame(maxWidth: .infinity, alignment: .leading)
            Text("Vol / 交易笔数").frame(width: 112, alignment: .trailing)
            Button { mcapMode.toggle() } label: {
                HStack(spacing: 2) {
                    Text(mcapMode ? "价格" : "市值")
                    Image(systemName: "arrow.left.arrow.right").font(.caption2)
                    Text("/ " + (tfs.first { $0.1 == tf && $0.0 != "1m→" }?.0 ?? "5m") + "%")
                }
            }
            .buttonStyle(.plain)
            .frame(width: 118, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func valueText(_ it: FavItem) -> String {
        if mcapMode { return GMPx.fiat(it.mcap) }
        return it.price.map { GMPx.usd($0) } ?? "—"
    }

    private func row(_ it: FavItem) -> some View {
        let ch: Chain = Chain(rawValue: it.chain) ?? .solana
        let v: Double? = chg(it)
        let c: Color = (v ?? 0) >= 0 ? Color.green : Color.red
        let pct: String = v.map { String(format: "%+.1f%%", $0) } ?? "—"
        return HStack(spacing: 0) {
            Rectangle().fill(padColor(it)).frame(width: 3)
            HStack(spacing: 10) {
                AvTokenLogo(chain: ch, address: it.address, symbol: it.symbol, hint: it.logo, size: 46, dex: it.dex)
                VStack(alignment: .leading, spacing: 3) {
                    Text(it.symbol).font(.headline).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(ageText(it)).foregroundStyle(Color.orange)
                        Text(GMPx.fiat(it.liq)).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    if let n = it.note {
                        Text(n).font(.caption2).foregroundStyle(Color.orange).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(GMPx.fiat(vol(it))).font(.subheadline.weight(.semibold).monospacedDigit())
                    Text(txc(it).map { String($0) } ?? "—").font(.caption).foregroundStyle(.secondary)
                }
                .frame(width: 100, alignment: .trailing)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(valueText(it)).font(.subheadline.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
                    Text(pct).font(.caption.weight(.bold)).foregroundStyle(c)
                }
                .frame(width: 100, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background(Color.card)
        .contentShape(Rectangle())
        .onTapGesture { open(it) }
        .contextMenu {
            Button("编辑备注") { noteItem = it }
            Menu("移到分组") {
                Button("默认") { store.setGroup(it.id, nil) }
                ForEach(groups, id: \.self) { g in Button(g) { store.setGroup(it.id, g) } }
            }
            Button("移除收藏", role: .destructive) { store.remove(it) }
        }
    }

    private var empty: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.items.isEmpty ? "还没有收藏" : "没有符合当前筛选的币").font(.headline)
                Text("在「代币」页查到币后，点头部右上角的 ☆ 就会收到这里；收藏的币会自动监控，价格急动、流动性骤降、放量、卖压时发本地通知。").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    tableHeader.padding(.top, 4)
                    if rows.isEmpty {
                        empty
                    } else {
                        LazyVStack(spacing: 1) {
                            ForEach(rows) { it in row(it) }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text("到底了").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(LogoRefreshHook { await refresh() })
            }
            .background(Color.page)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showLog) { MonitorSheet() }
            .sheet(isPresented: $showSearch) {
                GMSearchSheet(vm: UTokenVM.shared, hist: $hist, onStart: { AppRouter.shared.tab = 0 })
            }
            .sheet(isPresented: $showFilter) { GMFavFilterSheet() }
            .sheet(item: $noteItem) { it in GMNoteSheet(item: it) }
            .alert("新建分组", isPresented: $newGroup) {
                TextField("分组名称", text: $groupName)
                Button("创建") {
                    let n = groupName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
                    if !n.isEmpty && !groups.contains(n) && n != "全部" && n != "默认" {
                        groupsStr = (groups + [n]).joined(separator: ",")
                        groupSel = n
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .task { await refresh() }
        }
    }
}

// MARK: - 筛选规则
struct GMFavFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("favFMinMcap", store: Cfg.defaults) private var fMinMcap = ""
    @AppStorage("favFMaxMcap", store: Cfg.defaults) private var fMaxMcap = ""
    @AppStorage("favFMinLiq", store: Cfg.defaults) private var fMinLiq = ""
    @AppStorage("favFMinVol", store: Cfg.defaults) private var fMinVol = ""
    @AppStorage("favFMinChg", store: Cfg.defaults) private var fMinChg = ""
    @AppStorage("favFMaxChg", store: Cfg.defaults) private var fMaxChg = ""

    private func field(_ title: String, _ unit: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("不限", text: text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
            Text(unit).foregroundStyle(.secondary).font(.footnote)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("市值（美元）") {
                    field("最低", "$", $fMinMcap)
                    field("最高", "$", $fMaxMcap)
                }
                Section("流动性 / 成交额（美元）") {
                    field("流动性最低", "$", $fMinLiq)
                    field("成交额最低（按当前周期）", "$", $fMinVol)
                }
                Section("涨跌幅（按当前周期，如 5 分钟涨跌）") {
                    field("涨幅至少", "%", $fMinChg)
                    field("涨幅至多（负数 = 跌幅）", "%", $fMaxChg)
                }
                Section {
                    Button("重置全部筛选", role: .destructive) {
                        fMinMcap = ""; fMaxMcap = ""; fMinLiq = ""; fMinVol = ""; fMinChg = ""; fMaxChg = ""
                    }
                }
            }
            .navigationTitle("筛选规则")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 备注
struct GMNoteSheet: View {
    let item: FavItem
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(item.symbol + " 的备注") {
                    TextEditor(text: $text).frame(minHeight: 120)
                }
            }
            .navigationTitle("备注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        FavStore.shared.setNote(item.id, text)
                        dismiss()
                    }
                }
            }
            .onAppear { text = item.note ?? "" }
        }
        .presentationDetents([.medium])
    }
}
