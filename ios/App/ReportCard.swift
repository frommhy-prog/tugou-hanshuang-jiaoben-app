import SwiftUI

// 数据新鲜度：每块数据各自的更新时间，超时标「旧」（超过 12 小时带日期），旧数据照样显示；右侧一个「全部刷新」
struct FreshnessRow: View {
    @ObservedObject var vm: UTokenVM

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { ctx in
            let items: [(String, Date?, Double)] = [
                ("行情", vm.stamps.pairs, 90), ("成交", vm.stamps.trades, 90), ("持有人", vm.stamps.holders, 900),
                ("大户拆解", vm.stamps.analyses, 900), ("合约安全", vm.stamps.security, 1800), ("AI", vm.stamps.ai, 1800),
            ]
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if vm.refreshing {
                        ProgressView().controlSize(.mini)
                        Text("刷新中").font(.caption2).foregroundStyle(.secondary)
                    }
                    if vm.analyzing {
                        Text("大户拆解 " + String(vm.analyzedDone) + "/" + String(vm.analyzeTotal)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("全部刷新") { vm.refreshAll() }.font(.caption2.weight(.semibold))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(items, id: \.0) { it in chip(it.0, it.1, it.2, ctx.date) }
                    }
                }
                if let n = vm.refreshNote { Text(n).font(.caption2).foregroundStyle(Color.orange) }
                if let hn = vm.holderNote, !hn.isEmpty, (vm.stamps.holders.map { Date().timeIntervalSince($0) > 900 } ?? true) {
                    Text(cat("持有人刷新失败：", hn)).font(.caption2).foregroundStyle(Color.orange)
                }
            }
        }
    }

    private func ago(_ s: Double) -> String {
        if s < 90 { return String(Int(s)) + " 秒前" }
        if s < 5400 { return String(Int(s / 60)) + " 分钟前" }
        return String(Int(s / 3600)) + " 小时前"
    }

    private func chip(_ name: String, _ d: Date?, _ limit: Double, _ now: Date) -> some View {
        var text = name + " 无数据"
        var col = Color.gray
        if let d = d {
            let age = now.timeIntervalSince(d)
            let stale = age > limit
            let ts: String = age > 43_200 ? d.formatted(date: .abbreviated, time: .shortened) : d.formatted(date: .omitted, time: .standard)
            text = name + " " + ts + (stale ? "（旧 " + ago(age) + "）" : "")
            col = stale ? .orange : .green
        }
        return Text(text).font(.caption2).padding(.horizontal, 7).padding(.vertical, 3).background(col.opacity(0.14), in: Capsule()).foregroundStyle(col)
    }
}

struct ScoreBar: View {
    var score: Int
    var color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(color).frame(width: g.size.width * CGFloat(max(0, min(100, score))) / 100)
            }
        }
        .frame(height: 6)
    }
}

// 分项明细（规则引擎的 7 个维度，每条结论带依据）+ AI 研判。结论、利空利好、盯盘阈值在上方「综合研判」。
struct ReportCard: View {
    @ObservedObject var vm: UTokenVM

    private func levelColor(_ l: String) -> Color {
        switch l {
        case "risk": return .red
        case "warn": return .orange
        case "ok": return .green
        default: return .blue
        }
    }

    private func dimColor(_ s: Int) -> Color { s >= 75 ? .green : (s >= 55 ? .yellow : (s >= 35 ? .orange : .red)) }

    var body: some View {
        let r = AnalysisEngine.build(vm)
        VStack(spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("分项明细").font(.headline)
                        Text("规则 · 不依赖 AI").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2).background(Color.blue.opacity(0.14), in: Capsule()).foregroundStyle(Color.blue)
                        Spacer()
                    }
                    if !r.hard.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(r.hard, id: \.self) { h in
                                Label(h, systemImage: "exclamationmark.octagon.fill").font(.caption.bold()).foregroundStyle(Color.red)
                            }
                        }
                    }
                    ForEach(r.dims) { d in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(d.finds) { f in
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(alignment: .top, spacing: 6) {
                                            Circle().fill(levelColor(f.level)).frame(width: 7, height: 7).padding(.top, 5)
                                            Text(f.text).font(.caption)
                                        }
                                        Text("依据：" + f.basis).font(.caption2).foregroundStyle(.secondary).padding(.leading, 13)
                                    }
                                }
                                Text("来源：" + d.source).font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: d.icon).frame(width: 18).foregroundStyle(dimColor(d.score))
                                Text(d.title).font(.subheadline)
                                ScoreBar(score: d.score, color: dimColor(d.score)).frame(maxWidth: 90)
                                Spacer()
                                Text(String(d.score)).font(.subheadline.bold()).foregroundStyle(dimColor(d.score))
                            }
                        }
                    }
                    if !r.unknown.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("未知（数据没读到，不参与打分，也不拿假数凑）").font(.caption).foregroundStyle(.secondary)
                            ForEach(r.unknown, id: \.self) { u in Text("· " + u).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            AIResultCard(title: "AI 研判（与规则并行）", result: vm.ai, loading: vm.aiLoading, message: vm.aiMsg, onRun: vm.reAI)
        }
    }
}
