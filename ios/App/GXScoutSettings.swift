import SwiftUI
import UIKit

// MARK: - 自动找币 / 找钱包 参数：链、币（市值档）、阶段、发射台、钱包类型，全部用图标选择
struct GXScanCfg: Codable {
    var on: Bool?
    var intervalMin: Double?
    var chains: [String]?
    var minLiq: Double?
    var maxLiq: Double?
    var minVol24: Double?
    var minMcap: Double?
    var maxMcap: Double?
    var minAgeMin: Double?
    var maxAgeH: Double?
    var minTx1h: Double?
    var minBuyPct1h: Double?
    var maxPerRun: Double?
    var cooldownH: Double?
    var stages: [String]?
    var pads: [String]?
    var walletOn: Bool?
    var walletMinNet: Double?
    var wKinds: [String]?
}

struct GXScanResp: Codable {
    var cfg: GXScanCfg
}

struct GXScanRun: Codable {
    var candidates: Int?
    var matched: Int?
}

@MainActor
final class GXScanVM: ObservableObject {
    @Published var cfg = GXScanCfg()
    @Published var last: GXScanRun?
    @Published var running: Bool = false
    @Published var hits: [GXHit] = []
    private var saveTask: Task<Void, Never>?

    func load() async {
        if let r: GXScanResp = try? await API.get("/v1/scan/config") { cfg = r.cfg }
        if let h: GXHitResp = try? await API.get("/v1/scan/hits") { hits = h.hits }
    }

    func edit(_ f: (inout GXScanCfg) -> Void) {
        f(&cfg)
        saveTask?.cancel()
        let c: GXScanCfg = cfg
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            let _: API.Empty? = try? await API.post("/v1/scan/config", c, method: "PUT")
        }
    }

    func dry() async {
        running = true
        defer { running = false }
        last = try? await API.get("/v1/scan/run", ["dry": "1"])
    }
}

struct GXScoutSettingsView: View {
    @StateObject private var vm = GXScanVM()

    private let chains: [Chain] = [.solana, .bsc, .base, .eth, .robinhood, .arbitrum, .optimism, .polygon, .xlayer]
    private let pads: [GMLaunchpad] = [.pump, .fourMeme, .flap, .bonk, .moonshot, .clanker, .virtuals, .bags, .believe, .boop, .heaven, .launchLab, .jupStudio, .daos, .zora, .pons]
    private let stages: [(String, String, String, Color)] = [
        ("inner", "内盘", "flame.fill", Color.orange),
        ("outer", "外盘", "graduationcap.fill", Color.green),
        ("new", "新池", "sparkles", Color.yellow),
        ("hot", "热门", "chart.line.uptrend.xyaxis", Color.red),
    ]
    private let tiers: [(String, String, Double, Double)] = [
        ("全部", "infinity", 0, 0),
        ("微型", "smallcircle.filled.circle", 0, 100_000),
        ("小型", "circle.circle", 100_000, 1_000_000),
        ("中型", "circle.fill", 1_000_000, 10_000_000),
        ("大型", "largecircle.fill.circle", 10_000_000, 0),
    ]
    private let kinds: [(String, String, String, Color)] = [
        ("big", "大额", "dollarsign.circle.fill", Color.green),
        ("smart", "聪明钱", "brain.head.profile", Color.purple),
        ("sniper", "狙击", "scope", Color.red),
    ]
    private let cols = [GridItem(.adaptive(minimum: 64), spacing: 8)]

    private func has(_ a: [String]?, _ k: String) -> Bool { (a ?? []).contains(k) }

    private func toggled(_ a: [String]?, _ k: String) -> [String] {
        var x: [String] = a ?? []
        if let i = x.firstIndex(of: k) { x.remove(at: i) } else { x.append(k) }
        return x
    }

