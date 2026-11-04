# 补丁清单（第一批）：AI 容错解码、模型层持久化与提速、切换界面不丢信息
AI_TYPES = r'''struct AIPoint: Codable {
    var claim: String?
    var why: String?
    var evidence: String?
    var basis: String?
}

// 解码对模型输出的各种怪形状全部容错：数组里混进空字符串、字段是数组/对象/数字，都不会让整份结果失败
struct AIAnalysis: Codable {
    var headline: String?
    var stance: String?
    var summary: String?
    var judgement: String?
    var points: [AIPoint]?
    var risks: [String]?
    var watch: [String]?
    var unknown: [String]?

    init(headline: String? = nil, stance: String? = nil, summary: String? = nil, judgement: String? = nil, points: [AIPoint]? = nil, risks: [String]? = nil, watch: [String]? = nil, unknown: [String]? = nil) {
        self.headline = headline
        self.stance = stance
        self.summary = summary
        self.judgement = judgement
        self.points = points
        self.risks = risks
        self.watch = watch
        self.unknown = unknown
    }

    enum CodingKeys: String, CodingKey { case headline, stance, summary, judgement, points, risks, watch, unknown }

    private static func pick(_ o: [String: JV], _ keys: [String]) -> String? {
        for k in keys { if let t = o[k]?.text { return t } }
        return nil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        headline = c.jv(.headline).text
        stance = c.jv(.stance).text
        summary = c.jv(.summary).text
        judgement = c.jv(.judgement).text
        var pts: [AIPoint] = []
        for p in c.jv(.points).array ?? [] {
            if let o = p.object {
                guard let claim = AIAnalysis.pick(o, ["claim", "point", "title"]) else { continue }
                pts.append(AIPoint(claim: claim, why: AIAnalysis.pick(o, ["why", "reason"]), evidence: AIAnalysis.pick(o, ["evidence"]), basis: AIAnalysis.pick(o, ["basis"])))
            } else if let s = p.text {
                pts.append(AIPoint(claim: s, why: nil, evidence: nil, basis: nil))
            }
        }
        points = pts.isEmpty ? nil : pts
        let r = c.jv(.risks).strings
        risks = r.isEmpty ? nil : r
        let w = c.jv(.watch).strings
        watch = w.isEmpty ? nil : w
        let u = c.jv(.unknown).strings
        unknown = u.isEmpty ? nil : u
    }

    var isUsable: Bool { !(points ?? []).isEmpty || !((headline ?? judgement ?? "").isEmpty) }
}

struct AIResult: Codable {
    var analysis: AIAnalysis?
    var model: String?
    var provider: String?
    var cached: Bool?
    var generatedAt: Double?
    var error: String?
    var detail: String?
    var note: String?

    init(analysis: AIAnalysis? = nil, model: String? = nil, provider: String? = nil, cached: Bool? = nil, generatedAt: Double? = nil, error: String? = nil, detail: String? = nil, note: String? = nil) {
        self.analysis = analysis
        self.model = model
        self.provider = provider
        self.cached = cached
        self.generatedAt = generatedAt
        self.error = error
        self.detail = detail
        self.note = note
    }

    enum CodingKeys: String, CodingKey { case analysis, model, provider, cached, generatedAt, error, detail, note }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        analysis = try? c.decodeIfPresent(AIAnalysis.self, forKey: .analysis)
        model = c.jv(.model).text
        provider = c.jv(.provider).text
        cached = try? c.decodeIfPresent(Bool.self, forKey: .cached)
        generatedAt = try? c.decodeIfPresent(Double.self, forKey: .generatedAt)
        error = c.jv(.error).text
        detail = c.jv(.detail).text
        note = c.jv(.note).text
    }
}

'''

