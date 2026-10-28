import WidgetKit
import SwiftUI
import Charts
import ActivityKit

struct PortEntry: TimelineEntry {
    let date: Date
    let snap: Snapshot?
}

// 小组件自己联网取数（不依赖 App 是否打开）；取不到就用最近一次快照
enum WidgetLoader {
    static func load() async -> Snapshot? {
        let ws = Cfg.wallets
        guard !Cfg.token.isEmpty, !ws.isEmpty else { return nil }
        var rs: [PortfolioResponse] = []
        for w in ws {
            let param = w.chains.map { $0 + ":" + w.address }.joined(separator: ",")
            if let r: PortfolioResponse = try? await API.get("/api/wallet-portfolio", ["wallets": param, "mode": "merged"]) {
                rs.append(r)
            }
        }
        if rs.isEmpty { return nil }
        let snap = Snapshot.build(rs)
        Cfg.snapshot = snap
        return snap
    }
}

struct PortProvider: TimelineProvider {
    func placeholder(in context: Context) -> PortEntry { PortEntry(date: Date(), snap: Snapshot.sample) }

    func getSnapshot(in context: Context, completion: @escaping (PortEntry) -> Void) {
        completion(PortEntry(date: Date(), snap: Cfg.snapshot ?? Snapshot.sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PortEntry>) -> Void) {
        Task {
            let fresh = await WidgetLoader.load()
            let entry = PortEntry(date: Date(), snap: fresh ?? Cfg.snapshot)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
}

struct PortView: View {
    let entry: PortEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let s = entry.snap { content(s) } else { empty }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Image(systemName: "wallet.pass")
            Text(Cfg.token.isEmpty ? "先在 App 里连接服务" : "添加钱包后显示").font(.caption).multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func content(_ s: Snapshot) -> some View {
        switch family {
        case .accessoryInline:
            Text("TSTZ-M " + Money.format(s.totalUsd))
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Text(Money.format(s.totalUsd)).font(.caption2.weight(.bold)).minimumScaleFactor(0.5).lineLimit(1).padding(4)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("TSTZ-M 总资产").font(.caption2)
                Text(Money.format(s.totalUsd)).font(.headline)
                Text(s.items.first.map { $0.symbol + " 最大持仓" } ?? "").font(.caption2)
            }
        case .systemSmall:
            VStack(alignment: .leading, spacing: 4) {
                Text("总资产").font(.caption).foregroundStyle(.secondary)
                Text(Money.format(s.totalUsd)).font(.system(.title2, design: .rounded).weight(.bold)).minimumScaleFactor(0.5).lineLimit(1)
                Spacer()
                if let t = s.items.first { Text(t.symbol + " " + Money.format(t.usd)).font(.caption.weight(.semibold)) }
                Text(s.at.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("总资产").font(.caption).foregroundStyle(.secondary)
                    Text(Money.format(s.totalUsd)).font(.system(.title, design: .rounded).weight(.bold)).minimumScaleFactor(0.5).lineLimit(1)
                    Spacer()
                    Text(s.at.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(s.items.prefix(4)), id: \.self) { it in
                        HStack {
                            Text(it.symbol).font(.caption.weight(.semibold))
                            Spacer()
                            Text(Money.format(it.usd)).font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("总资产").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(s.at.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                }
                Text(Money.format(s.totalUsd)).font(.system(.largeTitle, design: .rounded).weight(.bold)).minimumScaleFactor(0.5).lineLimit(1)
                Chart(s.items, id: \.self) { it in
                    SectorMark(angle: .value("价值", it.usd), innerRadius: .ratio(0.6), angularInset: 1.5)
                        .cornerRadius(3)
                        .foregroundStyle(by: .value("代币", it.symbol))
                }
                .chartLegend(.hidden)
                .frame(maxHeight: 150)
                ForEach(Array(s.items.prefix(4)), id: \.self) { it in
                    HStack {
                        Text(it.symbol).font(.caption.weight(.semibold))
                        Spacer()
                        Text(Money.format(it.usd)).font(.caption.monospacedDigit())
                    }
                }
            }
        }
    }
}

struct PortWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TSTZMPortfolio", provider: PortProvider()) { entry in
            PortView(entry: entry)
        }
        .configurationDisplayName("资产总览")
        .description("钱包总资产与持仓占比")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - 灵动岛 / 锁屏实时活动
struct WatchLiveView: View {
    let ctx: ActivityViewContext<WatchAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ctx.attributes.symbol).font(.headline)
                Text(ctx.attributes.chain).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(ctx.state.updated, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(Money.price(ctx.state.price)).font(.system(.title, design: .rounded).weight(.bold))
                if let c = ctx.state.change24h {
                    Text(String(format: "%+.2f%%", c)).font(.subheadline.weight(.semibold)).foregroundStyle(c >= 0 ? Color.green : Color.red)
                }
            }
            if let l = ctx.state.liquidity { Text("流动性 " + Money.format(l)).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(14)
    }
}

struct WatchLive: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WatchAttributes.self) { ctx in
            WatchLiveView(ctx: ctx)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Text(ctx.attributes.symbol).font(.headline) }
                DynamicIslandExpandedRegion(.trailing) { Text(Money.price(ctx.state.price)).font(.headline.monospacedDigit()) }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let c = ctx.state.change24h {
                            Text(String(format: "24h %+.2f%%", c)).foregroundStyle(c >= 0 ? Color.green : Color.red)
                        }
                        Spacer()
                        if let l = ctx.state.liquidity { Text("流动性 " + Money.format(l)).foregroundStyle(.secondary) }
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Text(ctx.attributes.symbol).font(.caption2.weight(.bold))
            } compactTrailing: {
                Text(Money.price(ctx.state.price)).font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "chart.line.uptrend.xyaxis")
            }
        }
    }
}

@main
struct TSTZMWidgets: WidgetBundle {
    var body: some Widget {
        PortWidget()
        WatchLive()
    }
}