    private func chipBox<Content: View>(_ on: Bool, _ tap: @escaping () -> Void, @ViewBuilder _ content: () -> Content) -> some View {
        Button(action: tap) {
            content()
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(on ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.1), in: Capsule())
                .overlay(Capsule().stroke(on ? Color.accentColor : Color.clear, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }

    private func money(_ v: Double) -> String {
        if v >= 1_000_000 { return "$" + String(format: "%g", v / 1_000_000) + "M" }
        if v >= 1_000 { return "$" + String(format: "%g", v / 1_000) + "K" }
        return "$" + String(format: "%g", v)
    }

    private func menu(_ icon: String, _ values: [Double], _ cur: Double?, _ fmt: @escaping (Double) -> String, _ set: @escaping (Double) -> Void) -> some View {
        var vals: [Double] = values
        if let c = cur, !vals.contains(c) {
            vals.append(c)
            vals.sort()
        }
        let sel: Double = cur ?? values[0]
        return HStack {
            Image(systemName: icon).frame(width: 26)
            Spacer()
            Picker("", selection: Binding(get: { sel }, set: { v in set(v) })) {
                ForEach(vals, id: \.self) { v in Text(fmt(v)).tag(v) }
            }
            .pickerStyle(.menu)
        }
    }

    private func tierOn(_ t: (String, String, Double, Double)) -> Bool {
        (vm.cfg.minMcap ?? 0) == t.2 && (vm.cfg.maxMcap ?? 0) == t.3
    }

    private func kindIcon(_ k: String) -> (String, Color) {
        switch k {
        case "big": return ("dollarsign.circle.fill", Color.green)
        case "smart": return ("brain.head.profile", Color.purple)
        case "sniper": return ("scope", Color.red)
        default: return ("questionmark.circle", Color.secondary)
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { vm.cfg.on ?? true }, set: { v in vm.edit { $0.on = v } })) {
                    Image(systemName: "power")
                }
                HStack {
                    Button { Task { await vm.dry() } } label: { Image(systemName: "play.fill") }
                    if vm.running { ProgressView() }
                    Spacer()
                    if let r = vm.last {
                        Label(String(r.candidates ?? 0), systemImage: "magnifyingglass")
                        Label(String(r.matched ?? 0), systemImage: "checkmark.seal.fill").foregroundStyle(Color.green)
                    }
                }
            }
            Section {
                LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                    ForEach(chains) { c in
                        chipBox(has(vm.cfg.chains, c.rawValue), { vm.edit { $0.chains = toggled($0.chains, c.rawValue) } }) {
                            AvChainBadge(chain: c, size: 22)
                        }
                    }
                }
            } header: { Image(systemName: "link") }
            Section {
                LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                    ForEach(stages, id: \.0) { s in
                        chipBox(has(vm.cfg.stages, s.0), { vm.edit { $0.stages = toggled($0.stages, s.0) } }) {
                            HStack(spacing: 4) {
                                Image(systemName: s.2).foregroundStyle(s.3)
                                Text(s.1).font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
            } header: { Image(systemName: "flag.checkered") }
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(0..<pads.count, id: \.self) { i in
                        let key: String = "\(pads[i])"
                        chipBox(has(vm.cfg.pads, key), { vm.edit { $0.pads = toggled($0.pads, key) } }) {
                            GMLaunchLogo(pad: pads[i], size: 22).frame(width: 22, height: 22).clipShape(Circle())
                        }
                    }
                }
            } header: { Image(systemName: "rocket.fill") }
            Section {
                LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                    ForEach(0..<tiers.count, id: \.self) { i in
                        let t = tiers[i]
                        chipBox(tierOn(t), { vm.edit { $0.minMcap = t.2; $0.maxMcap = t.3 } }) {
                            HStack(spacing: 4) {
                                Image(systemName: t.1)
                                Text(t.0).font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
                menu("drop.fill", [0, 3000, 8000, 20000, 50000, 100000, 300000], vm.cfg.minLiq, { $0 == 0 ? "—" : money($0) }) { v in vm.edit { $0.minLiq = v } }
                menu("chart.bar.fill", [0, 10000, 20000, 50000, 100000, 500000], vm.cfg.minVol24, { $0 == 0 ? "—" : money($0) }) { v in vm.edit { $0.minVol24 = v } }
                menu("clock.fill", [0, 1, 3, 6, 12, 24, 72, 168, 720], vm.cfg.maxAgeH, { $0 == 0 ? "∞" : String(format: "%g", $0) + "h" }) { v in vm.edit { $0.maxAgeH = v } }
                menu("arrow.up.right.circle.fill", [0, 50, 52, 55, 60, 65], vm.cfg.minBuyPct1h, { $0 == 0 ? "—" : String(format: "%g", $0) + "%" }) { v in vm.edit { $0.minBuyPct1h = v } }
                menu("arrow.left.arrow.right", [0, 10, 30, 60, 120, 300], vm.cfg.minTx1h, { $0 == 0 ? "—" : String(format: "%g", $0) }) { v in vm.edit { $0.minTx1h = v } }
            } header: { Image(systemName: "circle.hexagongrid.fill") }
            Section {
                Toggle(isOn: Binding(get: { vm.cfg.walletOn ?? true }, set: { v in vm.edit { $0.walletOn = v } })) {
                    Image(systemName: "wallet.pass.fill")
                }
                LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                    ForEach(kinds, id: \.0) { k in
                        chipBox(has(vm.cfg.wKinds, k.0), { vm.edit { $0.wKinds = toggled($0.wKinds, k.0) } }) {
                            HStack(spacing: 4) {
                                Image(systemName: k.2).foregroundStyle(k.3)
                                Text(k.1).font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
                menu("dollarsign.circle.fill", [1000, 3000, 10000, 30000, 100000], vm.cfg.walletMinNet, { money($0) }) { v in vm.edit { $0.walletMinNet = v } }
            } header: { Image(systemName: "person.crop.circle.badge.checkmark") }
            Section {
                menu("timer", [2, 3, 5, 10, 15], vm.cfg.intervalMin, { String(format: "%g", $0) + "m" }) { v in vm.edit { $0.intervalMin = v } }
                menu("number", [1, 2, 3, 5, 10], vm.cfg.maxPerRun, { String(format: "%g", $0) }) { v in vm.edit { $0.maxPerRun = v } }
                menu("snowflake", [2, 8, 24, 72], vm.cfg.cooldownH, { String(format: "%g", $0) + "h" }) { v in vm.edit { $0.cooldownH = v } }
            } header: { Image(systemName: "slider.horizontal.3") }
            Section {
                ForEach(vm.hits.filter { $0.kind == "token" }.prefix(20)) { h in
                    let ch: Chain = Chain(rawValue: h.chain ?? "") ?? .eth
                    Button {
                        GXOpen.token(chain: h.chain, address: h.token ?? "")
                    } label: {
                        HStack(spacing: 10) {
                            AvTokenLogo(chain: ch, address: h.token ?? "", symbol: h.sym ?? "?", hint: nil, size: 34)
                            Text(h.sym ?? "?").font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                            AvChainBadge(chain: ch, size: 16)
                            Spacer()
                            Text(TZ.short(Date(timeIntervalSince1970: (h.at ?? 0) / 1000))).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(vm.hits.filter { $0.kind == "wallet" }.prefix(20)) { h in
                    walletRow(h)
                }
            } header: { Image(systemName: "clock.arrow.circlepath") }
        }
        .navigationTitle("自动找币")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }

    private func walletRow(_ h: GXHit) -> some View {
        let parts: [String] = (h.msg ?? "").components(separatedBy: "|")
        let addr: String = parts.first ?? ""
        let tags: [String] = parts.count > 1 ? parts[1].components(separatedBy: ",") : []
        let net: String = parts.count > 2 ? parts[2] : ""
        let ch: Chain = Chain(rawValue: h.chain ?? "") ?? .eth
        return Menu {
            GMWalletMenuContent(chain: ch, addr: addr)
        } label: {
            HStack(spacing: 8) {
                AvChainBadge(chain: ch, size: 18)
                Text(Addr.short(addr)).font(.caption.monospaced()).foregroundStyle(Color.primary)
                ForEach(tags, id: \.self) { t in
                    Image(systemName: kindIcon(t).0).foregroundStyle(kindIcon(t).1)
                }
                Spacer()
                Text(net).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
