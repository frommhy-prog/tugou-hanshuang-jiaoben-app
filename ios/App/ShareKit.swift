import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// 分享图片：白底、标题、关键数据、要点，末尾按设置附开发者联系方式
struct ShareCardView: View {
    let title: String
    let subtitle: String
    let lines: [(String, String)]
    let bullets: [(String, Color)]
    let contact: ContactSettings?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title2.bold()).foregroundStyle(Color.black)
                    Text(subtitle).font(.footnote).foregroundStyle(Color.gray)
                }
                Spacer()
                Text("TSTZ-M").font(.caption.weight(.heavy)).foregroundStyle(Color.blue)
            }
            Divider()
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                HStack {
                    Text(l.0).font(.footnote).foregroundStyle(Color.gray)
                    Spacer()
                    Text(l.1).font(.footnote.weight(.semibold).monospacedDigit()).foregroundStyle(Color.black)
                }
            }
            if !bullets.isEmpty {
                Divider()
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, b in
                    HStack(alignment: .top, spacing: 6) {
                        Circle().fill(b.1).frame(width: 7, height: 7).padding(.top, 5)
                        Text(b.0).font(.footnote).foregroundStyle(Color.black).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let c = contact {
                Divider()
                ContactFooter(settings: c, compact: true)
            }
            Text("数据来自链上与公共行情接口，仅供参考，不构成投资建议 · " + TZ.format(Date()) + " " + TZ.label)
                .font(.system(size: 9)).foregroundStyle(Color.gray)
        }
        .padding(18)
        .frame(width: 380)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

enum ShareKit {
    @MainActor
    static func render(_ card: ShareCardView) -> UIImage? {
        let r = ImageRenderer(content: card)
        r.scale = 3
        return r.uiImage
    }

    static func color(_ level: String) -> Color {
        switch level {
        case "risk": return Color.red
        case "warn": return Color.orange
        case "ok": return Color.green
        default: return Color.gray
        }
    }

    // 分享文本里只放遮挡后的联系入口 + 一个跳转页链接
    static func contactText(_ s: ContactSettings) -> String {
        guard s.showInShare else { return "" }
        let who = s.entries.filter { !$0.value.isEmpty }.map { s.maskText ? $0.masked : $0.value }.joined(separator: " · ")
        let link = ContactStore.contactPageLink(s)
        return "\n\n" + s.headline + "\n" + who + (link.isEmpty ? "" : "\n点这里联系：" + link)
    }

    @MainActor
    static func tokenItems(_ vm: UTokenVM) -> [Any] {
        let s = ContactStore.settings
        let m = vm.main
        let order: [String: Int] = ["risk": 0, "warn": 1, "info": 2, "ok": 3]
        let top = vm.insights.sorted { (order[$0.level] ?? 9) < (order[$1.level] ?? 9) }.prefix(6)
        var lines: [(String, String)] = []
        lines.append(("现价", Money.price(m?.price)))
        if let c = m?.priceChange?["h24"] { lines.append(("24 小时涨跌", String(format: "%+.1f%%", c))) }
        lines.append(("流动性", Money.format(m?.liquidity?.usd)))
        lines.append(("市值 / FDV", Money.format(m?.marketCap ?? m?.fdv)))
        lines.append(("24h 成交额", Money.format(m?.volume?["h24"])))
        if let t10 = vm.conc?.wallets10 { lines.append(("前 10 大普通钱包", String(format: "%.1f%%", t10))) }
        let bullets: [(String, Color)] = top.map { ($0.text, color($0.level)) }
        let card = ShareCardView(title: vm.symbol + " · " + vm.chain.title, subtitle: Addr.short(vm.address), lines: lines, bullets: bullets, contact: s.showInShare ? s : nil)
        var items: [Any] = []
        if let img = render(card) { items.append(img) }
        var text = vm.symbol + "（" + vm.chain.title + "）代币分析\n现价 " + Money.price(m?.price)
        text += "\n" + top.map { "• " + $0.text }.joined(separator: "\n")
        text += "\n地址：" + vm.address
        text += contactText(s)
        items.append(text)
        return items
    }

    @MainActor
    static func generalItems(title: String, subtitle: String, lines: [(String, String)], bullets: [(String, Color)], plain: String) -> [Any] {
        let s = ContactStore.settings
        let card = ShareCardView(title: title, subtitle: subtitle, lines: lines, bullets: bullets, contact: s.showInShare ? s : nil)
        var items: [Any] = []
        if let img = render(card) { items.append(img) }
        items.append(plain + contactText(s))
        return items
    }
}
