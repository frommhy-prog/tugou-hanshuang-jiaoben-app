import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - 统一时区：全 App 的时间、引擎文本里的 UTC 时间都按这里显示
enum TZ {
    static let options: [(id: String, name: String)] = [
        ("Asia/Shanghai", "北京时间（UTC+8）"),
        ("Asia/Hong_Kong", "香港（UTC+8）"),
        ("Asia/Singapore", "新加坡（UTC+8）"),
        ("Asia/Tokyo", "东京（UTC+9）"),
        ("Asia/Seoul", "首尔（UTC+9）"),
        ("Asia/Dubai", "迪拜（UTC+4）"),
        ("Europe/London", "伦敦"),
        ("Europe/Berlin", "柏林"),
        ("America/New_York", "纽约"),
        ("America/Chicago", "芝加哥"),
        ("America/Los_Angeles", "洛杉矶"),
        ("UTC", "UTC"),
        ("", "跟随系统"),
    ]
    private static var cached: (String, DateFormatter)?

    static var id: String {
        get { Cfg.defaults.string(forKey: "tz") ?? "Asia/Shanghai" }
        set { Cfg.defaults.set(newValue, forKey: "tz"); cached = nil; apply() }
    }
    static var current: TimeZone {
        if id.isEmpty { return TimeZone.autoupdatingCurrent }
        return TimeZone(identifier: id) ?? TimeZone.current
    }
    static func apply() {
        if id.isEmpty {
            NSTimeZone.resetSystemTimeZone()
            NSTimeZone.default = NSTimeZone.system
        } else if let z = TimeZone(identifier: id) {
            NSTimeZone.default = z
        }
    }
    static var label: String {
        let s = current.secondsFromGMT()
        let h = s / 3600
        let m = abs(s % 3600) / 60
        return "UTC" + (h >= 0 ? "+" : "-") + String(abs(h)) + (m > 0 ? ":" + String(format: "%02d", m) : "")
    }
    private static func formatter() -> DateFormatter {
        if let c = cached, c.0 == id { return c.1 }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        cached = (id, f)
        return f
    }
    static func format(_ d: Date) -> String { formatter().string(from: d) }
    static func format(ts: Double?) -> String {
        guard let ts = ts else { return "未知" }
        return format(Date(timeIntervalSince1970: ts))
    }
    static func short(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = current
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    // 引擎文本里的「2026-10-28 22:15 UTC」按所选时区改写
    static func render(_ text: String) -> String {
        guard text.contains("UTC"), let re = try? NSRegularExpression(pattern: "(\\d{4}-\\d{2}-\\d{2}) (\\d{2}:\\d{2}) UTC") else { return text }
        let ns = text as NSString
        let ms = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        if ms.isEmpty { return text }
        let p = DateFormatter()
        p.locale = Locale(identifier: "en_US_POSIX")
        p.timeZone = TimeZone(identifier: "UTC")
        p.dateFormat = "yyyy-MM-dd HH:mm"
        var out = text
        for m in ms.reversed() {
            let raw = ns.substring(with: m.range)
            let core = String(raw.dropLast(4))
            if let d = p.date(from: core), let r = Range(m.range, in: out) {
                out.replaceSubrange(r, with: format(d) + "（" + label + "）")
            }
        }
        return out
    }
}

// MARK: - 查询记录（代币与钱包）
struct HistoryItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: String      // token / wallet
    var chain: String
    var address: String
    var title: String
    var at: Date
}

enum QueryHistory {
    static var items: [HistoryItem] {
        get {
            guard let d = Cfg.defaults.data(forKey: "qhist"), let v = try? JSONDecoder().decode([HistoryItem].self, from: d) else { return [] }
            return v
        }
        set { Cfg.defaults.set(try? JSONEncoder().encode(newValue), forKey: "qhist") }
    }
    static func add(kind: String, chain: String, address: String, title: String) {
        var list = items.filter { !($0.kind == kind && $0.address.lowercased() == address.lowercased()) }
        list.insert(HistoryItem(kind: kind, chain: chain, address: address, title: title, at: Date()), at: 0)
        items = Array(list.prefix(40))
    }
    static func remove(_ id: UUID) { items = items.filter { $0.id != id } }
    static func clear(kind: String) { items = items.filter { $0.kind != kind } }
}

