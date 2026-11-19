import SwiftUI
import UIKit

// MARK: - 钱包标签（聪明钱 / 开发者 / 狙击 / 机器人 / 新钱包 / 交易所 …）：所有出现钱包地址的地方共用
struct GXTag: Identifiable {
    let id: String
    let emoji: String
    let text: String
    let color: Color
    var brand: String? = nil
}

@MainActor
enum GXWalletTags {
    static func intelTags(_ r: IntelReport) -> [GXTag] {
        var out: [GXTag] = []
        func add(_ e: String, _ t: String, _ c: Color) { out.append(GXTag(id: t, emoji: e, text: t, color: c)) }
        for l in r.labels {
            switch l.name {
            case "机器人": add("🤖", "机器人", Color.orange)
            case "狙击手 / 极短线": add("🎯", "狙击手", Color.red)
            case "高频短线": add("⚡", "高频短线", Color.orange)
            case "巨鲸": add("🐋", "巨鲸", Color.blue)
            case "大户": add("🐳", "大户", Color.blue)
            case "新钱包": add("🌱", "新钱包", Color.green)
            case "休眠": add("😴", "休眠", Color.gray)
            case "聪明钱（样本内）": add("🧠", "聪明钱", Color.green)
            case "净输家": add("📉", "净输家", Color.red)
            case "靠单笔暴利": add("🍀", "靠单笔暴利", Color.orange)
            case "疑似做市 / 路由 / 中转账户": add("🔀", "做市/路由", Color.gray)
            default: break
            }
        }
        return out
    }

    static func tags(chain: Chain, addr: String, vm: UTokenVM) -> [GXTag] {
        let low: String = addr.lowercased()
        var out: [GXTag] = []
        func push(_ t: GXTag) {
            if !out.contains(where: { $0.text == t.text }) { out.append(t) }
        }
        for w in GMGNStore.shared.wallets() where w.addr.lowercased() == low {
            for t in w.tags {
                let s: String = GMTagIcon.text(t)
                let ps: [Substring] = s.split(separator: " ", maxSplits: 1)
                if ps.count == 2 { push(GXTag(id: String(ps[1]), emoji: String(ps[0]), text: String(ps[1]), color: Color.orange)) }
            }
            if let n = w.name, let bk = GMBrand.match(n) { push(GXTag(id: n, emoji: "🏷", text: n, color: Color.blue, brand: bk)) }
        }
        for w in GMFreeStore.shared.wallets where w.addr.lowercased() == low {
            if let tg = w.tag, !tg.isEmpty { push(GXTag(id: tg, emoji: "🏷", text: tg, color: Color.blue, brand: GMBrand.match(tg))) }
            if w.isContract { push(GXTag(id: "合约", emoji: "📜", text: "合约/池子", color: Color.gray)) }
        }
        if let h = vm.holders.first(where: { $0.owner.lowercased() == low }), h.rank <= 10 {
            let rk: String = "持有榜#" + String(h.rank)
            push(GXTag(id: rk, emoji: "🏦", text: rk, color: Color.purple))
        }
        let an: UHolderAnalysis? = vm.analyses[addr] ?? vm.analyses[low]
        if let dm = an?.position?.delayMin {
            if dm <= 1 { push(GXTag(id: "狙击", emoji: "🎯", text: "狙击(1分钟内入场)", color: Color.red)) }
            else if dm <= 10 { push(GXTag(id: "早鸟", emoji: "⚡", text: "早鸟(10分钟内入场)", color: Color.orange)) }
        }
        if let r = GXHoldersStore.shared.reports[addr] {
            for t in intelTags(r) { push(t) }
        }
        for w in GMLabStore.shared.rep2.wallets where w.addr.lowercased() == low {
            if w.isBot { push(GXTag(id: "bot", emoji: "🤖", text: "机器人/MEV", color: Color.orange)) }
            else if w.tags.contains("追高买入") { push(GXTag(id: "chase", emoji: "🚀", text: "追高买入", color: Color.red)) }
        }
        let watch: String = Cfg.defaults.string(forKey: "gmWatchList") ?? ""
        if watch.lowercased().contains(low) { push(GXTag(id: "watch", emoji: "⭐", text: "已关注", color: Color.yellow)) }
        return Array(out.prefix(6))
    }
}

// MARK: - 钱包行里的小标签：头像 + 标签图标 + 地址；点开钱包卡片，长按是跳转菜单
struct GXWalletLabel: View {
    let chain: Chain
    let addr: String
    @State private var open = false

