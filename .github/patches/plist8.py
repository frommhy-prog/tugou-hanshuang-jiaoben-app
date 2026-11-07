# 补丁清单（第八批）：垃圾币过滤补到「叙事分析」卡片（第七批里这个文件的锚点不唯一，重写）
def register(rep, cut):
    E = 'ios/App/NarrativeEngine.swift'
    rep('ne_spam2', E,
        '        let a: String = p.baseToken?.address ?? ""\n        if a.isEmpty { return nil }\n',
        '        let a: String = p.baseToken?.address ?? ""\n        if a.isEmpty { return nil }\n        if (b.symbol ?? "").count > 14 || (b.name ?? "").count > 48 { return nil }\n')
    rep('ne_row2', E,
        'Text(s.sym).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)',
        'Text(s.sym).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)')
