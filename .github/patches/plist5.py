# 补丁清单（第五批）：把生命周期与社交卡片放进代币页
def register(rep, cut):
    U = 'ios/App/UnifiedToken.swift'
    rep('tok_life_social', U, '            ReportCard(vm: vm)\n', '            ReportCard(vm: vm)\n            LifecycleCard(vm: vm)\n            SocialCard(vm: vm)\n')
