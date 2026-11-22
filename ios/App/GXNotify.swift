import SwiftUI
import UIKit
import UserNotifications
import BackgroundTasks

// MARK: - 打开代币页：通知点击、tstzm:// 链接、雷达列表统一走这里
enum GXOpen {
    @MainActor
    static func token(chain: String?, address: String) {
        UTokenVM.shared.start(address)
        AppRouter.shared.tab = 0
        NotificationCenter.default.post(name: .gmCloseDash, object: nil)
    }
}

// MARK: - 本机通知（App 自己发的，图标和名字都是 TSTZ-M；点击直接进代币页）
final class GXNoteDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = GXNoteDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let addr: String = (info["address"] as? String) ?? ""
        let chain: String? = info["chain"] as? String
        if !addr.isEmpty {
            Task { @MainActor in GXOpen.token(chain: chain, address: addr) }
        }
        completionHandler()
    }
}

enum GXNote {
    static func boot() {
        let c = UNUserNotificationCenter.current()
        c.delegate = GXNoteDelegate.shared
        c.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        GXBG.register()
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in GXBG.schedule() }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in GXHits.shared.start() }
        }
    }

    static func post(title: String, body: String, chain: String?, address: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.threadIdentifier = "tstzm"
        c.userInfo = ["chain": chain ?? "", "address": address]
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}

// MARK: - 后台刷新：系统不定时唤醒，唤醒时补发错过的命中（免费账号没有 APNs，做不到秒级）
enum GXBG {
    static let id: String = "com.Hao-Yi-Miao.TSTZ-M.refresh"

    static func register() {
        guard let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String], ids.contains(id) else { return }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            GXBG.schedule()
            let work = Task { @MainActor in
                await GXHits.shared.sync()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        guard let ids = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String], ids.contains(id) else { return }
        let r = BGAppRefreshTaskRequest(identifier: id)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }
}

// MARK: - 服务器命中记录（自动找币 / 提醒触发 / 盯钱包）→ 本机通知
struct GXHit: Decodable, Identifiable {
    var id: Int
    var at: Double?
    var kind: String?
    var chain: String?
    var token: String?
    var sym: String?
    var msg: String?
}

struct GXHitResp: Decodable {
    var hits: [GXHit]
}

@MainActor
final class GXHits: ObservableObject {
    static let shared = GXHits()
    @Published var recent: [GXHit] = []
    private var loop: Task<Void, Never>?

    func start() {
        if loop != nil { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sync()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    func sync() async {
        if Cfg.token.isEmpty { return }
        let d = Cfg.defaults
        if !d.bool(forKey: "gxHitInit") {
            // 第一次只记下当前位置，不把历史命中一次性全弹出来
            if let r: GXHitResp = try? await API.get("/v1/scan/hits") {
                d.set(r.hits.map { $0.id }.max() ?? 0, forKey: "gxHitLast")
                d.set(true, forKey: "gxHitInit")
                recent = r.hits
            }
            return
        }
        let last: Int = d.integer(forKey: "gxHitLast")
        guard let r: GXHitResp = try? await API.get("/v1/scan/hits", ["since": String(last)]) else { return }
        let localOn: Bool = (d.object(forKey: "alertCh.local") as? Bool) != false
        var top: Int = last
        for h in r.hits {
            top = max(top, h.id)
            if !localOn { continue }
            let k: String = h.kind ?? ""
            if k == "token" || k == "alert" || k == "watch" {
                let ch: Chain? = Chain(rawValue: h.chain ?? "")
                let sym: String = h.sym ?? ""
                let title: String = sym.isEmpty ? (ch?.title ?? "TSTZ-M") : sym + " · " + (ch?.title ?? "")
                GXNote.post(title: title, body: h.msg ?? "", chain: h.chain, address: h.token ?? "")
            }
        }
        d.set(top, forKey: "gxHitLast")
        if !r.hits.isEmpty { recent = Array((Array(r.hits.reversed()) + recent).prefix(60)) }
    }
}
