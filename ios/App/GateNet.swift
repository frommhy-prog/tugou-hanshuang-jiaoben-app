import Foundation

// 全局限流网关：注册成 URLProtocol 后，URLSession.shared 发出的行情类请求会自动
// 1) 同域名按间隔排队，前台请求排在后台请求前面；2) 相同请求合并成一次；3) 短时间内重复请求走缓存（404 也短缓存）；
// 4) 429 / Cloudflare 1015 后整个域名冷却，按 Retry-After 自动重试；5) 重试仍失败时回退到最近一次成功的缓存（响应头 X-Gate-Stale: 1），不再直接报错。
// 只拦截 GET；图片 CDN（dd.dexscreener.com 等）不限流。
struct GateRule {
    var interval: Double
    var ttl: Double
    var stale: Double
}

enum GateRules {
    static func rule(host h0: String, path p: String) -> GateRule? {
        let h: String = h0.lowercased()
        if h == "api.geckoterminal.com" {
            if p.contains("/ohlcv/") { return GateRule(interval: 2.2, ttl: 8, stale: 1800) }
            if p.contains("/trades") { return GateRule(interval: 2.2, ttl: 10, stale: 600) }
            if p.hasSuffix("/info") { return GateRule(interval: 2.2, ttl: 900, stale: 86400) }
            return GateRule(interval: 2.2, ttl: 30, stale: 1800)
        }
        if h == "api.dexscreener.com" {
            if p.contains("/token-profiles") || p.contains("/token-boosts") || p.contains("/community-takeovers") || p.contains("/ads") || p.contains("/orders") || p.contains("/metas") {
                return GateRule(interval: 1.1, ttl: 30, stale: 600)
            }
            if p.contains("/dex/pairs/") { return GateRule(interval: 0.22, ttl: 2.5, stale: 120) }
            return GateRule(interval: 0.22, ttl: 6, stale: 300)
        }
        if h == "api.coingecko.com" { return GateRule(interval: 4.0, ttl: 60, stale: 3600) }
        if h == "api.gopluslabs.io" { return GateRule(interval: 1.2, ttl: 180, stale: 7200) }
        if h == "api.rugcheck.xyz" { return GateRule(interval: 1.0, ttl: 120, stale: 3600) }
        if h == "api.honeypot.is" { return GateRule(interval: 1.0, ttl: 120, stale: 3600) }
        if h == "lite-api.jup.ag" || h == "api.jup.ag" || h == "price.jup.ag" { return GateRule(interval: 2.1, ttl: 15, stale: 300) }
        if h.hasSuffix("blockscout.com") { return GateRule(interval: 0.5, ttl: 30, stale: 600) }
        return nil
    }
}

final class GateCore: @unchecked Sendable {
    static let shared = GateCore()

    struct Entry {
        var at: Double
        var code: Int
        var headers: [String: String]
        var body: Data
        var stale: Bool = false
    }

    typealias Done = (Entry?, Error?) -> Void

    private struct Waiter {
        let id: Int
        let done: Done
    }

    private struct Job {
        let key: String
        let req: URLRequest
        let rule: GateRule
        var tries: Int
        let low: Bool
        let deadline: Double
    }

    private let q = DispatchQueue(label: "tstzm.gate")
    private var cache: [String: Entry] = [:]
    private var waiters: [String: [Waiter]] = [:]
    private var queues: [String: [Job]] = [:]
    private var nextAt: [String: Double] = [:]
    private var cool: [String: Double] = [:]
    private var pumping: Set<String> = []
    private var seq: Int = 0
    private let session: URLSession

    private init() {
        let c = URLSessionConfiguration.default
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = 25
        c.timeoutIntervalForResource = 60
        c.httpMaximumConnectionsPerHost = 6
        c.protocolClasses = []
        session = URLSession(configuration: c)
    }