AI_MSG = r'''func aiMessage(_ r: AIResult) -> String? {
    if r.error == nil, let a = r.analysis, a.isUsable { return nil }
    guard let e = r.error else { return "AI 返回了空内容" }
    let d = r.detail.map { "：" + String($0.prefix(80)) } ?? ""
    if e == "no_groq_key" { return "未绑定 Groq 密钥（设置 → API 密钥与额度），规则分析不受影响" }
    if e == "ai_all_failed" { return "云端 AI 各模型均未返回可用内容" + d }
    if e.hasPrefix("groq_429") { return "Groq 已限额，稍后自动恢复；规则分析不受影响" }
    return "AI 暂时不可用（" + e + d + "）"
}
'''

NEW_FIELDS = r'''    @Published var shareItems: [Any] = []
    @Published var stamps = Stamps()
    @Published var refreshing = false
    @Published var refreshNote: String?
    @Published var analyzedDone = 0
    @Published var analyzeTotal = 0
    private var runID = 0
    private var tradesDone = false
    private var holdersDone = false
    private var aiUsed = 0
    private var persistTask: Task<Void, Never>?

    static let shared = UTokenVM()

    init() {
        if let a = Cfg.defaults.string(forKey: "lastTokenAddr"), !a.isEmpty, let s = TokenStore.load(a) {
            apply(s)
            input = s.address
        }
    }
'''

NEW_START_RUN = r'''    func start(_ raw: String) {
        let addr = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Addr.isEVM(addr) || Addr.isSolana(addr) else {
            error = "地址格式不对：EVM 是 0x 开头 42 位，Solana 是 32–44 位 Base58"
            return
        }
        runID += 1
        let id = runID
        let same = addr.lowercased() == address.lowercased() && !pairs.isEmpty
        if !same {
            resetState()
            if let s = TokenStore.load(addr) { apply(s) } // 先显示上次的旧数据（带时间），后台再刷新
        }
        address = addr
        input = addr
        error = nil
        loading = pairs.isEmpty
        refreshing = true
        Cfg.defaults.set(addr, forKey: "lastTokenAddr")
        Task { await run(addr, id) }
    }

    private func resetState() {
        pairs = []; candles = []; trades = []; holders = []; conc = nil; holderNote = nil; holderFindings = []
        analyses = [:]; analysisErr = [:]; security = nil; ai = nil; aiMsg = nil; insights = []; error = nil
        chartNote = nil; tradesNote = nil; authorities = nil; holderComplete = true; holderPages = 3
        stamps = Stamps(); refreshNote = nil; analyzedDone = 0; analyzeTotal = 0; aiUsed = 0
    }

    private func apply(_ s: TokenSnapshot) {
        address = s.address
        chain = Chain(rawValue: s.chain) ?? chain
        pairs = s.pairs
        trades = s.trades
        holders = s.holders
        conc = s.conc
        holderNote = s.holderNote
        holderFindings = s.holderFindings
        holderComplete = s.holderComplete
        authorities = s.authorities
        analyses = s.analyses
        security = s.security
        ai = s.ai
        stamps = s.stamps
        rebuild()
    }

    func schedulePersist() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            self?.persist()
        }
    }

    func persist() {
        guard !address.isEmpty, !pairs.isEmpty else { return }
        TokenStore.save(TokenSnapshot(address: address, chain: chain.rawValue, pairs: pairs, trades: Array(trades.prefix(300)), holders: holders, conc: conc, holderNote: holderNote, holderFindings: holderFindings, holderComplete: holderComplete, authorities: authorities, analyses: analyses, security: security, ai: ai, stamps: stamps, savedAt: Date()))
    }

    // 一次请求同时拿到链和池子；成交、持有人、安全、AI 全部并行，AI 不等大户拆解
    private func run(_ addr: String, _ id: Int) async {
        do {
            let (c, ps) = try await MarketAPI.resolve(addr)
            guard id == runID else { return }
            if ps.isEmpty {
                if pairs.isEmpty { error = "这条链上没有找到该代币的交易池（Dexscreener 无数据）。可能是新币尚未被收录，或地址/链不对。" } else { refreshNote = "池子数据刷新为空，显示的是旧数据" }
                loading = false; refreshing = false
                return
            }
            chain = c
            pairs = ps
            stamps.pairs = Date()
            refreshNote = nil
            QueryHistory.add(kind: "token", chain: c.rawValue, address: addr, title: ps[0].baseToken?.symbol ?? Addr.short(addr))
        } catch {
            guard id == runID else { return }
            if pairs.isEmpty { self.error = error.localizedDescription } else { refreshNote = "刷新失败，显示的是旧数据：" + Net.message(error) }
            loading = false; refreshing = false
            return
        }
        loading = false
        rebuild()
        tradesDone = false
        holdersDone = false
        await withTaskGroup(of: Void.self) { g in
            g.addTask { await self.loadTrades(id) }
            g.addTask { await self.loadSecurity(id) }
            g.addTask { await self.loadHolders(id); await self.analyzeHolders(id) }
            g.addTask { await self.autoAI(id) }
        }
        guard id == runID else { return }
        refreshing = false
        persist()
        if AIMode.auto, analyses.count >= 2, analyses.count > aiUsed { await runAI(id, fresh: false) } // 拆解完成后补一版 AI
    }

    private func autoAI(_ id: Int) async {
        guard AIMode.auto else { return }
        var waited = 0.0
        while waited < 25, id == runID, !(tradesDone && holdersDone) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            waited += 0.3
        }
        guard id == runID else { return }
        await runAI(id, fresh: false)
    }

'''

