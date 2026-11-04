import SwiftUI

// 各块数据的更新时间：旧数据照样显示，并标注它是什么时候的
struct Stamps: Codable {
    var pairs: Date?
    var trades: Date?
    var holders: Date?
    var analyses: Date?
    var security: Date?
    var ai: Date?
}

struct TokenSnapshot: Codable {
    var address: String
    var chain: String
    var pairs: [DexPair]
    var trades: [UTrade]
    var holders: [UHolder]
    var conc: Conc?
    var holderNote: String?
    var holderFindings: [Finding]
    var holderComplete: Bool
    var authorities: TokAuth?
    var analyses: [String: UHolderAnalysis]
    var security: TokenResponse?
    var ai: AIResult?
    var stamps: Stamps
    var savedAt: Date
}

// 本地落盘：切换页面、杀掉 App 再打开，查询结果都还在（最近 12 个代币）
enum TokenStore {
    private static let dir: URL = {
        let b = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TSTZM", isDirectory: true)
        try? FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        return b
    }()

    private static func url(_ addr: String) -> URL {
        let a = Addr.isEVM(addr) ? addr.lowercased() : addr
        let safe = a.filter { $0.isLetter || $0.isNumber }
        return dir.appendingPathComponent("snap-" + safe + ".json")
    }

    static func save(_ s: TokenSnapshot) {
        guard let d = try? JSONEncoder().encode(s) else { return }
        let u = url(s.address)
        DispatchQueue.global(qos: .utility).async {
            try? d.write(to: u, options: .atomic)
            prune()
        }
    }

    static func load(_ addr: String) -> TokenSnapshot? {
        guard let d = try? Data(contentsOf: url(addr)) else { return nil }
        return try? JSONDecoder().decode(TokenSnapshot.self, from: d)
    }

    // 控制台/仪表盘用：已缓存的代币列表
    static func list() -> [TokenSnapshot] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var out: [TokenSnapshot] = []
        for u in items where u.lastPathComponent.hasPrefix("snap-") {
            if let d = try? Data(contentsOf: u), let s = try? JSONDecoder().decode(TokenSnapshot.self, from: d) { out.append(s) }
        }
        return out.sorted { $0.savedAt > $1.savedAt }
    }

    static func clearAll() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for u in items { try? fm.removeItem(at: u) }
    }

    private static func prune() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let snaps = items.filter { $0.lastPathComponent.hasPrefix("snap-") }
        if snaps.count <= 12 { return }
        func mod(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast }
        let sorted = snaps.sorted { mod($0) > mod($1) }
        for u in sorted.dropFirst(12) { try? fm.removeItem(at: u) }
    }
}

// K 线本地缓存：再次打开立刻有图，再补最新一页
enum KLineCache {
    private static var lastSave: [String: Date] = [:]
    private static let dir: URL = {
        let b = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TSTZM", isDirectory: true)
        try? FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        return b
    }()

    private static func file(_ key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return dir.appendingPathComponent("k-" + safe + ".json")
    }

    static func load(_ key: String) -> [Candle] {
        guard let d = try? Data(contentsOf: file(key)), let rows = try? JSONDecoder().decode([[Double]].self, from: d) else { return [] }
        return rows.compactMap { r in r.count >= 6 ? Candle(t: r[0], o: r[1], h: r[2], l: r[3], c: r[4], v: r[5]) : nil }
    }

    static func save(key: String, _ cs: [Candle]) {
        if cs.count < 5 { return }
        if let t = lastSave[key], Date().timeIntervalSince(t) < 8 { return }
        lastSave[key] = Date()
        let rows: [[Double]] = cs.suffix(3000).map { [$0.t, $0.o, $0.h, $0.l, $0.c, $0.v] }
        let u = file(key)
        DispatchQueue.global(qos: .utility).async {
            if let d = try? JSONEncoder().encode(rows) { try? d.write(to: u, options: .atomic) }
        }
    }
}

// 一次请求同时拿到「在哪条链 + 所有池子」，省掉原来的两次串行请求
extension MarketAPI {
    static func resolve(_ addr: String) async throws -> (Chain, [DexPair]) {
        if Addr.isSolana(addr) && !Addr.isEVM(addr) {
            return (.solana, try await pairs(.solana, addr))
        }
        if let url = URL(string: "https://api.dexscreener.com/latest/dex/search?q=" + addr) {
            var req = URLRequest(url: url, timeoutInterval: 20)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            if let r = try? await Net.fetch(req), let code = (r.1 as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) {
                struct Resp: Decodable { var pairs: [DexPair]? }
                if let all = (try? JSONDecoder().decode(Resp.self, from: r.0))?.pairs {
                    let key = addr.lowercased()
                    let mine = all.filter { ($0.baseToken?.address ?? "").lowercased() == key }
                    var score: [Chain: Double] = [:]
                    for p in mine {
                        if let cid = p.chainId, let ch = Chain.fromDex(cid) { score[ch, default: 0] += p.liq + 1 }
                    }
                    if let best = score.max(by: { $0.value < $1.value })?.key {
                        let ps = mine.filter { Chain.fromDex($0.chainId ?? "") == best }.sorted { $0.liq > $1.liq }
                        if !ps.isEmpty { return (best, ps) }
                    }
                }
            }
        }
        let c = await detect(addr) ?? .bsc
        return (c, try await pairs(c, addr))
    }
}
