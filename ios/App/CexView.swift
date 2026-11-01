import SwiftUI
import Charts

// MARK: - 钱包页外壳：链上钱包 / 交易所 / 查询任意地址
struct WalletsRoot: View {
    @State private var seg = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $seg) {
                Text("链上钱包").tag(0)
                Text("交易所").tag(1)
                Text("查询地址").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            switch seg {
            case 0: WalletsView()
            case 1: CexView()
            default: AdHocWalletRoot()
            }
        }
    }
}

// MARK: - 查询任意钱包（带查询记录）
struct AdHocTarget: Hashable {
    let address: String
    let chains: [String]
}

struct AdHocWalletRoot: View {
    @State private var input = ""
    @State private var hist: [HistoryItem] = QueryHistory.items.filter { $0.kind == "wallet" }
    @State private var path: [AdHocTarget] = []

    private func chainsFor(_ a: String) -> [String] {
        Addr.isEVM(a) ? Chain.evmDefault.map { $0.rawValue } : [Chain.solana.rawValue]
    }

    private func open(_ addr: String) {
        let a = addr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Addr.isEVM(a) || Addr.isSolana(a) else { return }
        QueryHistory.add(kind: "wallet", chain: Addr.isEVM(a) ? "evm" : "solana", address: a, title: Addr.short(a))
        hist = QueryHistory.items.filter { $0.kind == "wallet" }
        path.append(AdHocTarget(address: a, chains: chainsFor(a)))
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("查询任意钱包地址（Solana / EVM 自动识别）") {
                    TextField("粘贴钱包地址", text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        Button("粘贴") { if let s = UIPasteboard.general.string { input = s } }
                        Spacer()
                        Button("查询") { open(input) }
                            .buttonStyle(.borderedProminent)
                            .disabled(!(Addr.isEVM(input.trimmingCharacters(in: .whitespacesAndNewlines)) || Addr.isSolana(input.trimmingCharacters(in: .whitespacesAndNewlines))))
                    }
                }
                Section {
                    if hist.isEmpty { Text("还没有查询记录").foregroundStyle(.secondary) }
                    ForEach(hist) { h in
                        Button { open(h.address) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Addr.short(h.address)).font(.subheadline.monospaced()).foregroundStyle(Color.primary)
                                    Text(h.chain == "solana" ? "Solana" : "EVM").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(TZ.short(h.at)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { idx in
                        for i in idx { QueryHistory.remove(hist[i].id) }
                        hist = QueryHistory.items.filter { $0.kind == "wallet" }
                    }
                } header: {
                    HStack {
                        Text("查询记录")
                        Spacer()
                        if !hist.isEmpty { Button("清空") { QueryHistory.clear(kind: "wallet"); hist = [] }.font(.caption) }
                    }
                }
            }
            .navigationTitle("查询地址")
            .navigationDestination(for: AdHocTarget.self) { t in AdHocDetail(target: t) }
        }
    }
}

struct AdHocDetail: View {
    let target: AdHocTarget
    @State private var result: WalletResult?
    var body: some View {
        let w = Wallet(address: target.address, label: "查询", chains: target.chains)
        WalletDetailView(wallet: w, result: result)
            .task {
                if result == nil { result = await WalletsVM.fetch(w) }
            }
    }
}

// MARK: - 交易所只读持仓
struct CexAsset: Codable, Identifiable {
    var sym: String
    var amount: Double?
    var usd: Double?
    var acct: String?
    var id: String { sym + "|" + (acct ?? "") }
}

struct CexResult: Codable {
    var ex: String?
    var totalUsd: Double?
    var unpriced: Int?
    var accounts: [String: Double]?
    var assets: [CexAsset]?
    var error: String?
    var detail: String?
    var at: Double?
}

struct CexSign: Codable {
    struct Req: Codable {
        var id: String
        var method: String
        var url: String
        var headers: [String: String]
    }
    var requests: [Req]?
    var error: String?
    var detail: String?
}

@MainActor
final class CexVM: ObservableObject {
    static let names: [(String, String)] = [("binance", "币安"), ("okx", "欧易"), ("gate", "Gate")]
    @Published var results: [String: CexResult] = [:]
    @Published var loading: Set<String> = []
    @Published var updated: Date?

    var total: Double { results.values.reduce(0) { $0 + ($1.totalUsd ?? 0) } }

