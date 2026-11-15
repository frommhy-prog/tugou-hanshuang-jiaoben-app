import SwiftUI
import UIKit

// MARK: - Logo 抠图：资源里的 Logo 是白底图，这里把「和图片边缘相连的白底」抠掉（边缘按颜色转透明做柔边），圈内的白保留，裁掉留白后只在内存里算一次
enum LogoCut {
    static let image: UIImage? = make()

    private static func make() -> UIImage? {
        guard let src = UIImage(named: "Logo")?.cgImage else { return nil }
        let n = 256
        let rect = CGRect(x: 0, y: 0, width: n, height: n)
        let cs = CGColorSpaceCreateDeviceRGB()
        let info: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue
        var buf = [UInt8](repeating: 0, count: n * n * 4)
        var drawn = false
        buf.withUnsafeMutableBytes { p in
            if let ctx = CGContext(data: p.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: cs, bitmapInfo: info) {
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(rect)
                ctx.interpolationQuality = .high
                ctx.draw(src, in: rect)
                drawn = true
            }
        }
        if !drawn { return nil }

        // 1) 从四边开始泛洪，找出和边缘相连的近白像素
        var isW = [Bool](repeating: false, count: n * n)
        for i in 0..<(n * n) {
            isW[i] = buf[i * 4] > 238 && buf[i * 4 + 1] > 238 && buf[i * 4 + 2] > 238
        }
        var bg = [Bool](repeating: false, count: n * n)
        var stack: [Int] = []
        func seed(_ x: Int, _ y: Int) {
            let i = y * n + x
            if isW[i] && !bg[i] {
                bg[i] = true
                stack.append(i)
            }
        }
        for k in 0..<n {
            seed(k, 0)
            seed(k, n - 1)
            seed(0, k)
            seed(n - 1, k)
        }
        while let i = stack.popLast() {
            let x = i % n
            let y = i / n
            if x > 0 { seed(x - 1, y) }
            if x < n - 1 { seed(x + 1, y) }
            if y > 0 { seed(x, y - 1) }
            if y < n - 1 { seed(x, y + 1) }
        }

        // 2) 背景 → 全透明；背景边上 2 像素内 → 颜色转透明（去白边）；其余保持不透明
        var minX = n, minY = n, maxX = -1, maxY = -1
        for y in 0..<n {
            for x in 0..<n {
                let idx = y * n + x
                let i = idx * 4
                if bg[idx] {
                    buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 0
                    continue
                }
                var near = false
                var dy = -2
                while dy <= 2 && !near {
                    var dx = -2
                    while dx <= 2 {
                        let nx = x + dx
                        let ny = y + dy
                        if nx >= 0 && ny >= 0 && nx < n && ny < n && bg[ny * n + nx] { near = true; break }
                        dx += 1
                    }
                    dy += 1
                }
                if near {
                    let r = Double(buf[i]) / 255.0
                    let g = Double(buf[i + 1]) / 255.0
                    let b = Double(buf[i + 2]) / 255.0
                    let a = max(1.0 - r, max(1.0 - g, 1.0 - b))
                    if a < 0.04 {
                        buf[i] = 0; buf[i + 1] = 0; buf[i + 2] = 0; buf[i + 3] = 0
                        continue
                    }
                    let k = 1.0 - a
                    buf[i] = UInt8(max(0, min(255, (r - k) * 255.0)))
                    buf[i + 1] = UInt8(max(0, min(255, (g - k) * 255.0)))
                    buf[i + 2] = UInt8(max(0, min(255, (b - k) * 255.0)))
                    buf[i + 3] = UInt8(max(0, min(255, a * 255.0)))
                }
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }

        var out: CGImage?
        buf.withUnsafeMutableBytes { p in
            if let ctx = CGContext(data: p.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: cs, bitmapInfo: info) {
                out = ctx.makeImage()
            }
        }
        guard var cg = out else { return nil }
        if maxX > minX && maxY > minY {
            let w = maxX - minX + 1
            let h = maxY - minY + 1
            let side = min(n, Int(Double(max(w, h)) * 1.06) + 2)
            let cx = (minX + maxX) / 2
            let cy = (minY + maxY) / 2
            let x0 = max(0, min(n - side, cx - side / 2))
            let y0 = max(0, min(n - side, cy - side / 2))
            if let c = cg.cropping(to: CGRect(x: x0, y: y0, width: side, height: side)) { cg = c }
        }
        return UIImage(cgImage: cg)
    }
}

// MARK: - 加载动画：Logo 抠出来做成金币——左右摆动翻转 + 扫光 + 金色彗星环 + 呼吸光晕 + 三颗绕飞火花
struct LogoLoaderFrame: View {
    let t: Double
    let size: CGFloat
    var pull: Double? = nil   // nil = 加载中；0...1 = 下拉进度

