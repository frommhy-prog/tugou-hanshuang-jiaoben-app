# TSTZ-M 交接说明（新对话先读这个）

不含任何密钥。令牌、Groq、Helius、Alchemy、交易所密钥都在用户手里或 Worker 加密库/Secret 里，不要写进仓库。
用户不会写代码：方案要自动执行；回答极度简洁、简体中文、无客套、无结尾总结。**铁律：数据必须客观真实，查不到写「未知」，每条结论给依据；拿不准的宁可不算。**

## 项目目标
免费原生 iOS App「TSTZ-M」，Mac 开发，日常使用脱离电脑。优先：代币分析（行情/K线/成交流向/池子/持有人/大户成本盈亏/叙事/安全）、钱包交易记录分析、交易所持仓、分享、寒霜启示录兑换。用户要的是「分析」（给判断和依据），不是把买了多少卖了多少列出来；要交易所风格图表，不要圆环/仪表盘。

## 架构（全部免费）
- 仓库 `frommhy-prog/tugou-hanshuang-jiaoben-app`（公开）。iOS 工程 `ios/`（XcodeGen）。旧 `xcode-prep/` 待删。
- **Worker 源码在仓库，改仓库文件再 `gh_deploy`（绑定/Secret 自动保留）**：
  - 引擎 `worker-engine/`（worker.js + evm.js + v2.js）：`gh_deploy`（path=`worker-engine/worker.js`、extra_paths=`["worker-engine/evm.js","worker-engine/v2.js"]`、root=`worker-engine/`、script=`tstzm-engine`、compat_date=`2026-10-27`）。以后新增引擎功能优先写进 v2.js（`/e/v2/*`），不要再动 worker.js。
  - API 网关 `worker-api/worker.js`：`gh_deploy`（path=`worker-api/worker.js`、root=`worker-api/`、script=`tstzm-api`）。密钥白名单 PROVIDERS 已含 alchemy。
  - 联系页 `tstzm-contact`（小 Worker，源码即 `docs/c.html` 内嵌，线上 https://tstzm-contact.from-mhy.workers.dev/ ，页面读 URL # 后的 base64url 载荷，账号遮挡显示，点击跳转邮件/Telegram，二维码用 api.qrserver.com 生成）。GitHub Pages 用 token 开不了（403），所以走 Worker。
  - 旧 Worker `tugou-hanshuang-jiaoben-app`（Muse 做，源码 `worker/src/index.js`）：`/api/token`（EVM 安全信号）、`/api/wallet-portfolio`、`/api/wos-codes`、`/api/fx`、`/api/feedback` 等，经服务绑定调用。
- 云编译：`.github/workflows/ios-build.yml`（约 2 分钟）。**判断是否编译通过：`gh_api GET /repos/<repo>/commits/<sha>/check-runs?per_page=1` 看 conclusion；失败读 `ios/ci/build-errors.txt`。不要用 `gh_runs`、`gh_commits`（输出巨大）。** `gh_put` 只能整文件覆盖、不要传 branch；改大 Swift 文件要整份重发，所以新功能尽量放新文件。
- 队列远程控制台（调试）：`cf_api POST /queues/26998799521b4a35832fd73df7b77b03/messages`，body `{"body":{"name":"x","op":"api","path":"/e/...","max":4000,"hint":"apac"}}`（`hint` 指定 DO 机房；`/e/v2/cex*` 自动亚太）或不带 op 直接探测第三方（url 里 `{{alchemy}}`/`{{helius}}`/`{{groq}}` 自动代入；域名后缀白名单见 worker.js `HOST_SUFFIX`）。等 20–40 秒用 `cf_d1_query` 读 D1 `tstzm`（id `7c59261f-fbe3-4ae7-b428-21b5d14c3a1e`）表 `selftest`。
- 密钥：`ALCHEMY_API_KEY` 已作为 Secret 写入 `tstzm-engine`（用户在聊天里给的免费 Key；也可在 App「设置 → API 密钥」绑定 alchemy）。Groq/Helius/Telegram/Bark/交易所密钥在 D1 加密库。
- 免费档限制：Worker 单次 10ms CPU、50 子请求；Helius 会 429；Alchemy 3000 万 CU/月、约 300 CU/s；**Dexscreener/GeckoTerminal 从引擎云出口经常 429（Cloudflare 1015），所以公共行情由手机直连**；**币安（api.binance.com 与 data-api.binance.vision）对 Cloudflare 出口返回 403，不可从引擎调用**；欧易、Gate 公共/私有接口从引擎可用。
- 记忆写入：本对话用过连接器后系统禁止写记忆，进度只存在这份文件和仓库里。