    func loadAll() async {
        await withTaskGroup(of: Void.self) { g in
            for n in CexVM.names { g.addTask { [weak self] in await self?.load(n.0) } }
        }
        updated = Date()
    }

    func load(_ ex: String) async {
        loading.insert(ex)
        defer { loading.remove(ex) }
        do {
            var r: CexResult = try await Engine.get("/e/v2/cex", ["ex": ex])
            if ex == "binance", let e = r.error, e.contains("http_403") || e.contains("http_451") {
                r = await binanceDirect()
            }
            results[ex] = r
        } catch {
            results[ex] = CexResult(ex: ex, error: "net", detail: Net.message(error))
        }
    }

    // 币安会拒绝云服务器出口 IP：引擎只签名（密钥不出服务端），请求由手机直连币安
    private func binanceDirect() async -> CexResult {
        do {
            let s: CexSign = try await Engine.get("/e/v2/cexsign", ["ex": "binance"])
            if let e = s.error { return CexResult(ex: "binance", error: e, detail: s.detail) }
            var assets: [CexAsset] = []
            var accounts: [String: Double] = [:]
            var prices: [String: Double] = [:]
            if let pu = URL(string: "https://api.binance.com/api/v3/ticker/price"), let pr = try? await Net.fetch(URLRequest(url: pu, timeoutInterval: 20)),
               let arr = try? JSONSerialization.jsonObject(with: pr.0) as? [[String: Any]] {
                for t in arr { if let sym = t["symbol"] as? String, let p = Double((t["price"] as? String) ?? "") { prices[sym] = p } }
            }
            func price(_ a: String) -> Double? {
                let stable: Set<String> = ["USDT", "USDC", "FDUSD", "BUSD", "TUSD", "USD1", "DAI"]
                if stable.contains(a) { return 1 }
                if let p = prices[a + "USDT"] { return p }
                if let p = prices[a + "BUSD"] { return p }
                if let p = prices[a + "BTC"], let b = prices["BTCUSDT"] { return p * b }
                return nil
            }
            for q in s.requests ?? [] {
                guard let url = URL(string: q.url) else { continue }
                var req = URLRequest(url: url, timeoutInterval: 25)
                req.httpMethod = q.method
                for (k, v) in q.headers { req.setValue(v, forHTTPHeaderField: k) }
                let r: (Data, URLResponse)
                do { r = try await Net.fetch(req) } catch { return CexResult(ex: "binance", error: "direct_net", detail: "手机直连币安失败：" + Net.message(error)) }
                let code = (r.1 as? HTTPURLResponse)?.statusCode ?? 0
                if q.id == "spot" && code != 200 {
                    let hint = (code == 403 || code == 451) ? "币安拒绝了你当前网络出口（\(code)），换个节点再试" : "币安返回 \(code)"
                    return CexResult(ex: "binance", error: "http_\(code)", detail: hint)
                }
                if code != 200 { continue }
                guard let o = try? JSONSerialization.jsonObject(with: r.0) else { continue }
                var sum = 0.0
                let acct = q.id == "spot" ? "现货" : "资金"
                let rows: [[String: Any]] = q.id == "spot" ? ((o as? [String: Any])?["balances"] as? [[String: Any]] ?? []) : (o as? [[String: Any]] ?? [])
                for b in rows {
                    guard let a = b["asset"] as? String else { continue }
                    let free = Double((b["free"] as? String) ?? "") ?? 0
                    let locked = Double((b["locked"] as? String) ?? "") ?? 0
                    let freeze = Double((b["freeze"] as? String) ?? "") ?? 0
                    let amt = free + locked + freeze
                    if amt <= 0 { continue }
                    let base = (a.hasPrefix("LD") && a != "LDO" && a.count > 2) ? String(a.dropFirst(2)) : a
                    let u = price(base).map { $0 * amt }
                    assets.append(CexAsset(sym: a, amount: amt, usd: u, acct: acct))
                    sum += u ?? 0
                }
                accounts[acct] = sum
            }
            let total = assets.reduce(0) { $0 + ($1.usd ?? 0) }
            let unp = assets.filter { $0.usd == nil }.count
            assets.sort { ($0.usd ?? 0) > ($1.usd ?? 0) }
            return CexResult(ex: "binance", totalUsd: total, unpriced: unp, accounts: accounts, assets: Array(assets.prefix(80)), at: Date().timeIntervalSince1970 * 1000)
        } catch {
            return CexResult(ex: "binance", error: "sign", detail: error.localizedDescription)
        }
    }
}

