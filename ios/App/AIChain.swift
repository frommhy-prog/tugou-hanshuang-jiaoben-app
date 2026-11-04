import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// AI 轨道：云端（引擎里 Groq 多模型 → 可选后端）→ 苹果设备端模型。两者都不可用时由调用方显示原因；规则分析引擎始终独立并行工作，不依赖 AI。
enum AIChain {
    static func timed<T>(_ sec: Double, _ op: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { g in
            g.addTask { try await op() }
            g.addTask {
                try await Task.sleep(nanoseconds: UInt64(sec * 1_000_000_000))
                throw APIError.network("请求超时（" + String(Int(sec)) + " 秒）")
            }
            guard let r = try await g.next() else { throw APIError.network("没有返回") }
            g.cancelAll()
            return r
        }
    }

    static func run<F: Encodable>(kind: String, facts: F, fresh: Bool) async -> AIResult {
        var reasons: [String] = []
        do {
            let r: AIResult = try await timed(55) { try await Engine.post("/e/v2/ai", AIPayload(kind: kind, facts: facts, fresh: fresh ? true : nil)) }
            if let m = aiMessage(r) { reasons.append(m) } else { return r }
        } catch {
            reasons.append(Net.message(error))
        }
        let note = "云端 AI 不可用：" + reasons.joined(separator: "；")
        var factsText = ""
        if let d = try? JSONEncoder().encode(facts), let s = String(data: d, encoding: .utf8) { factsText = s }
        if let a = await AppleAI.analyze(kind: kind, factsJSON: factsText) {
            return AIResult(analysis: a, model: "苹果设备端模型", provider: "apple", note: note)
        }
        return AIResult(error: "ai_unavailable", detail: reasons.joined(separator: "；"))
    }
}

enum AppleAI {
    static let system = "你是为链上交易员服务的分析师。只依据用户给出的 facts 判断，禁止编造数字，数组里不要放空字符串。只输出 JSON：{\"headline\":\"\",\"stance\":\"偏风险|中性|偏积极|数据不足\",\"points\":[{\"claim\":\"\",\"why\":\"\",\"evidence\":\"\"}],\"risks\":[\"\"],\"watch\":[\"\"],\"unknown\":[\"\"]}。简体中文。"

    static func analyze(kind: String, factsJSON: String) async -> AIAnalysis? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return await FMRunner.run(kind: kind, facts: factsJSON) }
        #endif
        return nil
    }

    static func parse(_ text: String) -> AIAnalysis? {
        guard let i = text.firstIndex(of: "{"), let j = text.lastIndex(of: "}"), i < j else { return nil }
        let s = String(text[i...j])
        guard let d = s.data(using: .utf8), let a = try? JSONDecoder().decode(AIAnalysis.self, from: d), a.isUsable else { return nil }
        return a
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
enum FMRunner {
    static func run(kind: String, facts: String) async -> AIAnalysis? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        let session = LanguageModelSession(instructions: AppleAI.system)
        let prompt = "类型：" + kind + "\nfacts：" + String(facts.prefix(2000))
        do {
            let text: String = try await AIChain.timed(30) {
                let resp = try await session.respond(to: prompt)
                return resp.content
            }
            return AppleAI.parse(text)
        } catch {
            return nil
        }
    }
}
#endif

extension AIStyle {
    static func footnote(_ r: AIResult?) -> String {
        var s = "AI 只解读程序算出的数据，不引入外部信息；不构成投资建议"
        if let m = r?.model, !m.isEmpty { s += " · 模型 " + m }
        if r?.cached == true { s += " · 缓存结果" }
        if let g = r?.generatedAt { s += " · 生成于 " + Date(timeIntervalSince1970: g / 1000).formatted(date: .omitted, time: .standard) }
        if let n = r?.note, !n.isEmpty { s += " · " + n }
        return s
    }
}
