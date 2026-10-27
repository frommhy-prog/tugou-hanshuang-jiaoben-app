import WidgetKit
import SwiftUI
#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

// v3：v2 被骂“纯黑板 + 数据，没有设计”是对的——v2 只剩底色和数字，
// v1 又是把壁纸原样抄进来，口号堆满。v3 走中间：用壁纸的视觉系统，重新排版，
// 而不是把壁纸当内容贴上去，也不是扔掉壁纸只剩黑板。
// 壁纸系统 = 黑颗粒底 + 细灰描边 + 灰白字阶 + 断角框 + 灰色胶囊 + 白色重音。
// v3 的用法：断角框只做边框（细、退后），MAKE MONEY 只出现一次、做顶部小字标，
// 搞钱只做图标焦点，不在小组件里反复喊；胶囊从壁纸的开仓/平仓钮借形，
// 改做链/币标签和风险等级，不做交易按钮（App 永远不交易）。
// 布局是原创的：小款是“标头 + 总价 + 分隔线 + 最重仓”；中款是“标头 + 总价 +
// 持仓胶囊行 + 占比条”；大款是“标头 + 总价 + 持仓列表 + 风险胶囊 + 脚注”。
// 两款都不自己联网，只读 App 写进 App Group 的快照；没快照就显示
// “未同步，去 App 里刷新”，不编总价、不编涨跌。刷新约 15 分钟一次，
// 是 WidgetKit 系统限制，不是秒级实时。

struct GaoQianEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot?
}

struct GaoQianProvider: TimelineProvider {
    func placeholder(in context: Context) -> GaoQianEntry {
        GaoQianEntry(date: Date(), snapshot: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (GaoQianEntry) -> Void) {
        completion(GaoQianEntry(date: Date(), snapshot: SharedStore.loadSnapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GaoQianEntry>) -> Void) {
        let entry = GaoQianEntry(date: Date(), snapshot: SharedStore.loadSnapshot())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
    }
}

// 金额换算：快照里永远存美元，显示时按 App 里选的计价货币换算。
// 汇率没拿到就回落美元，不编汇率、不把美元数直接贴上别的货币符号。
private func money(_ v: Double?) -> String {
    guard let v else { return "—" }
    return CurrencyFormatter.formatUsd(v)
}

// 断角框（壁纸的框，v3 只做边框，不做内容）：四个角，细线，退后，不抢数据。
struct BrokenCornerFrame: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, l: CGFloat = 20, inset: CGFloat = 6
            Path { p in
                p.move(to: CGPoint(x: inset, y: inset + l)); p.addLine(to: CGPoint(x: inset, y: inset)); p.addLine(to: CGPoint(x: inset + l, y: inset))
                p.move(to: CGPoint(x: w - inset - l, y: inset)); p.addLine(to: CGPoint(x: w - inset, y: inset)); p.addLine(to: CGPoint(x: w - inset, y: inset + l))
                p.move(to: CGPoint(x: inset, y: h - inset - l)); p.addLine(to: CGPoint(x: inset, y: h - inset)); p.addLine(to: CGPoint(x: inset + l, y: h - inset))
                p.move(to: CGPoint(x: w - inset - l, y: h - inset)); p.addLine(to: CGPoint(x: w - inset, y: h - inset)); p.addLine(to: CGPoint(x: w - inset, y: h - inset - l))
            }
            .stroke(Color.white.opacity(0.45), lineWidth: 1.2)
        }
    }
}

// 胶囊标签（壁纸开仓/平仓钮的形状，借形不借功能）：链、币、风险等级都用它，
// 不是交易按钮，点按只打开 App。
struct PillTag: View {
    var text: String
    var color: Color = Color(white: 0.65)
    var body: some View {
        Text(text).font(.caption2).bold().foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
    }
}

private func pct(_ v: Double?) -> String {
    guard let v else { return "—" }
    return String(format: "%@%.2f%%", v >= 0 ? "+" : "", v)
}

// 持仓占比条：长度就是该币占总价的比例，不是装饰，是数据本身。
struct ShareBar: View {
    var share: Double // 0...1
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color(white: 0.18))
                Rectangle().fill(Color.white).frame(width: max(2, geo.size.width * CGFloat(min(1, max(0, share)))))
            }
        }.frame(height: 4)
    }
}