struct CexView: View {
    @StateObject private var vm = CexVM()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    totalCard
                    ForEach(CexVM.names, id: \.0) { n in exCard(n.0, n.1) }
                    Text("只读：只查询余额，不下单、不提现。API 密钥加密存放在你自己的 Cloudflare 里；请只开「读取」权限，且不要设置 IP 白名单（云端出口 IP 不固定）。").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .background(Color.page)
            .navigationTitle("交易所")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !vm.loading.isEmpty { ProgressView() } else { Button { Task { await vm.loadAll() } } label: { Image(systemName: "arrow.clockwise") } }
                }
            }
            .refreshable { await vm.loadAll() }
            .task { if vm.results.isEmpty { await vm.loadAll() } }
        }
    }

    private var totalCard: some View {
        let rows = topAssets()
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("交易所总资产").font(.footnote).foregroundStyle(.secondary)
                Text(Money.format(vm.total)).font(.system(size: 32, weight: .bold, design: .rounded))
                if let u = vm.updated { Text("更新于 " + TZ.format(u)).font(.caption2).foregroundStyle(.secondary) }
                if rows.count >= 2 {
                    Chart(rows) { r in
                        BarMark(x: .value("美元", r.usd), y: .value("币种", r.sym))
                            .foregroundStyle(Color.blue.opacity(0.75))
                            .annotation(position: .trailing) { Text(Fmt2.usd(r.usd)).font(.system(size: 9)).foregroundStyle(.secondary) }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(rows.count) * 24 + 10)
                }
            }
        }
    }

    struct AssetSum: Identifiable { let sym: String; let usd: Double; var id: String { sym } }

    private func topAssets() -> [AssetSum] {
        var m: [String: Double] = [:]
        for r in vm.results.values { for a in r.assets ?? [] { m[a.sym, default: 0] += a.usd ?? 0 } }
        return m.filter { $0.value >= 1 }.map { AssetSum(sym: $0.key, usd: $0.value) }.sorted { $0.usd > $1.usd }.prefix(6).map { $0 }
    }

    private func exCard(_ ex: String, _ name: String) -> some View {
        let r = vm.results[ex]
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(name, systemImage: "building.columns").font(.headline)
                    Spacer()
                    if vm.loading.contains(ex) { ProgressView() }
                    else if let r = r, r.error == nil { Text(Money.format(r.totalUsd)).font(.headline.monospacedDigit()) }
                }
                if let r = r {
                    if let e = r.error {
                        if e == "no_key" { Text("还没绑定 API 密钥：设置 → API 密钥与额度").font(.footnote).foregroundStyle(.secondary) }
                        else { Text(errText(e, r.detail)).font(.footnote).foregroundStyle(Color.orange) }
                        Button("重试") { Task { await vm.load(ex) } }.font(.footnote.weight(.semibold))
                    } else {
                        if let acc = r.accounts, acc.count > 1 {
                            HStack(spacing: 12) {
                                ForEach(acc.keys.sorted(), id: \.self) { k in Text(k + " " + Money.format(acc[k])).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        let list = (r.assets ?? []).filter { ($0.usd ?? 0) >= 0.01 || $0.usd == nil }.prefix(15)
                        if list.isEmpty { Text("账户里没有可估值的资产（或余额极小）").font(.footnote).foregroundStyle(.secondary) }
                        ForEach(Array(list)) { a in
                            HStack {
                                Text(a.sym).font(.subheadline.weight(.semibold))
                                if let ac = a.acct { Text(ac).font(.caption2).foregroundStyle(.secondary) }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(a.usd != nil ? Money.format(a.usd) : "无报价").font(.subheadline.monospacedDigit())
                                    Text(Fmt2.qty(a.amount)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if (r.unpriced ?? 0) > 0 { Text("\(r.unpriced ?? 0) 个资产没有现货报价，不计入总值").font(.caption2).foregroundStyle(.secondary) }
                    }
                } else if !vm.loading.contains(ex) {
                    Text("未查询").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func errText(_ e: String, _ d: String?) -> String {
        let extra = d.map { "：" + $0 } ?? ""
        if e.hasPrefix("http_401") || e.hasPrefix("http_403") { return "交易所拒绝访问（密钥无效、权限不足或被 IP 白名单拦截）" + extra }
        return e + extra
    }
}
