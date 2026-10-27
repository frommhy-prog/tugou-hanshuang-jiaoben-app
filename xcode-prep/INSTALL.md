# 搞钱安装准备（2026-10-28，未在 Xcode 验证，Mac 上第一步就是验证工程）

## 这次优化先做了什么
- 体检双打改二选一：以前每次体检先打快价、再打全量，全量一到快价就被覆盖，
  等于每次白烧一次 Dex/Gecko 调用，限流窗口更容易撞 429。现在全量优先只打一次，
  全量失败才打快价兜底，快价到了界面会明说“全量失败，先用快价，风险字段可能不全”，
  不把快价当全量卖。这是之前文档里就记着的待做项，不是新发明。
- 补了 App 入口：以前只有 ContentView，没有 @main App，Xcode 里根本跑不起来。
  现在 GaoQianApp 已补上。
- 修了小组件入口：小组件扩展只能有一个 @main，现在用 WidgetBundle 把普通小组件
  和灵动岛包在一起，否则 Xcode 会报重复入口。
- 以上三处已同步到 repo-staging 与 phase1 两份，括号平衡检查通过。

## 安装包里有什么
- `xcode-prep/GaoQian.xcodeproj/project.pbxproj`：starter 工程，两个 target：
  GaoQian（App，显示名已设成“搞钱”，iOS 16.1 起）与 GaoQianWidget（小组件 + 灵动岛）。
- `xcode-prep/GaoQian/`：App 全部 Swift 文件 + AppIcon（1024 主图已放好）+ App Group 权利文件。
- `xcode-prep/GaoQianWidget/`：小组件 + 灵动岛文件 + 共用快照文件 + 权利文件。
- `GaoQian-xcode-prep.zip`：上面整个 xcode-prep 的压缩包，Mac 上解压就能开。
- 注意：这个 pbxproj 是在这台 Linux 上手写的 starter 工程，没经过 Xcode 打开验证。
  如果 Xcode 打开时提示升级或修复，按下面第 3–5 步走，不要硬编。

## Mac 上安装步骤（免费 Apple ID 路线）
1. 把 zip 解压到 Mac，或等 Jon 批准后推到 GitHub 再 git clone（推仓库要 Jon 批准，
   本轮没推，只在本地备好）。
2. 打开 `xcode-prep/GaoQian.xcodeproj`，选 GaoQian target > Signing & Capabilities：
   Team 选自己的免费 Apple ID 个人团队；Bundle ID 现在是占位 `com.jon.gaoqian`，
   如果提示已被占用，改后缀（例如加自己的英文名缩写），改完不用改代码。
3. App Group：两个 target 都加 Capability > App Groups，勾选新建
   `group.tugou-hanshuang-jiaoben-app`，必须和代码里 SharedStore.groupID 一致，
   不一致小组件读不到钱包和快照。建好前不要改代码里的占位值，建好后核对一次。
4. 插上 iPhone，顶部选自己的手机，点 Run。第一次手机上会提示“不受信任的开发者”，
   去 iPhone 设置 > 通用 > VPN 与设备管理 > 信任自己的 Apple ID，再回桌面打开搞钱。
5. 首次使用清单（只填公开地址，不要私钥、不要游戏密码）：
   - 持仓页加钱包，跑一次“我的钱包全量分析”，小组件才会从“未同步”变成真实总价。
   - 桌面长按 > 编辑主屏幕 > 左上角 + > 搜“搞钱”，加中款或大款；锁屏长按 > 自定 >
     锁屏 > 添加小组件 > 搜“搞钱”，加矩形或圆形。
   - 体检页查到币后点“灵动岛盯盘”，看灵动岛紧凑和展开是不是价和涨跌。
   - 设置页核对提醒开关：默认只开本地 + Telegram，Bark 默认关；自动推要 Cron 批准后才生效。
   - 寒霜页先手动去官方兑换中心领 WOS1025（如果还没领），自动兑换未接，不要在任何
     非官方页填游戏密码。

## 免费路线的硬限制（再说一次，不绕）
- 免费 Apple ID 证书 7 天过期，7 天后 App 打不开，要连 Mac 重新 Run 一次。
  这和“日常完全脱离电脑”直接冲突，没有免费代码解法；长期脱离电脑要付费开发者账号
  （99 美元/年，以苹果官网为准），这是 Jon 要定的分发决策，本轮不替他定。
- 远程 APNs 推到搞钱 App 本身、远程灵动岛更新：没有付费账号做不了。
  现在能用的是本地通知 + Telegram/Bark 中转 + 本地灵动岛。
- 小组件约 15 分钟刷新一次，单币轮询最短 10 秒，免费档没有秒级实时。

## 维护
- API 用量与剩余：设置页和钱包页看当日端点次数，剩余量标未知（上游不返回，不编数）。
- 缓存与旧价：单币/组合 60 秒，组合价格 300 秒内新鲜、300 秒后上游失败回旧价标 stale，
  小组件 >15 分钟标旧数据，App 里年龄按原始 fetchedAt 算。
- 反馈：设置 > 用户反馈，手动发送才上传，存 Worker KV 30 天，不要写私钥、助记词、游戏密码。
- Worker 与仓库名不动：tugou-hanshuang-jiaoben-app；App 显示名是搞钱。
