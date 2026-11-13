# 补丁清单（第十六批）：Xcode 直装与 SideStore 安装合并为同一个应用 + 看板里显示安装信息
def register(rep, cut):
    # Xcode 调试版（免费账号拿不到 App Group）直接用本机偏好；CI / SideStore 的发布版继续用 App Group
    K = 'ios/Shared/Core.swift'
    rep('h16_defaults', K, r'''    static let defaults: UserDefaults = UserDefaults(suiteName: Cfg.group) ?? UserDefaults.standard
''', r'''    #if DEBUG
    static let defaults: UserDefaults = UserDefaults.standard
    #else
    static let defaults: UserDefaults = UserDefaults(suiteName: Cfg.group) ?? UserDefaults.standard
    #endif
''')

    # 盯盘看板底部加「安装信息」
    B = 'ios/App/MarketBoard.swift'
    rep('h16_install_card', B, r'''                    diagLink
''', r'''                    InstallInfoCard()
                    diagLink
''')
