# 2026-11-20 图标统一（Ave 同款）+ Pons 发射台 + 去掉头部 App 跳转排 + 菜单品牌图标
def register(rep, cut):
    H = 'ios/App/GMHeader.swift'
    # 头部合约行：App 跳转图标排只属于钱包地址菜单，这里去掉（又丑又占地方）
    rep('p29-hdr-apps', H,
        "                GXAppIcons(chain: vm.chain, addr: vm.address, pair: m.pairAddress, size: 22)\n",
        "")
    # ⋯ 菜单：外链全部带品牌图标，复制合约地址带图标
    rep('p29-hdr-menu', H,
        "                ForEach(ls.indices, id: \\.self) { i in\n"
        "                    Link(ls[i].0, destination: ls[i].1)\n"
        "                }\n"
        "                Button(\"复制合约地址\") { UIPasteboard.general.string = vm.address }\n",
        "                ForEach(ls.indices, id: \\.self) { i in\n"
        "                    Link(destination: ls[i].1) {\n"
        "                        Label { Text(ls[i].0) } icon: { GXIcons.menuImage(ls[i].0) }\n"
        "                    }\n"
        "                }\n"
        "                Button { UIPasteboard.general.string = vm.address } label: { Label(\"复制合约地址\", systemImage: \"doc.on.doc\") }\n")
    # Pons 识别结果出来后刷新头部
    rep('p29-hdr-pons-state', H,
        "    @State private var showTokenSheet = false\n",
        "    @State private var showTokenSheet = false\n"
        "    @ObservedObject private var pons = GXPons.shared\n")
    rep('p29-hdr-pons-task', H,
        "        .task(id: nKey) { await GXInfoStore.shared.load(vm: vm) }\n",
        "        .task(id: nKey) { await GXInfoStore.shared.load(vm: vm) }\n"
        "        .task(id: nKey) { await GXPons.shared.check(chain: vm.chain, address: vm.address) }\n")

    # Pons 发射台
    M = 'ios/App/GMMarks.swift'
    rep('p29-pad-case', M,
        "jupStudio, daos, zora\n",
        "jupStudio, daos, zora, pons\n")
    rep('p29-pad-title', M,
        "        case .zora: return \"Zora\"\n",
        "        case .zora: return \"Zora\"\n"
        "        case .pons: return \"Pons\"\n")
    rep('p29-pad-detect1', M,
        "        if d.contains(\"zora\") { return .zora }\n",
        "        if d.contains(\"zora\") { return .zora }\n"
        "        if d.contains(\"pons\") { return .pons }\n")
    rep('p29-pad-detect2', M,
        "        if chain == .base && a.hasSuffix(\"b07\") { return .clanker }\n",
        "        if chain == .base && a.hasSuffix(\"b07\") { return .clanker }\n"
        "        if chain == .robinhood && GXPonsStore.shared.has(a) { return .pons }\n")
    L = 'ios/App/GMLogos.swift'
    rep('p29-pad-key', L,
        "        case .zora: return \"zora\"\n",
        "        case .zora: return \"zora\"\n"
        "        case .pons: return \"pons\"\n")
    rep('p29-pad-embed', L,
        "let i = UIImage(contentsOfFile: p) else { return nil }\n",
        "let i = UIImage(contentsOfFile: p) else { return GXEmbedded.image(name) }\n")
    rep('p29-pad-inner', 'ios/App/GMMetrics.swift',
        "\"heaven\", \"daosfun\"]",
        "\"heaven\", \"daosfun\", \"pons\"]")

    # 顶部数据条：Ave 同款图标 + 中性底色；去掉「调」字
    B = 'ios/App/GXBadges.swift'
    rep('p29-chip-icon', B,
        "                } else if let em = GMTagIcon.metric(id) {\n"
        "                    Text(em).font(.system(size: 11))\n",
        "                } else if GXAveGlyph.has(id) {\n"
        "                    GXAveIcon(id: id, color: v.color, size: 13)\n"
        "                } else if let em = GMTagIcon.metric(id) {\n"
        "                    Text(em).font(.system(size: 11))\n")
    rep('p29-chip-icon2', B,
        "                } else if let em = GMTagIcon.metric(id) {\n"
        "                    Text(em).font(.system(size: 10))\n",
        "                } else if GXAveGlyph.has(id) {\n"
        "                    GXAveIcon(id: id, color: v.color, size: 12)\n"
        "                } else if let em = GMTagIcon.metric(id) {\n"
        "                    Text(em).font(.system(size: 10))\n")
    rep('p29-chip-bg', B,
        "            .background(v.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))\n",
        "            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))\n")
    rep('p29-narr-icon', B,
        "                Text(\"叙事\")\n"
        "                    .font(.system(size: 10, weight: .heavy))\n"
        "                    .padding(.horizontal, 5)\n"
        "                    .padding(.vertical, 1)\n"
        "                    .background(Color.purple.opacity(0.18), in: Capsule())\n"
        "                    .foregroundStyle(Color.purple)\n",
        "                Image(systemName: \"text.quote\")\n"
        "                    .font(.system(size: 11, weight: .bold))\n"
        "                    .foregroundStyle(Color.purple)\n"
        "                    .padding(.top, 2)\n")
    rep('p29-adjust-btn', 'ios/App/GMMetrics.swift',
        "                        Image(systemName: \"slider.horizontal.3\").font(.footnote)\n"
        "                        Text(\"调\").font(.caption2)\n",
        "                        Image(systemName: \"slider.horizontal.3\").font(.footnote)\n")