NEW_ANALYZE = r'''    // 最多 10 个普通钱包，三路并行，边出结果边显示；10 分钟内拆解过的不重复请求
    func analyzeHolders(_ id: Int) async {
        let recent = stamps.analyses.map { Date().timeIntervalSince($0) < 600 } ?? false
        let targets = holders.filter { $0.kind == "wallet" }.prefix(10).map { $0.owner }.filter { analyses[$0] == nil || !recent }
        if targets.isEmpty { return }
        analyzing = true
        analyzedDone = 0
        analyzeTotal = targets.count
        defer { analyzing = false }
        let lanes = 3
        await withTaskGroup(of: Void.self) { group in
            for lane in 0..<lanes {
                group.addTask { [weak self] in
                    var i = lane
                    while i < targets.count {
                        await self?.analyzeOne(targets[i], id)
                        i += lanes
                    }
                }
            }
        }
        guard id == runID else { return }
        stamps.analyses = Date()
        rebuild()
        schedulePersist()
    }

'''

NEW_RUNAI = r'''    func runAI(_ id: Int, fresh: Bool) async {
        guard id == runID, main != nil else { return }
        aiLoading = true
        aiMsg = nil
        aiUsed = analyses.count
        defer { aiLoading = false }
        let r = await AIChain.run(kind: "代币综合分析（行情、成交流向、池子、持有人成本与盈亏、安全）", facts: buildFacts(), fresh: fresh)
        guard id == runID else { return }
        if let m = aiMessage(r) {
            aiMsg = m + (ai != nil ? "（下方仍是上次的 AI 结果）" : "")
        } else {
            ai = r
            stamps.ai = r.generatedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        }
        schedulePersist()
    }

'''


