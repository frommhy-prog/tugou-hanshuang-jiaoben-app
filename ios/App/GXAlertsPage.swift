import SwiftUI
import UIKit

// MARK: - 设置 → 提醒：三个通道各一个开关（TSTZ-M 本机 / Telegram / Bark）
struct GXPushCfg: Codable {
    var tg: Bool?
    var bark: Bool?
}

struct GXPushResp: Codable {
    var cfg: GXPushCfg?
}

@MainActor
final class GXAlertsVM: ObservableObject {
    @Published var tgBound: Bool?
    @Published var barkBound: Bool?
    @Published var tgOn: Bool = true
    @Published var barkOn: Bool = true
    @Published var testing: Bool = false
    @Published var result: [Bool?] = []

    func load() async {
        if let k: KeysResponse = try? await API.get("/v1/keys") {
            let has = { (id: String) -> Bool in k.providers.first { $0.id == id }?.present ?? false }
            tgBound = has("telegram_token") && has("telegram_chat")
            barkBound = has("bark")
        }
        if let r: GXPushResp = try? await API.get("/v1/push/config") {
            tgOn = r.cfg?.tg ?? true
            barkOn = r.cfg?.bark ?? true
        }
    }

    func save(tg: Bool?, bark: Bool?) async {
        let _: API.Empty? = try? await API.post("/v1/push/config", GXPushCfg(tg: tg, bark: bark), method: "PUT")
    }

    func test() async {
        struct R: Decodable {
            var telegram: Bool?
            var bark: Bool?
        }
        testing = true
        defer { testing = false }
        if let r: R = try? await API.get("/v1/push/test") {
            result = [r.telegram, r.bark]
        } else {
            result = [false, false]
        }
        GXNote.post(title: "TSTZ-M", body: "WETH", chain: "eth", address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")
    }
}

struct GXPageAlerts2: View {
    @StateObject private var vm = GXAlertsVM()
    @AppStorage("alertCh.local", store: Cfg.defaults) private var local = true
    @State private var showRules = false

    private func status(_ ok: Bool?) -> some View {
        let sym: String = ok == nil ? "ellipsis.circle" : (ok == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
        let col: Color = ok == nil ? Color.secondary : (ok == true ? Color.green : Color.orange)
        return Image(systemName: sym).foregroundStyle(col)
    }

    private func chip(_ sym: String, _ c: Color) -> some View {
        Image(systemName: sym)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 32, height: 32)
            .background(c, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func resultIcon(_ i: Int) -> some View {
        let v: Bool? = vm.result.count > i ? vm.result[i] : nil
        return status(v)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    BrandMark(size: 32)
                    Text("TSTZ-M")
                    Spacer()
                    Toggle("", isOn: $local).labelsHidden()
                }
                HStack(spacing: 12) {
                    chip("paperplane.fill", Color.blue)
                    Text("Telegram")
                    Spacer()
                    status(vm.tgBound)
                    Toggle("", isOn: Binding(get: { vm.tgOn }, set: { v in
                        vm.tgOn = v
                        Task { await vm.save(tg: v, bark: nil) }
                    })).labelsHidden().disabled(vm.tgBound != true)
                }
                HStack(spacing: 12) {
                    chip("bell.badge.fill", Color.orange)
                    Text("Bark")
                    Spacer()
                    status(vm.barkBound)
                    Toggle("", isOn: Binding(get: { vm.barkOn }, set: { v in
                        vm.barkOn = v
                        Task { await vm.save(tg: nil, bark: v) }
                    })).labelsHidden().disabled(vm.barkBound != true)
                }
            }
            Section {
                NavigationLink { KeysView() } label: { Image(systemName: "key.fill") }
                Button { Task { await vm.test() } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "paperplane")
                        if vm.testing { ProgressView() }
                        Spacer()
                        resultIcon(0)
                        resultIcon(1)
                    }
                }
                Button { showRules = true } label: { Image(systemName: "bell.badge") }
                NavigationLink { GXScoutSettingsView() } label: { Image(systemName: "dot.radiowaves.left.and.right") }
            }
        }
        .navigationTitle("提醒")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRules) { AlertsView() }
        .task { await vm.load() }
    }
}
