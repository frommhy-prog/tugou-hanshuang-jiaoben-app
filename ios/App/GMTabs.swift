import SwiftUI

// MARK: - 代币页分析分页（交易所 / GMGN / Ave 风格：K 线下面一条分页标签，点哪个下面就显示哪个）
struct GMTabDef: Identifiable {
    let id: String
    let title: String
    let icon: String
    let color: Color
}

enum GMTabCatalog {
    static let all: [GMTabDef] = [
        GMTabDef(id: "trade", title: "交易记录", icon: "arrow.left.arrow.right", color: Color.green),
        GMTabDef(id: "wallet", title: "钱包分析", icon: "person.crop.rectangle.stack.fill", color: Color.indigo),
        GMTabDef(id: "holder", title: "持有者", icon: "person.3.fill", color: Color.orange),
        GMTabDef(id: "liq", title: "流动性", icon: "drop.fill", color: Color.cyan),
        GMTabDef(id: "verdict", title: "综合研判", icon: "checkmark.shield.fill", color: Color.blue),
        GMTabDef(id: "risk", title: "合约安全", icon: "lock.shield.fill", color: Color.red),
        GMTabDef(id: "narr", title: "叙事社交", icon: "text.bubble.fill", color: Color.purple),
        GMTabDef(id: "intel", title: "庄家情报", icon: "eye.fill", color: Color.teal),
        GMTabDef(id: "tools", title: "更多工具", icon: "square.grid.2x2.fill", color: Color.gray),
    ]

    static func def(_ id: String) -> GMTabDef? {
        return all.first(where: { $0.id == id })
    }

    static func order(_ s: String) -> [String] {
        var out: [String] = []
        for p in s.split(separator: ",") {
            let id: String = String(p)
            if def(id) != nil && !out.contains(id) { out.append(id) }
        }
        for d in all where !out.contains(d.id) { out.append(d.id) }
        return out
    }
}

@MainActor
final class GMTabState: ObservableObject {
    static let shared = GMTabState()
    @Published var sel: String {
        didSet { Cfg.defaults.set(sel, forKey: "gmTabSel") }
    }

    init() {
        let a: String? = Cfg.defaults.string(forKey: "gmTabSel")
        let b: String? = Cfg.defaults.string(forKey: "gmTabDefault")
        sel = a ?? b ?? "trade"
    }

    // 旧入口（头部叙事标签等）用数字页号打开分页
    func open(_ i: Int) {
        let m: [Int: String] = [0: "verdict", 1: "trade", 2: "holder", 3: "risk", 4: "narr", 5: "intel", 6: "tools"]
        if let id = m[i] { sel = id }
    }
}

struct GMTabsSection<Content: View>: View {
    @ObservedObject var vm: UTokenVM
    var onMonitor: () -> Void
    private let page: (String) -> Content
    @ObservedObject private var st = GMTabState.shared
    @AppStorage("gmTabOrder", store: Cfg.defaults) private var orderStr = ""
    @AppStorage("gmTabHidden", store: Cfg.defaults) private var hiddenStr = ""
    @AppStorage("gmTabStyle", store: Cfg.defaults) private var style = "tabs"
    @AppStorage("gmTabSticky", store: Cfg.defaults) private var sticky = true

    init(vm: UTokenVM, onMonitor: @escaping () -> Void, @ViewBuilder page: @escaping (String) -> Content) {
        self.vm = vm
        self.onMonitor = onMonitor
        self.page = page
    }

    private var tabs: [GMTabDef] {
        let hidden: Set<String> = Set(hiddenStr.split(separator: ",").map { String($0) })
        return GMTabCatalog.order(orderStr).filter { !hidden.contains($0) }.compactMap { GMTabCatalog.def($0) }
    }

