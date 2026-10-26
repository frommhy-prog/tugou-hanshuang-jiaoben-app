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

    var body: some View {
        NavigationView {
            Form {
                Picker("链", selection: $chain) {
                    ForEach(Chain.allCases) { c in Text(c.displayName).tag(c) }
                }
                TextField("粘贴合约地址", text: $contract)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Section("说明") {
                    Text("粘贴后走 Worker 查价格、流动性、24h 量。持仓人数、税、蜜罐、权限、LP 锁定第二阶段再接，不编数。")
                        .font(.footnote)
                }
                Section("跳转") {
                    Link("Ave", destination: URL(string: "https://ave.ai/")!)
                    Link("GMGN", destination: URL(string: "https://gmgn.ai/")!)
                    Link("Dexscreener", destination: URL(string: "https://dexscreener.com/")!)
                }
            }
            .navigationTitle("合约体检")
        }
    }
}

struct HoldingsView: View {
    @ObservedObject var wallets: WalletStore

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
                }
                Section("交易所") {
                    Text("币安、欧易、Gate：只读 Key 到位后接通，现在不显示假持仓。")
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
