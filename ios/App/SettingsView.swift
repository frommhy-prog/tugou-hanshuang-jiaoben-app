import SwiftUI
import PhotosUI
import UIKit

struct SettingsView: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("currency", store: Cfg.defaults) private var currency = "USD"
    @State private var tokenInput = ""
    @State private var pingText: String?
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("主题", selection: $theme) {
                        Text("跟随系统").tag("system")
                        Text("日间").tag("light")
                        Text("夜间").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }
                Section("计价货币") {
                    NavigationLink {
                        CurrencyPicker(selected: $currency)
                    } label: {
                        HStack { Text("货币"); Spacer(); Text(currency).foregroundStyle(.secondary) }
                    }
                }
                Section("连接") {
                    SecureField(Cfg.token.isEmpty ? "粘贴令牌" : "令牌已保存（粘贴新令牌可替换）", text: $tokenInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button("保存并测试") { Task { await test() } }.disabled(testing)
                        if testing { Spacer(); ProgressView() }
                    }
                    if let p = pingText { Text(p).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("数据与密钥") {
                    NavigationLink("API 密钥与额度") { KeysView() }
                }
                Section("分享与反馈") {
                    ShareLink(item: "TSTZ-M：土狗体检 + 钱包 + 寒霜启示录，一个 App 搞定") {
                        Label("分享 TSTZ-M", systemImage: "square.and.arrow.up")
                    }
                    NavigationLink { FeedbackView() } label: { Label("反馈问题", systemImage: "bubble.left.and.text.bubble.right") }
                }
                Section("关于") {
                    HStack { Text("版本"); Spacer(); Text(version).foregroundStyle(.secondary) }
                    Text("小组件只跟随系统的日间 / 夜间外观；灵动岛盯盘只在 App 前台时更新。").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
        }
    }

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") + " (" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1") + ")"
    }

    private func test() async {
        testing = true
        if !tokenInput.trimmingCharacters(in: .whitespaces).isEmpty { Cfg.token = tokenInput; tokenInput = "" }
        do {
            let p: Ping = try await API.get("/v1/ping")
            var s = p.ok == true ? "连接正常" : "服务无响应"
            if let e = p.lastEval, let at = e.at {
                s += " · 提醒检查上次运行 " + Date(timeIntervalSince1970: at / 1000).formatted(date: .omitted, time: .shortened)
            } else {
                s += " · 提醒检查器已启动，约 5 分钟内首次运行"
            }
            pingText = s
        } catch { pingText = error.localizedDescription }
        testing = false
    }
}

struct CurrencyPicker: View {
    @Binding var selected: String
    var body: some View {
        List(Money.all) { c in
            Button {
                selected = c.code
                Task { await FX.refresh() }
            } label: {
                HStack {
                    Text(c.code + " " + c.name).foregroundStyle(Color.primary)
                    Spacer()
                    if selected == c.code { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                }
            }
        }
        .navigationTitle("计价货币")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Text("汇率为每日参考价，不是实时外汇牌价；取不到汇率时回落显示美元。").font(.caption2).foregroundStyle(.secondary).padding(8)
        }
    }
}

// MARK: - API 密钥与额度
@MainActor
final class KeysVM: ObservableObject {
    @Published var keys: [KeyInfo] = []
    @Published var q: QuotasV?
    @Published var fetchedAt = Date()
    @Published var error: String?

