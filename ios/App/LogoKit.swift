import SwiftUI
import UIKit

// 应用 Logo 转圈（图来自资源 Logo.imageset，和桌面图标是同一张）
struct LogoSpin: View {
    var size: CGFloat = 20
    @State private var spin = false
    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
    }
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

// 全 App 的转圈统一换成 Logo：同名类型放在本模块，会覆盖 SwiftUI 自带的 ProgressView
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
            HStack(spacing: 6) {
                LogoSpin(size: 22)
                if let t = title { Text(t).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}

// 下拉刷新：隐藏系统转圈，换成应用 Logo（随下拉角度旋转，刷新中持续转动）
final class LogoRefreshControl: UIRefreshControl {
    private let logo = UIImageView()

    override init() {
        super.init()
        tintColor = .clear
        logo.image = UIImage(named: "Logo")
        logo.contentMode = .scaleAspectFit
        logo.layer.cornerRadius = 7
        logo.clipsToBounds = true
        logo.alpha = 0
        addSubview(logo)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s: CGFloat = 32
        logo.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        logo.center = CGPoint(x: bounds.midX, y: bounds.midY)
        if logo.layer.animation(forKey: "spin") == nil {
            let p = min(1, max(0, bounds.height / 64))
            logo.alpha = p
            logo.transform = CGAffineTransform(rotationAngle: p * .pi * 2)
        }
    }

    func spin() {
        let a = CABasicAnimation(keyPath: "transform.rotation.z")
        a.fromValue = 0
        a.toValue = Double.pi * 2
        a.duration = 0.9
        a.repeatCount = .infinity
        logo.layer.add(a, forKey: "spin")
        logo.alpha = 1
    }

    func stopSpin() {
        logo.layer.removeAnimation(forKey: "spin")
        logo.alpha = 0
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
