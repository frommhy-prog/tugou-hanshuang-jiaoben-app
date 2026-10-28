import SwiftUI
import UIKit

extension Color {
    static let card = Color(UIColor.secondarySystemGroupedBackground)
    static let page = Color(UIColor.systemGroupedBackground)
    static let navy = Color(red: 0, green: 28.0 / 255.0, blue: 68.0 / 255.0)
    static let gold = Color(red: 226.0 / 255.0, green: 183.0 / 255.0, blue: 91.0 / 255.0)
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct Pill: View {
    let text: String
    var color: Color = Color.secondary
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var tint: Color = Color.primary
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

struct ErrorCard: View {
    let text: String
    var retry: (() -> Void)? = nil
    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
                VStack(alignment: .leading, spacing: 8) {
                    Text(text).font(.subheadline)
                    if let retry = retry {
                        Button("重试", action: retry).font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle().fill(Color.navy)
            Circle().strokeBorder(Color.gold, lineWidth: size * 0.04)
            Text("TSTZ-M")
                .font(.system(size: size * 0.24, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
    }
}

enum Verdict {
    static func color(_ s: String?) -> Color {
        let t = (s ?? "").lowercased()
        if t.contains("红") || t.contains("red") { return Color.red }
        if t.contains("黄") || t.contains("yellow") { return Color.orange }
        if t.contains("绿") || t.contains("green") { return Color.green }
        return Color.gray
    }
    static func label(_ s: String?) -> String {
        let t = (s ?? "").lowercased()
        if t.contains("红") || t.contains("red") { return "高风险" }
        if t.contains("黄") || t.contains("yellow") { return "需谨慎" }
        if t.contains("绿") || t.contains("green") { return "较安全" }
        return "未知"
    }
}

enum RiskState {
    case good, warn, bad, unknown
    var color: Color {
        switch self {
        case .good: return Color.green
        case .warn: return Color.orange
        case .bad: return Color.red
        case .unknown: return Color.gray
        }
    }
    var icon: String {
        switch self {
        case .good: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.circle.fill"
        case .bad: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

struct RiskRow: View {
    let label: String
    let text: String
    let state: RiskState
    var body: some View {
        HStack {
            Image(systemName: state.icon).foregroundStyle(state.color)
            Text(label).font(.subheadline)
            Spacer()
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(state.color)
        }
    }
}

func mmss(_ sec: Int) -> String {
    let s = max(0, sec)
    if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
    return String(format: "%02d:%02d", s / 60, s % 60)
}

func pctText(_ v: Double?) -> String {
    guard let v = v else { return "未知" }
    return String(format: "%.1f%%", v)
}

// 分享图：渲染成图片后走系统分享面板（微信、微博、X、Telegram、WhatsApp 等装了就有）
struct ShareCard: View {
    let symbol: String
    let chain: String
    let price: String
    let change: Double?
    let liq: String
    let holders: Int?
    let verdict: String?
    let score: Double?
    let headline: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TSTZ-M 体检").font(.headline).foregroundStyle(Color.white)
                    Text(chain).font(.caption).foregroundStyle(Color.white.opacity(0.6))
                }
                Spacer()
                if let v = verdict { Pill(text: Verdict.label(v), color: Verdict.color(v)) }
            }
            Text(symbol).font(.system(size: 34, weight: .heavy, design: .rounded)).foregroundStyle(Color.white)
            HStack(alignment: .firstTextBaseline) {
                Text(price).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Color.gold)
                if let c = change {
                    Text(String(format: "%+.2f%%", c)).font(.subheadline.weight(.semibold))
                        .foregroundStyle(c >= 0 ? Color.green : Color.red)
                }
            }
            HStack(spacing: 18) {
                VStack(alignment: .leading) { Text("流动性").font(.caption).foregroundStyle(Color.white.opacity(0.6)); Text(liq).font(.headline).foregroundStyle(Color.white) }
                VStack(alignment: .leading) { Text("持仓人数").font(.caption).foregroundStyle(Color.white.opacity(0.6)); Text(holders.map { "\($0)" } ?? "未知").font(.headline).foregroundStyle(Color.white) }
                if let s = score {
                    VStack(alignment: .leading) { Text("安全分").font(.caption).foregroundStyle(Color.white.opacity(0.6)); Text(String(format: "%.0f", s)).font(.headline).foregroundStyle(Color.white) }
                }
            }
            if let h = headline, !h.isEmpty {
                Text(h).font(.subheadline).foregroundStyle(Color.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            }
            Text("数据仅供参考，不构成投资建议 · TSTZ-M").font(.caption2).foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(22)
        .frame(width: 360, alignment: .leading)
        .background(Color.navy)
    }
}
