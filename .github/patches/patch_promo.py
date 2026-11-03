import pathlib

files = {}
log = []
ok = True


def load(p):
    if p not in files:
        files[p] = pathlib.Path(p).read_text(encoding='utf-8')
    return files[p]


def rep(p, old, new):
    global ok
    s = load(p)
    n = s.count(old)
    if n != 1:
        ok = False
        log.append('FAIL %s count=%d: %r' % (p, n, old[:70]))
        return
    files[p] = s.replace(old, new)
    log.append('OK   %s: %r' % (p, old[:50]))


rep('ios/App/UnifiedToken.swift', '            KLineCard(vm: vm)\n            statsGrid\n            insightsCard\n', '            KLineCard(vm: vm)\n            statsGrid\n            insightsCard\n            PromoCard(vm: vm)\n')

S = 'ios/App/SettingsView.swift'
rep(S, '    @AppStorage("currency", store: Cfg.defaults) private var currency = "USD"\n', '    @AppStorage("currency", store: Cfg.defaults) private var currency = "USD"\n    @AppStorage("aiAuto", store: Cfg.defaults) private var aiAuto = true\n')
rep(S, '                Section("计价货币") {\n', '                Section("AI 触发方式") {\n                    Picker("触发方式", selection: $aiAuto) {\n                        Text("自动").tag(true)\n                        Text("手动").tag(false)\n                    }\n                    .pickerStyle(.segmented)\n                    Text("自动：查币、查钱包、停在 K 线上都自动请求 AI。手动：只在点按钮时请求，省 Groq 额度。").font(.caption).foregroundStyle(.secondary)\n                }\n                Section("计价货币") {\n')

if ok:
    for p, s in files.items():
        pathlib.Path(p).write_text(s, encoding='utf-8')
    log.append('APPLIED')
else:
    log.append('NOT APPLIED')

pathlib.Path('ios/ci').mkdir(parents=True, exist_ok=True)
pathlib.Path('ios/ci/patch-result.txt').write_text('\n'.join(log) + '\n', encoding='utf-8')
