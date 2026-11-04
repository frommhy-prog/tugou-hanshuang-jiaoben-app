import SwiftUI

// 仪表盘 + 控制台：所有网络请求（行情源、引擎、AI）统一记录，能看到哪个数据源在失效、速度如何；
// 控制台可以「切断」某个来源，直接验证兜底是否真的生效。
struct SourceLog: Identifiable {
    let id = UUID()
    let t: Date
    let host: String
    let path: String
    let code: Int
    let ms: Int
    let err: String?
    var ok: Bool { err == nil && code >= 200 && code < 300 }
}

struct SourceStat: Identifiable {
    var id: String { host }
    var host: String
    var n: Int
    var okN: Int
    var avgMs: Int
    var last: SourceLog?
}

@MainActor
final class SourceHub: ObservableObject {
    static let shared = SourceHub()
    @Published var logs: [SourceLog] = []

    static let names: [String: String] = [
        "api.dexscreener.com": "Dexscreener（行情/池子）",
        "api.geckoterminal.com": "GeckoTerminal（K线/成交）",
        "api.dexpaprika.com": "DexPaprika（备用行情）",
        "api.gopluslabs.io": "GoPlus（合约安全）",
        "api.rugcheck.xyz": "RugCheck（Solana 风险）",
        "tstzm-api.from-mhy.workers.dev": "TSTZ 服务（Worker）",
        "api.fxtwitter.com": "X 资料（fxtwitter）",
    ]

    static func name(_ host: String) -> String {
        if let n = names[host] { return n }
        if host.hasSuffix("workers.dev") { return "TSTZ 服务（Worker）" }
        return host
    }

    static func install() {
        Net.onLog = { host, path, code, ms, err in
            Task { @MainActor in SourceHub.shared.add(host, path, code, ms, err) }
        }
    }

    func add(_ host: String, _ path: String, _ code: Int, _ ms: Int, _ err: String?) {
        logs.insert(SourceLog(t: Date(), host: host, path: path, code: code, ms: ms, err: err), at: 0)
        if logs.count > 300 { logs.removeLast(logs.count - 300) }
    }

    func clear() { logs = [] }

    var stats: [SourceStat] {
        var d: [String: [SourceLog]] = [:]
        for l in logs { d[l.host, default: []].append(l) }
        var out: [SourceStat] = []
        for (h, ls) in d {
            let okN = ls.filter { $0.ok }.count
            let avg = ls.reduce(0) { $0 + $1.ms } / max(1, ls.count)
            out.append(SourceStat(host: h, n: ls.count, okN: okN, avgMs: avg, last: ls.first))
        }
        return out.sorted { $0.n > $1.n }
    }
}

struct AITestRow: Decodable {
    var p: String?
    var ok: Bool?
    var ms: Int?
    var err: String?
}

struct AITestResp: Decodable {
    var providers: [AITestRow]?
}

struct ProbeResult: Identifiable {
    let id = UUID()
    var name: String
    var ok: Bool
    var ms: Int
    var note: String
}

struct DashboardView: View {
    @ObservedObject private var hub = SourceHub.shared
    @State private var ai: [AITestRow] = []
    @State private var aiBusy = false
    @State private var aiErr: String?
    @State private var snaps: [TokenSnapshot] = []

