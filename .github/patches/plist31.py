# 2026-11-20 内外盘 / 发射台：Pons 链上识别（两代工厂 + graduationStatus），数据条显示发射台 logo；Logo 抓取多路兜底
def register(rep, cut):
    A = 'ios/App/GXAve.swift'
    cut('p31-pons-chain', A,
        "// MARK: - Pons（Robinhood Chain 发射台）识别：代币合约的创建者是 Pons 发币工厂合约\n",
        "// MARK: - 菜单里的品牌小图标（链接名 → 图标）",
        "// MARK: - Pons（Robinhood Chain 发射台）识别：直接问 Pons 官方文档公布的两代工厂合约，同时读出是否已毕业（内盘 / 外盘）\n"
        "final class GXPonsStore: @unchecked Sendable {\n"
        "    static let shared = GXPonsStore()\n"
        "    private let lock = NSLock()\n"
        "    private var set: Set<String> = []\n"
        "    private var grad: [String: Bool] = [:]\n"
        "\n"
        "    func has(_ a: String) -> Bool {\n"
        "        lock.lock()\n"
        "        defer { lock.unlock() }\n"
        "        return set.contains(a.lowercased())\n"
        "    }\n"
        "\n"
        "    func graduated(_ a: String) -> Bool? {\n"
        "        lock.lock()\n"
        "        defer { lock.unlock() }\n"
        "        return grad[a.lowercased()]\n"
        "    }\n"
        "\n"
        "    func add(_ a: String, graduated: Bool?) {\n"
        "        lock.lock()\n"
        "        set.insert(a.lowercased())\n"
        "        if let g = graduated { grad[a.lowercased()] = g }\n"
        "        lock.unlock()\n"
        "    }\n"
        "}\n"
        "\n"
        "@MainActor\n"
        "final class GXPons: ObservableObject {\n"
        "    static let shared = GXPons()\n"
        "    @Published var n: Int = 0\n"
        "    private var running: Set<String> = []\n"
        "    private var done: Set<String> = []\n"
        "    private var tries: [String: Int] = [:]\n"
        "\n"
        "    // 官方文档：现行工厂 + 旧工厂（Robinhood Chain，chainId 4663）\n"
        "    static let factories: [String] = [\"0xA5aAb3F0c6EeadF30Ef1D3Eb997108E976351feB\", \"0x0c37a24F5D23A486FA692d1500881d698B1F77a4\"]\n"
        "    static let rpc: String = \"https://rpc.mainnet.chain.robinhood.com\"\n"
        "\n"
        "    private func ethCall(_ to: String, _ data: String) async -> String? {\n"
        "        guard let u = URL(string: GXPons.rpc) else { return nil }\n"
        "        var req = URLRequest(url: u, timeoutInterval: 12)\n"
        "        req.httpMethod = \"POST\"\n"
        "        req.setValue(\"application/json\", forHTTPHeaderField: \"Content-Type\")\n"
        "        let call: [String: Any] = [\"to\": to, \"data\": data]\n"
        "        let body: [String: Any] = [\"jsonrpc\": \"2.0\", \"id\": 1, \"method\": \"eth_call\", \"params\": [call, \"latest\"]]\n"
        "        req.httpBody = try? JSONSerialization.data(withJSONObject: body)\n"
        "        guard let r = try? await URLSession.shared.data(for: req),\n"
        "              let o = (try? JSONSerialization.jsonObject(with: r.0)) as? [String: Any],\n"
        "              let res = o[\"result\"] as? String else { return nil }\n"
        "        return res\n"
        "    }\n"
        "\n"
        "    // 返回值第 i 个 32 字节字是否非零\n"
        "    private func word(_ hex: String, _ i: Int) -> Bool? {\n"
        "        let chars: [Character] = Array(hex)\n"
        "        if chars.count < (i + 1) * 64 { return nil }\n"
        "        return chars[(i * 64)..<((i + 1) * 64)].contains(where: { $0 != \"0\" })\n"
        "    }\n"
        "\n"
        "    func check(chain: Chain, address: String) async {\n"
        "        guard chain == .robinhood, address.count == 42 else { return }\n"
        "        let a: String = address.lowercased()\n"
        "        if done.contains(a) || running.contains(a) { return }\n"
        "        running.insert(a)\n"
        "        defer { running.remove(a) }\n"
        "        let arg: String = String(repeating: \"0\", count: 24) + String(a.dropFirst(2))\n"
        "        for f in GXPons.factories {\n"
        "            // getLaunchedToken(address)：第 12 个字 exists = 是这个工厂发的币\n"
        "            guard let res = await ethCall(f, \"0x3cf28b5a\" + arg) else { continue }\n"
        "            if word(String(res.dropFirst(2)), 11) != true { continue }\n"
        "            var g: Bool? = nil\n"
        "            // graduationStatus(address)：第 3 个字 graduated = 已毕业（外盘）\n"
        "            if let r2 = await ethCall(f, \"0x98d652f1\" + arg) { g = word(String(r2.dropFirst(2)), 2) }\n"
        "            GXPonsStore.shared.add(a, graduated: g)\n"
        "            done.insert(a)\n"
        "            n += 1\n"
        "            return\n"
        "        }\n"
        "        let t: Int = (tries[a] ?? 0) + 1\n"
        "        tries[a] = t\n"
        "        if t >= 3 { done.insert(a) }\n"
        "    }\n"
        "}\n"
        "\n")

    # 内盘 / 外盘：Pons 以链上毕业状态为准；数据条上的内外盘格子带发射台 logo
    K = 'ios/App/GMMetrics.swift'
    rep('p31-kind-sig', K,
        "    static func text(dex: String?, pad: GMLaunchpad?) -> String? {\n"
        "        let d: String = (dex ?? \"\").lowercased()\n",
        "    static func text(dex: String?, pad: GMLaunchpad?, addr: String? = nil) -> String? {\n"
        "        if pad == .pons, let a = addr, let g = GXPonsStore.shared.graduated(a) { return g ? \"外盘\" : \"内盘\" }\n"
        "        let d: String = (dex ?? \"\").lowercased()\n")
    rep('p31-val-pad', K,
        "    var icon: String? = nil\n"
        "    var rows: [(String, String)] = []\n"
        "}\n",
        "    var icon: String? = nil\n"
        "    var rows: [(String, String)] = []\n"
        "    var pad: GMLaunchpad? = nil\n"
        "}\n")
    rep('p31-curve-a', K,
        "guard let t = GMMarketKind.text(dex: d, pad: pad) else {",
        "guard let t = GMMarketKind.text(dex: d, pad: pad, addr: vm.address) else {")
    rep('p31-curve-b', K,
        "rows: [(\"当前交易所\", d ?? \"未知\"), (\"发射台\", pad?.title ?? \"未识别\")])",
        "rows: [(\"当前交易所\", d ?? \"未知\"), (\"发射台\", pad?.title ?? \"未识别\")], pad: pad)")
    rep('p31-strip-obs', K,
        "    @ObservedObject private var gxi = GXInfoStore.shared\n",
        "    @ObservedObject private var gxi = GXInfoStore.shared\n"
        "    @ObservedObject private var gxp = GXPons.shared\n")
    rep('p31-chip-pad', 'ios/App/GXBadges.swift',
        "                } else if GXAveGlyph.has(id) {\n"
        "                    GXAveIcon(id: id, color: v.color, size: 13)\n",
        "                } else if let p = v.pad {\n"
        "                    GMLaunchLogo(pad: p, size: 15)\n"
        "                } else if GXAveGlyph.has(id) {\n"
        "                    GXAveIcon(id: id, color: v.color, size: 13)\n")

    # Logo 抓取：favicon 取不到时多路兜底；新增 Pons；清晰度上限 256
    S = 'ios/tools/fetch_logos.sh'
    rep('p31-fetch-cands', S,
        "  for u in \"$@\"; do\n"
        "    rm -f \"$t\"\n",
        "  local cands=() x d\n"
        "  for x in \"$@\"; do\n"
        "    cands+=(\"$x\")\n"
        "    case \"$x\" in\n"
        "      *faviconV2*)\n"
        "        d=$(echo \"$x\" | sed -E 's#.*url=https://([^&]+)&.*#\\1#')\n"
        "        cands+=(\"https://$d/apple-touch-icon.png\" \"https://$d/apple-touch-icon-precomposed.png\" \"https://$d/favicon.png\" \"https://$d/favicon.ico\" \"https://www.google.com/s2/favicons?domain=$d&sz=128\" \"https://icons.duckduckgo.com/ip3/$d.ico\")\n"
        "        ;;\n"
        "    esac\n"
        "  done\n"
        "  for u in \"${cands[@]}\"; do\n"
        "    rm -f \"$t\"\n")
    rep('p31-fetch-pons', S,
        "run gml_zora      \"$(gfav zora.co)\"\n",
        "run gml_zora      \"$(gfav zora.co)\"\n"
        "run gml_pons      \"https://pons.family/apple-touch-icon.png\" \"$(gfav pons.family)\"\n")
    rep('p31-fetch-hd', S,
        "if [ \"$w\" -gt 192 ]; then sips -Z 192 \"$OUT/$name.png\" >/dev/null 2>&1; fi",
        "if [ \"$w\" -gt 256 ]; then sips -Z 256 \"$OUT/$name.png\" >/dev/null 2>&1; fi")
