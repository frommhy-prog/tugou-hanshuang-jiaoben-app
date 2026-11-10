# TSTZ-M 新对话接手清单（2026-11-10，构建通过）

仓库 frommhy-prog/tugou-hanshuang-jiaoben-app，App 在 `ios/`，改动用 CI 云编译，用户不会写代码，全部由助手直接改仓库并验证。

## 一、工作方式（先读这一节）
- 小改动用补丁清单：`.github/patches/plistN.py`（`rep(tag, 文件, 旧文本, 新文本)` / `cut(tag, 文件, 起点, 终点, 新文本)`），CI 编译前由 `apply.py` 应用；按文件事务（任一锚点不匹配，该文件整体不改），已应用的标签记在 `.github/patches/applied.txt`，补丁后的源码会被 CI 回写仓库。新增大块功能直接新建 Swift 文件（gh_put / gh_push）。
- 读结果：`ios/ci/patch-result.txt`（PATCH_OK / PATCH_FAILED）、`ios/ci/build-result.txt`、`ios/ci/build-errors.txt`、`ios/ci/bundle-check.txt`。一次构建约 8 分钟，同一时间只保留最新一次（并发取消）。
- 编译器常见坑：表达式过长要拆开（`the compiler is unable to type-check`）；ViewBuilder 一组最多 10 个子视图；`Verdict` 已被占用，综合研判类型叫 `TokenVerdict`；字符串拼接统一用 `cat(...)`；模型输出/接口 JSON 用 `JV` 容错解码（`Lossy.swift`）。
- 引擎（Cloudflare Worker `tstzm-engine`）：源码 `worker-engine/`，`v2.js` 是入口包装，原模块在 `v2base.js`，AI 在 `ai.js`；部署用 gh_deploy（extra_paths 含 evm.js、v2.js、v2base.js、ai.js）。可以用队列控制台探测：`POST /queues/<id>/messages` 发 `{op:"api",path:"/e/..."}` 或 `{url:"https://..."}`，结果读 D1 `selftest`。注意：云端出口被 GeckoTerminal / Dexscreener / GoPlus 限流，这些接口必须在手机直连验证。
- SideStore 源：`sidestore/source.json`，每个构建一个固定下载地址 `releases/download/build-N/TSTZ-M.ipa`，只保留最近 6 个。改了源后用户要在 SideStore 里删掉源再重新添加一次。

## 二、已完成（不要重做）
- AI：引擎端清洗输出 + Groq 多模型 + 可选后端（Cerebras/Gemini/OpenRouter/Mistral，有密钥才启用）；App 端容错解码 + 苹果设备端模型兜底；不使用 Workers AI（用户不接受）。
- 规则分析引擎（不依赖 AI）：`AnalysisEngine.swift`；综合研判 `Verdict.swift`（安全分、一句话结论、利空利好、盯盘阈值、较上次变化、数据覆盖度、AI 冲突提示）；分项明细 `ReportCard.swift`。
- 生命周期 + 社交 `LifeSocial.swift`；叙事（15 类主题词库 + 相似叙事 + 级别 + 热度）`NarrativeEngine.swift`。
- 钱包情报 `WalletIntel.swift`（Solana，自研：标签 + 行为信号；Wallet Intel 托管接口按次收费、Psych 仓库无许可证，所以不调用不复制）；持有人一键全查 `HoldersIntelView`；钱包页「查询地址」整合我的钱包与情报入口。
- 数据落盘（`TokenSnapshot.swift`）、旧数据显示时间（`FreshnessRow`）、启动即刷新旧数据、全局「全部刷新」。
- 仪表盘 + 控制台（`Dashboard.swift`，代币页左上角入口）；`Net.fetch` 带请求日志和「切断来源」。
- K 线：TradingView Lightweight Charts v4，主图/副图两个图表，指标 MA/EMA/BOLL/SAR/SUPER + VOL/MACD/KDJ/RSI/ROC，十字线浮窗，市值/价格切换，大户标记，向左拖懒加载历史，本地缓存。
- 代币页：K 线卡片顶部内嵌紧凑头部（头部与 K 线合二为一），下面标签页（总览/成交/筹码/风险/叙事/更多）。
- 寒霜已从 App 移除（`FrostView.swift`、`WosRedeem.swift`、标签页、深链、路由字段全部删除，构建通过）。

## 三、待办（按优先级）
1. 选中 K 线后「成交/钱包分析」查不到：原因是 GeckoTerminal 成交只有最近约 300 笔 / 24 小时，选中更早的 K 线就为空。设计：引擎新增 `/e/sol/window?pair=&mint=&from=&to=`——用 RPC `getSignaturesForAddress(pair)` 翻页（每页 1000，带 blockTime）定位窗口内签名，再用 Helius `POST /v0/transactions`（≤100 个签名一批）解析 swap，返回买卖笔数、地址聚合、原始成交；App 侧在 `UTokenVM` 加 `selWindow`（`KLineCard` 选中时写入），在「成交」标签页加 `WindowTradesCard` 展示，USD 用该 K 线价格 × 代币数量估算。EVM 需按时间二分找区块 + `eth_getLogs`。
2. 更多热门链：`ios/Shared/Core.swift` 的 `Chain` 枚举加 avalanche(gecko `avax`)、linea、scroll、blast、zksync、mantle、fantom(`ftm`)、cronos(`cro`)、sonic、berachain 等（Dexscreener chainId 与 GeckoTerminal 网络 id 要在手机上用 `/api/v2/networks` 核对）；非 EVM（tron / ton / sui）要补地址识别（Tron 地址与 Solana 的 Base58 正则冲突，要先判 `^T[1-9A-HJ-NP-Za-km-z]{33}$`）；引擎 `EVMX` 支持的链表决定持有人/安全能不能查，不支持的链要优雅提示。
3. 行情源备用：DexPaprika 免费无密钥额度已被全球耗尽（要用户注册免费 key）；GoPlus、RugCheck 云端被限流，只能手机直连。Dexscreener 失效时切 GeckoTerminal 的映射（`attributes` → Dexscreener 字段）还没写。
4. EVM 钱包情报（目前只有 Solana）。
5. 用户说过「K 线还是不对」但没说具体哪里，需要用户圈出来。
6. 寒霜后端残留：旧 Worker 源码 `worker/`（97KB，含寒霜兑换码与 Telegram）、旧原型目录 `app/`、`xcode-prep/`、相关文档，没有删（删 Worker 源码不会删线上 Worker，但会影响重新部署），要用户确认后再删。
7. 页面顶部的「粘贴并分析」输入框还占一块高度，可收成一行搜索栏。
8. Xcode 本地运行：两个 target 的 Signing (Debug) 的 Team 要选 Personal Team；免费账号不支持 App Groups，本地真机跑可能再报错，正路是 CI 的 IPA + SideStore。

## 四、用户偏好
简体中文；极度简洁；用无序列表；不要开场白和结尾套话；全部免费方案；数据必须准确、缺什么就写「未知」不编造；任何功能要有备用兜底；AI 与不依赖 AI 的规则分析两条轨道并行。
