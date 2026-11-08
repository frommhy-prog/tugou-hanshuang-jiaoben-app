# 补丁清单（第十批）：综合研判接入代币页；生命周期结果带上数值；叙事/生命周期加载完成后通知综合研判重算
def register(rep, cut):
    L = 'ios/App/LifeSocial.swift'
    rep('ls_lifereport_fields', L,
        'struct LifeReport {\n    var phases: [LifePhase]\n    var stage: String\n    var stageBasis: String\n    var n: Int\n    var tfTitle: String\n}\n',
        'struct LifeReport {\n    var phases: [LifePhase]\n    var stage: String\n    var stageBasis: String\n    var n: Int\n    var tfTitle: String\n    var dd: Double = 0\n    var ratio: Double = 0\n    var mult: Double = 1\n    var athAgoH: Double = 0\n}\n')
    rep('ls_lifereport_return', L,
        '        return LifeReport(phases: phases, stage: stage, stageBasis: sb, n: cs.count, tfTitle: tf.title)\n',
        '        return LifeReport(phases: phases, stage: stage, stageBasis: sb, n: cs.count, tfTitle: tf.title, dd: dd, ratio: ratio, mult: mult, athAgoH: (last.t - ath.t) / 3600)\n')
    rep('ls_life_notify', L,
        '                Self.store[key] = (r, Date())\n',
        '                Self.store[key] = (r, Date())\n                vm.objectWillChange.send()\n')

    N = 'ios/App/NarrativeEngine.swift'
    rep('ne_notify', N,
        '        Self.store[key] = r\n        report = r\n        loading = false\n',
        '        Self.store[key] = r\n        report = r\n        loading = false\n        vm.objectWillChange.send()\n')

    U = 'ios/App/UnifiedToken.swift'
    rep('tok_verdict', U,
        '            TerminalHeader(vm: vm)\n            FreshnessRow(vm: vm)\n',
        '            TerminalHeader(vm: vm)\n            FreshnessRow(vm: vm)\n            VerdictCard(vm: vm)\n')
