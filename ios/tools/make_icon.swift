import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 生成 TSTZ-M 图标：白底 1024×1024，海军蓝金圈圆标居中（占 80%）
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let W = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: W, height: W, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }

ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: W))
// 之后用左上角为原点的坐标
ctx.translateBy(x: 0, y: CGFloat(W))
ctx.scaleBy(x: 1, y: -1)

let t = CGFloat(W) * 0.8
let off = (CGFloat(W) - t) / 2
let circle = CGRect(x: off, y: off, width: t, height: t)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1) }

// 金色外圈（上浅下深渐变）
ctx.saveGState()
ctx.addEllipse(in: circle)
ctx.clip()
let ringGrad = CGGradient(colorsSpace: cs, colors: [rgb(250, 217, 129), rgb(205, 159, 70)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(ringGrad, start: CGPoint(x: 0, y: off), end: CGPoint(x: 0, y: off + t), options: [])
ctx.restoreGState()

// 海军蓝圆底
let ring = t * 0.0146
ctx.setFillColor(rgb(0, 28, 68))
ctx.fillEllipse(in: circle.insetBy(dx: ring, dy: ring))

// 字母多边形：坐标是 0...1000 的圆内相对坐标
let white: [[[Double]]] = [
    [[486.2, 431.2], [345.0, 431.2], [228.5, 543.5], [228.5, 581.5], [363.9, 665.7], [331.9, 698.0], [228.5, 698.0], [192.1, 740.2], [355.2, 741.6], [407.6, 691.0], [407.6, 636.2], [280.9, 557.6], [371.2, 473.3], [446.9, 473.3]],
    [[212.5, 508.4], [382.8, 294.9], [471.6, 294.9], [510.9, 250.0], [221.3, 250.0], [187.8, 294.9], [314.4, 297.8], [212.5, 431.2]],
]
let gold: [[[Double]]] = [
    [[439.6, 632.0], [441.0, 658.7], [540.0, 658.7], [538.6, 630.6]],
    [[816.6, 561.8], [812.2, 561.8], [732.2, 647.5], [650.7, 567.4], [652.1, 740.2], [684.1, 740.2], [685.6, 650.3], [733.6, 698.0], [778.7, 648.9], [780.2, 738.8], [816.6, 738.8]],
    [[739.4, 504.2], [493.4, 505.6], [458.5, 539.3], [460.0, 543.5], [570.6, 544.9], [570.6, 748.6], [614.3, 705.1], [614.3, 544.9], [701.6, 543.5]],
    [[804.9, 250.0], [557.5, 251.4], [529.8, 276.7], [518.2, 293.5], [687.0, 296.3], [502.2, 470.5], [502.2, 474.7], [768.6, 473.3], [807.9, 431.2], [615.7, 429.8]],
]

func path(_ polys: [[[Double]]]) -> CGPath {
    let p = CGMutablePath()
    for poly in polys {
        for (i, pt) in poly.enumerated() {
            let x = off + CGFloat(pt[0]) / 1000 * t
            let y = off + CGFloat(pt[1]) / 1000 * t
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
    }
    return p
}

ctx.setFillColor(rgb(255, 255, 255))
ctx.addPath(path(white))
ctx.fillPath()

ctx.saveGState()
ctx.addPath(path(gold))
ctx.clip()
let goldGrad = CGGradient(colorsSpace: cs, colors: [rgb(238, 197, 102), rgb(214, 170, 78)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(goldGrad, start: CGPoint(x: 0, y: off + t * 0.25), end: CGPoint(x: 0, y: off + t * 0.75), options: [])
ctx.restoreGState()

guard let img = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(2) }
CGImageDestinationAddImage(dest, img, nil)
if !CGImageDestinationFinalize(dest) { exit(3) }
print("icon written: \(out)")