def register(rep, cut):
    E = 'ios/App/Engine.swift'
    cut('ai_types', E, 'struct AIPoint: Codable {', 'struct AIPayload<F: Encodable>: Encodable {', AI_TYPES)
    rep('ai_footnote', E, 'Text("AI 只解读程序算出的数据，不引入外部信息；不构成投资建议" + ((result?.cached ?? false) ? "（缓存结果）" : "")).font(.caption2).foregroundStyle(.secondary)', 'Text(AIStyle.footnote(result)).font(.caption2).foregroundStyle(.secondary)')
    rep('ai_msgline', E, 'Button("重新分析", action: onRun).font(.caption2)\n                    }\n                } else if let m = message {', 'Button("重新分析", action: onRun).font(.caption2)\n                    }\n                    if let m = message { Text(m).font(.caption2).foregroundStyle(Color.orange) }\n                } else if let m = message {')
    cut('ai_msgfn', E, 'func aiMessage(_ r: AIResult) -> String? {', None, AI_MSG)

    M = 'ios/App/UnifiedTokenModel.swift'
    for n, o, w in [
        ('dtok', 'struct DexTok: Decodable {', 'struct DexTok: Codable {'),
        ('dtx', 'struct DexTx: Decodable {', 'struct DexTx: Codable {'),
        ('dliq', 'struct DexLiq: Decodable {', 'struct DexLiq: Codable {'),
        ('dsoc', 'struct DexSocial: Decodable {', 'struct DexSocial: Codable {'),
        ('dweb', 'struct DexWeb: Decodable {', 'struct DexWeb: Codable {'),
        ('dinfo', 'struct DexInfo: Decodable {', 'struct DexInfo: Codable {'),
        ('dpair', 'struct DexPair: Decodable, Identifiable {', 'struct DexPair: Codable, Identifiable {'),
        ('utrade', 'struct UTrade: Identifiable {', 'struct UTrade: Identifiable, Codable {'),
        ('uholder', 'struct UHolder: Identifiable {', 'struct UHolder: Identifiable, Codable {'),
    ]:
        rep('m_codable_' + n, M, o, w)
    rep('m_fields', M, '    @Published var shareItems: [Any] = []\n    private var runID = 0\n', NEW_FIELDS)
    cut('m_startrun', M, '    func start(_ raw: String) {', '    func loadCandles(_ id: Int) async {', NEW_START_RUN)
    rep('m_trades_defer', M, '    func loadTrades(_ id: Int) async {\n        guard let p = main?.pairAddress else { return }\n', '    func loadTrades(_ id: Int) async {\n        defer { tradesDone = true }\n        guard let p = main?.pairAddress else { return }\n')
    rep('m_trades_stamp', M, '            trades = ts\n            tradesNote = ts.isEmpty ? "最近没有成交记录" : nil\n            rebuild()\n', '            trades = ts\n            tradesNote = ts.isEmpty ? "最近没有成交记录" : nil\n            stamps.trades = Date()\n            rebuild()\n            schedulePersist()\n')
    rep('m_tick', M, '        if let ps = try? await MarketAPI.pairs(chain, address), !ps.isEmpty, id == runID { pairs = ps }\n        await loadCandles(id)\n        await loadTrades(id)\n', '        if let ps = try? await MarketAPI.pairs(chain, address), !ps.isEmpty, id == runID { pairs = ps; stamps.pairs = Date() }\n        await loadTrades(id)\n')
    rep('m_h_sol', M, '["mint": address, "fresh": "1"]', '["mint": address]')
    rep('m_h_evm', M, '"pages": String(holderPages), "fresh": "1"]', '"pages": String(holderPages)]')
    rep('m_h_defer', M, '        holderLoading = true\n        defer { holderLoading = false }\n', '        holderLoading = true\n        defer { holderLoading = false; holdersDone = true }\n')
    rep('m_h_stamp', M, '                holderNote = "该链暂不支持持有人榜单"\n            }\n            rebuild()\n', '                holderNote = "该链暂不支持持有人榜单"\n            }\n            if !holders.isEmpty { stamps.holders = Date() }\n            rebuild()\n            schedulePersist()\n')
    rep('m_sec_stamp', M, '            security = r\n            rebuild()\n', '            security = r\n            stamps.security = Date()\n            rebuild()\n')
    cut('m_analyze', M, '    // 最多 10 个普通钱包，两路并行，边出结果边显示\n', '    func analyzeOne(_ owner: String, _ id: Int) async {', NEW_ANALYZE)
    rep('m_one_done', M, '            analysisErr[owner] = error.localizedDescription\n        }\n        rebuild()\n    }\n\n    var agg: HolderAgg {', '            analysisErr[owner] = error.localizedDescription\n        }\n        analyzedDone += 1\n        rebuild()\n    }\n\n    var agg: HolderAgg {')
    cut('m_runai', M, '    func runAI(_ id: Int, fresh: Bool) async {', '    func reAI() {', NEW_RUNAI)

    U = 'ios/App/UnifiedToken.swift'
    rep('tok_shared', U, '@StateObject private var vm = UTokenVM()', '@ObservedObject private var vm = UTokenVM.shared')
    rep('tok_cards', U, '            headerCard\n            KLineCard(vm: vm)\n', '            headerCard\n            FreshnessRow(vm: vm)\n            KLineCard(vm: vm)\n            ReportCard(vm: vm)\n')

    P = 'ios/App/ProChart.swift'
    rep('kl_vars', P, '    var dark = true\n    private var trades: [UTrade] = []\n', '    var dark = true\n    static let autoPages = 1\n    @Published var histMore = false\n    var extraMarks: [[Double]] = []\n    private var trades: [UTrade] = []\n')
    rep('kl_loop', P, '        while g == gen && pages < 12 {', '        while g == gen && pages < KLineVM.autoPages {')
    rep('kl_sleep', P, '                try? await Task.sleep(nanoseconds: 2_300_000_000)\n            } catch {', '                if pages < KLineVM.autoPages { try? await Task.sleep(nanoseconds: 2_300_000_000) }\n            } catch {')
    rep('kl_more_flag', P, '        if !histDone && pages >= 12 { histCapped = true }', '        if !histDone && pages >= KLineVM.autoPages { histMore = true }')
    rep('kl_loadmore', P, '    func retry() { reload() }', '    func loadMore() {\n        if loadingHist || histDone || candles.isEmpty { return }\n        let g = gen\n        let b = (candles.first?.t ?? 0) - 1\n        histMore = false\n        Task { await loadHistory(g, startBefore: b) }\n    }\n\n    func retry() { reload() }')
    rep('kl_cache_load', P, '        candles = []\n        note = nil\n        histDone = false\n', '        candles = KLineCache.load(chain.rawValue + ":" + pair + ":" + tf.rawValue)\n        if !candles.isEmpty { rebuild() }\n        note = nil\n        histDone = false\n')
    rep('kl_cache_save', P, '            payload = s\n            seq += 1\n        }\n    }', '            payload = s\n            seq += 1\n        }\n        KLineCache.save(key: chain.rawValue + ":" + pair + ":" + tf.rawValue, candles)\n    }')
    rep('kl_marks', P, '        var created: Any = NSNull()', '        for m in extraMarks where m.count >= 4 {\n            let b = (m[0] / sec).rounded(.down) * sec\n            if let f = candles.first?.t, let l = candles.last?.t, b >= f, b <= l { mk.append([b + off, m[1], m[2], m[3]]) }\n        }\n        var created: Any = NSNull()')
    rep('aifold_dedupe', P, '            AIResultCard(title: "AI 研判", result: vm.ai, loading: vm.aiLoading, message: vm.aiMsg, onRun: vm.reAI)\n', '')

    C = 'ios/App/CexView.swift'
    rep('wr_state', C, 'struct WalletsRoot: View {\n    @State private var seg = 0\n', 'struct WalletsRoot: View {\n    @State private var seg = 0\n    @State private var visited: Set<Int> = [0]\n')
    rep('wr_switch', C, '            switch seg {\n            case 0: WalletsView()\n            case 1: CexView()\n            default: AdHocWalletRoot()\n            }', '            ZStack {\n                if visited.contains(0) { WalletsView().opacity(seg == 0 ? 1 : 0).allowsHitTesting(seg == 0) }\n                if visited.contains(1) { CexView().opacity(seg == 1 ? 1 : 0).allowsHitTesting(seg == 1) }\n                if visited.contains(2) { AdHocWalletRoot().opacity(seg == 2 ? 1 : 0).allowsHitTesting(seg == 2) }\n            }\n            .onChange(of: seg) { _, v in visited.insert(v) }')

    R = 'ios/App/Promo.swift'
    rep('promo_state', R, '    @State private var payer = ""\n', '    @State private var payer = ""\n    @State private var loadedKey = ""\n')
    rep('promo_guard', R, '        if vm.address.isEmpty || vm.main == nil { return }\n        let chain = vm.chain\n', '        if vm.address.isEmpty || vm.main == nil { return }\n        if loadedKey == key && orders != nil { return }\n        loadedKey = key\n        let chain = vm.chain\n')
