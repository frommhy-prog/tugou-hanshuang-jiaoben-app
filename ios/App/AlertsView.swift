import SwiftUI
import UIKit

enum AlertKind: String, CaseIterable, Identifiable {
    case price_above, price_below, change5m_abs, change1h_abs, drop_from_ref, liq_below, vol24_above
    var id: String { rawValue }
    var title: String {
        switch self {
        case .price_above: return "价格高于"
        case .price_below: return "价格低于"
        case .change5m_abs: return "5 分钟涨跌幅超过"
        case .change1h_abs: return "1 小时涨跌幅超过"
        case .drop_from_ref: return "较当前价下跌超过"
        case .liq_below: return "流动性低于"
        case .vol24_above: return "24h 成交高于"
        }
    }
    var unit: String {
        switch self {
        case .price_above, .price_below, .liq_below, .vol24_above: return "美元"
        default: return "%"
        }
    }
}

@MainActor
final class AlertsVM: ObservableObject {
    @Published var rules: [AlertRule] = []
    @Published var channelOK = false
    @Published var loading = false
    @Published var error: String?
    @Published var info: String?

    func load() async {
        loading = true
        error = nil
        do {
            let r: AlertsResponse = try await API.get("/v1/alerts")
            rules = r.alerts
            let k: KeysResponse = try await API.get("/v1/keys")
            let has = { (id: String) -> Bool in k.providers.first { $0.id == id }?.present ?? false }
            channelOK = (has("telegram_token") && has("telegram_chat")) || has("bark")
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    func toggle(_ r: AlertRule, _ on: Bool) async {
        struct B: Encodable { let active: Bool }
        let _: API.Empty? = try? await API.post("/v1/alerts", B(active: on), method: "PATCH", query: ["id": String(r.id)])
        await load()
    }

    func delete(_ r: AlertRule) async {
        let _: API.Empty? = try? await API.send("/v1/alerts", query: ["id": String(r.id)], method: "DELETE", body: nil)
        await load()
    }

    func testPush() async {
        struct R: Decodable { var telegram: Bool?; var bark: Bool? }
        do {
            let r: R = try await API.get("/v1/push/test")
            if r.telegram == nil && r.bark == nil { info = "还没配置推送通道" }
            else { info = "测试已发送：Telegram " + (r.telegram.map { $0 ? "成功" : "失败" } ?? "未配置") + "，Bark " + (r.bark.map { $0 ? "成功" : "失败" } ?? "未配置") }
        } catch { info = error.localizedDescription }
    }
}

struct AlertsView: View {
    @StateObject private var vm = AlertsVM()
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: vm.channelOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(vm.channelOK ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vm.channelOK ? "推送通道已配置" : "还没配置推送通道").font(.subheadline.weight(.semibold))
                            Text(vm.channelOK ? "条件满足时服务器每 5 分钟检查并推送到 Telegram / Bark" : "到 设置 → API 密钥与额度 绑定 Telegram 或 Bark").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if vm.channelOK {
                        Button("发送测试推送") { Task { await vm.testPush() } }
                    }
                    if let i = vm.info { Text(i).font(.footnote).foregroundStyle(.secondary) }
                }
                if let e = vm.error { Section { Text(e).font(.footnote).foregroundStyle(Color.orange) } }
                Section("我的提醒") {
                    if vm.rules.isEmpty && !vm.loading {
                        Text("还没有提醒，点右上角 + 添加").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(vm.rules) { r in row(r) }
                }
            }
            .navigationTitle("提醒")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await vm.load() }
            .task { await vm.load() }
            .sheet(isPresented: $showAdd) {
                AlertEditor(prefill: nil) { Task { await vm.load() } }
            }
        }
    }

    private func row(_ r: AlertRule) -> some View {
        let kind = AlertKind(rawValue: r.kind)
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(r.symbol ?? Addr.short(r.address ?? "")).font(.subheadline.weight(.semibold))
                    Pill(text: Chain(rawValue: r.chain ?? "")?.title ?? (r.chain ?? ""), color: Color.blue)
                }
                Text((kind?.title ?? r.kind) + " " + valueText(r.value) + (kind?.unit ?? "")).font(.footnote).foregroundStyle(.secondary)
                if let f = r.lastFired, f > 0 {
                    Text("上次触发 " + Date(timeIntervalSince1970: f / 1000).formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { (r.active ?? 0) == 1 }, set: { on in Task { await vm.toggle(r, on) } })).labelsHidden()
        }
        .swipeActions {
            Button(role: .destructive) { Task { await vm.delete(r) } } label: { Label("删除", systemImage: "trash") }
        }
    }

    private func valueText(_ v: Double?) -> String {
        guard let v = v else { return "—" }
        if v >= 1 { return String(format: "%g", v) }
        return String(format: "%.8g", v)
    }
}