    private func strip(_ cur: String) -> some View {
        HStack(spacing: 6) {
            if style == "grid" {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                    ForEach(tabs) { t in
                        Button { st.sel = t.id } label: {
                            VStack(spacing: 4) {
                                Image(systemName: t.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(t.color)
                                    .frame(width: 40, height: 40)
                                    .background(t.color.opacity(cur == t.id ? 0.28 : 0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Text(t.title).font(.caption2.weight(cur == t.id ? .bold : .regular)).foregroundStyle(cur == t.id ? Color.primary : Color.secondary).lineLimit(1).minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                ScrollViewReader { sp in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: style == "capsule" ? 8 : 20) {
                            ForEach(tabs) { t in
                                Button { st.sel = t.id } label: {
                                    if style == "capsule" {
                                        Text(t.title)
                                            .font(.subheadline.weight(cur == t.id ? .bold : .regular))
                                            .padding(.horizontal, 14).padding(.vertical, 7)
                                            .background(cur == t.id ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.1), in: Capsule())
                                            .foregroundStyle(cur == t.id ? Color.accentColor : Color.secondary)
                                    } else {
                                        VStack(spacing: 4) {
                                            HStack(spacing: 4) {
                                                Image(systemName: t.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(cur == t.id ? t.color : Color.secondary)
                                                Text(t.title)
                                                    .font(.subheadline.weight(cur == t.id ? .bold : .regular))
                                                    .foregroundStyle(cur == t.id ? Color.primary : Color.secondary)
                                            }
                                            Capsule().fill(cur == t.id ? Color.accentColor : Color.clear).frame(height: 2.5)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .id(t.id)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .onChange(of: st.sel) { _, v in
                        withAnimation { sp.scrollTo(v, anchor: .center) }
                    }
                }
                Button { onMonitor() } label: {
                    Image(systemName: "bell.badge").font(.subheadline).foregroundStyle(Color.yellow)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 14)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .padding(.horizontal, style == "grid" ? 16 : 0)
        .background(Color.page)
    }

    private func pageView(_ cur: String) -> some View {
        VStack(spacing: 14) { page(cur) }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .id(cur)
    }

    var body: some View {
        let cur: String = tabs.contains(where: { $0.id == st.sel }) ? st.sel : (tabs.first?.id ?? "trade")
        Group {
            if sticky && style != "grid" {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        pageView(cur)
                    } header: {
                        strip(cur)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    strip(cur)
                    pageView(cur)
                }
            }
        }
        .onChange(of: vm.main?.price) { _, _ in GMTrend.record(vm) }
    }
}

// MARK: - 设置：分页显示方式 / 排序 / 默认页
struct GMTabEditor: View {
    @AppStorage("gmTabOrder", store: Cfg.defaults) private var orderStr = ""
    @AppStorage("gmTabHidden", store: Cfg.defaults) private var hiddenStr = ""
    @Environment(\.dismiss) private var dismiss

    private var ids: [String] { GMTabCatalog.order(orderStr) }
    private var hidden: Set<String> { Set(hiddenStr.split(separator: ",").map { String($0) }) }

    private func setHidden(_ id: String, _ off: Bool) {
        var h: Set<String> = hidden
        if off { h.insert(id) } else { h.remove(id) }
        hiddenStr = h.sorted().joined(separator: ",")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ids, id: \.self) { id in
                        if let d = GMTabCatalog.def(id) {
                            HStack(spacing: 10) {
                                Image(systemName: d.icon).foregroundStyle(d.color).frame(width: 24)
                                Text(d.title)
                                Spacer()
                                Toggle("", isOn: Binding(get: { !hidden.contains(id) }, set: { setHidden(id, !$0) })).labelsHidden()
                            }
                        }
                    }
                    .onMove { from, to in
                        var a: [String] = ids
                        a.move(fromOffsets: from, toOffset: to)
                        orderStr = a.joined(separator: ",")
                    }
                } footer: {
                    Text("按住右侧拖动排序；开关关掉的分页不显示。至少保留一个。")
                }
                Section {
                    Button("恢复默认排序和显示") {
                        orderStr = ""
                        hiddenStr = ""
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("分页排序与显示")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
    }
}

struct GMTabSettings: View {
    @AppStorage("gmTabStyle", store: Cfg.defaults) private var style = "tabs"
    @AppStorage("gmTabSticky", store: Cfg.defaults) private var sticky = true
    @AppStorage("gmTabDefault", store: Cfg.defaults) private var def = "trade"
    @State private var edit = false

    var body: some View {
        Section("代币页分析分页") {
            Picker("显示方式", selection: $style) {
                Text("标签栏").tag("tabs")
                Text("胶囊").tag("capsule")
                Text("宫格").tag("grid")
            }
            .pickerStyle(.segmented)
            Toggle("标签栏吸顶（上滑时固定在顶部）", isOn: $sticky).disabled(style == "grid")
            Picker("默认打开", selection: $def) {
                ForEach(GMTabCatalog.all) { d in Text(d.title).tag(d.id) }
            }
            .onChange(of: def) { _, v in GMTabState.shared.sel = v }
            Button("排序与显示…") { edit = true }
                    }
        .sheet(isPresented: $edit) { GMTabEditor() }
    }
}
