import SwiftUI
import UIKit

// MARK: - MCP 连接器：App 既是客户端（连你自己的交易所/钱包/脚本的 MCP 服务），也自带一个 MCP 服务（给外部助手连）
struct McpServer: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var token: String
}

enum McpStore {
    static var servers: [McpServer] {
        get {
            guard let d = Cfg.defaults.data(forKey: "mcpServers"), let v = try? JSONDecoder().decode([McpServer].self, from: d) else { return [] }
            return v
        }
        set { Cfg.defaults.set(try? JSONEncoder().encode(newValue), forKey: "mcpServers") }
    }
}

struct McpTool: Identifiable, Hashable {
    let name: String
    let desc: String
    let schema: String
    var id: String { name }
}

enum McpError: LocalizedError {
    case bad(String)
    var errorDescription: String? {
        switch self { case .bad(let m): return m }
    }
}

// 无状态/有状态 Streamable HTTP 都支持；响应可以是 JSON 或 SSE
final class McpSession {
    let server: McpServer
    var sessionId: String?
    private var nextId = 1

    init(_ s: McpServer) { server = s }

    private func request(_ body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: server.url) else { throw McpError.bad("连接器地址无效") }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if !server.token.isEmpty { req.setValue("Bearer " + server.token, forHTTPHeaderField: "Authorization") }
        if let s = sessionId { req.setValue(s, forHTTPHeaderField: "Mcp-Session-Id") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let r: (Data, URLResponse)
        do { r = try await Net.fetch(req) } catch { throw McpError.bad("网络失败：" + Net.message(error)) }
        guard let http = r.1 as? HTTPURLResponse else { throw McpError.bad("响应无效") }
        if http.statusCode == 401 || http.statusCode == 403 { throw McpError.bad("连接器拒绝访问（\(http.statusCode)），检查令牌") }
        if !(200..<300).contains(http.statusCode) { throw McpError.bad("连接器返回 \(http.statusCode)") }
        return (r.0, http)
    }

    private func parse(_ data: Data, _ http: HTTPURLResponse, id: Int) throws -> [String: Any] {
        let ct = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if ct.contains("event-stream") {
            let text = String(data: data, encoding: .utf8) ?? ""
            for line in text.components(separatedBy: "\n").reversed() {
                let l = line.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("data:") {
                    let j = String(l.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if let d = j.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], (o["id"] as? Int) == id { return o }
                }
            }
            throw McpError.bad("没有读到响应")
        }
        guard let o = try? JSONSerialization.jsonObject(with: data) else { throw McpError.bad("响应不是 JSON") }
        if let a = o as? [[String: Any]], let f = a.first(where: { ($0["id"] as? Int) == id }) { return f }
        guard let d = o as? [String: Any] else { throw McpError.bad("响应格式异常") }
        return d
    }

    func call(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        let id = nextId
        nextId += 1
        let (data, http) = try await request(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        if let s = http.value(forHTTPHeaderField: "Mcp-Session-Id") { sessionId = s }
        let o = try parse(data, http, id: id)
        if let e = o["error"] as? [String: Any] { throw McpError.bad((e["message"] as? String) ?? "连接器返回错误") }
        return (o["result"] as? [String: Any]) ?? [:]
    }

    func initialize() async throws {
        _ = try await call("initialize", ["protocolVersion": "2025-03-26", "capabilities": [String: Any](), "clientInfo": ["name": "TSTZ-M", "version": "1"]])
        _ = try? await request(["jsonrpc": "2.0", "method": "notifications/initialized"])
    }

    func tools() async throws -> [McpTool] {
        let r = try await call("tools/list")
        let arr = (r["tools"] as? [[String: Any]]) ?? []
        return arr.map { t in
            let schema = (t["inputSchema"]).flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys]) }.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return McpTool(name: (t["name"] as? String) ?? "?", desc: (t["description"] as? String) ?? "", schema: schema)
        }
    }

    func run(_ name: String, args: [String: Any]) async throws -> String {
        let r = try await call("tools/call", ["name": name, "arguments": args])
        let content = (r["content"] as? [[String: Any]]) ?? []
        let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return text.isEmpty ? String(data: (try? JSONSerialization.data(withJSONObject: r, options: [.prettyPrinted])) ?? Data(), encoding: .utf8) ?? "" : text
    }
}

struct ConnectorsView: View {
    @State private var servers = McpStore.servers
    @State private var adding = false
    @State private var copied = false

