import SwiftUI
import UIKit

@MainActor
final class FrostVM: ObservableObject {
    @Published var player: WosPlayer?
    @Published var codes: [WosCode] = []
    @Published var redeemUrl = "https://wos-giftcode.centurygame.com/"
    @Published var source: String?
    @Published var note: String?
    @Published var loading = false
    @Published var error: String?

    func load() async {
        loading = true
        error = nil
        if let p: ProfileResponse = try? await API.get("/v1/config"), let pr = p.profile {
            player = pr
            if let u = pr.redeemUrl, !u.isEmpty { redeemUrl = u }
        }
        do {
            let r: WosCodesResponse = try await API.get("/api/wos-codes")
            if player == nil { player = r.player }
            if let u = r.redeemUrl, !u.isEmpty, player?.redeemUrl == nil { redeemUrl = u }
            codes = r.codes ?? []
            source = r.source
            note = r.note
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

struct FrostView: View {
    @StateObject private var vm = FrostVM()
    @Environment(\.openURL) private var openURL
    @State private var toast: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    lordCard
                    if let e = vm.error { ErrorCard(text: e) { Task { await vm.load() } } }
                    codesCard
                }
                .padding(16)
            }
            .background(Color.page)
            .navigationTitle("寒霜启示录")
            .refreshable { await vm.load() }
            .task { await vm.load() }
            .overlay(alignment: .bottom) {
                if let t = toast {
                    Text(t).font(.footnote.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule()).padding(.bottom, 12)
                        .transition(.opacity)
                }
            }
        }
    }

    private var lordCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "snowflake").font(.title2).foregroundStyle(Color.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.player?.name ?? "领主信息").font(.headline)
                        Text("联盟 " + (vm.player?.alliance ?? "—")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    StatTile(title: "ID", value: vm.player?.id ?? "—")
                    StatTile(title: "王国", value: kingdomText)
                }
                Button {
                    if let id = vm.player?.id { UIPasteboard.general.string = id }
                    flash("已复制 ID，到官方兑换中心粘贴")
                    if let u = URL(string: vm.redeemUrl) { openURL(u) }
                } label: {
                    Label("复制 ID 并打开官方兑换中心", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.player?.id == nil)
            }
        }
    }

    private var kingdomText: String {
        guard let k = vm.player?.kingdom else { return "—" }
        if let i = vm.player?.initialKingdom, !i.isEmpty { return k + "（初始 " + i + "）" }
        return k
    }

    private var codesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("兑换码", systemImage: "gift").font(.headline)
                    Spacer()
                    if vm.loading { ProgressView() }
                }
                if vm.codes.isEmpty && !vm.loading {
                    Text("暂无兑换码数据").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(Array(vm.codes.enumerated()), id: \.offset) { _, c in codeRow(c) }
                if let s = vm.source { Text("来源：" + s).font(.caption2).foregroundStyle(.secondary) }
                Text("官方兑换需要图形验证码，所以这里是一键复制并跳转，验证码要你本人输入。").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func codeRow(_ c: WosCode) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(c.code ?? "—").font(.system(.body, design: .monospaced).weight(.semibold))
                if let r = c.rewards, !r.isEmpty { Text(r).font(.caption).foregroundStyle(.secondary) }
                if let n = c.note, !n.isEmpty { Text(n).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Pill(text: c.status ?? "未知", color: statusColor(c.status))
                Button("复制并兑换") {
                    if let code = c.code { UIPasteboard.general.string = code }
                    flash("已复制兑换码")
                    if let u = URL(string: vm.redeemUrl) { openURL(u) }
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private func statusColor(_ s: String?) -> Color {
        let t = (s ?? "").lowercased()
        if t.contains("有效") || t.contains("active") || t.contains("valid") { return Color.green }
        if t.contains("过期") || t.contains("expired") || t.contains("失效") { return Color.red }
        return Color.gray
    }

    private func flash(_ s: String) {
        withAnimation { toast = s }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { toast = nil }
        }
    }
}
