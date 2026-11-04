import Foundation

// 容错 JSON：模型输出里数组可能混进空字符串、字段形状不一致。把任何 JSON 读成值，再按需取字符串，绝不因一条坏数据让整份结果解码失败。
indirect enum JV: Decodable {
    case null
    case bool(Bool)
    case num(Double)
    case str(String)
    case arr([JV])
    case obj([String: JV])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let n = try? c.decode(Double.self) { self = .num(n); return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let s = try? c.decode(String.self) { self = .str(s); return }
        if let a = try? c.decode([JV].self) { self = .arr(a); return }
        if let o = try? c.decode([String: JV].self) { self = .obj(o); return }
        self = .null
    }

    var text: String? {
        switch self {
        case .str(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case .num(let n):
            if n == n.rounded() && abs(n) < 1e15 { return String(Int(n)) }
            return String(n)
        case .bool(let b):
            return b ? "是" : "否"
        case .arr(let a):
            let p = a.compactMap { $0.text }
            return p.isEmpty ? nil : p.joined(separator: "；")
        case .obj(let o):
            let p = o.keys.sorted().compactMap { o[$0]?.text }
            return p.isEmpty ? nil : p.joined(separator: "：")
        case .null:
            return nil
        }
    }

    var strings: [String] {
        switch self {
        case .arr(let a): return a.compactMap { $0.text }
        case .null: return []
        default:
            if let t = text { return [t] }
            return []
        }
    }

    var object: [String: JV]? {
        if case .obj(let o) = self { return o }
        return nil
    }

    var array: [JV]? {
        if case .arr(let a) = self { return a }
        return nil
    }
}

extension KeyedDecodingContainer {
    func jv(_ key: Key) -> JV {
        if let v = try? decodeIfPresent(JV.self, forKey: key) { return v }
        return .null
    }
}