## 已完成（本轮，云编译均通过，用户已安装最新版）
引擎（已部署）：
- `/e/evm/*`（Alchemy）：钱包逐笔配对、持有人还原、`/e/v2/holder` 持有人拆解。BSC 实测：Alchemy 对 BSC 不支持 internal，卖出所得用区块前后余额差反推（标 ≈，每次最多 300 笔，同区块多笔不硬分，读取失败/疑似转出的币标 partial/xout，不计盈亏与剩余持仓）。
- `/e/v2/holder`（Solana + EVM）：金额统一折算美元（SOL/BNB/ETH 计价按成交时刻小时开盘价线性插值，价格源 Gate 公共 K 线 → 欧易回退；稳定币取面值），输出入场时点（狙击/早期/上线首小时/后来者）、平均成本、现价、浮动/已兑现、综合回报、抛压（持仓价值÷池子流动性）、状态、规则洞察（每条附依据）。EVM 已用真实 BSC 数据测通；**Solana 路径尚未用真实数据实测。**
- `/e/v2/ai`（旧 `/e/ai` 也并入）：Groq 多模型回退（gpt-oss-120b → llama-3.3-70b → gpt-oss-20b → llama-3.1-8b）、15 分钟结果缓存、输出 headline/stance/points[claim,why,evidence]/risks/watch/unknown，禁止字段路径式依据。已实测。
- `/e/v2/narrative`：依据名称/简介/社交/分类归纳叙事，资料不足写「信息不足」。已实测。
- `/e/v2/cex?ex=okx|gate|binance` 只读持仓；`/e/v2/cexsign?ex=binance` 返回签名好的只读请求，由手机直连币安（密钥不出服务端）。OKX 实测通（该账户只有极小余额）；Gate、币安中继路径未实测。
- `/e/mcp`：MCP 服务（Streamable HTTP，工具 wallet_analysis/token_holders/holder_analysis/cex_balances，Bearer 同 App 令牌）。`/e/v2/px`、`/e/v2/_get` 为调试接口。
iOS（新增/重写的文件）：
- `Core.swift`：`Net.fetch`（独立任务 + 瞬时错误重试，修「网络失败：已取消」）、Chain 增加 `dexId/geckoId`。`Engine.swift`：统一时区格式化、美元格式、新版 AI 卡片、`FindingRow` 时间改写。
- `Prefs.swift`：统一时区 `TZ`（默认北京时间，设置里可改，引擎文本里的「yyyy-MM-dd HH:mm UTC」自动改写）、查询记录 `QueryHistory`、开发者联系方式 `ContactStore`（邮箱 from_xm@qq.com / tstzrxm@gmail.com、微信 TSTZ-M（二维码链接 `https://u.wechat.com/MH_5bYaNJF6LZ9VEznuZbNQ?s=2`，分享图只显示二维码）、Telegram CA_PYBARAS（一键跳转 + 字样「可按需定制」）；设置里可增删、可选是否在分享中展示/遮挡/只显二维码；分享文本带遮挡后的联系页链接，链接里的账号只是 base64 编码，不是强加密）。
- `UnifiedTokenModel.swift` + `UnifiedToken.swift`：统一代币页（一个输入框自动识别 Solana/EVM，查询记录，每 20 秒自动刷新）：头部、K 线+成交量（Swift Charts，1分/5分/15分/1时/4时/日，可拖动读数，GeckoTerminal 直连）、关键数据、规则分析结论、AI 研判、叙事（`Narrative.swift`，含「历史相似叙事」：用名称/关键词在 Dexscreener 搜同类代币统计现状，提示存活偏差）、**代币成交分析**（GeckoTerminal 最近成交：多窗口买卖/净流入、资金流向图、活跃地址、大单、对敲嫌疑）与**池子分析**（各池流动性占比、成交、价差）分开、持有人与大户拆解（集中度条、前 10 普通钱包两路并行拆解、综合回报条形图、可展开明细）、合约安全、跳转。
- `ShareKit.swift`：分享图片+文本（代币页右上角分享，按设置附联系方式）。`CexView.swift`：`WalletsRoot`（链上钱包/交易所/查询地址三段）、`AdHocWalletRoot`（查询任意地址+记录）、交易所持仓页。`Connectors.swift`：MCP 连接器（对外：本 App 服务地址/令牌/配置；对内：添加其他 MCP 服务并调用工具）。设置页新增时区、MCP 连接器、联系方式与分享。
- `FrostView.swift`/`WosRedeem.swift`：手动/自动合并为「兑换」一键（自动失败自动转官方页，ID 与兑换码已填好）；领主资料本机兜底（ID 726154631、王国 4124、初始 4186、联盟 ONE，可编辑，修「王国空白」）；登录接口异常不再直接判死。
- `TSTZMApp.swift`：根视图用 `UnifiedTokenRoot`/`WalletsRoot`，启动应用时区。旧 `SolTokenView.swift`（AnalyzeRoot）、`TokenView.swift`（仅 `AlertPrefill` 仍被使用）已成死代码。

