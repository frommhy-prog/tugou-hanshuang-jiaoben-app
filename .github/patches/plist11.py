# 补丁清单（第十一批）：综合研判的结果类型和已有的 Verdict 重名，改名 TokenVerdict
def register(rep, cut):
    V = 'ios/App/Verdict.swift'
    rep('vd_type', V, 'struct Verdict {\n    var score: Int?', 'struct TokenVerdict {\n    var score: Int?')
    rep('vd_fn', V, '    static func build(_ vm: UTokenVM) -> Verdict {\n', '    static func build(_ vm: UTokenVM) -> TokenVerdict {\n')
    rep('vd_ret1', V, 'return Verdict(score: nil,', 'return TokenVerdict(score: nil,')
    rep('vd_ret2', V, '        return Verdict(score: score, grade: g.0', '        return TokenVerdict(score: score, grade: g.0')