// MARK: - 开发者联系方式（可在设置里自己增删；分享时可选择是否附带）
enum ContactKind: String, Codable, CaseIterable, Identifiable {
    case email, wechat, telegram, x, discord, whatsapp, line, qq, signal, link
    var id: String { rawValue }
    var title: String {
        switch self {
        case .email: return "邮箱"
        case .wechat: return "微信"
        case .telegram: return "Telegram（飞机）"
        case .x: return "X（推特）"
        case .discord: return "Discord"
        case .whatsapp: return "WhatsApp"
        case .line: return "LINE"
        case .qq: return "QQ"
        case .signal: return "Signal"
        case .link: return "其他链接"
        }
    }
    var icon: String {
        switch self {
        case .email: return "envelope"
        case .wechat: return "message"
        case .telegram: return "paperplane"
        case .x: return "at"
        case .discord: return "bubble.left.and.bubble.right"
        case .whatsapp: return "phone.bubble"
        case .line: return "text.bubble"
        case .qq: return "person.2"
        case .signal: return "lock.shield"
        case .link: return "link"
        }
    }
    var placeholder: String {
        switch self {
        case .email: return "name@example.com"
        case .wechat: return "微信号，或名片二维码链接"
        case .telegram: return "用户名（不带 @）"
        case .x: return "用户名（不带 @）"
        case .discord: return "用户名或邀请链接"
        case .whatsapp: return "带区号的手机号，如 8613800000000"
        case .line: return "LINE ID"
        case .qq: return "QQ 号"
        case .signal: return "手机号或 signal.me 链接"
        case .link: return "https://…"
        }
    }
}

struct ContactEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: ContactKind
    var value: String
    var qrLink: String = ""    // 有二维码链接时，分享卡片只显示二维码，不显示账号
    var tagline: String = ""   // 例如「可按需定制」
    var shareLink: String {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .email: return "mailto:" + v
        case .telegram: return "https://t.me/" + v
        case .x: return "https://x.com/" + v
        case .whatsapp: return "https://wa.me/" + v
        case .line: return "https://line.me/ti/p/~" + v
        case .discord, .signal, .link: return v.hasPrefix("http") ? v : ""
        case .wechat: return qrLink.isEmpty ? "" : qrLink
        case .qq: return "mqq://im/chat?chat_type=wpa&uin=" + v + "&version=1&src_type=web"
        }
    }
    // 站内点击时的跳转：优先原生 App，再回落网页
    var openLinks: [String] {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .email: return ["mailto:" + v]
        case .telegram: return ["tg://resolve?domain=" + v, "https://t.me/" + v]
        case .x: return ["twitter://user?screen_name=" + v, "https://x.com/" + v]
        case .whatsapp: return ["whatsapp://send?phone=" + v, "https://wa.me/" + v]
        case .line: return ["https://line.me/ti/p/~" + v]
        case .discord, .signal, .link: return v.hasPrefix("http") ? [v] : []
        case .wechat: return qrLink.isEmpty ? ["weixin://"] : ["weixin://", qrLink]
        case .qq: return ["mqq://im/chat?chat_type=wpa&uin=" + v + "&version=1&src_type=web"]
        }
    }
    // 遮挡后的显示文本，例如 f***@qq.com
    var masked: String {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .email, let at = v.firstIndex(of: "@") {
            let name = String(v[v.startIndex..<at])
            let dom = String(v[at...])
            return String(name.prefix(1)) + "***" + dom
        }
        if v.count <= 2 { return "***" }
        return String(v.prefix(1)) + String(repeating: "*", count: min(6, max(2, v.count - 2))) + String(v.suffix(1))
    }
}

struct ContactSettings: Codable {
    var entries: [ContactEntry]
    var showInShare: Bool = true
    var maskText: Bool = true
    var showQR: Bool = true
    var headline: String = "需要定制、合作或反馈？联系开发者"

    static let defaultValue = ContactSettings(entries: [
        ContactEntry(kind: .email, value: "from_xm@qq.com"),
        ContactEntry(kind: .email, value: "tstzrxm@gmail.com"),
        ContactEntry(kind: .wechat, value: "TSTZ-M", qrLink: "https://u.wechat.com/MH_5bYaNJF6LZ9VEznuZbNQ?s=2"),
        ContactEntry(kind: .telegram, value: "CA_PYBARAS", tagline: "可按需定制"),
    ])
}

enum ContactStore {
    static var settings: ContactSettings {
        get {
            guard let d = Cfg.defaults.data(forKey: "contact"), let v = try? JSONDecoder().decode(ContactSettings.self, from: d) else { return ContactSettings.defaultValue }
            return v
        }
        set { Cfg.defaults.set(try? JSONEncoder().encode(newValue), forKey: "contact") }
    }

