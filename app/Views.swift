import SwiftUI

// 黑色硬核主题：黑底 + 高对比，参考“不开仓怎么搞钱”壁纸。
struct Hardcore {
    static let background = Color.black
    static let card = Color(white: 0.11)
    static let text = Color.white
    static let accent = Color.yellow
    static let danger = Color.red
    static let ok = Color.green
}

struct ContentView: View {
    @StateObject private var wallets = WalletStore()

    var body: some View {
        TabView {
            TokenCheckView()
                .tabItem { Label("体检", systemImage: "magnifyingglass") }
            HoldingsView(wallets: wallets)
                .tabItem { Label("持仓", systemImage: "wallet.pass") }
            WalletListView(store: wallets)
                .tabItem { Label("钱包", systemImage: "plus.circle") }
        }
        .preferredColorScheme(.dark)
    }
}

struct TokenCheckView: View {
    @State private var chain: Chain = .bsc
    @State private var contract: String = ""
    @State private var result: APIClient.TokenResponse?
    @State private var errorText: String?
    @State private var loading = false

    var body: some View {
        NavigationView {
            Form {
                Picker("链", selection: $chain) {
                    ForEach(Chain.allCases) { c in Text(c.displayName).tag(c) }
                }
                TextField("粘贴合约地址", text: $contract)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Button(loading ? "查询中…" : "体检") {
                    Task {
                        loading = true; errorText = nil; result = nil
                        do {
                            // 先快后全：快价 1 秒内先显示，全量体检到了再覆盖，不等全量才出数
                            if let fast = try? await APIClient.fetchTokenFast(chain: chain, address: contract) {
                                result = fast
                            }
                            result = try await APIClient.fetchToken(chain: chain, address: contract)
                        } catch {
                            if result == nil {
                                errorText = "查不到或网络失败：\(error.localizedDescription)"
                            }
                        }
                        loading = false
                    }
                }
                .disabled(loading || contract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let errorText {
                    Section("提示") { Text(errorText).font(.footnote) }
                }
                if let result, let price = result.price {
                    Section("价格（\(price.source ?? "")）") {
                        Text("\(price.name ?? "") \(price.symbol ?? "")")
                        if let v = price.priceUsd { Text("价格：$\(v)") }
                        if let v = price.liquidityUsd { Text("流动性：$\(v)") }
                        if let v = price.volume24hUsd { Text("24h 量：$\(v)") }
                        if let v = price.priceChange24hPct { Text("24h 涨跌：\(v)%") }
                        if let v = result.marketCapUsd { Text("本链市值：$\(v)") }
                        if let tx = result.txns24h, let b = tx.buys, let s = tx.sells { Text("24h 买卖笔数：买 \(b) / 卖 \(s)") }
                        if let v = result.realHolders { Text("真实持仓人数：\(v)") }
                        if let v = result.queryTimeMs { Text("查询耗时：\(v) 毫秒\(result.cached == true ? "（缓存）" : "")\(result.fast == true ? "（快价）" : "")") }
                    }
                    Section("风险") {
                        if let r = result.risk { Text("风险灯：\(r)（来源：\(result.riskSource ?? "")）") }
                        if let v = result.holders { Text("持仓人数：\(v)") }
                        if let v = result.topHoldersPct { Text("Top10 占比：\(v)%") }
                        if let v = result.buyTax { Text("买税：\(v)%") }
                        if let v = result.sellTax { Text("卖税：\(v)%") }
                        if let v = result.honeypot { Text("蜜罐：\(v ? "是" : "否")") }
                        if let v = result.mintable { Text("可增发：\(v ? "是" : "否")") }
                        if let v = result.blacklist { Text("黑名单：\(v ? "是" : "否")") }
                        if let v = result.lpLocked { Text("LP 锁定：\(v ? "是" : "否")") }
                        if let v = result.lpBurnPct { Text("LP 销毁占比：\(v)%") }
                        if let v = result.lpTopHolder { Text("LP 最大持有人：\(v)") }
                        if let v = result.poolAge { Text("池子年龄：\(v) 天") }
                        if let c = result.creatorHistory?.creatorAddress { Text("创建者：\(c)") }
                        if result.holders == nil && result.topHoldersPct == nil && result.creatorHistory == nil {
                            Text("持仓/Top10/创建者这一轮没出，可能是上游间歇或大币按设计跳过，不显示假数。").font(.footnote)
                        }
                    }
                    Section("跳转") {
                        if let url = result.tradeLinks?.ave, let u = URL(string: url) { Link("Ave", destination: u) }
                        if let url = result.tradeLinks?.gmgn, let u = URL(string: url) { Link("GMGN", destination: u) }
                        if let url = result.tradeLinks?.dexscreener, let u = URL(string: url) { Link("Dexscreener", destination: u) }
                    }
                } else if result != nil {
                    Section("结果") {
                        Text("这个合约在 Dexscreener 上没查到池子，先核对链和合约有没有贴错。").font(.footnote)
                    }
                }
            }
            .navigationTitle("合约体检")
        }
    }
}

struct HoldingsView: View {
    @ObservedObject var wallets: WalletStore
    @State private var holdings: APIClient.HoldingsResponse?
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            List {
                if wallets.wallets.isEmpty {
                    Text("还没有钱包。去“钱包”页添加，支持多钱包、多链混加，随时可换。")
                } else {
                    ForEach(wallets.wallets) { w in
                        VStack(alignment: .leading) {
                            Text(w.label.isEmpty ? w.chain.displayName : w.label).bold()
                            Text("\(w.chain.displayName) · \(w.address)").font(.caption).lineLimit(1)
                        }
                    }
                    Button("刷新聚合（走 Worker）") {
                        Task {
                            do {
                                holdings = try await APIClient.fetchHoldings(wallets: wallets.wallets)
                                errorText = nil
                            } catch {
                                errorText = "聚合失败：\(error.localizedDescription)"
                            }
                        }
                    }
                }
                if let holdings {
                    Section("聚合结果") {
                        Text("通过校验的钱包：\(holdings.wallets.count) 个")
                        Text("格式不对的：\(holdings.invalid.count) 个")
                        Text("余额来源：\(holdings.balanceSource ?? "pending")（接通前不显示假余额）")
                            .font(.footnote)
                        if let v = holdings.totalUsd { Text("总价值：$\(v)") }
                        if let note = holdings.note { Text(note).font(.footnote) }
                    }
                }
                if let errorText {
                    Section("提示") { Text(errorText).font(.footnote) }
                }
                Section("交易所") {
                    Text("币安、欧易、Gate：只读 Key 先跳过，这一版不显示交易所持仓，等 Key 到位再接。")
                        .font(.footnote)
                }
            }
            .navigationTitle("全链持仓")
        }
    }
}

struct WalletListView: View {
    @ObservedObject var store: WalletStore
    @State private var chain: Chain = .bsc
    @State private var address: String = ""
    @State private var label: String = ""

    var body: some View {
        NavigationView {
            List {
                Section("添加钱包（只填公开地址，不要私钥）") {
                    Picker("链", selection: $chain) {
                        ForEach(Chain.allCases) { c in Text(c.displayName).tag(c) }
                    }
                    TextField("备注名（可选）", text: $label)
                    TextField("公开钱包地址", text: $address)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Button("添加") {
                        store.add(chain: chain, address: address, label: label)
                        address = ""; label = ""
                    }
                }
                Section("已添加（可左滑删除，随时换）") {
                    ForEach(store.wallets) { w in
                        VStack(alignment: .leading) {
                            Text(w.label).bold()
                            Text("\(w.chain.displayName) · \(w.address)").font(.caption).lineLimit(1)
                        }
                    }
                    .onDelete(perform: store.remove)
                }
            }
            .navigationTitle("钱包管理")
        }
    }
}
