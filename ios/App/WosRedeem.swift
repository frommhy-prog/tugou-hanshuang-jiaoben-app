import Foundation
import CryptoKit
import Vision
import CoreImage
import UIKit
import SwiftUI
import WebKit

// MARK: - 兑换结果与本地记录
enum WosStatus: String, Codable {
    case success, already, expired, invalid, used, failed
    var title: String {
        switch self {
        case .success: return "兑换成功"
        case .already: return "已领取过"
        case .expired: return "已过期"
        case .invalid: return "无效码"
        case .used: return "已被领完"
        case .failed: return "未完成"
        }
    }
    var color: Color {
        switch self {
        case .success, .already: return Color.green
        case .expired, .invalid, .used: return Color.red
        case .failed: return Color.orange
        }
    }
    // 这些状态不需要再试
    var isFinal: Bool { self != .failed }
}

struct WosResult: Codable {
    var status: WosStatus
    var message: String
    var at: Date
}

enum WosStore {
    static var results: [String: WosResult] {
        get {
            guard let d = Cfg.defaults.data(forKey: "wosResults"), let m = try? JSONDecoder().decode([String: WosResult].self, from: d) else { return [:] }
            return m
        }
        set { Cfg.defaults.set(try? JSONEncoder().encode(newValue), forKey: "wosResults") }
    }
}

// MARK: - 官方兑换接口（与官网兑换中心同一套：登录 → 取验证码 → 提交）
enum WosAPI {
    static let base = "https://wos-giftcode-api.centurygame.com/api/"
    static let signKey = "tB87#kPtkxqOS2"

    static func md5(_ s: String) -> String {
        Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func call(_ path: String, _ fields: [String: String]) async throws -> [String: Any] {
        var p = fields
        p["time"] = String(Int(Date().timeIntervalSince1970 * 1000))
        let raw = p.keys.sorted().map { $0 + "=" + (p[$0] ?? "") }.joined(separator: "&")
        p["sign"] = md5(raw + signKey)
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = p.keys.sorted().map { $0 + "=" + ((p[$0] ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }.joined(separator: "&")
        guard let url = URL(string: base + path) else { throw APIError.network("地址无效") }
        var req = URLRequest(url: url, timeoutInterval: 25)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("https://wos-giftcode.centurygame.com", forHTTPHeaderField: "Origin")
        req.setValue("https://wos-giftcode.centurygame.com/", forHTTPHeaderField: "Referer")
        req.httpBody = Data(body.utf8)
        let result = try await URLSession.shared.data(for: req)
        guard let j = try JSONSerialization.jsonObject(with: result.0) as? [String: Any] else {
            throw APIError.decode(String((String(data: result.0, encoding: .utf8) ?? "").prefix(120)))
        }
        return j
    }

    static func msg(_ r: [String: Any]) -> String {
        if let m = r["msg"] as? String, !m.isEmpty { return m }
        return String(describing: r).prefix(160).description
    }

    static func redeem(fid: String, code: String, log: @escaping @MainActor (String) -> Void) async -> WosResult {
        func done(_ s: WosStatus, _ m: String) -> WosResult { WosResult(status: s, message: m, at: Date()) }
        await log("登录 ID \(fid)…")
        do {
            let r = try await call("player", ["fid": fid])
            if (r["code"] as? Int) != 0 { return done(.failed, "登录失败：" + msg(r)) }
            let nick = ((r["data"] as? [String: Any])?["nickname"] as? String) ?? "?"
            await log("登录成功：\(nick)")
        } catch {
            return done(.failed, "登录请求失败：" + error.localizedDescription)
        }

        var last = "未完成"
        for attempt in 1...6 {
            await log("第 \(attempt) 次：取验证码")
            var imgData: Data?
            do {
                let r = try await call("captcha", ["fid": fid, "init": "0"])
                if (r["code"] as? Int) == 0, let d = r["data"] as? [String: Any], let img = d["img"] as? String {
                    let b64 = img.contains(",") ? String(img.split(separator: ",", maxSplits: 1).last ?? "") : img
                    imgData = Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
                } else {
                    let m = msg(r)
                    last = "取验证码失败：" + m
                    await log(last)
                    if m.uppercased().contains("FREQUENT") { try? await Task.sleep(nanoseconds: 8_000_000_000) }
                    continue
                }
            } catch {
                last = "取验证码请求失败：" + error.localizedDescription
                await log(last)
                continue
            }
            guard let data = imgData else { last = "验证码图片解码失败"; await log(last); continue }
            let guesses = await CaptchaOCR.solve(data)
            guard let guess = guesses.first else {
                last = "没识别出 4 位验证码"
                await log(last + "，换一张")
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                continue
            }
            await log("识别为 \(guess)，提交")
            do {
                let r = try await call("gift_code", ["fid": fid, "cdk": code, "captcha_code": guess])
                let m = msg(r)
                let u = m.uppercased()
                await log("服务器：" + m)
                if u.contains("SUCCESS") || u.contains("SAME TYPE") { return done(.success, m) }
                if u.contains("RECEIVED") { return done(.already, m) }
                if u.contains("TIME ERROR") || u.contains("EXPIRED") { return done(.expired, m) }
                if u.contains("NOT FOUND") { return done(.invalid, m) }
                if u.contains("CAPTCHA") && u.contains("FREQUENT") { try? await Task.sleep(nanoseconds: 8_000_000_000); last = m; continue }
                if u.contains("CAPTCHA") { last = "验证码识别错误"; try? await Task.sleep(nanoseconds: 1_500_000_000); continue }
                if u.contains("TIMEOUT") { last = m; continue }
                if u.contains("USED") { return done(.used, m) }
                return done(.failed, m)
            } catch {
                last = "提交失败：" + error.localizedDescription
                await log(last)
            }
        }
        return done(.failed, last + "（可改用手动兑换）")
    }
}

// MARK: - 验证码识别（手机本机 Vision，免费，不上传）
enum CaptchaOCR {
    static func solve(_ data: Data) async -> [String] {
        guard let ui = UIImage(data: data), let cg = ui.cgImage else { return [] }
        var variants: [CGImage] = [cg]
        if let p = preprocess(cg, contrast: 1.8) { variants.append(p) }
        if let p = preprocess(cg, contrast: 3.0) { variants.append(p) }
        var out: [String] = []
        for v in variants {
            for c in await recognize(v) where !out.contains(c) { out.append(c) }
        }
        return out
    }

    static func preprocess(_ cg: CGImage, contrast: Double) -> CGImage? {
        let ci = CIImage(cgImage: cg)
        guard let f = CIFilter(name: "CIColorControls") else { return nil }
        f.setValue(ci, forKey: kCIInputImageKey)
        f.setValue(0.0, forKey: kCIInputSaturationKey)
        f.setValue(contrast, forKey: kCIInputContrastKey)
        f.setValue(0.1, forKey: kCIInputBrightnessKey)
        guard var out = f.outputImage else { return nil }
        out = out.transformed(by: CGAffineTransform(scaleX: 3, y: 3))
        let bg = CIImage(color: CIColor.white).cropped(to: out.extent.insetBy(dx: -60, dy: -60))
        out = out.composited(over: bg)
        return CIContext().createCGImage(out, from: out.extent)
    }

    static func recognize(_ cg: CGImage) async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var found: [String] = []
                let req = VNRecognizeTextRequest { r, _ in
                    for o in (r.results as? [VNRecognizedTextObservation]) ?? [] {
                        for c in o.topCandidates(5) {
                            let s = String(c.string.filter { $0.isLetter || $0.isNumber })
                            if s.count == 4 { found.append(s) }
                        }
                    }
                }
                req.recognitionLevel = .accurate
                req.usesLanguageCorrection = false
                let h = VNImageRequestHandler(cgImage: cg, options: [:])
                try? h.perform([req])
                cont.resume(returning: found)
            }
        }
    }
}

