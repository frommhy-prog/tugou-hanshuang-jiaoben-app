# 2026-11-20：紧凑数据条里没数据的格子不占位；分享快照里去掉没用的变量
def register(rep, cut):
    rep('g28_chip_hide', 'ios/App/GXBadges.swift', r'''        if compact {
            HStack(spacing: 2) {''', r'''        if compact && v.text == "—" {
            EmptyView()
        } else if compact {
            HStack(spacing: 2) {''')
    rep('g28_share_df1', 'ios/App/GXShare.swift', r'''        let df = ISO8601DateFormatter()
''', '')
    rep('g28_share_df2', 'ios/App/GXShare.swift', r'''        _ = df
''', '')