struct AlertEditor: View {
    @Environment(\.dismiss) private var dismiss
    let prefill: AlertPrefill?
    var onSaved: () -> Void

    @State private var address = ""
    @State private var symbol = ""
    @State private var chain: Chain = .bsc
    @State private var kind: AlertKind = .price_below
    @State private var valueText = ""
    @State private var cooldown = 60
    @State private var refPrice: Double?
    @State private var busy = false
    @State private var message: String?

    private var addr: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { (Addr.isEVM(addr) || Addr.isSolana(addr)) && (Double(valueText) ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("代币合约") {
                    TextField("粘贴合约地址", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Button("从剪贴板粘贴") { address = UIPasteboard.general.string ?? address }
                    Picker("链", selection: $chain) {
                        ForEach(Chain.allCases.filter { $0.tokenSupported }) { Text($0.title).tag($0) }
                    }
                }
                Section("条件") {
                    Picker("类型", selection: $kind) {
                        ForEach(AlertKind.allCases) { Text($0.title).tag($0) }
                    }
                    HStack {
                        TextField("数值", text: $valueText).keyboardType(.decimalPad)
                        Text(kind.unit).foregroundStyle(.secondary)
                    }
                    Picker("同一条件间隔", selection: $cooldown) {
                        Text("15 分钟").tag(15)
                        Text("1 小时").tag(60)
                        Text("4 小时").tag(240)
                        Text("24 小时").tag(1440)
                    }
                }
                if let m = message { Section { Text(m).font(.footnote).foregroundStyle(Color.orange) } }
            }
            .navigationTitle("添加提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { if busy { ProgressView() } else { Text("保存") } }
                        .disabled(!valid || busy)
                }
            }
            .onAppear {
                if let p = prefill {
                    address = p.address; symbol = p.symbol; chain = p.chain; refPrice = p.price
                }
            }
            .onChange(of: address) { _, _ in
                if Addr.isSolana(addr) { chain = .solana }
                else if Addr.isEVM(addr) && prefill == nil {
                    Task { if let c = await TokenVM.detect(addr) { chain = c } }
                }
            }
        }
    }

    private func save() async {
        busy = true; message = nil
        var ref = refPrice
        if kind == .drop_from_ref && ref == nil {
            let t: TokenResponse? = try? await API.get("/api/token-fast", ["chain": chain.rawValue, "address": addr])
            ref = t?.price?.priceUsd
            if symbol.isEmpty { symbol = t?.price?.symbol ?? "" }
            if ref == nil { message = "没取到当前价，无法设置下跌提醒"; busy = false; return }
        }
        let draft = AlertDraft(kind: kind.rawValue, chain: chain.rawValue, address: addr, symbol: symbol, value: Double(valueText) ?? 0, ref: ref, cooldownMin: cooldown)
        do {
            let _: API.Empty = try await API.post("/v1/alerts", draft)
            onSaved()
            dismiss()
        } catch {
            message = error.localizedDescription
        }
        busy = false
    }
}