    @discardableResult
    func submit(_ req: URLRequest, key: String, rule: GateRule, fresh: Bool, low: Bool, done: @escaping Done) -> Int {
        var id: Int = 0
        q.sync {
            seq += 1
            id = seq
        }
        let myId: Int = id
        q.async {
            let now: Double = Date().timeIntervalSince1970
            if !fresh, let e = self.cache[key] {
                let ttl: Double = e.code == 404 ? min(rule.ttl, 60) : rule.ttl
                if now - e.at < ttl {
                    done(e, nil)
                    return
                }
            }
            if self.waiters[key] != nil {
                self.waiters[key]?.append(Waiter(id: myId, done: done))
                return
            }
            self.waiters[key] = [Waiter(id: myId, done: done)]
            let host: String = req.url?.host?.lowercased() ?? ""
            let job = Job(key: key, req: req, rule: rule, tries: 0, low: low, deadline: now + 40)
            self.enqueue(job, host: host, front: false)
        }
        return myId
    }

    // 没有任何排队 / 在途的网关请求 = 空闲（今日雷达只在空闲时自动扫描）
    func idle() -> Bool {
        return q.sync { waiters.isEmpty }
    }

    func cancel(key: String, id: Int) {
        q.async {
            guard var ws = self.waiters[key] else { return }
            ws.removeAll { $0.id == id }
            if ws.isEmpty {
                self.waiters.removeValue(forKey: key)
            } else {
                self.waiters[key] = ws
            }
        }
    }

    private func enqueue(_ job: Job, host: String, front: Bool) {
        var list: [Job] = queues[host] ?? []
        if front {
            list.insert(job, at: 0)
        } else if job.low {
            list.append(job)
        } else {
            var i: Int = list.count
            while i > 0 && list[i - 1].low { i -= 1 }
            list.insert(job, at: i)
        }
        queues[host] = list
        pump(host)
    }

    private func pump(_ host: String) {
        if pumping.contains(host) { return }
        guard var list = queues[host], !list.isEmpty else { return }
        let job: Job = list.removeFirst()
        queues[host] = list
        pumping.insert(host)
        let now: Double = Date().timeIntervalSince1970
        let at: Double = max(now, max(nextAt[host] ?? 0, cool[host] ?? 0))
        nextAt[host] = at + job.rule.interval
        let delay: Double = max(0, at - now)
        q.asyncAfter(deadline: .now() + delay) { self.fire(job, host: host) }
    }

    private func fire(_ job: Job, host: String) {
        pumping.remove(host)
        let now: Double = Date().timeIntervalSince1970
        if let c = cool[host], now < c {
            var list: [Job] = queues[host] ?? []
            list.insert(job, at: 0)
            queues[host] = list
            nextAt[host] = max(nextAt[host] ?? 0, c)
            pump(host)
            return
        }
        pump(host)
        guard waiters[job.key] != nil else { return }
        if now > job.deadline {
            giveUp(job, nil, now)
            return
        }
        GMUsage.shared.hit(GMUsage.provider(host: host) ?? host) // 真实发出的请求才计数（命中缓存 / 合并的重复请求不算）
        let task = session.dataTask(with: job.req) { [weak self] data, resp, err in
            guard let self = self else { return }
            self.q.async { self.finish(job, host: host, data: data, resp: resp, err: err) }
        }
        task.resume()
    }

    private func finish(_ job: Job, host: String, data: Data?, resp: URLResponse?, err: Error?) {
        let now: Double = Date().timeIntervalSince1970
        guard waiters[job.key] != nil else { return }
        if let http = resp as? HTTPURLResponse, err == nil {
            let code: Int = http.statusCode
            var text: String = ""
            if code == 403 || code == 503, let d = data { text = String(decoding: d.prefix(300), as: UTF8.self) }
            let ra: String? = http.value(forHTTPHeaderField: "Retry-After")
            let limited: Bool = code == 429 || (code == 403 && text.contains("1015")) || (code == 503 && ra != nil)
            if limited {
                var wait: Double = Double(ra ?? "") ?? 0
                if wait <= 0 { wait = min(45, 5 * pow(2.0, Double(job.tries))) }
                wait = min(wait, 90)
                cool[host] = max(cool[host] ?? 0, now + wait)
                if job.tries < 2 && now + wait < job.deadline {
                    var j: Job = job
                    j.tries += 1
                    enqueue(j, host: host, front: true)
                    return
                }
                if let e = cache[job.key], now - e.at < job.rule.stale {
                    var s: Entry = e
                    s.stale = true
                    deliver(job.key, entry: s, error: nil)
                } else {
                    deliver(job.key, entry: makeEntry(http, data, now), error: nil)
                }
                return
            }
            if code >= 500, let e = cache[job.key], now - e.at < job.rule.stale {
                var s: Entry = e
                s.stale = true
                deliver(job.key, entry: s, error: nil)
                return
            }
            let ent: Entry = makeEntry(http, data, now)
            if (200..<300).contains(code) || code == 404 { store(job.key, ent) }
            deliver(job.key, entry: ent, error: nil)
            return
        }
        if job.tries < 1 {
            var j: Job = job
            j.tries += 1
            enqueue(j, host: host, front: true)
            return
        }
        giveUp(job, err, now)
    }

