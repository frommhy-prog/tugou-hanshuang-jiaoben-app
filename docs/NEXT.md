# TSTZ-M 新对话接手清单（2026-11-14 更新）

仓库 frommhy-prog/tugou-hanshuang-jiaoben-app，App 在 `ios/`，改动用 CI 云编译，用户不会写代码，全部由助手直接改仓库并验证。

## 零之一、本轮（2026-11-14）已完成（CI 构建 88 通过，引擎已部署）
- 品牌图：新增资源 `Assets.xcassets/Logo.imageset`（与桌面图标同一张 `icon.png` 的 blob）；`BrandMark`（令牌页、分享卡等）改为显示这张图，不再自绘。
- 转圈：`LogoKit.swift` 里自定义了同名类型 `ProgressView`（覆盖 SwiftUI 自带，全 App 的转圈都成 Logo 旋转；支持 `ProgressView()` / `ProgressView("文字")` / `ProgressView(value:total:)`，不支持带闭包标签的写法）；下拉刷新用 `LogoRefreshHook`（给祖先 UIScrollView 装自定义 `UIRefreshControl`），目前只接在代币页，其它页面的 `.refreshable` 还是系统转圈。
- 代币页整屏布局：头部 + K 线通栏（无卡片边距），交易所样式头部（左大价格 + 24h 涨跌，右侧市值/流动性/24h 成交/池龄），图表高度 `KHero.chartHeight`（屏幕高度一半），头部右侧 ☆ 收藏、⤢ 全屏图表（`fullScreenCover`，通过通知 `.tstzmFullChart` 触发）。
- K 线价格轴修复（`Web/chart.html`）：极小价格原来轴显示 0.99999…，现在对价格放大 10^k 后再画（`S.F`），轴/十字线/图例用「0.0₆1587」写法；KDJ/RSI/ROC 与成交量 MA 不再走价格格式。
- K 线实时与速度（`ProChart.swift` 的 `KLineVM`）：`liveLoop` 每 3 秒用 Dexscreener 单池实时价把最新一根补到「现在」（`applyLive`，空档用平盘 K 填，实时覆盖层不写缓存）；切周期时先用本地更细周期缓存汇总出当前周期（`deriveFromFiner`）再拉网络；进入后 7 秒后台预取其它周期（`prefetchOthers`）。
- 限流网关 `DataGate.swift`：GeckoTerminal 任意两次请求至少隔 2.1 秒、Dexscreener 0.22 秒、GoPlus 1.1 秒；429 后按 Retry-After 整体退避并重试一次；`MarketAPI.json(url, ttl:)` 支持短缓存。`MarketAPI.pairs` 查空时自动换 Dexscreener 老接口 `legacyPairs`。
- 持有人刷新失败的根因：热门币转账 >3000 笔，原 `/e/evm/token` 只读 3 页读不完就返回空榜单。现在 App 改调 `/e/v2/holders2`（引擎 `intel.js`，最多 14 页、不带时间戳、一次批量 eth_getCode），仍读不完或失败时手机直连 GoPlus（前 10 大 + 持有人数 + 创建者占比），再退 GeckoTerminal 代币信息里的持有人统计（`HolderFallback.swift`）。线上实测：BSC USDT 读 12 页正常返回「读不完」，没触发子请求或 CPU 限制。
- 收藏 + 自动监控 `Favorites.swift`：头部 ☆ 收藏，搜索栏下的收藏条一点直接查（长按移除），`WatchMonitor` 前台每 45 秒扫一遍（价格 5 分钟 ≥8%、1 小时涨 ≥25% 或跌 ≥15%、流动性 −25%、5 分钟放量 5 倍、5 分钟卖压 3 倍），命中发本地通知。免费账号没有服务器推送，App 退到后台就停。
- 「情报」标签（代币页第 6 个标签，“更多”后移到第 7）`FlowIntel.swift`：庄家/控盘画像、洗盘刷量检测、机器人识别、聪明钱、钱包关联（引擎 `/e/v2/links`：每个大户的第一笔原生币来源聚类，EVM 用 Alchemy，Solana 用 Helius funded-by）、交易复盘（用 K 线缓存算大户买点/回撤/卖飞）、DeFade 取证（可选，需用户自己的 df_ 密钥，MCP 协议 `https://api.defade.org/mcp`，EVM 需其付费套餐，工具名未在线上验证）。
- 调研结论：DeFade（MIT SDK，托管 API）；FlowLens（tobenwarrior/FlowLens，AGPL-3.0，只借思路不拷代码）；chain-trace 最接近 crypttrace（首笔资金来源追踪）；wallet-analyzer 名字重名太多，现有 `WalletIntel.swift` 已覆盖思路；STRATA 搜到的是 Injective 测试网做市商竞技场等无关项目，未接入。
- 版本号差异：CI 用 `MARKETING_VERSION=1.0.<运行号>`、`CURRENT_PROJECT_VERSION=<运行号>`，Xcode 走 `project.yml` 里的 1.0.0(1)。只是显示不同；Xcode 走 Debug（没有 App Group，小组件拿不到主 App 数据）、CI 是 Release。