    private var spinning: Bool { pull == nil }
    private var p: Double { pull ?? 1 }

    @ViewBuilder
    private func base(_ w: CGFloat) -> some View {
        if let ui = LogoCut.image {
            Image(uiImage: ui).resizable().scaledToFit().frame(width: w, height: w)
        } else {
            Image("Logo").resizable().scaledToFit().frame(width: w, height: w).clipShape(Circle())
        }
    }

    @ViewBuilder
    private func shine(_ w: CGFloat) -> some View {
        if spinning, let ui = LogoCut.image {
            let x: CGFloat = CGFloat((t * 0.9).truncatingRemainder(dividingBy: 1.9) - 0.45)
            LinearGradient(colors: [Color.clear, Color.white.opacity(0.95), Color.clear], startPoint: UnitPoint(x: x - 0.3, y: 0.15), endPoint: UnitPoint(x: x, y: 0.85))
                .mask(Image(uiImage: ui).resizable().scaledToFit())
                .frame(width: w, height: w)
                .blendMode(.plusLighter)
        }
    }

    private func coin(_ sc: Double, _ flip: Double) -> some View {
        let w: CGFloat = size * 0.8
        return base(w)
            .overlay(shine(w))
            .scaleEffect(CGFloat(sc))
            .rotation3DEffect(.degrees(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .shadow(color: Color.gold.opacity(0.5), radius: size * 0.1)
    }

    private func spark(_ i: Int) -> some View {
        let a: Double = (t * 1.4 + Double(i) / 3.0) * 2.0 * Double.pi
        let tw: Double = 0.5 + 0.5 * sin(t * 5.0 + Double(i) * 2.1)
        let r: Double = Double(size) * (0.64 + 0.04 * Double(i))
        return Image(systemName: "sparkle")
            .font(.system(size: size * CGFloat(0.16 + 0.05 * tw)))
            .foregroundStyle(Color.gold)
            .opacity(0.35 + 0.65 * tw)
            .offset(x: CGFloat(cos(a) * r), y: CGFloat(sin(a) * r))
    }

    var body: some View {
        let glow: Double = spinning ? 0.6 + 0.4 * sin(t * 3.6) : p * 0.6
        let flip: Double = spinning ? sin(t * 2.4) * 58.0 : p * 270.0
        let sc: Double = spinning ? 0.94 + 0.06 * sin(t * 5.2) : 0.5 + 0.5 * p
        let spin: Double = spinning ? t * 330.0 : p * 120.0
        let arc: CGFloat = spinning ? 0.3 : CGFloat(0.3 * p)
        let ring = AngularGradient(gradient: Gradient(colors: [Color.gold.opacity(0), Color.gold]), center: .center, startAngle: .degrees(0), endAngle: .degrees(108))
        let halo = RadialGradient(colors: [Color.gold.opacity(0.45 * glow), Color.gold.opacity(0)], center: .center, startRadius: 0, endRadius: size * 0.75)
        return ZStack {
            Circle().fill(halo).frame(width: size * 1.5, height: size * 1.5)
            Circle()
                .trim(from: 0, to: arc)
                .stroke(ring, style: StrokeStyle(lineWidth: max(1.5, size * 0.06), lineCap: .round))
                .frame(width: size * 1.12, height: size * 1.12)
                .rotationEffect(.degrees(spin))
            coin(sc, flip)
            if spinning {
                spark(0)
                spark(1)
                spark(2)
            }
        }
        .frame(width: size, height: size)
    }
}

struct LogoLoader: View {
    var size: CGFloat = 24

    var body: some View {
        TimelineView(.animation) { ctx in
            LogoLoaderFrame(t: ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600), size: size)
        }
        .frame(width: size, height: size)
    }
}

// 兼容旧名字
struct LogoSpin: View {
    var size: CGFloat = 20
    var body: some View { LogoLoader(size: size) }
}

private struct LogoBar: View {
    var fraction: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(Color.accentColor).frame(width: g.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
        .frame(height: 4)
    }
}

// 全 App 的转圈统一换成 Logo 动画：同名类型放在本模块，会覆盖 SwiftUI 自带的 ProgressView
struct ProgressView: View {
    private var value: Double?
    private var total: Double
    private var title: String?

