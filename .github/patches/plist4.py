# 补丁清单（第四批）：Ave 风格 K 线的 Swift 侧（周期栏 / 指标栏 / 市值切换 / 向左懒加载 / 大户标记）
CHART_BLOCK = r'''    private var mainList: [String] { mainSet.split(separator: ",").map { String($0) } }

    private func toggleMain(_ n: String) {
        var s = Set(mainList)
        if s.contains(n) { s.remove(n) } else { s.insert(n) }
        mainSet = ["MA", "EMA", "BOLL", "SAR", "SUPER"].filter { s.contains($0) }.joined(separator: ",")
    }

    private func applyCfg() {
        cvm.cfgMain = mainSet
        cvm.cfgSub = subInd
        cvm.cfgMcap = mcap
        var mult = 1.0
        if let m = vm.main, let p = m.price, p > 0, let mc = m.marketCap ?? m.fdv, mc > 0 { mult = mc / p }
        cvm.cfgMult = mult
        var marks: [[Double]] = []
        for (owner, an) in vm.analyses {
            let rank = vm.holders.first(where: { kNorm($0.owner) == kNorm(owner) })?.rank ?? 0
            for t in an.trades ?? [] {
                guard let u = t.usd, u > 0 else { continue }
                marks.append([t.t, t.side == "buy" ? 1 : -1, u, Double(rank)])
            }
        }
        marks.sort { $0[2] > $1[2] }
        cvm.extraMarks = Array(marks.prefix(40))
    }

    private var periodBar: some View {
        let main: [TF] = [.m1, .m5, .h1, .h4, .d1]
        return HStack(spacing: 4) {
            ForEach(main) { t in
                Button { cvm.setTF(t) } label: {
                    Text(t.title).font(.footnote.weight(cvm.tf == t ? .bold : .regular)).padding(.horizontal, 8).padding(.vertical, 4).background(cvm.tf == t ? Color.accentColor.opacity(0.18) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Menu {
                ForEach(TF.allCases.filter { !main.contains($0) }) { t in Button(t.title) { cvm.setTF(t) } }
            } label: {
                Text(main.contains(cvm.tf) ? "更多 ▾" : cvm.tf.title + " ▾").font(.footnote.weight(main.contains(cvm.tf) ? .regular : .bold))
            }
            Spacer()
            Button { mcap.toggle() } label: {
                Text(mcap ? "市值 ⇄" : "价格 ⇄").font(.footnote.weight(.semibold))
            }
        }
    }

    private var indicatorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(["MA", "EMA", "BOLL", "SAR", "SUPER"], id: \.self) { n in
                    Button { toggleMain(n) } label: {
                        Text(n).font(.footnote.weight(mainList.contains(n) ? .bold : .regular)).foregroundStyle(mainList.contains(n) ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Divider().frame(height: 14)
                ForEach(["VOL", "MACD", "KDJ", "RSI", "ROC"], id: \.self) { n in
                    Button { subInd = (subInd == n ? "" : n) } label: {
                        Text(n).font(.footnote.weight(subInd == n ? .bold : .regular)).foregroundStyle(subInd == n ? Color.primary : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var chartBlock: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("K 线", systemImage: "chart.xyaxis.line").font(.headline)
                    Spacer()
                    Text(cvm.statusText).font(.caption2).foregroundStyle(.secondary)
                }
                periodBar
                if cvm.payload.isEmpty {
                    if let n = cvm.note {
                        Text(n).font(.footnote).foregroundStyle(.secondary)
                        Button("重试") { cvm.retry() }.font(.footnote.weight(.semibold))
                    } else {
                        HStack(spacing: 8) { ProgressView(); Text("加载 K 线…").font(.footnote).foregroundStyle(.secondary) }
                    }
                } else {
                    KLineWeb(payload: cvm.payload, seq: cvm.seq, clearToken: cvm.clearToken) { t in cvm.onWeb(t) }
                        .frame(height: 460)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    indicatorBar
                    if cvm.histPaused {
                        Button("历史加载被限速打断，点这里继续补全") { cvm.resume() }.font(.footnote.weight(.semibold))
                    }
                    Text("来源 GeckoTerminal 最深池子 · 主图可叠加多个指标，副图单选 · 绿/红箭头 = 该根里的大额买/卖，圆点 #n = 已拆解的第 n 大持有人的成交 · 市值 = 价格 × 当前供应量（按现在的市值÷现价折算）· 点一根 K 线选中，再点取消 · 往左拖自动补历史").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .onChange(of: mainSet) { _, _ in applyCfg(); cvm.rebuild() }
            .onChange(of: subInd) { _, _ in applyCfg(); cvm.rebuild() }
            .onChange(of: mcap) { _, _ in applyCfg(); cvm.rebuild() }
            .onChange(of: vm.stamps.analyses) { _, _ in applyCfg(); cvm.rebuild() }
        }
    }
}

'''


def register(rep, cut):
    P = 'ios/App/ProChart.swift'
    rep('av_vars', P, '    var extraMarks: [[Double]] = []\n    private var trades: [UTrade] = []\n', '    var extraMarks: [[Double]] = []\n    var cfgMain = "MA,SUPER"\n    var cfgSub = "MACD"\n    var cfgMcap = false\n    var cfgMult = 1.0\n    private var trades: [UTrade] = []\n')
    rep('av_obj', P, '            "dark": dark,\n        ]', '            "dark": dark,\n            "main": cfgMain,\n            "sub": cfgSub,\n            "mcap": cfgMcap,\n            "mult": (cfgMult.isFinite && cfgMult > 0) ? cfgMult : 1.0,\n        ]')
    rep('av_onweb', P, '    func onWeb(_ t: Double?) {\n        if let t = t { selT = t - tzOff } else { selT = nil }\n    }', '    func onWeb(_ t: Double?) {\n        if let t = t, t < 0 { loadMore(); return } // 网页向左滚到头 → 补历史\n        if let t = t { selT = t - tzOff } else { selT = nil }\n    }')
    rep('av_coord', P, '            else if type == "clear" { onWeb(nil) }\n', '            else if type == "clear" { onWeb(nil) }\n            else if type == "more" { onWeb(-1) }\n')
    rep('av_state', P, '    @StateObject private var cvm = KLineVM()\n    @Environment(\\.colorScheme) private var scheme\n', '    @StateObject private var cvm = KLineVM()\n    @Environment(\\.colorScheme) private var scheme\n    @AppStorage("kMain", store: Cfg.defaults) private var mainSet = "MA,SUPER"\n    @AppStorage("kSub", store: Cfg.defaults) private var subInd = "MACD"\n    @AppStorage("kMcap", store: Cfg.defaults) private var mcap = false\n')
    rep('av_task', P, '            cvm.dark = (scheme == .dark)\n            cvm.sync(trades: vm.trades, createdMs: vm.main?.pairCreatedAt)\n', '            cvm.dark = (scheme == .dark)\n            applyCfg()\n            cvm.sync(trades: vm.trades, createdMs: vm.main?.pairCreatedAt)\n')
    rep('av_loop', P, '                await cvm.refreshLatest()\n', '                applyCfg()\n                await cvm.refreshLatest()\n')
    cut('av_block', P, '    @ViewBuilder\n    private var chartBlock: some View {', '// MARK: - 单根 K 线的切片计算', CHART_BLOCK)
