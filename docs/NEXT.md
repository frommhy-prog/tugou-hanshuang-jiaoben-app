# TSTZ-M 新对话接手清单（2026-11-13）

仓库 frommhy-prog/tugou-hanshuang-jiaoben-app，App 在 `ios/`，改动用 CI 云编译，用户不会写代码，全部由助手直接改仓库并验证。

## 零、先看这个
- 同一个仓库可能被多个对话同时改。2026-11-12 07:55 另一个对话覆盖了 `Avatars.swift`、`MarketBoard.swift` 并新增了重复的 `KRoll.swift`，造成编译失败，已还原为统一版本。新对话开头先看最近提交，别重做已完成的事；提示用户「同一个项目不要开两个对话同时改」。
- 用户已澄清：不是把 OSVIA 合并进 TSTZ-M；目标只是 TSTZ-M「Xcode 直装」和「SideStore 安装」是同一个应用（见第二节）。

## 一、工作方式
- 小改动用补丁清单：`.github/patches/plistN.py`（`rep(tag, 文件, 旧文本, 新文本)` / `cut(tag, 文件, 起点, 终点, 新文本)`），CI 编译前由 `apply.py` 应用；按文件事务（任一锚点不匹配，该文件整体不改），已应用的标签记在 `.github/patches/applied.txt`，补丁后的源码会被 CI 回写仓库。新增大块功能直接新建 Swift 文件。目前最大补丁批次是 plist16。
- 读结果：`ios/ci/patch-result.txt`（PATCH_OK / PATCH_FAILED）、`ios/ci/build-result.txt`、`ios/ci/build-errors.txt`、`ios/ci/bundle-check.txt`。一次构建约 5–8 分钟，**每次推送到 `ios/App/**`、`ios/Shared/**`、`ios/project.yml`、`.github/patches/**`、工作流都会触发构建并取消在途的那次**，所以一批改动要连续推完（新文件先推，补丁文件最后推）；文档（`docs/`、README）不触发构建。
- 等构建：`bash_tool` 里 `sleep 200` 可以用；`gh_commits` 和 `gh_api GET commits` 输出极长，查最近提交改了哪些文件用 `git/trees/<提交>:ios/App` 对比文件大小；要把旧版本文件原样还原，用 git data API（`git/trees` 带 `base_tree` + 旧 blob sha，再 `git/commits`、`PATCH git/refs/heads/main`），不用重发内容。
- 编译器常见坑：表达式过长要拆开（`the compiler is unable to type-check`）；ViewBuilder 一组最多 10 个子视图；`Verdict` 已被占用，综合研判类型叫 `TokenVerdict`；字符串拼接统一用 `cat(...)`；模型输出/接口 JSON 用 `JV` 容错解码（`Lossy.swift`）；新增类型名带独特前缀（头像体系用 `Av`），避免与已有类型重名。
- 引擎（Cloudflare Worker `tstzm-engine`）：源码 `worker-engine/`，`v2.js` 是入口包装，原模块在 `v2base.js`，AI 在 `ai.js`；部署用 gh_deploy（extra_paths 含 evm.js、v2.js、v2base.js、ai.js）。可以用队列控制台探测：`POST /queues/<id>/messages` 发 `{op:"api",path:"/e/..."}` 或 `{url:"https://..."}`，结果读 D1 `selftest`。注意：云端出口被 GeckoTerminal / Dexscreener / GoPlus 限流，这些接口必须在手机直连验证。
- SideStore 源：`sidestore/source.json`，每个构建一个固定下载地址 `releases/download/build-N/TSTZ-M.ipa`，只保留最近 6 个。改了源后用户要在 SideStore 里删掉源再重新添加一次。

