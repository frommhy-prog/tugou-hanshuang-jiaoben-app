import WidgetKit
import SwiftUI

// 小组件：只看不交易，点按只跳 App。
// 读 WalletStore 同一份钱包列表 + Worker 聚合 JSON（第一版先读钱包列表，聚合接通后替换为 Worker 数据）。
struct HoldingsEntry: TimelineEntry {
    var date: Date
    var walletCount: Int
}

struct HoldingsProvider: TimelineProvider {
    func placeholder(in context: Context) -> HoldingsEntry { HoldingsEntry(date: Date(), walletCount: 0) }
    func getSnapshot(in context: Context, completion: @escaping (HoldingsEntry) -> Void) {
        completion(HoldingsEntry(date: Date(), walletCount: 0))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<HoldingsEntry>) -> Void) {
        let entry = HoldingsEntry(date: Date(), walletCount: 0)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
    }
}

struct HoldingsWidgetView: View {
    var entry: HoldingsEntry
    var body: some View {
        VStack(alignment: .leading) {
            Text("土狗寒霜脚本").bold()
            Text("钱包 \(entry.walletCount) 个 · 持仓聚合接通后显示总浮盈亏")
                .font(.caption)
        }
        .containerBackground(.black, for: .widget)
    }
}

@main
struct HoldingsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoldingsWidget", provider: HoldingsProvider()) { entry in
            HoldingsWidgetView(entry: entry)
        }
        .configurationDisplayName("全链持仓")
        .description("总浮盈亏与持仓总览，只看不交易。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}
