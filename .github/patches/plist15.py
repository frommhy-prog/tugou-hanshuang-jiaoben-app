# 补丁清单（第十五批）：深度分析卡片接入代币页三个标签、钱包页、选中 K 线的交易分析
def register(rep, cut):
    U = 'ios/App/UnifiedToken.swift'
    rep('h15_tab0', U, r'''            VerdictCard(vm: vm)
''', r'''            VerdictCard(vm: vm)
            TokenDeepCard(vm: vm)
''')
    rep('h15_tab1', U, r'''        case 1:
            flowCard
''', r'''        case 1:
            TradeDeepCard(vm: vm)
            flowCard
''')
    rep('h15_tab2', U, r'''            HoldersIntelButton(vm: vm)
''', r'''            HoldersIntelButton(vm: vm)
            HolderDeepCard(vm: vm)
''')

    V = 'ios/App/WalletsView.swift'
    rep('h15_wv_hold', V, r'''                if seg == 0 { holdingsSection }
''', r'''                if seg == 0 {
                    HoldingsDeepCard(result: result)
                    holdingsSection
                }
''')
    rep('h15_wv_intel', V, r'''                VStack(spacing: 14) {
                    if let s = w.stats {
''', r'''                VStack(spacing: 14) {
                    WalletIntelInline(address: wallet.address)
                    if let s = w.stats {
''')

    C = 'ios/App/ProChart.swift'
    rep('h15_slice', C, r'''                        if let b = big { Text("最大一笔：" + (b.buy ? "买入 " : "卖出 ") + Fmt2.usd(b.usd) + " · " + Addr.short(b.who)).font(.footnote) }
''', r'''                        if let b = big { Text("最大一笔：" + (b.buy ? "买入 " : "卖出 ") + Fmt2.usd(b.usd) + " · " + Addr.short(b.who)).font(.footnote) }
                        Text(KDeep.sliceExtra(s.inWin)).font(.footnote)
''')