## 零、先看这个
- 同一个仓库可能被多个对话同时改。2026-11-12 07:55 另一个对话覆盖了 `Avatars.swift`、`MarketBoard.swift` 并新增了重复的 `KRoll.swift`，造成编译失败，已还原为统一版本。新对话开头先看最近提交，别重做已完成的事；提示用户「同一个项目不要开两个对话同时改」。
- 用户已澄清：不是把 OSVIA 合并进 TSTZ-M；目标只是 TSTZ-M「Xcode 直装」和「SideStore 安装」是同一个应用（见第二节）。

## 一、工作方式
- 小改动用补丁清单：`.github/patches/plistN.py`（`rep(tag, 文件, 旧文本, 新文本)` / `cut(tag, 文件, 起点, 终点, 新文本)`），CI 编译前由 `apply.py` 应用；按文件事务（任一锚点不匹配，该文件整体不改），已应用的标签记在 `.github/patches/applied.txt`，补丁后的源码会被 CI 回写仓库。新增大块功能直接新建 Swift 文件。目前最大补丁批次是 plist18。
- 读结果：`ios/ci/patch-result.txt`（PATCH_OK / PATCH_FAILED）、`ios/ci/build-result.txt`、`ios/ci/build-errors.txt`、`ios/ci/bundle-check.txt`。一次构建约 5–8 分钟，**每次推送到 `ios/App/**`、`ios/Shared/**`、`ios/project.yml`、`.github/patches/**`、工作流都会触发构建并取消在途的那次**，所以一批改动要连续推完（新文件先推，补丁文件最后推）；文档（`docs/`、README）不触发构建。
- CI 的「Commit generated files」步骤 2026-11-14 改成 `git pull --rebase --autostash` 并把失败原因写进注解（之前一次因为未暂存改动推送失败，结果文件没回写）；构建结果和错误前 700 字也会写进注解（`GET /check-runs/<id>/annotations`）。不要用 `GET actions/runs/<id>/logs`，返回的是二进制 zip。
- 等构建：`bash_tool` 里 `sleep 270` 可以用；`gh_commits`、`gh_ls`、`gh_api GET commits`、`actions/runs` 输出极长，尽量不用；要把旧版本文件原样还原，用 git data API（`git/trees` 带 `base_tree` + 旧 blob sha，再 `git/commits`、`PATCH git/refs/heads/main`），不用重发内容。
- 编译器常见坑：表达式过长要拆开；ViewBuilder 一组最多 10 个子视图；`Verdict` 已被占用，综合研判类型叫 `TokenVerdict`；读 `UTokenVM`（MainActor）的静态方法所在类型要标 `@MainActor`（`Intel` 就是这样报错的）；字符串拼接统一用 `cat(...)`；模型输出/接口 JSON 用 `JV` 容错解码（`Lossy.swift`）；新增类型名带独特前缀，避免与已有类型重名。
- 引擎（Cloudflare Worker `tstzm-engine`）：源码 `worker-engine/`，`v2.js` 是入口包装（现在还路由 `/e/v2/holders2`、`/e/v2/links` 到 `intel.js`），原模块在 `v2base.js`，AI 在 `ai.js`；部署用 gh_deploy（path `worker-engine/worker.js`、root `worker-engine/`、extra_paths 含 evm.js、v2.js、v2base.js、ai.js、intel.js）。可以用队列控制台探测：`POST /queues/26998799521b4a35832fd73df7b77b03/messages` 发 `{op:"api",name:"..",max:1500,path:"/e/..."}` 或 `{url:"https://..."}`，结果读 D1 `selftest`（数据库 id `7c59261f-fbe3-4ae7-b428-21b5d14c3a1e`）。注意：云端出口被 GeckoTerminal / Dexscreener / GoPlus 限流，这些接口必须在手机直连验证。
- SideStore 源：`sidestore/source.json`，每个构建一个固定下载地址 `releases/download/build-N/TSTZ-M.ipa`，只保留最近 6 个。改了源后用户要在 SideStore 里删掉源再重新添加一次。

## 二、安装方式：Xcode 与 SideStore 是同一个应用
- SideStore 重签会把标识改成「原标识.团队 ID」（扩展是「原标识.团队 ID.Widget」，App Group 同样补团队 ID）。以前 Xcode 直装用的是不带后缀的原标识，所以手机上会有两个一模一样的图标。
- 现在 `ios/project.yml` 里 Debug 配置的标识是 `com.Hao-Yi-Miao.TSTZ-M.$(DEVELOPMENT_TEAM)`（扩展再加 `.Widget`），和 SideStore 重签后一致，Xcode 运行（默认就是 Debug）会直接覆盖 SideStore 装的那一份。Release（CI 出的 IPA）标识不变。
- 免费账号拿不到 App Group，所以 Debug 用不含 App Group 的权限文件 `ios/Config/AppDebug.entitlements`、`WidgetDebug.entitlements`，且 `Cfg.defaults` 在 Debug 下用本机偏好。结果：Xcode 覆盖安装后令牌/钱包要重新填一次（深链 `tstzm://setup?token=...` 一键写入令牌）；之后再用 SideStore 装 CI 的 IPA，App Group 里的旧数据会回来。
- 用 Xcode 时必须在两个 target 的 Signing 里选 Personal Team（团队 ID 才会拼进标识）；别用 Release / Archive 去装，否则又是不带后缀的标识。
- 旧的「不带后缀」Xcode 副本只能用户手动删一次（长按图标 → 删除 App）。判断方法：新版「盯盘看板」（代币页左上角仪表图标）底部有「安装信息」卡片，显示标识和团队 ID；没有这张卡片的那个图标就是旧副本。
- 免费账号限制（资料口径，未逐条验证）：同时最多 3 个应用（SideStore 本体算 1 个），扩展占 App ID，每周最多 10 个新 App ID；所以别改应用标识（会白白消耗 App ID）。小组件和灵动岛已经在同一个扩展 `TSTZMWidget` 里（`TSTZMWidgets` 组合），只占一个扩展名额。

