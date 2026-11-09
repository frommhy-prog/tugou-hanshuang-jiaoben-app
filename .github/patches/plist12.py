# 补丁清单（第十二批）：交易所风格的代币页——头部 + K 线同屏，下面用标签页分组（总览 / 成交 / 筹码 / 风险 / 叙事 / 更多），一次只看一块；标题栏常驻价格
def register(rep, cut):
    U = 'ios/App/UnifiedToken.swift'
    rep('tab_state', U,
        '    @State private var showDash = false\n',
        '''    @State private var showDash = false
    @AppStorage("tokTab", store: Cfg.defaults) private var tokTab = 0

    private var navTitle: String {
        guard let m = vm.main else { return "代币" }
        let s: String = m.baseToken?.symbol ?? vm.symbol
        let p: String = m.price.map { Money.price($0) } ?? ""
        return s + " " + p
    }

    private var tabNames: [String] { ["总览", "成交", "筹码", "风险", "叙事", "更多"] }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabNames.indices, id: \\.self) { i in
                    Button { tokTab = i } label: {
                        Text(tabNames[i])
                            .font(.subheadline.weight(tokTab == i ? .bold : .regular))
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(tokTab == i ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: Capsule())
                            .foregroundStyle(tokTab == i ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var tabBody: some View {
        switch tokTab {
        case 0:
            VerdictCard(vm: vm)
            AIResultCard(title: "AI 研判（与规则并行）", result: vm.ai, loading: vm.aiLoading, message: vm.aiMsg, onRun: vm.reAI)
            LifecycleCard(vm: vm)
        case 1:
            flowCard
            poolsCard
        case 2:
            HoldersIntelButton(vm: vm)
            holdersCard
        case 3:
            ReportCard(vm: vm)
            securityCard
        case 4:
            NarrativeRulesCard(vm: vm)
            SocialCard(vm: vm)
            AIFoldCard(vm: vm)
        default:
            PromoCard(vm: vm)
        }
    }
''')
    rep('tab_g1', U,
        '            TerminalHeader(vm: vm)\n            FreshnessRow(vm: vm)\n            VerdictCard(vm: vm)\n            KLineCard(vm: vm)\n            NarrativeRulesCard(vm: vm)\n            ReportCard(vm: vm)\n            LifecycleCard(vm: vm)\n            SocialCard(vm: vm)\n            PromoCard(vm: vm)\n',
        '            CompactHeader(vm: vm)\n            KLineCard(vm: vm)\n            FreshnessRow(vm: vm)\n            tabBar\n')
    rep('tab_g2', U,
        '            flowCard\n            poolsCard\n            holdersCard\n            securityCard\n            AIFoldCard(vm: vm)\n',
        '            tabBody\n')
    rep('tab_nav', U,
        '            .navigationTitle("代币")\n',
        '            .navigationTitle(navTitle)\n            .navigationBarTitleDisplayMode(.inline)\n')

    R = 'ios/App/ReportCard.swift'
    rep('rc_noai', R,
        '            AIResultCard(title: "AI 研判（与规则并行）", result: vm.ai, loading: vm.aiLoading, message: vm.aiMsg, onRun: vm.reAI)\n',
        '')