    private func rate(_ s: SourceStat) -> Double { s.n == 0 ? 0 : Double(s.okN) / Double(s.n) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("数据源健康").font(.headline)
                            if hub.stats.isEmpty { Text("还没有请求记录：去代币页查一次，这里就会出现各来源的成功率和速度").font(.caption).foregroundStyle(.secondary) }
                            ForEach(hub.stats) { s in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(SourceHub.name(s.host)).font(.subheadline)
                                        Spacer()
                                        Text(cat(String(s.okN), "/", String(s.n), " 成功 · 平均 ", String(s.avgMs), " ms")).font(.caption).foregroundStyle(.secondary)
                                    }
                                    ScoreBar(score: Int(rate(s) * 100), color: rate(s) >= 0.9 ? .green : (rate(s) >= 0.6 ? .orange : .red))
                                    if let l = s.last, !l.ok {
                                        Text(cat("最近一次失败：", l.err ?? String(l.code), " · ", l.t.formatted(date: .omitted, time: .standard))).font(.caption2).foregroundStyle(Color.orange)
                                    }
                                }
                            }
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("AI 后端自检").font(.headline)
                                Spacer()
                                Button(aiBusy ? "检测中…" : "立即检测") { Task { await runAITest() } }.disabled(aiBusy)
                            }
                            if let e = aiErr { Text(e).font(.caption).foregroundStyle(Color.orange) }
                            ForEach(Array(ai.enumerated()), id: \.offset) { _, r in
                                HStack {
                                    Image(systemName: (r.ok ?? false) ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle((r.ok ?? false) ? Color.green : Color.red)
                                    Text(r.p ?? "?").font(.caption)
                                    Spacer()
                                    Text((r.ok ?? false) ? cat(String(r.ms ?? 0), " ms") : (r.err ?? "不可用")).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Text("AI 只是其中一条轨道；规则分析引擎不依赖它，AI 全部不可用时规则分析照常出结果。").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("已缓存的代币（断网也能看）").font(.headline)
                            if snaps.isEmpty { Text("暂无缓存").font(.caption).foregroundStyle(.secondary) }
                            ForEach(snaps, id: \.address) { s in
                                Button {
                                    UTokenVM.shared.start(s.address)
                                    AppRouter.shared.tab = 0
                                } label: {
                                    HStack {
                                        Text(s.pairs.first?.baseToken?.symbol ?? Addr.short(s.address))
                                        Spacer()
                                        Text(s.savedAt.formatted(date: .abbreviated, time: .standard)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if !snaps.isEmpty { Button("清除全部缓存", role: .destructive) { TokenStore.clearAll(); snaps = [] } }
                        }
                    }
                    NavigationLink { ConsoleView() } label: {
                        Card { HStack { Label("控制台：请求日志 / 切断来源测试兜底 / 全链路自检", systemImage: "terminal"); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary) } }
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationTitle("仪表盘")
            .onAppear { snaps = TokenStore.list() }
        }
    }

    private func runAITest() async {
        aiBusy = true
        aiErr = nil
        defer { aiBusy = false }
        do {
            let r: AITestResp = try await Engine.get("/e/v2/aitest", [:])
            ai = r.providers ?? []
        } catch {
            aiErr = Net.message(error)
        }
    }
}

struct ConsoleView: View {
    @ObservedObject private var hub = SourceHub.shared
    @State private var blocked: Set<String> = Net.blocked
    @State private var onlyFail = false
    @State private var probes: [ProbeResult] = []
    @State private var busy = false

    private let hosts = ["api.dexscreener.com", "api.geckoterminal.com", "api.dexpaprika.com", "api.gopluslabs.io", "api.rugcheck.xyz"]

    var body: some View {
        List {
            Section("切断来源（测试兜底；退出控制台不会自动恢复，请记得打开）") {
                ForEach(hosts, id: \.self) { h in
                    Toggle(SourceHub.name(h), isOn: Binding(get: { blocked.contains(h) }, set: { on in
                        if on { blocked.insert(h) } else { blocked.remove(h) }
                        Net.blocked = blocked
                    }))
                }
            }
            Section("全链路自检") {
                Button(busy ? "检测中…" : "检测全部数据源") { Task { await runProbes() } }.disabled(busy)
                ForEach(probes) { p in
                    HStack {
                        Image(systemName: p.ok ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(p.ok ? Color.green : Color.red)
                        Text(p.name).font(.subheadline)
                        Spacer()
                        Text(p.ok ? cat(String(p.ms), " ms") : p.note).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Toggle("只看失败", isOn: $onlyFail)
                Button("复制日志") {
                    let text = hub.logs.prefix(100).map { cat($0.t.formatted(date: .omitted, time: .standard), " ", $0.host, $0.path, " ", String($0.code), " ", String($0.ms), "ms ", $0.err ?? "") }.joined(separator: "\n")
                    UIPasteboard.general.string = text
                }
                Button("清空日志", role: .destructive) { hub.clear() }
            }
            Section("请求日志（最近 100 条）") {
                ForEach(hub.logs.filter { !onlyFail || !$0.ok }.prefix(100)) { l in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(l.ok ? "OK" : "失败").font(.caption.bold()).foregroundStyle(l.ok ? Color.green : Color.red)
                            Text(SourceHub.name(l.host)).font(.caption)
                            Spacer()
                            Text(cat(String(l.code), " · ", String(l.ms), " ms")).font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(cat(l.path, l.err.map { " · " + $0 } ?? "")).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        Text(l.t.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle("控制台")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func probe(_ name: String, _ urlStr: String) async -> ProbeResult {
        guard let url = URL(string: urlStr) else { return ProbeResult(name: name, ok: false, ms: 0, note: "地址无效") }
        let t0 = Date()
        do {
            let r = try await Net.fetch(URLRequest(url: url, timeoutInterval: 15))
            let code = (r.1 as? HTTPURLResponse)?.statusCode ?? 0
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            return ProbeResult(name: name, ok: (200..<300).contains(code), ms: ms, note: cat("HTTP ", String(code)))
        } catch {
            return ProbeResult(name: name, ok: false, ms: Int(Date().timeIntervalSince(t0) * 1000), note: Net.message(error))
        }
    }

    private func runProbes() async {
        busy = true
        defer { busy = false }
        async let a = probe("Dexscreener", "https://api.dexscreener.com/latest/dex/search?q=SOL")
        async let b = probe("GeckoTerminal", "https://api.geckoterminal.com/api/v2/networks")
        async let c = probe("DexPaprika", "https://api.dexpaprika.com/networks")
        async let d = probe("GoPlus", "https://api.gopluslabs.io/api/v1/supported_chains")
        async let e = probe("RugCheck", "https://api.rugcheck.xyz/v1/stats/new_tokens")
        var res = [await a, await b, await c, await d, await e]
        let t0 = Date()
        do {
            let _: JV = try await Engine.get("/e/v2/aitest", [:])
            res.append(ProbeResult(name: "TSTZ 引擎", ok: true, ms: Int(Date().timeIntervalSince(t0) * 1000), note: ""))
        } catch {
            res.append(ProbeResult(name: "TSTZ 引擎", ok: false, ms: Int(Date().timeIntervalSince(t0) * 1000), note: Net.message(error)))
        }
        probes = res
    }
}
