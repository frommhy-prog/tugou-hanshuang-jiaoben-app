# 2026-11-20 钱包分析：加资金榜（净买入 / 净卖出，老仓卖家也算）、成本覆盖率；分页标签加图标；去掉多余说明
def register(rep, cut):
    L = 'ios/App/GMLab2.swift'
    rep('p30-w-presellamt', L,
        "    var preSellUsd: Double = 0\n",
        "    var preSellUsd: Double = 0\n"
        "    var preSellAmt: Double = 0\n")
    rep('p30-w-presellamt2', L,
        "if rem > 0 { w.preSellUsd += rem * t.px }\n",
        "if rem > 0 {\n"
        "                        w.preSellUsd += rem * t.px\n"
        "                        w.preSellAmt += rem\n"
        "                    }\n")
    rep('p30-w-fields', L,
        "    var losers: [GL2Wallet] = []\n",
        "    var losers: [GL2Wallet] = []\n"
        "    var netBuyers: [GL2Wallet] = []\n"
        "    var netSellers: [GL2Wallet] = []\n"
        "    var covered: Double = 0\n")
    rep('p30-w-calc', L,
        "        out.losers = Array(list.filter { $0.pnl < 0 && $0.roi != nil }.sorted { $0.pnl < $1.pnl }.prefix(5))\n",
        "        out.losers = Array(list.filter { $0.pnl < 0 && $0.roi != nil }.sorted { $0.pnl < $1.pnl }.prefix(5))\n"
        "        func flowNet(_ w: GL2Wallet) -> Double { return w.buyUsd - w.sellUsd }\n"
        "        let buyers: [GL2Wallet] = list.filter { flowNet($0) > 0 }.sorted { flowNet($0) > flowNet($1) }\n"
        "        let sellers: [GL2Wallet] = list.filter { flowNet($0) < 0 }.sorted { flowNet($0) < flowNet($1) }\n"
        "        out.netBuyers = Array(buyers.prefix(5))\n"
        "        out.netSellers = Array(sellers.prefix(5))\n"
        "        var grossAll: Double = 0\n"
        "        var grossMatched: Double = 0\n"
        "        for w in list {\n"
        "            grossAll += w.gross\n"
        "            if w.roi != nil { grossMatched += w.gross }\n"
        "        }\n"
        "        out.covered = grossAll > 0 ? grossMatched / grossAll * 100 : 0\n")
    # 界面
    rep('p30-w-note', L,
        "个活跃地址。盈亏按 FIFO 把窗口内的买入和卖出配对；窗口之前的仓位没有成本，只标记为老仓。点 ☆ 可关注钱包，点地址跳转 GMGN / 浏览器。\")",
        "个地址 · 成本能配对的成交额占 \" + String(format: \"%.0f%%\", r.covered) + \"，其余是窗口前的老仓，盈亏记不到\")")
    rep('p30-w-flowrow', L,
        "private func moveRow(_ m: GL2Move) -> some View {\n",
        "private func flowRow(_ w: GL2Wallet) -> some View {\n"
        "        let net: Double = w.buyUsd - w.sellUsd\n"
        "        return HStack(spacing: 8) {\n"
        "            GXWalletLabel(chain: vm.chain, addr: w.addr)\n"
        "            if w.status == \"老仓卖出\" { Image(systemName: \"clock.arrow.circlepath\").font(.caption2).foregroundStyle(Color.orange) }\n"
        "            Spacer()\n"
        "            Text(GMPx.fiat(net, signed: true)).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(net >= 0 ? Color.green : Color.red)\n"
        "        }\n"
        "    }\n"
        "\n"
        "    private func moveRow(_ m: GL2Move) -> some View {\n")
    rep('p30-w-flowcard', L,
        "if !r.winners.isEmpty || !r.losers.isEmpty {\n",
        "if !r.netBuyers.isEmpty || !r.netSellers.isEmpty {\n"
        "                Card {\n"
        "                    VStack(alignment: .leading, spacing: 8) {\n"
        "                        if !r.netBuyers.isEmpty {\n"
        "                            Label(\"净买入\", systemImage: \"arrow.down.circle.fill\").font(.subheadline.weight(.semibold)).foregroundStyle(Color.green)\n"
        "                            ForEach(r.netBuyers) { flowRow($0) }\n"
        "                        }\n"
        "                        if !r.netSellers.isEmpty {\n"
        "                            if !r.netBuyers.isEmpty { Divider() }\n"
        "                            Label(\"净卖出\", systemImage: \"arrow.up.circle.fill\").font(.subheadline.weight(.semibold)).foregroundStyle(Color.red)\n"
        "                            ForEach(r.netSellers) { flowRow($0) }\n"
        "                        }\n"
        "                    }\n"
        "                }\n"
        "            }\n"
        "            if !r.winners.isEmpty || !r.losers.isEmpty {\n")
    rep('p30-w-win', L,
        "Text(\"赚得最多\").font(.subheadline.weight(.semibold))",
        "Label(\"赚得最多\", systemImage: \"trophy.fill\").font(.subheadline.weight(.semibold)).foregroundStyle(Color.green)")
    rep('p30-w-lose', L,
        "Text(\"亏得最多\").font(.subheadline.weight(.semibold))",
        "Label(\"亏得最多\", systemImage: \"arrow.down.right.circle.fill\").font(.subheadline.weight(.semibold)).foregroundStyle(Color.red)")

    # 分页标签：图标 + 标题；设置里去掉重复说明
    T = 'ios/App/GMTabs.swift'
    rep('p30-tab-icon', T,
        "                                            Text(t.title)\n"
        "                                                .font(.subheadline.weight(cur == t.id ? .bold : .regular))\n"
        "                                                .foregroundStyle(cur == t.id ? Color.primary : Color.secondary)\n",
        "                                            HStack(spacing: 4) {\n"
        "                                                Image(systemName: t.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(cur == t.id ? t.color : Color.secondary)\n"
        "                                                Text(t.title)\n"
        "                                                    .font(.subheadline.weight(cur == t.id ? .bold : .regular))\n"
        "                                                    .foregroundStyle(cur == t.id ? Color.primary : Color.secondary)\n"
        "                                            }\n")
    rep('p30-tab-note', T,
        "Text(\"K 线下面这一排就是分析分页：交易记录、钱包分析、持有者、流动性、综合研判、合约安全、叙事社交、庄家情报、更多工具。\").font(.caption).foregroundStyle(.secondary)\n",
        "")