    var body: some View {
        let tags: [GXTag] = GXWalletTags.tags(chain: chain, addr: addr, vm: UTokenVM.shared)
        Button { open = true } label: {
            HStack(spacing: 4) {
                AvWalletIcon(address: addr, chain: nil, size: 18)
                ForEach(tags.prefix(3)) { t in
                    if let b = t.brand { GMBrandIcon(key: b, size: 12) } else { Text(t.emoji).font(.system(size: 11)) }
                }
                Text(Addr.short(addr)).font(.caption2.monospaced()).foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.plain)
        .contextMenu { GMWalletMenuContent(chain: chain, addr: addr) }
        .sheet(isPresented: $open) { GXWalletSheet(chain: chain, addr: addr) }
    }
}

// MARK: - 钱包卡片（点钱包头像弹出）
struct GXWalletSheet: View {
    let chain: Chain
    let addr: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var hs = GXHoldersStore.shared
    @State private var report: IntelReport?
    @State private var loading = false
    @State private var err: String?

    private func kv(_ k: String, _ v: String, _ c: Color = Color.primary) -> some View {
        HStack {
            Text(k).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(c)
        }
    }

    private func header(_ tags: [GXTag]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    AvWalletIcon(address: addr, chain: chain, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Addr.short(addr)).font(.title3.monospaced().bold())
                        Text(chain.title + " 钱包").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { UIPasteboard.general.string = addr } label: { Image(systemName: "doc.on.doc") }
                }
                if !tags.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(tags) { t in
                            HStack(spacing: 4) {
                                if let b = t.brand { GMBrandIcon(key: b, size: 13) } else { Text(t.emoji).font(.caption) }
                                Text(t.text).font(.caption.weight(.semibold)).lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(t.color.opacity(0.15), in: Capsule())
                            .foregroundStyle(t.color)
                        }
                    }
                } else {
                    Text("没有命中任何已知标签（聪明钱 / 开发者 / 钓鱼 / 捆绑 / 狙击 / 机器人 / 交易所）").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func context(_ vm: UTokenVM) -> some View {
        let low: String = addr.lowercased()
        let w: GL2Wallet? = GMLabStore.shared.rep2.wallets.first(where: { $0.addr.lowercased() == low })
        let h: UHolder? = vm.holders.first(where: { $0.owner.lowercased() == low })
        let p = (vm.analyses[addr] ?? vm.analyses[low])?.position
        if w != nil || h != nil || p != nil {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("在 " + vm.symbol + " 里的表现").font(.headline)
                    if let h = h { kv("持有排名", "#" + String(h.rank) + (h.pct.map { String(format: " · %.2f%%", $0) } ?? "")) }
                    if let w = w {
                        kv("买入", GMPx.fiat(w.buyUsd) + "·" + String(w.nb), Color.green)
                        kv("卖出", GMPx.fiat(w.sellUsd) + "·" + String(w.ns), Color.red)
                        kv("盈亏（FIFO 估算）", GMPx.fiat(w.pnl, signed: true), w.pnl >= 0 ? Color.green : Color.red)
                        kv("状态", w.status)
                    }
                    if let p = p {
                        if let d = p.delayMin { kv("入场时点", d < 0 ? "早于池子创建" : String(format: "池子创建后 %.1f 分钟", d)) }
                        if let r = p.roi { kv("综合回报", String(format: "%+.0f%%", r * 100), r >= 0 ? Color.green : Color.red) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var intelBlock: some View {
        if chain == .solana {
            if let r = report {
                IntelReportView(r: r)
            } else if loading {
                Card { HStack(spacing: 10) { ProgressView(); Text("读取这个钱包的链上交易并计算标签…").font(.subheadline) } }
            } else if let e = err {
                Card { Text("钱包情报读取失败：" + e).font(.footnote).foregroundStyle(Color.orange) }
            }
        } else {
            Card {
                Text("EVM 钱包的行为分析请用「钱包 → 查询任意地址」；这里已按本币成交和持有榜给出标签与表现。").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        let vm: UTokenVM = UTokenVM.shared
        let tags: [GXTag] = GXWalletTags.tags(chain: chain, addr: addr, vm: vm)
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header(tags)
                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("一键跳转").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            GXAppIcons(chain: chain, addr: addr, wallet: true, size: 30)
                        }
                    }
                    context(vm)
                    intelBlock
                    if let u = URL(string: "https://x.com/search?q=" + addr) {
                        Link(destination: u) {
                            Label("在 X 搜索这个地址的最新讨论", systemImage: "magnifyingglass").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(16)
            }
            .background(Color.page)
            .navigationTitle("钱包")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task {
            guard chain == .solana else { return }
            if let r = hs.reports[addr] { report = r; return }
            loading = true
            report = await hs.fetchOne(addr)
            err = hs.errors[addr]
            loading = false
        }
    }
}
