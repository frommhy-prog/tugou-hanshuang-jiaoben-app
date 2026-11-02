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


T = 'ios/App/UnifiedToken.swift'
rep(T, '            chartCard\n', '            KLineCard(vm: vm)\n')
rep(T, '            AIResultCard(title: "AI 研判", result: vm.ai, loading: vm.aiLoading, message: vm.aiMsg, onRun: vm.reAI)\n', '')
rep(T, '            NarrativeCard(chain: vm.chain, address: vm.address, main: vm.main)\n', '')
rep(T, '            securityCard\n            linksCard\n', '            securityCard\n            linksCard\n            AIFoldCard(vm: vm)\n')

M = 'ios/App/UnifiedTokenModel.swift'
rep(M, '        await runAI(id, fresh: false)\n', '        if AIMode.auto { await runAI(id, fresh: false) } // 设置里可改为手动\n')

N = 'ios/App/Narrative.swift'
rep(N, '.task(id: chain.rawValue + address) { await vm.load(chain: chain, address: address, main: main) }', '.task(id: chain.rawValue + address) { if AIMode.auto { await vm.load(chain: chain, address: address, main: main) } }')
rep(N, '                    Text("读取公开资料并归纳…").font(.footnote).foregroundStyle(.secondary)\n                }\n', '                    Text("读取公开资料并归纳…").font(.footnote).foregroundStyle(.secondary)\n                } else if !AIMode.auto {\n                    Button { Task { await vm.load(chain: chain, address: address, main: main) } } label: { Label("生成叙事与同类对比（手动）", systemImage: "sparkles") }.buttonStyle(.bordered)\n                }\n')

rep('ios/App/WalletsView.swift', '        if w != nil { await runAI(address) }\n', '        if w != nil && AIMode.auto { await runAI(address) }\n')
rep('ios/App/EvmWallet.swift', '        if w != nil { await runAI(address) }\n', '        if w != nil && AIMode.auto { await runAI(address) }\n')

if ok:
    for p, s in files.items():
        pathlib.Path(p).write_text(s, encoding='utf-8')
    log.append('APPLIED')
else:
    log.append('NOT APPLIED')

pathlib.Path('ios/ci').mkdir(parents=True, exist_ok=True)
pathlib.Path('ios/ci/patch-result.txt').write_text('\n'.join(log) + '\n', encoding='utf-8')
