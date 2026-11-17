# 2026-11-17：限流网关接线、中文万/亿单位、品牌 / 社交 / 钱包 / 标签图标、发射台内外盘标识
import re

# String(format: "%.2fM", x / 1_000_000) 之类 -> CNUnit.wrap("前缀", x, 2, "后缀")（金额、数量统一显示万 / 亿）
CN_PAT = re.compile(r'String\(format:\s*"([^"%\\\n]*)%\.(\d)f([KMB])([^"%\\\n]*)",\s*([^\n]+?)\s*/\s*(?:1_000_000_000|1_000_000|1_000|1e9|1e6|1e3|1000000000|1000000|1000)(?:\.0)?\)')
SCAN = re.compile(r'%\.\d?f\s?[KMB]\b|"[KMB]"|[0-9)]\s?[KMB]"')


def _cn_sub(m):
    return 'CNUnit.wrap("%s", %s, %s, "%s")' % (m.group(1), m.group(5), m.group(2), m.group(4))


def register(rep, cut):
    g = rep.__globals__
    ROOT = g['ROOT']
    files = g['files']
    bad = g['bad']
    done = g['done']
    total = 0
    touched = []
    scan = []
    for base in ('ios/App', 'ios/Shared'):
        for path in sorted((ROOT / base).rglob('*.swift')):
            p = path.relative_to(ROOT).as_posix()
            if p in bad:
                continue
            t = files[p] if p in files else path.read_text(encoding='utf-8')
            new, n = CN_PAT.subn(_cn_sub, t)
            if n:
                files[p] = new
                done.setdefault(p, []).append('g24_cn_' + path.stem)
                total += n
                touched.append('%s:%d' % (p, n))
                t = new
            for i, line in enumerate(t.split('\n'), 1):
                if SCAN.search(line):
                    scan.append('%s:%d: %s' % (p, i, line.strip()[:150]))
    print('CN_REWRITE', total, ' '.join(touched))
    print('FMT_SCAN_LEFT', len(scan))
    for s in scan[:80]:
        print('  ' + s)

    # 启动时安装全局限流网关
    rep('g24_a1', 'ios/App/TSTZMApp.swift', r'''init() { TZ.apply(); SourceHub.install() }''', r'''init() { TZ.apply(); SourceHub.install(); GateNet.install() }''')

    # 数据条：每项加图标（Dex 付费用 Dexscreener 真 logo，老鼠仓 / 聪明钱 / 狙击者 / Dev 等用系统表情）
    M = 'ios/App/GMMetrics.swift'
    rep('g24_m1', M, r'''Text(title).underline(true, pattern: .dot, color: Color.secondary).font(.system(size: 9.5)).foregroundStyle(Color.secondary)''', r'''if id == "dexpaid" { GMBrandIcon(key: "dexscreener", size: 12) } else if let em = GMTagIcon.metric(id) { Text(em).font(.system(size: 10)) }
                Text(title).underline(true, pattern: .dot, color: Color.secondary).font(.system(size: 9.5)).foregroundStyle(Color.secondary)''')
    rep('g24_m2', M, r'''if let ic = v.icon { Image(systemName: ic).font(.caption2).foregroundStyle(v.color) }''', r'''if let ic = v.icon, id != "dexpaid" { Image(systemName: ic).font(.caption2).foregroundStyle(v.color) }''')
    rep('g24_m3', M, r'''if let ic = v.icon { Image(systemName: ic).font(.title).foregroundStyle(v.color) }''', r'''if id == "dexpaid" { GMBrandIcon(key: "dexscreener", size: 30) } else if let ic = v.icon { Image(systemName: ic).font(.title).foregroundStyle(v.color) }''')
    rep('g24_m4', M, r'''Text(w.name ?? Addr.short(w.addr)).font(.caption.monospaced()).foregroundStyle(Color.primary)''', r'''HStack(spacing: 4) {
                    if let bk = GMBrand.match(w.name ?? "") { GMBrandIcon(key: bk, size: 14) }
                    Text(w.name ?? Addr.short(w.addr)).font(.caption.monospaced()).foregroundStyle(Color.primary)
                }''')
    rep('g24_m5', M, r'''Text(w.tags.prefix(3).joined(separator: " · ")).font(.caption2).foregroundStyle(Color.orange).lineLimit(1)''', r'''Text(w.tags.prefix(3).map { GMTagIcon.text($0) }.joined(separator: " · ")).font(.caption2).foregroundStyle(Color.orange).lineLimit(1)''')
    rep('g24_m6', M, r'''"bonkfun", "believe", "flap", "virtuals"]''', r'''"bonkfun", "believe", "flap", "virtuals", "boop", "heaven", "daosfun"]''')

    # 头部：社交 / 外链用真实图标；发射台标签 = 图标 + 名称 + 内盘/外盘
    H = 'ios/App/GMHeader.swift'
    rep('g24_h1', H, r'''// MARK: 合约 + 社交 + 外部行情''', r'''@ViewBuilder
    private func socialIcon(_ name: String) -> some View {
        if let k = GMBrand.socialKey(name) {
            GMBrandIcon(key: k, size: 22)
        } else {
            chipText(name, Color.accentColor)
        }
    }

    private func extIcon(_ name: String) -> some View {
        HStack(spacing: 4) {
            if let k = GMBrand.externalKey(name) { GMBrandIcon(key: k, size: 14) }
            Text(name + " ↗").font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.14), in: Capsule())
        .foregroundStyle(Color.secondary)
    }

    // MARK: 合约 + 社交 + 外部行情''')
    rep('g24_h2', H, r'''Link(destination: ss[i].1) { chipText(ss[i].0, Color.accentColor) }''', r'''Link(destination: ss[i].1) { socialIcon(ss[i].0) }''')
    rep('g24_h3', H, r'''Link(destination: ex[i].1) { chipText(ex[i].0 + " ↗", Color.secondary) }''', r'''Link(destination: ex[i].1) { extIcon(ex[i].0) }''')
    rep('g24_h4', H, r'''if let p = pad { Text(p.title).font(.caption2.weight(.semibold)).foregroundStyle(Color.orange).lineLimit(1).fixedSize().layoutPriority(1) }''', r'''if let p = pad { GMLaunchChip(pad: p, stage: mk).fixedSize().layoutPriority(1) }''')
    rep('g24_h5', H, r'''if let t = mk { chipText(t, t == "内盘" ? Color.orange : Color.green).fixedSize().layoutPriority(1) }''', r'''if pad == nil, let t = mk { chipText(t, t == "内盘" ? Color.orange : Color.green).fixedSize().layoutPriority(1) }''')

    # 发射台：新增 Believe / Boop / Heaven / LaunchLab / Jupiter Studio / DAOS.FUN / Zora；头像徽标外圈按内外盘着色；DEX 图标过滤占位图
    K = 'ios/App/GMMarks.swift'
    rep('g24_k1', K, r'''case pump, bonk, fourMeme, flap, moonshot, clanker, virtuals, bags''', r'''case pump, bonk, fourMeme, flap, moonshot, clanker, virtuals, bags, believe, boop, heaven, launchLab, jupStudio, daos, zora''')
    rep('g24_k2', K, r'''case .bags: return "Bags"''', r'''case .bags: return "Bags"
        case .believe: return "Believe"
        case .boop: return "Boop"
        case .heaven: return "Heaven"
        case .launchLab: return "LaunchLab"
        case .jupStudio: return "Jupiter Studio"
        case .daos: return "DAOS.FUN"
        case .zora: return "Zora"''')
    rep('g24_k3', K, r'''if d.contains("bonk") { return .bonk }''', r'''if d.contains("believe") { return .believe }
        if d.contains("boop") { return .boop }
        if d.contains("heaven") { return .heaven }
        if d.contains("launchlab") { return .launchLab }
        if d.contains("daos") { return .daos }
        if d.contains("zora") { return .zora }
        if d.contains("bonk") { return .bonk }''')
    rep('g24_k4', K, r'''disc(Color(red: 0.2, green: 0.85, blue: 0.4), Color(red: 0.05, green: 0.55, blue: 0.25), "B", Color.white)''', r'''disc(Color(red: 0.2, green: 0.85, blue: 0.4), Color(red: 0.05, green: 0.55, blue: 0.25), "B", Color.white)
        default:
            disc(Color(red: 0.35, green: 0.35, blue: 0.4), Color(red: 0.12, green: 0.12, blue: 0.16), String(pad.title.prefix(1)).uppercased(), Color.white)''')
    rep('g24_k5', K, r'''.overlay(Circle().stroke(Color.card, lineWidth: 1.5))''', r'''.overlay(Circle().stroke(GMMarketKind.ring(dex: dex, pad: p), lineWidth: 1.8))''')
    rep('g24_k6', K, r'''.task(id: dex) { img = await GMDexIcons.load(dex) }''', r'''.task(id: dex) { img = await GMDexIcons2.load(dex) }''')
