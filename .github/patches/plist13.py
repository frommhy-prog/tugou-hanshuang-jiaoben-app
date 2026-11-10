# 补丁清单（第十三批）：彻底移除寒霜（标签页、深链、路由字段）；代币头部并进 K 线卡片（合二为一）
def register(rep, cut):
    A = 'ios/App/TSTZMApp.swift'
    rep('frost_tab_rm', A, '            FrostView()\n                .tabItem { Label("寒霜", systemImage: "snowflake") }\n                .tag(2)\n', '')
    rep('frost_deeplink_rm', A,
        '        } else if url.host == "frost" {\n            let code = items.first(where: { $0.name == "code" })?.value\n            DispatchQueue.main.async {\n                AppRouter.shared.tab = 2\n                AppRouter.shared.pendingCode = code\n            }\n        }\n',
        '        }\n')
    rep('frost_router_rm', A, '    @Published var pendingCode: String?\n', '')

    U = 'ios/App/UnifiedToken.swift'
    rep('merge_header_a', U, '            CompactHeader(vm: vm)\n            KLineCard(vm: vm)\n', '            KLineCard(vm: vm)\n')

    P = 'ios/App/ProChart.swift'
    rep('merge_header_b', P,
        '                HStack {\n                    Label("K 线", systemImage: "chart.xyaxis.line").font(.headline)\n                    Spacer()\n                    Text(cvm.statusText).font(.caption2).foregroundStyle(.secondary)\n                }\n                periodBar\n',
        '                CompactHeader(vm: vm, embedded: true)\n                Divider()\n                periodBar\n                Text(cvm.statusText).font(.caption2).foregroundStyle(.secondary)\n')

    H = 'ios/App/CompactHeader.swift'
    rep('merge_header_c1', H, '    @State private var expanded = false\n', '    var embedded: Bool = false\n    @State private var expanded = false\n')
    rep('merge_header_c2', H,
        '    @ViewBuilder\n    private func content(_ m: DexPair) -> some View {\n',
        '    @ViewBuilder\n    private func wrap<C: View>(@ViewBuilder _ c: () -> C) -> some View {\n        if embedded { c() } else { Card { c() } }\n    }\n\n    @ViewBuilder\n    private func content(_ m: DexPair) -> some View {\n')
    rep('merge_header_c3', H, '        let ls = links(m) + externals(m)\n        Card {\n', '        let ls = links(m) + externals(m)\n        wrap {\n')