// MARK: - 桌面款（system 家族：颗粒黑卡 + 断角边框 + 胶囊标签 + 灰白字阶）
struct HomeWidgetView: View {
    var entry: GaoQianEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        ZStack {
            WallpaperStyle.background
            BrokenCornerFrame()
            content
                .padding(family == .systemSmall ? 16 : 20)
        }
        .widgetBackground()
    }

    @ViewBuilder var content: some View {
        if let snap = entry.snapshot {
            let total = snap.totalUsd ?? 0
            switch family {
            case .systemSmall:
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("MAKE MONEY").font(.system(size: 8, weight: .light)).tracking(2).foregroundStyle(WallpaperStyle.grayText)
                        Spacer()
                        if let t = snap.topSymbol { PillTag(text: t) }
                    }
                    Text(money(snap.totalUsd)).font(.system(size: 26, weight: .heavy)).foregroundStyle(WallpaperStyle.whiteText)
                    Rectangle().fill(Color(white: 0.25)).frame(height: 1)
                    HStack {
                        Text("最重仓").font(.caption).foregroundStyle(WallpaperStyle.grayText)
                        Spacer()
                        Text("\(snap.topSymbol ?? "—") · \(pct(snap.topChangePct))").font(.caption).bold().foregroundStyle((snap.topChangePct ?? 0) >= 0 ? WallpaperStyle.up : WallpaperStyle.down)
                    }
                    if snap.isStale { Text("旧数据 · \(snap.ageText ?? "")").font(.caption2).foregroundStyle(WallpaperStyle.grayText) }
                }
            case .systemMedium:
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("MAKE MONEY").font(.system(size: 8, weight: .light)).tracking(2).foregroundStyle(WallpaperStyle.grayText)
                        Spacer()
                        Text("钱包 \(snap.walletCount ?? 0) 个").font(.caption).foregroundStyle(WallpaperStyle.grayText)
                    }
                    Text(money(snap.totalUsd)).font(.system(size: 30, weight: .heavy)).foregroundStyle(WallpaperStyle.whiteText)
                    if let hs = snap.holdings, !hs.isEmpty {
                        ForEach(hs.prefix(3).indices, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    PillTag(text: hs[i].symbol ?? "—")
                                    Spacer()
                                    Text(money(hs[i].usd)).font(.caption).foregroundStyle(WallpaperStyle.grayText)
                                    Text(pct(hs[i].changePct)).font(.caption).bold().foregroundStyle((hs[i].changePct ?? 0) >= 0 ? WallpaperStyle.up : WallpaperStyle.down)
                                }
                                ShareBar(share: total > 0 ? (hs[i].usd ?? 0) / total : 0)
                            }
                        }
                    }
                    HStack {
                        if let r = snap.risk { PillTag(text: r, color: r.contains("谨慎") || r.contains("高") ? Color.red : Color.green) }
                        Spacer()
                        Text(snap.isStale ? "旧数据 · \(snap.ageText ?? "")" : "同步于 \(snap.ageText ?? "")").font(.caption2).foregroundStyle(WallpaperStyle.grayText)
                    }
                }
            default: // systemLarge
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("MAKE MONEY").font(.system(size: 8, weight: .light)).tracking(2).foregroundStyle(WallpaperStyle.grayText)
                        Spacer()
                        PillTag(text: "只看不交易")
                    }
                    Text(money(snap.totalUsd)).font(.system(size: 34, weight: .heavy)).foregroundStyle(WallpaperStyle.whiteText)
                    if let t = snap.topSymbol, let sh = snap.topSharePct {
                        Text("最重仓 \(t) · 占 \(String(format: "%.1f%%", sh))").font(.caption).foregroundStyle(WallpaperStyle.grayText)
                    }
                    if let hs = snap.holdings, !hs.isEmpty {
                        ForEach(hs.prefix(5).indices, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    PillTag(text: hs[i].symbol ?? "—")
                                    Spacer()
                                    Text(money(hs[i].usd)).font(.subheadline).foregroundStyle(WallpaperStyle.grayText)
                                    Text(pct(hs[i].changePct)).font(.subheadline).bold().foregroundStyle((hs[i].changePct ?? 0) >= 0 ? WallpaperStyle.up : WallpaperStyle.down)
                                }
                                ShareBar(share: total > 0 ? (hs[i].usd ?? 0) / total : 0)
                            }
                        }
                    }
                    HStack {
                        if let r = snap.risk { PillTag(text: r, color: r.contains("谨慎") || r.contains("高") ? Color.red : Color.green) }
                        Spacer()
                        Text("点开 App 看 risks 与 unknowns 全文").font(.caption2).foregroundStyle(WallpaperStyle.grayText)
                    }
                    Text("币圈不大 · 创造神话").font(.caption2).foregroundStyle(WallpaperStyle.grayText)
                    Text(snap.isStale ? "旧数据 · \(snap.ageText ?? "")" : "同步于 \(snap.ageText ?? "")").font(.caption2).foregroundStyle(WallpaperStyle.grayText)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("MAKE MONEY").font(.system(size: 8, weight: .light)).tracking(2).foregroundStyle(WallpaperStyle.grayText)
                Text("未同步").font(.title2).bold().foregroundStyle(WallpaperStyle.whiteText)
                Text("先在 App 里跑一次“我的钱包全量分析”，小组件才会显示真实总价，不编数。").font(.caption).foregroundStyle(WallpaperStyle.grayText)
                PillTag(text: "只看不交易")
            }
        }
    }
}

