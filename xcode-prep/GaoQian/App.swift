import SwiftUI

// 搞钱 App 入口：以前只有 ContentView，没有 @main App，Xcode 里根本跑不起来，
// 这是安装准备时补上的缺口。Display Name 在 Xcode 工程里设成“搞钱”，
// 这里不写死名字，名字以工程设置为准。
@main
struct GaoQianApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
