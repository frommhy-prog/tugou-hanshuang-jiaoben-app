# 2026-11-19：GMScout.swift 里几处长字符串拼接让编译器类型检查超时，拆成独立函数
def register(rep, cut):
    SC = 'ios/App/GMScout.swift'
    rep('g27_sc_status', SC, r'''Text("上次扫描 " + TZ.format(Date(timeIntervalSince1970: r.at)) + "，用掉 " + String(r.calls) + " 次请求").font(.caption2).foregroundStyle(.secondary)''',
        r'''Text(scanLine(r)).font(.caption2).foregroundStyle(.secondary)''')
    rep('g27_sc_heat', SC, r'''Text("24h 成交 " + GMPx.fiat(c.vol24) + " · " + String(c.txns) + " 笔 · " + String(c.pools) + " 个热门池").font(.caption2).foregroundStyle(.secondary)''',
        r'''Text(heatLine(c)).font(.caption2).foregroundStyle(.secondary)''')
    rep('g27_sc_token', SC, r'''Text(chain.title + " · 流动性 " + GMPx.fiat(t.liq) + " · 24h 成交 " + GMPx.fiat(t.vol24)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)''',
        r'''Text(tokenLine(chain, t)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)''')
    rep('g27_sc_summary', SC, r'''        return "最热的链 " + top + " · 可靠代币 " + String(r.tokens.count) + " 个 · 聪明钱 " + String(r.wallets.count) + " 个 · " + TZ.format(Date(timeIntervalSince1970: r.at))''',
        r'''        let nT: String = String(r.tokens.count)
        let nW: String = String(r.wallets.count)
        let tm: String = TZ.format(Date(timeIntervalSince1970: r.at))
        return ["最热的链 ", top, " · 可靠代币 ", nT, " 个 · 聪明钱 ", nW, " 个 · ", tm].joined()''')
    rep('g27_sc_helpers', SC, r'''    private var statusCard: some View {''', r'''    private func scanLine(_ r: GMScoutReport) -> String {
        let t: String = TZ.format(Date(timeIntervalSince1970: r.at))
        let n: String = String(r.calls)
        return ["上次扫描 ", t, "，用掉 ", n, " 次请求"].joined()
    }

    private func heatLine(_ c: GMScoutChain) -> String {
        let v: String = GMPx.fiat(c.vol24)
        let a: String = String(c.txns)
        let b: String = String(c.pools)
        return ["24h 成交 ", v, " · ", a, " 笔 · ", b, " 个热门池"].joined()
    }

    private func tokenLine(_ chain: Chain, _ t: GMScoutToken) -> String {
        let l: String = GMPx.fiat(t.liq)
        let v: String = GMPx.fiat(t.vol24)
        return [chain.title, " · 流动性 ", l, " · 24h 成交 ", v].joined()
    }

    private var statusCard: some View {''')