## 二、安装方式：Xcode 与 SideStore 是同一个应用
- SideStore 重签会把标识改成「原标识.团队ID」（扩展是「原标识.团队ID.Widget」，App Group 同样补团队 ID）。以前 Xcode 直装用的是不带后缀的原标识，所以手机上会有两个一模一样的图标。
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
- 2026-11-12 本轮：
  - 头像体系 `Avatars.swift`：代币头像多来源兜底（已知链接 → Dexscreener 图床 → GeckoTerminal 代币信息，内存 + 磁盘缓存）、链徽章（10 条链自绘）、钱包像素头像（按地址生成）；查询记录带头像地址 `HistoryItem.logo`。
  - 交易所风格头部 `CompactHeader.swift`：头像 + 链徽章 + 代币/报价币 + 叙事标签（紧挨头像，点一下跳叙事页）。
  - 一行搜索栏 `AvSearchBar` + 记录弹层 `AvHistorySheet`（可搜索、左滑删除、清空）+ 头像记录条 `AvRecentStrip`；钱包页（查询地址、我的钱包、钱包详情）同样带头像。
  - K 线周期加「周、月」（日线本地汇总，`KlineExtras.swift` 的 `TF.rolled` / `kBucket`，`TF` 新增 `.w1` `.mo1`）；图表自愈：页面脚本报错可见、3.5 秒没渲染就重载（最多 2 次）、仍失败退回系统基础 K 线图。
  - 盯盘看板 `MarketBoard.swift`（原仪表盘数据源诊断改名「系统诊断」`DiagnosticsView`，在看板底部入口）：大盘（CoinGecko）、我的盯盘（最近查过的代币，Dexscreener 批量行情）、各链热门/新池（GeckoTerminal），点一行直接分析；底部「安装信息」。
  - 深度分析 `DeepAnalysis.swift`：代币总览加「深度研判」（盘面温度、K 线结构：均线/RSI/支撑阻力/量能/阶段、承接与滑点）；成交页加「成交深度分析」（单笔大小分档、买卖地址数、节奏、连续同向、对倒嫌疑）；筹码页加「筹码深度分析」（成本中枢、获利盘/套牢盘、同批入场抱团、等效持有人数）；选中 K 线的交易分析补买卖地址数与大单占比；Solana 钱包分析页内嵌钱包情报 `WalletIntelInline`；钱包持仓页顶部加「持仓结构」`HoldingsDeepCard`。
  - 寒霜：App 内早已移除，本轮又删除了旧 Worker 源码 `worker/`、旧原型 `app/`、`xcode-prep/`，SideStore 源文案去掉寒霜字样。线上同名旧 Worker 没动。

## 四、待办（按优先级）
1. 选中 K 线后「成交/钱包分析」查不到：GeckoTerminal 成交只有最近约 300 笔 / 24 小时，选中更早的 K 线就为空。设计：引擎新增 `/e/sol/window?pair=&mint=&from=&to=`——用 RPC `getSignaturesForAddress(pair)` 翻页（每页 1000，带 blockTime）定位窗口内签名，再用 Helius `POST /v0/transactions`（≤100 个签名一批）解析 swap，返回买卖笔数、地址聚合、原始成交；App 侧在 `UTokenVM` 加 `selWindow`（`KLineCard` 选中时写入），在「成交」标签页加 `WindowTradesCard` 展示，USD 用该 K 线价格 × 代币数量估算。EVM 需按时间二分找区块 + `eth_getLogs`。
2. 更多热门链：`ios/Shared/Core.swift` 的 `Chain` 枚举加 avalanche(gecko `avax`)、linea、scroll、blast、zksync、mantle、fantom(`ftm`)、cronos(`cro`)、sonic、berachain 等（Dexscreener chainId 与 GeckoTerminal 网络 id 要在手机上核对）；非 EVM（tron / ton / sui）要补地址识别（Tron 地址与 Solana 的 Base58 正则冲突，要先判 `^T[1-9A-HJ-NP-Za-km-z]{33}$`）；新增链要同步补 `Avatars.swift` 里 `Chain.avMark` / `avColors` 两个 switch（否则编译失败），盯盘看板的链选择条也要加。
3. 行情源备用：DexPaprika 免费无密钥额度已被全球耗尽；GoPlus、RugCheck 云端被限流，只能手机直连。Dexscreener 失效时切 GeckoTerminal 的映射还没写。
4. EVM 钱包情报（目前只有 Solana）。
5. 需要用户在手机上验证：K 线是否还空白（现在有自愈和基础图兜底，若仍异常，页面左上角会显示脚本错误文字，让用户截图）；各链币头像是否出来；周线/月线；盯盘看板三个分段；Xcode 覆盖安装是否不再多出图标。
6. 「深度研判」里的结构分析取自图表当前周期与已加载范围；若要固定用某个周期（如 1 小时）做结构判断，需要单独拉一份 K 线。

## 五、用户偏好
简体中文；极度简洁；用无序列表；不要开场白和结尾套话；全部免费方案；数据必须准确、缺什么就写「未知」不编造；任何功能要有备用兜底；AI 与不依赖 AI 的规则分析两条轨道并行。