    static func qrImage(_ text: String, size: CGFloat = 240) -> UIImage? {
        let ctx = CIContext()
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let scale = size / out.extent.width
        let img = out.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = ctx.createCGImage(img, from: img.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // 分享文本里的联系入口：只放遮挡后的文字和一个可点击的跳转页，不暴露完整账号
    static func contactPageLink(_ s: ContactSettings) -> String {
        var payload: [String: Any] = [:]
        payload["h"] = s.headline
        payload["e"] = s.entries.map { ["k": $0.kind.rawValue, "v": $0.value, "q": $0.qrLink, "t": $0.tagline] }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return "" }
        let b64 = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "https://frommhy-prog.github.io/tugou-hanshuang-jiaoben-app/c.html#" + b64
    }

    static func open(_ e: ContactEntry) {
        Task { @MainActor in
            for s in e.openLinks {
                guard let u = URL(string: s) else { continue }
                if await UIApplication.shared.open(u) { return }
            }
            if e.kind == .wechat { UIPasteboard.general.string = e.value }
        }
    }
}

// MARK: - 设置页：联系方式与分享
struct ContactSettingsView: View {
    @State private var s = ContactStore.settings
    @State private var adding = false

    var body: some View {
        Form {
            Section("分享时附带开发者信息") {
                Toggle("在分享内容里展示联系方式", isOn: Binding(get: { s.showInShare }, set: { s.showInShare = $0; save() }))
                Toggle("遮挡账号文字（只显示 f***@qq.com 样式）", isOn: Binding(get: { s.maskText }, set: { s.maskText = $0; save() }))
                Toggle("有二维码的平台只显示二维码", isOn: Binding(get: { s.showQR }, set: { s.showQR = $0; save() }))
                TextField("引导语", text: Binding(get: { s.headline }, set: { s.headline = $0; save() }))
                Text("遮挡只影响分享图片和文字里的显示；别人点分享文字里的链接，会打开一个联系页，可直接发邮件或跳转到对话。").font(.caption).foregroundStyle(.secondary)
            }
            Section("联系方式（可自己增删）") {
                ForEach($s.entries) { $e in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: e.kind.icon).foregroundStyle(.secondary)
                            Picker("", selection: $e.kind) {
                                ForEach(ContactKind.allCases) { k in Text(k.title).tag(k) }
                            }
                            .labelsHidden()
                            Spacer()
                            Button { ContactStore.open(e) } label: { Text("试跳转").font(.caption.weight(.semibold)) }.buttonStyle(.bordered).controlSize(.mini)
                        }
                        TextField(e.kind.placeholder, text: $e.value)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if e.kind == .wechat || e.kind == .telegram || e.kind == .signal {
                            TextField("二维码链接（选填，有则分享时只显示二维码）", text: $e.qrLink)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.footnote)
                        }
                        TextField("备注字样（例如：可按需定制）", text: $e.tagline).font(.footnote)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { idx in s.entries.remove(atOffsets: idx); save() }
                Button { s.entries.append(ContactEntry(kind: .email, value: "")); save() } label: { Label("添加联系方式", systemImage: "plus.circle") }
            }
            Section("预览") {
                ContactFooter(settings: s, compact: false)
            }
        }
        .navigationTitle("联系方式与分享")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: s.entries) { _, _ in save() }
    }

    private func save() { ContactStore.settings = s }
}

// MARK: - 联系方式展示块（分享卡片和预览共用）
struct ContactFooter: View {
    let settings: ContactSettings
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(settings.headline).font(.footnote.weight(.semibold))
            let qrs = settings.entries.filter { settings.showQR && !$0.qrLink.isEmpty }
            let texts = settings.entries.filter { !($0.qrLink.isEmpty == false && settings.showQR) && !$0.value.isEmpty }
            if !qrs.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(qrs) { e in
                        VStack(spacing: 4) {
                            if let img = ContactStore.qrImage(e.kind == .telegram && e.qrLink.isEmpty ? "https://t.me/" + e.value : e.qrLink, size: compact ? 110 : 140) {
                                Image(uiImage: img).interpolation(.none).resizable().frame(width: compact ? 74 : 92, height: compact ? 74 : 92)
                            }
                            Text(e.kind.title).font(.caption2).foregroundStyle(.secondary)
                            if !e.tagline.isEmpty { Text(e.tagline).font(.caption2.weight(.semibold)) }
                        }
                    }
                }
            }
            ForEach(texts) { e in
                HStack(spacing: 6) {
                    Image(systemName: e.kind.icon).font(.caption)
                    Text(settings.maskText ? e.masked : e.value).font(.caption.monospaced())
                    if !e.tagline.isEmpty { Text(e.tagline).font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor) }
                    Spacer()
                    Button { ContactStore.open(e) } label: { Image(systemName: "arrow.up.right.circle") }.buttonStyle(.plain)
                }
            }
        }
    }
}
