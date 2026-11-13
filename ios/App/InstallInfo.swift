import SwiftUI

// 安装信息：告诉你手机上这个图标是用哪种方式装的、标识是什么，用来判断有没有多出来的旧副本。
// 规则：SideStore 重签会在标识后面接「.团队ID」，Xcode 调试版现在也按同样的拼法，所以两种方式装的是同一个应用。
enum InstallInfo {
    static let baseID = "com.Hao-Yi-Miao.TSTZ-M"

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "?" }

    // 重签后的标识 = 原标识 + "." + 团队 ID
    static var hasTeamSuffix: Bool {
        bundleID.hasPrefix(baseID + ".") && bundleID.count > baseID.count + 1
    }

    // 签名这个应用的团队 ID：从内嵌的描述文件里读
    static var teamID: String? {
        guard let p = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") else { return nil }
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: p)) else { return nil }
        guard let s = String(data: d, encoding: .isoLatin1) else { return nil }
        guard let a = s.range(of: "<?xml"), let b = s.range(of: "</plist>") else { return nil }
        let xml = String(s[a.lowerBound..<b.upperBound])
        guard let xd = xml.data(using: .utf8) else { return nil }
        guard let o = try? PropertyListSerialization.propertyList(from: xd, options: [], format: nil) as? [String: Any] else { return nil }
        guard let t = o["TeamIdentifier"] as? [String] else { return nil }
        return t.first
    }

    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return v + "（" + b + "）"
    }
}

struct InstallInfoCard: View {
    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.caption).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Text(v).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    var body: some View {
        let ok = InstallInfo.hasTeamSuffix
        let tip: String = ok
            ? "标识带团队后缀：SideStore 安装和 Xcode 直装用的是同一个标识，互相覆盖，不会多出图标。"
            : "标识没有团队后缀：这是旧的 Xcode 直装副本，会和 SideStore 装的那份并存成两个图标。删掉这个图标（长按 → 删除 App），只保留 SideStore 装的。"
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("安装信息", systemImage: "info.circle").font(.headline)
                row("应用标识", InstallInfo.bundleID)
                row("团队 ID", InstallInfo.teamID ?? "未读到")
                row("版本", InstallInfo.version)
                Text(tip).font(.footnote).foregroundStyle(ok ? Color.secondary : Color.orange)
            }
        }
    }
}