// MARK: - 锁屏款（accessory 家族，系统单色，只用字 + ▲▼）
struct LockWidgetView: View {
    var entry: GaoQianEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        if let snap = entry.snapshot {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Text(pct(snap.topChangePct)).font(.headline).bold()
                    Text(snap.topSymbol ?? "—").font(.caption2)
                }
            case .accessoryInline:
                Text("\(money(snap.totalUsd))")
            default: // accessoryRectangular
                VStack(alignment: .leading, spacing: 4) {
                    Text(snap.topSymbol ?? "—").font(.headline).bold()
                    Text("\(money(snap.totalUsd)) · \((snap.topChangePct ?? 0) >= 0 ? "▲" : "▼") \(pct(snap.topChangePct))").font(.subheadline)
                    if snap.isStale { Text("旧数据 · \(snap.ageText ?? "")").font(.caption2) }
                }
            }
        } else {
            switch family {
            case .accessoryInline: Text("未同步")
            case .accessoryCircular: VStack { Text("—").font(.headline).bold(); Text("未同步").font(.caption2) }
            default: VStack(alignment: .leading) { Text("未同步").bold(); Text("去 App 刷新").font(.caption) }
            }
        }
    }
}

struct GaoQianWidgetView: View {
    var entry: GaoQianEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            LockWidgetView(entry: entry)
        default:
            HomeWidgetView(entry: entry)
        }
    }
}

struct GaoQianWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "GaoQianWidget", provider: GaoQianProvider()) { entry in
            GaoQianWidgetView(entry: entry)
        }
        .configurationDisplayName("搞钱")
        .description("总价与最重仓，只看不交易，点按打开 App。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct GaoQianWidgetBundle: WidgetBundle {
    var body: some Widget {
        GaoQianWidget()
#if os(iOS) && canImport(ActivityKit)
        TokenLiveActivityWidget()
#endif
    }
}

#if os(iOS) && canImport(ActivityKit)
// MARK: - 灵动岛（本地 Live Activity）
// 紧凑：左币名，右涨跌；展开：价 + 风险；最小：只币名。远程更新做不了，更新只靠 App 自己推新状态。
// 本版不显示浮盈亏（成本不在体检页填，不编成本）。
struct TokenLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TokenLiveActivityAttributes.self) { context in
            ZStack {
                Color.black
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(context.state.symbol).bold().foregroundStyle(.white)
                        Spacer()
                        if let r = context.state.risk { Text("风险：\(r)").font(.caption).foregroundStyle(.gray) }
                    }
                    Text(fmtPrice(context.state.priceUsd)).font(.title2).bold().foregroundStyle(.white)
                    HStack {
                        if let c = context.state.changePct { Text(String(format: "%@%.2f%%", c >= 0 ? "+" : "", c)).foregroundStyle(c >= 0 ? .green : .red) }
                        Spacer()
                        Text("成本未填，不显示浮盈亏").font(.caption).foregroundStyle(.gray)
                    }.font(.subheadline)
                }.padding(16)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(context.state.symbol).bold().foregroundStyle(.white) }
                DynamicIslandExpandedRegion(.trailing) {
                    if let c = context.state.changePct { Text(String(format: "%@%.2f%%", c >= 0 ? "+" : "", c)).foregroundStyle(c >= 0 ? .green : .red) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(fmtPrice(context.state.priceUsd)).foregroundStyle(.white)
                        Spacer()
                        if let r = context.state.risk { Text(r).font(.caption).foregroundStyle(.gray) }
                    }
                }
            } compactLeading: {
                Text(context.state.symbol).foregroundStyle(.white)
            } compactTrailing: {
                if let c = context.state.changePct { Text(String(format: "%@%.2f%%", c >= 0 ? "+" : "", c)).foregroundStyle(c >= 0 ? .green : .red) }
            } minimal: {
                Text(context.state.symbol).foregroundStyle(.white)
            }
        }
    }
}
#endif

// iOS 17 才有的 containerBackground：部署目标是 16.2，直接写会在 16.2 上编不过，
// 所以用 #available 包一层；16.x 上小组件本来就有 ZStack 黑底，不缺这一层。
extension View {
    @ViewBuilder func widgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(WallpaperStyle.background, for: .widget)
        } else {
            self
        }
    }
}
