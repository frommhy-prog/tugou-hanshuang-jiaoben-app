# 补丁清单（第十八批）：Intel 的静态方法读取 UTokenVM（MainActor），整个 enum 标成 MainActor
def register(rep, cut):
    rep('h18_intel_mainactor', 'ios/App/FlowIntel.swift', 'enum Intel {', '@MainActor\nenum Intel {')
