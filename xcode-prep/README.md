# 搞钱 Xcode 安装包（v3 美观版）

这是从 Muse 直接推到 GitHub 的安装包，不再发 zip。Mac 上下载这个文件夹就能开。

## 先还原图标（只做一次）
GitHub 的 MCP 推送只能传文本，1024 图标 PNG 不能直接推，所以这里放的是 base64 文本。
在 `xcode-prep` 目录里跑一次：

```bash
cd xcode-prep
./decode-icon.sh
```

跑完 `GaoQian/Assets.xcassets/AppIcon.appiconset/icon-1024.png` 就会出现，之后按下面步骤开工程。

## 开工程
1. 打开 `xcode-prep/GaoQian.xcodeproj`，选 GaoQian target > Signing & Capabilities，Team 选自己的免费 Apple ID。
2. Bundle ID 现在是占位 `com.jon.gaoqian`，被占就改后缀，不用改代码。
3. App Group：两个 target 都加 App Groups，勾选新建 `group.tugou-hanshuang-jiaoben-app`，必须和代码里 SharedStore.groupID 一致。
4. 插 iPhone，点 Run；手机设置 > 通用 > VPN 与设备管理里信任自己的 Apple ID。
5. 首次：持仓页加钱包（只填公开地址），跑一次“我的钱包全量分析”，小组件才有真实总价；再加桌面和锁屏小组件。

## v3 设计说明
- 壁纸系统重新排版，不是纯黑板，也不是把壁纸原样抄进来：颗粒黑底 + 断角框只做边框 + MAKE MONEY 只做一次顶部小字 + 胶囊借开仓/平仓钮的形做链/币/风险标签，不做交易按钮。
- 图标：颗粒黑底 + 断角框 + 顶部 MAKE MONEY 小字 + 中央白色“搞钱”一个焦点，不再堆三句口号。
- 小组件：小款标头 + 总价 + 分隔线 + 最重仓；中款标头 + 总价 + 胶囊持仓行 + 占比条；大款标头 + 总价 + 持仓列表 + 风险胶囊 + 脚注。
- 计价货币：设置页选，36 个主流货币，汇率走 Worker /api/fx（每日参考价，不是实时外汇牌价）。
- 硬限制不变：免费 Apple ID 证书 7 天过期，要连 Mac 重签；远程 APNs 和远程灵动岛没有付费账号做不了。
- 这个 pbxproj 是 Linux 手写 starter，未经 Xcode 打开验证，Mac 上第一步就是验证工程与 Signing/App Group。

## 仓库与 Worker 名不动
仓库 frommhy-prog/tugou-hanshuang-jiaoben-app，Cloudflare 项目 tugou-hanshuang-jiaoben-app，App 显示名搞钱。