## 未完成 / 待核实（按优先级）
1. **让用户真机试新版并反馈**：代币页各块是否正常；EVM 持有人在大币上是否读不完（>6000 笔转账显示未知）；大户拆解耗时（Solana 每个钱包 2 页 Helius，两路并行，10 个约 30 秒）。
2. **Solana `/e/v2/holder` 用真实数据实测**（队列里发了 `sol-token-bonk` 探测但未读结果；取 BONK `DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263` 的最大普通钱包再测）。
3. **寒霜自动兑换「登录失败」根因未确认**：无法从引擎测官方接口（`centurygame.com` 不在探测台白名单）。已加重试和容错；请用户把寒霜页「兑换日志」复制给我，据此修（可能是接口改版/签名/地区限制）。
4. 交易所：Gate 与币安手机直连中继未实测；币安若手机出口也被拒（403/451），需换节点。
5. 钱包详情页仍是旧版：Solana 持仓只按 SOL 计价、没有美元统一和规则洞察、没有分享按钮、总资产页仍是圆环图（用户不喜欢圆形图，可换成条形/面积图）。应把大户拆解那套「美元口径+入场+洞察」搬到钱包页，并接 `ShareKit.generalItems`。
6. 「整体布局优化」只做了代币页与钱包外壳；提醒页、设置页、钱包页、小组件还没按交易所风格重做；速度优化可再做（K线/成交已直连并每 20 秒刷新；引擎结果已缓存）。
7. Telegram 二维码图未使用（分享图里 Telegram 以文字入口 + 一键跳转呈现）；如需二维码样式，可把 Telegram 条目的 `qrLink` 填 `https://t.me/CA_PYBARAS`。
8. 叙事的「历史叙事」目前解读为「历史相似叙事代币现状」（无历史最高价、无社媒热度，免费数据源没有）；可加 GoPlus/Rugcheck 安全信号、DexPaprika 成交明细作补充。
9. 其余：Robinhood/X Layer/OKTC 链数据源；持有人资金来源聚类；删除 `xcode-prep/` 与死代码；SideStore 自动续签验证（免费账号 3 个 App 限制）；Helius 额度与进度提示。

## 约定
- 改引擎：改仓库文件 → `gh_deploy` → 用队列探测验证；改 App：新功能放新文件，必须改旧大文件时整份重发，推送后用 check-runs 判编译。
- Swift 用 `SWIFT_VERSION 5.0`；SwiftUI 一个块最多 10 个子视图（`content` 已分两个 Group）；长字符串拼接可能触发「表达式过于复杂」，必要时拆开。
- 数据口径：原生币与美元计价分开显示；美元折算只用于大户拆解并写明是近似；卖出所得拿不准的币不计盈亏。