    private var endpoint: String { Engine.base + "/e/mcp" }
    private var configJSON: String {
        "{\n  \"mcpServers\": {\n    \"tstzm\": {\n      \"url\": \"" + endpoint + "\",\n      \"headers\": { \"Authorization\": \"Bearer 你的令牌\" }\n    }\n  }\n}"
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("本 App 自带 MCP 服务").font(.subheadline.weight(.semibold))
                    Text("让 Claude、Cursor 或你自己的脚本直接调用：钱包分析、代币持有人、大户盈亏拆解、交易所只读持仓。").font(.caption).foregroundStyle(.secondary)
                    Text(endpoint).font(.caption.monospaced()).textSelection(.enabled)
                    HStack {
                        Button("复制地址") { UIPasteboard.general.string = endpoint }.buttonStyle(.bordered).controlSize(.small)
                        Button("复制令牌") { UIPasteboard.general.string = Cfg.token }.buttonStyle(.bordered).controlSize(.small)
                        Button(copied ? "已复制" : "复制配置") { UIPasteboard.general.string = configJSON; copied = true }.buttonStyle(.bordered).controlSize(.small)
                    }
                    Text("认证方式：Authorization: Bearer 你的令牌（令牌就是「设置 → 连接」里那个）。").font(.caption2).foregroundStyle(.secondary)
                }
            } header: { Text("对外：别人连我") }
            Section {
                if servers.isEmpty { Text("还没有连接器。可添加你自己的 MCP 服务（其他交易所、钱包、自动化脚本），App 可列出并调用它的工具。").font(.footnote).foregroundStyle(.secondary) }
                ForEach(servers) { s in
                    NavigationLink { McpServerView(server: s) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.name).font(.subheadline.weight(.semibold))
                            Text(s.url).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
                .onDelete { idx in servers.remove(atOffsets: idx); McpStore.servers = servers }
                Button { adding = true } label: { Label("添加连接器", systemImage: "plus.circle") }
            } header: { Text("对内：我连别人") }
        }
        .navigationTitle("MCP 连接器")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            AddMcpSheet { s in servers.append(s); McpStore.servers = servers }
        }
    }
}

struct AddMcpSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (McpServer) -> Void
    @State private var name = ""
    @State private var url = ""
    @State private var token = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("连接器") {
                    TextField("名称（例如：我的脚本）", text: $name)
                    TextField("MCP 地址 https://…/mcp", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("令牌（可选，作为 Bearer）", text: $token)
                }
                Section { Text("支持 Streamable HTTP 的 MCP 服务（JSON 或 SSE 响应）。令牌只保存在本机。").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("添加连接器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onAdd(McpServer(name: name.isEmpty ? "连接器" : name, url: url.trimmingCharacters(in: .whitespacesAndNewlines), token: token))
                        dismiss()
                    }
                    .disabled(!url.hasPrefix("http"))
                }
            }
        }
    }
}

struct McpServerView: View {
    let server: McpServer
    @State private var tools: [McpTool] = []
    @State private var loading = false
    @State private var error: String?
    @State private var picked: McpTool?
    @State private var session: McpSession?

    var body: some View {
        List {
            Section {
                Button { Task { await connect() } } label: { Label(loading ? "连接中…" : "连接并列出工具", systemImage: "bolt.horizontal") }
                    .disabled(loading)
                if let e = error { Text(e).font(.footnote).foregroundStyle(Color.orange) }
            }
            if !tools.isEmpty {
                Section("工具（\(tools.count)）") {
                    ForEach(tools) { t in
                        Button { picked = t } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                                if !t.desc.isEmpty { Text(t.desc).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $picked) { t in
            if let s = session { McpToolSheet(tool: t, session: s) }
        }
    }

    private func connect() async {
        loading = true
        error = nil
        defer { loading = false }
        let s = McpSession(server)
        do {
            try await s.initialize()
            tools = try await s.tools()
            session = s
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct McpToolSheet: View {
    @Environment(\.dismiss) private var dismiss
    let tool: McpTool
    let session: McpSession
    @State private var argText = "{}"
    @State private var output = ""
    @State private var running = false

    var body: some View {
        NavigationStack {
            Form {
                Section("参数（JSON）") {
                    TextEditor(text: $argText).font(.system(.footnote, design: .monospaced)).frame(minHeight: 100)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    DisclosureGroup("参数说明（inputSchema）") { Text(tool.schema).font(.system(size: 10, design: .monospaced)).textSelection(.enabled) }
                }
                Section {
                    Button { Task { await run() } } label: { Label(running ? "运行中…" : "运行", systemImage: "play.fill") }.disabled(running)
                }
                if !output.isEmpty {
                    Section("结果") {
                        Text(output).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        Button("复制结果") { UIPasteboard.general.string = output }
                    }
                }
            }
            .navigationTitle(tool.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }

    private func run() async {
        running = true
        defer { running = false }
        guard let d = argText.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { output = "参数不是合法的 JSON 对象"; return }
        do { output = String((try await session.run(tool.name, args: o)).prefix(20000)) }
        catch { output = "失败：" + error.localizedDescription }
    }
}