    init() { value = nil; total = 1; title = nil }
    init(_ title: String) { value = nil; total = 1; self.title = title }
    init(value: Double?, total: Double = 1.0) { self.value = value; self.total = total; title = nil }

    var body: some View {
        if let v = value {
            LogoBar(fraction: total > 0 ? v / total : 0)
        } else {
            HStack(spacing: 8) {
                LogoLoader(size: 22).padding(4)
                if let t = title { Text(t).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - 下拉刷新：隐藏系统转圈，换成 Logo 金币（下拉时随进度翻转放大，刷新中播放完整动画）
final class LogoPullState: ObservableObject {
    @Published var pull: Double = 0
    @Published var spinning = false
}

private struct LogoPullView: View {
    @ObservedObject var st: LogoPullState

    var body: some View {
        Group {
            if st.spinning {
                LogoLoader(size: 30)
            } else if st.pull > 0.04 {
                LogoLoaderFrame(t: 0, size: 30, pull: st.pull)
            } else {
                Color.clear
            }
        }
        .frame(width: 60, height: 60)
    }
}

final class LogoRefreshControl: UIRefreshControl {
    private let st: LogoPullState
    private let host: UIHostingController<LogoPullView>

    override init() {
        let s = LogoPullState()
        st = s
        host = UIHostingController(rootView: LogoPullView(st: s))
        super.init()
        tintColor = .clear
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        addSubview(host.view)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        host.view.bounds = CGRect(x: 0, y: 0, width: 60, height: 60)
        host.view.center = CGPoint(x: bounds.midX, y: bounds.midY)
        if !st.spinning { st.pull = min(1, max(0, Double(bounds.height / 64))) }
    }

    func spin() { st.spinning = true }

    func stopSpin() {
        st.spinning = false
        st.pull = 0
    }
}

struct LogoRefreshHook: UIViewRepresentable {
    var action: @MainActor () async -> Void
    init(_ action: @escaping @MainActor () async -> Void) { self.action = action }

    func makeCoordinator() -> Coord { Coord() }

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ v: UIView, context: Context) {
        context.coordinator.action = action
        let c = context.coordinator
        DispatchQueue.main.async { c.attach(v) }
    }

    final class Coord: NSObject {
        var action: (@MainActor () async -> Void)?
        private var rc: LogoRefreshControl?

        func attach(_ v: UIView) {
            if rc != nil { return }
            var p: UIView? = v
            while let x = p {
                if let s = x as? UIScrollView { install(s); return }
                p = x.superview
            }
        }

        private func install(_ s: UIScrollView) {
            let c = LogoRefreshControl()
            c.addTarget(self, action: #selector(fire(_:)), for: .valueChanged)
            s.refreshControl = c
            s.alwaysBounceVertical = true
            rc = c
        }

        @objc func fire(_ sender: UIRefreshControl) {
            (sender as? LogoRefreshControl)?.spin()
            Task { @MainActor in
                await self.action?()
                (sender as? LogoRefreshControl)?.stopSpin()
                sender.endRefreshing()
            }
        }
    }
}
