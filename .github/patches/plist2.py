# 补丁清单（第二批）：修编译器「表达式过复杂」
def register(rep, cut):
    A = 'ios/App/AnalysisEngine.swift'
    rep('ae_score', A,
        '            let wsum = dims.reduce(0.0) { $0 + $1.weight }\n            let s = dims.reduce(0.0) { $0 + Double($1.score) * $1.weight } / wsum\n',
        '            var wsum = 0.0\n            var wtot = 0.0\n            for d in dims {\n                wsum += d.weight\n                wtot += Double(d.score) * d.weight\n            }\n            let s: Double = wtot / wsum\n')
    rep('ae_wash', A,
        '            let wash = ad.filter { $0.nb >= 3 && $0.ns >= 3 && abs($0.buy - $0.sell) / max(1, $0.buy + $0.sell) < 0.15 }\n            if !wash.isEmpty { b.add("warn", 10, String(wash.count) + " 个地址买卖各 ≥3 笔且买卖额接近，可能是套利机器人，也可能是对敲刷量（链上无法区分）", "买卖额差额 < 15%") }\n',
        '            var washN = 0\n            for x in ad where x.nb >= 3 && x.ns >= 3 {\n                let tot: Double = max(1.0, x.buy + x.sell)\n                let diff: Double = abs(x.buy - x.sell)\n                if diff / tot < 0.15 { washN += 1 }\n            }\n            if washN > 0 { b.add("warn", 10, String(washN) + " 个地址买卖各 ≥3 笔且买卖额接近，可能是套利机器人，也可能是对敲刷量（链上无法区分）", "买卖额差额 < 15%") }\n')
    rep('ae_social', A,
        '                b.add("ok", 0, "已登记官方链接：" + (names.isEmpty ? "" : names + "，") + (webs.isEmpty ? "无官网" : "有官网"), "Dexscreener 代币资料（只说明登记了链接，不代表真实可信）")\n',
        '                let namesPart: String = names.isEmpty ? "" : names + "，"\n                let webPart: String = webs.isEmpty ? "无官网" : "有官网"\n                b.add("ok", 0, "已登记官方链接：" + namesPart + webPart, "Dexscreener 代币资料（只说明登记了链接，不代表真实可信）")\n')