    func load() async {
        do {
            let k: KeysResponse = try await API.get("/v1/keys")
            keys = k.providers
            q = try await API.get("/v1/quotas")
            fetchedAt = Date()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func save(_ id: String, _ value: String) async -> String? {
        do {
            let _: API.Empty = try await API.post("/v1/keys", ["provider": id, "value": value], method: "PUT")
            await load()
            return nil
        } catch { return error.localizedDescription }
    }

    func remove(_ id: String) async {
        let _: API.Empty? = try? await API.send("/v1/keys", query: ["provider": id], method: "DELETE", body: nil)
        await load()
    }
}

let providerNames: [String: String] = [
    "groq": "Groq（AI 研判）", "helius": "Helius（Solana）",
    "telegram_token": "Telegram Bot Token", "telegram_chat": "Telegram Chat ID", "bark": "Bark Key 或链接",
    "binance_key": "币安 API Key（只读）", "binance_secret": "币安 Secret", "okx_key": "欧易 API Key（只读）",
    "okx_secret": "欧易 Secret", "okx_pass": "欧易 Passphrase", "gate_key": "Gate API Key（只读）", "gate_secret": "Gate Secret",
]

struct KeysView: View {
    @StateObject private var vm = KeysVM()
    @State private var editing: KeyInfo?

    var body: some View {
        List {
            if let e = vm.error { Section { Text(e).font(.footnote).foregroundStyle(Color.orange) } }
            groqSection
            if let items = vm.q?.legacy?.items, !items.isEmpty {
                Section("数据源额度") {
                    ForEach(items) { it in legacyRow(it) }
                }
            }
            if let u = vm.q?.usage, !u.isEmpty {
                Section("今日调用（\(vm.q?.day ?? "")）") {
                    ForEach(u) { x in HStack { Text(x.ep).font(.footnote.monospaced()); Spacer(); Text("\(x.n)").font(.footnote) } }
                }
            }
            Section("绑定密钥") {
                ForEach(vm.keys) { k in
                    Button { editing = k } label: {
                        HStack {
                            Text(providerNames[k.id] ?? k.id).foregroundStyle(Color.primary)
                            Spacer()
                            if k.present { Text("••••" + (k.last4 ?? "")).font(.footnote.monospaced()).foregroundStyle(.secondary) }
                            else { Text("未绑定").font(.footnote).foregroundStyle(.secondary) }
                        }
                    }
                }
                Text("密钥加密保存在你自己的服务器上，App 不存明文；交易所只绑定只读密钥。").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("API 密钥与额度")
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .sheet(item: $editing) { k in KeyEditor(info: k, vm: vm) }
    }

    private var groqSection: some View {
        Section("Groq 额度（服务端实测）") {
            if let g = vm.q?.groq {
                if g.keyPresent != true {
                    Text("未绑定密钥").font(.footnote).foregroundStyle(.secondary)
                } else if g.called != true {
                    Text("已绑定，尚未调用；第一次 AI 研判后显示真实剩余次数").font(.footnote).foregroundStyle(.secondary)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("今日请求").font(.subheadline)
                                Spacer()
                                Text(reqText(g)).font(.subheadline.weight(.semibold).monospacedDigit())
                            }
                            if let lim = g.limitRequests, let rem = g.remainingRequests, lim > 0 {
                                ProgressView(value: max(0, min(1, rem / lim)))
                            }
                            if g.limited == true, let t = g.retryAtMs ?? g.resetRequestsAtMs {
                                let left = Int(t / 1000 - ctx.date.timeIntervalSince1970)
                                Label(left > 0 ? "已限额，恢复倒计时 " + mmss(left) : "限额已恢复", systemImage: "hourglass").font(.footnote).foregroundStyle(Color.orange)
                            } else if let t = g.resetRequestsAtMs {
                                let left = Int(t / 1000 - ctx.date.timeIntervalSince1970)
                                Text(left > 0 ? "次数恢复倒计时 " + mmss(left) : "次数已恢复").font(.footnote).foregroundStyle(.secondary)
                            }
                            if let tr = g.remainingTokens, let tl = g.limitTokens {
                                Text("本分钟令牌 \(Int(tr)) / \(Int(tl))").font(.caption).foregroundStyle(.secondary)
                            }
                            if let m = g.model { Text("模型 " + m).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
            } else {
                Text("读取中…").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func reqText(_ g: QuotasV.GroqQ) -> String {
        guard let rem = g.remainingRequests else { return "未知" }
        if let lim = g.limitRequests { return "剩余 \(Int(rem)) / \(Int(lim))" }
        return "剩余 \(Int(rem))"
    }

    private func legacyRow(_ it: QuotaItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(it.name ?? it.id).font(.subheadline)
                Spacer()
                Text(it.keyPresent == false ? "未配置" : (it.remainingText ?? (it.remaining.map { "剩余 \($0)" } ?? "剩余未知"))).font(.footnote.weight(.semibold))
            }
            if let u = it.usedToday { Text("今日已用 " + u).font(.caption).foregroundStyle(.secondary) }
            if it.limited == true {
                if let s = it.resetsInSec {
                    let end = vm.fetchedAt.addingTimeInterval(TimeInterval(s))
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Label("已限额，恢复倒计时 " + mmss(Int(end.timeIntervalSince(ctx.date))), systemImage: "hourglass").font(.caption).foregroundStyle(Color.orange)
                    }
                } else {
                    Label("已限额", systemImage: "hourglass").font(.caption).foregroundStyle(Color.orange)
                }
            } else if let r = it.resetsText { Text(r).font(.caption).foregroundStyle(.secondary) }
            if let n = it.note { Text(n).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

extension KeyInfo: Hashable {
    static func == (a: KeyInfo, b: KeyInfo) -> Bool { a.id == b.id && a.present == b.present && a.last4 == b.last4 }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct KeyEditor: View {
    @Environment(\.dismiss) private var dismiss
    let info: KeyInfo
    @ObservedObject var vm: KeysVM
    @State private var value = ""
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section(providerNames[info.id] ?? info.id) {
                    SecureField("粘贴密钥", text: $value)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("从剪贴板粘贴") { value = UIPasteboard.general.string ?? value }
                }
                if let m = message { Section { Text(m).font(.footnote).foregroundStyle(Color.orange) } }
                if info.present {
                    Section { Button("删除已绑定密钥", role: .destructive) { Task { await vm.remove(info.id); dismiss() } } }
                }
            }
            .navigationTitle("绑定密钥")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            busy = true
                            if let e = await vm.save(info.id, value.trimmingCharacters(in: .whitespacesAndNewlines)) { message = e } else { dismiss() }
                            busy = false
                        }
                    } label: { if busy { ProgressView() } else { Text("保存") } }
                    .disabled(value.trimmingCharacters(in: .whitespaces).count < 4 || busy)
                }
            }
        }
    }
}

// MARK: - 反馈（文字，或文字加图片）
struct FeedbackView: View {
    @State private var text = ""
    @State private var type = "问题"
    @State private var item: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var busy = false
    @State private var result: String?

    var body: some View {
        Form {
            Section {
                Picker("类型", selection: $type) {
                    Text("问题").tag("问题"); Text("建议").tag("建议"); Text("数据不准").tag("数据不准")
                }
                .pickerStyle(.segmented)
                TextEditor(text: $text).frame(minHeight: 140)
            }
            Section("截图（可选）") {
                PhotosPicker(selection: $item, matching: .images) { Label(image == nil ? "选择图片" : "更换图片", systemImage: "photo") }
                if let img = image {
                    Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 180).clipShape(RoundedRectangle(cornerRadius: 10))
                    Button("移除图片", role: .destructive) { image = nil; item = nil }
                }
            }
            Section {
                Button { Task { await send() } } label: { HStack { Text("提交反馈"); if busy { Spacer(); ProgressView() } } }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                if let r = result { Text(r).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("反馈")
        .onChange(of: item) { _, new in
            Task {
                if let d = try? await new?.loadTransferable(type: Data.self), let ui = UIImage(data: d) { image = ui }
            }
        }
    }

    private func send() async {
        busy = true; result = nil
        var dataUrl: String?
        if let img = image {
            var q: CGFloat = 0.7
            var data = img.jpegData(compressionQuality: q)
            while let d = data, d.count > 600_000, q > 0.1 { q -= 0.15; data = img.jpegData(compressionQuality: q) }
            if let d = data { dataUrl = "data:image/jpeg;base64," + d.base64EncodedString() }
        }
        struct B: Encodable { let type: String; let text: String; let platform: String; let imageDataUrl: String? }
        do {
            let r: FeedbackResponse = try await API.post("/api/feedback", B(type: type, text: text, platform: "iOS App TSTZ-M", imageDataUrl: dataUrl))
            if r.stored == true { result = "已提交，谢谢"; text = ""; image = nil; item = nil }
            else { result = r.error ?? r.note ?? "提交失败" }
        } catch { result = error.localizedDescription }
        busy = false
    }
}
