# 2026-11-17：交易记录 / 钱包分析第二代（GMLab2.swift）接线
def register(rep, cut):
    L = 'ios/App/GMLab.swift'
    U = 'ios/App/UnifiedToken.swift'

    rep('g23_l1', L, r'''struct GLTrade {''', r'''struct GLTrade: Codable {''')
    rep('g23_l2', L, r'''@Published var rep = GLReport()''', r'''@Published var rep = GLReport()
    @Published var rep2 = GL2Report()''')
    rep('g23_l3', L, r'''func rebuild(_ vm: UTokenVM) {''', r'''func clearArchive(_ vm: UTokenVM) {
        let k: String = vm.chain.rawValue + ":" + vm.address.lowercased() + ":" + (vm.main?.pairAddress ?? "")
        GLArchive.clear(k)
        trades = []
        rep = GLReport()
        rep2 = GL2Report()
        key = ""
        Task { await load(vm, force: true) }
    }

    func rebuild(_ vm: UTokenVM) {''')
    rep('g23_l4', L, r'''rep = GLCalc.build(trades, curPx: vm.main?.price, holders: hd)''', r'''rep = GLCalc.build(trades, curPx: vm.main?.price, holders: hd)
        var hl: [GL2Holder] = []
        for h in vm.holders where h.kind == "wallet" {
            if let p = h.pct { hl.append(GL2Holder(addr: h.owner, pct: p, rank: h.rank)) }
        }
        if hl.isEmpty {
            var i: Int = 0
            for w in GMFreeStore.shared.wallets where !w.isContract {
                i += 1
                hl.append(GL2Holder(addr: w.addr, pct: w.pct, rank: i))
            }
        }
        rep2 = GL2Calc.build(trades, curPx: vm.main?.price, holders: hl)''')
    rep('g23_l5', L, r'''key = k''', r'''key = k
        if trades.isEmpty {
            let pre: [GLTrade] = GLArchive.load(k).sorted { $0.t > $1.t }
            rep2 = GL2Report()
            if !pre.isEmpty {
                trades = pre
                rebuild(vm)
            }
        }''')
    rep('g23_l6', L, r'''trades = out.sorted { $0.t > $1.t }''', r'''trades = GLArchive.merge(k, out)''')

    rep('g23_u1', U, r'''GMTradeLabView(vm: vm)''', r'''GMTradeLab2View(vm: vm)''')
    rep('g23_u2', U, r'''GMWalletLabView(vm: vm)''', r'''GMWalletLab2View(vm: vm)''')
