# 2026-11-22 市值口径（链上供应量，和 Ave 一致）、删长篇灰字说明、设置首页去副标题、钱包持仓图标化 + 垃圾币过滤、通知深链、二轮补抓图标
import re, pathlib, subprocess, sys


def register(rep, cut):
    root = pathlib.Path(__file__).resolve().parents[2]
    app = root / 'ios' / 'App'

    # 1) 市值 = min(marketCap, fdv)：marketCap 大于 fdv 说明 marketCap 是全网口径（如 IRYS 在 BSC 上只有约 6400 万条链上供应），按链上供应算
    pat = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*(?:\??\.[A-Za-z_][A-Za-z0-9_]*)*)(\??)\.marketCap \?\? \1\2\.fdv\b')
    n_cap = 0
    for f in sorted(app.glob('*.swift')):
        t = f.read_text(encoding='utf-8')
        new, k = pat.subn(lambda m: 'GMPx.minCap(' + m.group(1) + m.group(2) + '.marketCap, ' + m.group(1) + m.group(2) + '.fdv)', t)
        if k:
            f.write_text(new, encoding='utf-8')
            n_cap += k
    print('CAP_REWRITE', n_cap)

    # 2) 删掉长篇灰字说明（只删「不是某个代码块唯一一句」的，避免删空函数体）
    rx = re.compile(r'^\s*Text\("[^"\\]{18,}"\)\.font\(\.caption2?\)\.foregroundStyle\(\.secondary\)\s*$')
    n_txt = 0
    for f in sorted(app.glob('*.swift')):
        lines = f.read_text(encoding='utf-8').split('\n')
        out = []
        k = 0
        for i, ln in enumerate(lines):
            if rx.match(ln):
                prev = lines[i - 1].strip() if i > 0 else ''
                nxt = lines[i + 1].strip() if i + 1 < len(lines) else ''
                if prev.endswith('{') and nxt.startswith('}'):
                    out.append(ln)
                    continue
                k += 1
                continue
            out.append(ln)
        if k:
            f.write_text('\n'.join(out), encoding='utf-8')
            n_txt += k
    print('TEXT_SWEEP', n_txt)

    # 3) 通知：启动时装上通知代理 + 后台刷新；tstzm://token 深链
    A = 'ios/App/TSTZMApp.swift'
    rep('p32-boot', A,
        'init() { TZ.apply(); SourceHub.install(); GateNet.install() }',
        'init() { TZ.apply(); SourceHub.install(); GateNet.install(); GXNote.boot() }')
    rep('p32-deeplink', A,
        'if url.host == "setup" {',
        'if url.host == "token", let a = items.first(where: { $0.name == "address" })?.value, !a.isEmpty {\n'
        '            let ch = items.first(where: { $0.name == "chain" })?.value\n'
        '            Task { @MainActor in GXOpen.token(chain: ch, address: a) }\n'
        '            return\n'
        '        }\n'
        '        if url.host == "setup" {')
    rep('p32-fav-info', 'ios/App/Favorites.swift',
        'c.body = text',
        'c.body = text\n'
        '        c.userInfo = ["chain": it.chain, "address": it.address]\n'
        '        c.threadIdentifier = "tstzm"')

    # 4) 设置首页：去掉副标题、提醒页换成三通道开关、加「自动找币」入口
    S = 'ios/App/GXSettings.swift'
    rep('p32-set-sub', S,
        'Text(sub).font(.caption).foregroundStyle(.secondary)',
        'EmptyView()')
    rep('p32-set-alerts', S,
        'NavigationLink { GXPageAlerts() } label: { row("bell.badge", "提醒", "本地通知 · Telegram · Bark · 提醒规则") }',
        'NavigationLink { GXPageAlerts2() } label: { row("bell.badge", "提醒", "") }\n'
        '                    NavigationLink { GXScoutSettingsView() } label: { row("dot.radiowaves.left.and.right", "自动找币", "") }')

    # 5) 钱包持仓：代币图标 + 链角标，去掉「数量」字样，过滤空投垃圾币
    W = 'ios/App/WalletsView.swift'
    rep('p32-w-spam', W,
        'let hs = (result?.resp?.merged?.holdings ?? []).filter { $0.spamLikely != true }.sorted',
        'let hs = (result?.resp?.merged?.holdings ?? []).filter { $0.spamLikely != true && !GXSpam.looks($0) }.sorted')
    rep('p32-w-icon', W,
        'Text(h.symbol ?? "?").font(.subheadline.weight(.semibold))',
        'GXHoldIcon(h: h)\n'
        '                                Text(h.symbol ?? "?").font(.subheadline.weight(.semibold))')
    rep('p32-w-pill', W,
        'Pill(text: Chain(rawValue: h.chain ?? "")?.title ?? (h.chain ?? ""), color: Color.blue)',
        'EmptyView()')
    rep('p32-w-qty', W,
        'Text("数量 " + Fmt2.qty(h.amount)).font(.caption).foregroundStyle(.secondary)',
        'Text(Fmt2.qty(h.amount)).font(.caption).foregroundStyle(.secondary)')

    # 6) 二轮补抓图标（第一轮没抓到的）
    if sys.platform == 'darwin':
        try:
            r = subprocess.run(['bash', 'ios/tools/fetch_logos2.sh'], cwd=str(root), capture_output=True, text=True, timeout=600)
            print('LOGOS2:')
            print(r.stdout[-3000:])
        except Exception as e:
            print('LOGOS2_ERROR', e)