## 三、已完成（不要重做）
- AI：引擎端清洗输出 + Groq 多模型 + 可选后端（Cerebras/Gemini/OpenRouter/Mistral，有密钥才启用）；App 端容错解码 + 苹果设备端模型兜底；不使用 Workers AI（用户不接受）。
- 规则分析引擎（不依赖 AI）：`AnalysisEngine.swift`；综合研判 `Verdict.swift`；分项明细 `ReportCard.swift`。
- 生命周期 + 社交 `LifeSocial.swift`；叙事（15 类主题词库 + 相似叙事 + 级别 + 热度）`NarrativeEngine.swift`。
- 钱包情报 `WalletIntel.swift`（Solana，自研：标签 + 行为信号）；持有人一键全查 `HoldersIntelView`；钱包页「查询地址」整合我的钱包与情报入口。
- 数据落盘（`TokenSnapshot.swift`）、旧数据显示时间、启动即刷新旧数据、全局「全部刷新」。
- K 线：TradingView Lightweight Charts v4，主图/副图，指标 MA/EMA/BOLL/SAR/SUPER + VOL/MACD/KDJ/RSI/ROC，十字线浮窗，市值/价格切换，大户标记，向左拖懒加载历史，本地缓存。
- 2026-11-12：头像体系 `Avatars.swift`（代币头像多来源兜底、链徽章、钱包像素头像）；交易所风格头部 `CompactHeader.swift`；一行搜索栏 `AvSearchBar` + 记录弹层 `AvHistorySheet` + 头像记录条 `AvRecentStrip`；K 线周期加「周、月」（`KlineExtras.swift`）；图表自愈；盯盘看板 `MarketBoard.swift`（底部「安装信息」「系统诊断」`DiagnosticsView`）；深度分析 `DeepAnalysis.swift`（深度研判/成交深度/筹码深度/持仓结构）；寒霜已从 App 和仓库删除。

## 四、待办（按优先级）
1. 需要用户在手机上验证本轮（云端只能验证编译通过，验证不了视觉和手机直连）：令牌页 Logo、下拉 Logo、K 线价格轴「0.0₆」写法、实时价补齐、秒切周期、持有人榜单（或 GoPlus 前 10 大兜底）、收藏、情报标签。
2. 限流残留：头像（GeckoTerminal 代币信息）、盯盘看板热门/新池仍直接请求，没走 `DataGate`；其它页面的 `.refreshable` 还没换 Logo；K 线源只有 GeckoTerminal，添加「用链上 Swap/Sync 事件自建 K 线」作为第二源（Alchemy eth_getLogs，BSC 约 3 秒/块）。
3. 选中 K 线后「成交/钱包分析」查不到：GeckoTerminal 成交只有最近约 300 笔 / 24 小时。设计：引擎新增 `/e/sol/window?pair=&mint=&from=&to=`（`getSignaturesForAddress` 翻页 + Helius `POST /v0/transactions` 解析 swap）；EVM 按时间二分找区块 + `eth_getLogs`。
4. 更多热门链：`ios/Shared/Core.swift` 的 `Chain` 枚举加 avalanche、linea、scroll、blast、zksync、mantle、fantom、cronos、sonic、berachain 等；非 EVM（tron / ton / sui）要补地址识别；新增链要同步补 `Avatars.swift` 里 `Chain.avMark` / `avColors` 两个 switch。
5. 情报页还可加：EVM 钱包情报（目前只有 Solana）、Solana 捐绑/狙击（同区块买入的新钱包）、社交情绪（现有 `SocialCard` 只有官方链接与叙事）、服务器端监控（Cloudflare cron + Telegram 机器人推送，免费，需要用户的 bot token）。
6. DeFade：需要用户领到 df_ 密钥后在手机上试一次，确认 MCP 初始化流程和工具名（`get_token_scan` 等）正确；不对就按其返回的报错改。

## 五、用户偏好
简体中文；极度简洁；用无序列表；不要开场白和结尾套话；全部免费方案；数据必须准确、缺什么就写「未知」不编造；任何功能要有备用兜底；AI 与不依赖 AI 的规则分析两条轨道并行。