    private func giveUp(_ job: Job, _ err: Error?, _ now: Double) {
        if let e = cache[job.key], now - e.at < job.rule.stale {
            var s: Entry = e
            s.stale = true
            deliver(job.key, entry: s, error: nil)
        } else {
            deliver(job.key, entry: nil, error: err ?? URLError(.timedOut))
        }
    }

    private func makeEntry(_ http: HTTPURLResponse, _ data: Data?, _ now: Double) -> Entry {
        var h: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            guard let ks = k as? String, let vs = v as? String else { continue }
            let l: String = ks.lowercased()
            if l == "content-encoding" || l == "content-length" || l == "transfer-encoding" { continue }
            h[ks] = vs
        }
        return Entry(at: now, code: http.statusCode, headers: h, body: data ?? Data(), stale: false)
    }

    private func store(_ key: String, _ e: Entry) {
        if e.body.count > 2_000_000 { return }
        cache[key] = e
        if cache.count > 300 {
            let old = cache.sorted { $0.value.at < $1.value.at }.prefix(100)
            for (k, _) in old { cache.removeValue(forKey: k) }
        }
    }

    private func deliver(_ key: String, entry: Entry?, error: Error?) {
        let ws: [Waiter] = waiters.removeValue(forKey: key) ?? []
        for w in ws { w.done(entry, error) }
    }
}

final class GateProtocol: URLProtocol {
    private static let mark = "tstzm.gate.pass"
    private var gateKey: String = ""
    private var gateId: Int = 0

    override class func canInit(with request: URLRequest) -> Bool {
        guard let u = request.url, let h = u.host else { return false }
        if (request.httpMethod ?? "GET").uppercased() != "GET" { return false }
        if URLProtocol.property(forKey: mark, in: request) != nil { return false }
        return GateRules.rule(host: h, path: u.path) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let rule = GateRules.rule(host: url.host ?? "", path: url.path) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let key: String = url.absoluteString
        let pol = request.cachePolicy
        let fresh: Bool = pol == .reloadIgnoringLocalCacheData || pol == .reloadIgnoringLocalAndRemoteCacheData
        let low: Bool = request.networkServiceType == .background
        let m: NSMutableURLRequest = ((request as NSURLRequest).mutableCopy() as? NSMutableURLRequest) ?? NSMutableURLRequest(url: url)
        URLProtocol.setProperty(true, forKey: GateProtocol.mark, in: m)
        gateKey = key
        gateId = GateCore.shared.submit(m as URLRequest, key: key, rule: rule, fresh: fresh, low: low) { [weak self] entry, error in
            self?.deliver(entry, error, url)
        }
    }

    private func deliver(_ e: GateCore.Entry?, _ err: Error?, _ url: URL) {
        if let e = e {
            var h: [String: String] = e.headers
            if e.stale { h["X-Gate-Stale"] = "1" }
            if let r = HTTPURLResponse(url: url, statusCode: e.code, httpVersion: "HTTP/1.1", headerFields: h) {
                client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: e.body)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
        }
        client?.urlProtocol(self, didFailWithError: err ?? URLError(.cannotLoadFromNetwork))
    }

    override func stopLoading() {
        GateCore.shared.cancel(key: gateKey, id: gateId)
    }
}

enum GateNet {
    static func install() {
        URLProtocol.registerClass(GateProtocol.self)
        // 非网关域名（GMGN / OKX / 你的 Worker）的请求次数在 Net.fetch 层统计；网关域名在网关里按真实发出的请求统计
        Net.onCount = { host, _, _ in
            if GateRules.rule(host: host, path: "/") != nil { return }
            if let p = GMUsage.provider(host: host) { GMUsage.shared.hit(p) }
        }
    }
}