// MARK: - 手动兑换：应用内打开官方兑换中心，自动填好 ID（和兑换码）
struct RedeemWebView: UIViewRepresentable {
    let url: URL
    let fid: String
    let code: String?

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let ucc = WKUserContentController()
        ucc.addUserScript(WKUserScript(source: script(), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        cfg.userContentController = ucc
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.load(URLRequest(url: url))
        return w
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private func js(_ s: String) -> String {
        guard let d = try? JSONEncoder().encode(s), let t = String(data: d, encoding: .utf8) else { return "\"\"" }
        return t
    }

    private func script() -> String {
        let f = js(fid)
        let c = js(code ?? "")
        return """
        (function(){
          var FID=\(f), CODE=\(c);
          function setVal(el,v){
            var d=Object.getOwnPropertyDescriptor(HTMLInputElement.prototype,'value');
            d.set.call(el,v);
            el.dispatchEvent(new Event('input',{bubbles:true}));
            el.dispatchEvent(new Event('change',{bubbles:true}));
          }
          function visibleInputs(){
            return [].slice.call(document.querySelectorAll('input')).filter(function(i){
              var t=(i.type||'text').toLowerCase();
              return i.offsetParent!==null && !i.disabled && (t==='text'||t==='tel'||t==='number'||t==='search');
            });
          }
          function clickBtn(re){
            var bs=[].slice.call(document.querySelectorAll('button,div[role=button],.btn,.button'));
            for(var i=0;i<bs.length;i++){ if(re.test((bs[i].innerText||'').trim())){ bs[i].click(); return true; } }
            return false;
          }
          var step=0,tries=0,idEl=null;
          var timer=setInterval(function(){
            tries++; if(tries>90){clearInterval(timer);return;}
            var ins=visibleInputs();
            if(ins.length===0) return;
            if(step===0){
              idEl=ins[0]; setVal(idEl,FID); step=1;
              setTimeout(function(){ clickBtn(/login|log in|sign in|登录|登入|确认|confirm/i); },400);
              return;
            }
            if(step===1 && CODE){
              var ci=null;
              for(var i=0;i<ins.length;i++){ if(ins[i]!==idEl && /code|gift|礼|兑/i.test((ins[i].placeholder||'')+(ins[i].name||'')+(ins[i].id||''))){ci=ins[i];break;} }
              if(!ci){ for(var j=0;j<ins.length;j++){ if(ins[j]!==idEl){ci=ins[j];break;} } }
              if(ci){ setVal(ci,CODE); step=2; clearInterval(timer); }
            } else if(step===1 && !CODE){ clearInterval(timer); }
          },500);
        })();
        """
    }
}

struct WebRedeemSheet: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let fid: String
    let code: String?

    var body: some View {
        NavigationStack {
            RedeemWebView(url: url, fid: fid, code: code)
                .navigationTitle("官方兑换中心")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button("复制 ID") { UIPasteboard.general.string = fid }
                        Spacer()
                        if let c = code { Button("复制兑换码") { UIPasteboard.general.string = c } }
                        Spacer()
                        Button("用 Safari 打开") { UIApplication.shared.open(url) }
                    }
                }
        }
    }
}
