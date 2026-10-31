# TSTZ-M 交接说明（新对话先读这个）

不含任何密钥。令牌、Groq、Helius 等密钥都在用户手里或 Worker 加密库里，不要写进仓库。

## 项目目标
免费原生 iOS App「TSTZ-M」，Mac 开发，日常使用脱离电脑。**优先交易方向**：钱包交易记录分析判断、代币交易记录分析、持仓人分析；自己的钱包可多个添加、多选删除，能看具体交易记录和持仓。铁律：**数据必须客观真实，查不到写「未知」，每条结论给出依据**。用户不要和其他交易所/平台重复的功能。寒霜启示录先不管。
用户不会写代码：方案要自动执行；回答极度简洁、简体中文、无客套、无结尾总结。

## 架构（全部免费）
- 仓库：`frommhy-prog/tugou-hanshuang-jiaoben-app`（已公开）。新工程在 `ios/`（XcodeGen：`project.yml`，源码 `App/ Shared/ Widget/`）。旧的 `xcode-prep/` 是半成品，待用户确认新版可用后再删。
- 云编译：`.github/workflows/ios-build.yml`（macOS runner）。编译结果读 `ios/ci/build-result.txt`、`ios/ci/build-errors.txt`、`ios/ci/build-tail.txt`；成功后发布 Release `latest` 的 `TSTZ-M.ipa`，并更新 `sidestore/source.json`（SideStore 源：`https://raw.githubusercontent.com/frommhy-prog/tugou-hanshuang-jiaoben-app/main/sidestore/source.json`）。推送一批文件后等约 4–5 分钟再读结果；连续推送会取消前一次运行。
- 推送文件用 `gh_put`（原样文本，不要传 `branch` 参数，传了会报 malformed）。只能整文件覆盖，没有局部补丁。
- Bundle ID `com.Hao-Yi-Miao.TSTZ-M`，小组件 `.Widget`，App Group `group.com.Hao-Yi-Miao.TSTZ-M`，iOS 17+，URL scheme `tstzm://`（`setup?token=`、`frost?code=`）。图标由 `ios/tools/make_icon.swift` 在 CI 绘制（白底、海军蓝金圈 logo）。
- Cloudflare（账号 workers 子域 `from-mhy`）：
  - `tstzm-api`：App 主网关。Bearer 令牌鉴权，转发旧 Worker 的 `/api/*`，加密密钥库（D1 `vault`，主密钥 Secret `VAULT_KEY`），提醒 CRUD，寒霜新码检测，额度，Durable Object `Scheduler` 闹钟（每 5 分钟检查提醒、每 30 分钟检测新码）。账号 5 个 Cron 名额已被 `kuaishou-data-monitor`(1) 和 `tstz-im-gateway`(4) 占满，不要动它们，所以用 DO 闹钟。
  - `tstzm-engine`：分析引擎。App 直接请求，同一个 Bearer 令牌。路由 `/e/sol/token|wallet|holder|pool`、`/e/ai`。所有计算在 Durable Object `Job` 里（实测 DO 的 CPU 额度充足；普通 Worker 免费档只有 10ms CPU，别在里面做重计算）。
  - 旧 Worker `tugou-hanshuang-jiaoben-app`（Muse 做的，代码在 Cloudflare、读不全）：仍提供 `/api/token`、`/api/wallet-portfolio`、`/api/token-deep`、`/api/fx`、`/api/wos-codes`、`/api/feedback` 等，经服务绑定被调用。
  - D1 `tstzm`（id `7c59261f-fbe3-4ae7-b428-21b5d14c3a1e`）：表 `kv vault alerts quota usage selftest wos_codes cache`。Queue `tstzm-jobs`（id `26998799521b4a35832fd73df7b77b03`，消费者是 `tstzm-engine`）。
- 免费档限制：Worker 免费档单次 10ms CPU、50 个外部子请求；KV 每天 1000 次写；Helius 免费档会 429 限速（引擎已做退避和翻页间隔 450ms）。

## 我这边的远程调试方法（很有用）
没有网络直连时，用队列当"远程控制台"：
1. `cf_api POST /queues/26998799521b4a35832fd73df7b77b03/messages`，body 为 `{"body": {"name": "任意名", "op": "api", "path": "/e/sol/wallet?address=…&pages=2&fresh=1", "max": 6000}, "content_type": "json"}`。要带 POST 体就加 `"method":"POST","body":{…}`。也可不带 `op` 直接探测第三方（`url` 里用 `{{helius}}`、`{{groq}}` 自动代入库里的密钥，主机白名单见引擎代码）。
2. 等 20–40 秒，`cf_d1_query` 读 `SELECT name, json_extract(out,'$.status'), substr(json_extract(out,'$.head'),1,3000) FROM selftest WHERE name='…' ORDER BY ts DESC LIMIT 1`。
3. 用户应用内反馈存在旧 Worker 的 KV（namespace `a2682f9a6b074a508afdc16ff74c1bfb`，键 `feedback:*`，图片很大，读取前先用 `feedback:index` 看列表）。

## 已完成
- App：代币页（顶部切 Solana / EVM）、钱包页（一次粘贴多个、多选删除、详情含持仓/交易记录/分析）、寒霜页（手动一键跳转并预填、自动兑换引擎含本机验证码识别，未实测）、提醒页、设置页（主题三档、计价货币、连接令牌、API 密钥与额度含 Groq 真实剩余和倒计时、反馈）、小组件和灵动岛（只在 App 前台更新）。
- 引擎（Solana，已用真实数据测过）：
  - `/e/sol/token`：链上读 mint 权限、最大 20 个账户并按钱包/池子/合约分类、集中度、结论与依据。
  - `/e/sol/wallet`：Helius 解析后的 SWAP 历史 → 用链上余额变化提取买卖 → 平均成本法算已兑现盈亏、胜率、持仓时间、风格标签（每个标签附判定规则和数值）。卖出找不到买入的不计盈亏并明说。
  - `/e/sol/holder`：单个大户在该币上的成本/盈亏/首次买入 + 整体风格。
  - `/e/sol/pool`：池子最近 swap 的买卖额、集中度、对称地址提示。
  - `/e/ai`：Groq 只解读已算出的 facts。模型从 `/models` 动态挑选（现为 `openai/gpt-oss-120b`；旧的 llama-3.3 已下线）。额度响应头写入 D1 `quota`，设置页读取。
- 新码检测：6 个社区站点多站共识 + 旧 Worker 名单，首次只建基线不推送；新码推送到 Telegram/Bark（Bark 点开直接进寒霜页）。
- 已知真实发现：旧数据源对 Solana 没有持有人数据（所以界面原来全是"未知"）；Helius 解析后的单笔交易约 12KB，100 笔一页约 1.2MB。

## 待办（按优先级）
1. **EVM 钱包逐笔交易记录和分析、EVM 代币持有人分析**：计划用 Alchemy `alchemy_getAssetTransfers`（按交易哈希把进出的代币配对成 swap，原生币/稳定币计价）。Alchemy 密钥目前只在旧 Worker 的 Secret 里读不出来，需要用户在 App 里绑定：给 `tstzm-api` 的 `PROVIDERS` 加 `alchemy`（要重发整份代码），或在引擎里加密钥写入接口。
2. 让用户在真机上试 Solana 代币页和钱包详情，按反馈修界面和口径。
3. AI 请求的 facts 截断从 14000 字符降到约 8000（Groq 每分钟令牌上限 8000，过长会被限）。
4. 持有人资金来源聚类（同源资金的钱包簇）、更早历史的深度加载、更多 DEX 归属的覆盖统计。
5. Helius 额度与限速：核实免费档积分，必要时降低每次分析的翻页数，并在界面显示进度。
6. 寒霜：服务端验证码识别方案、自动兑换成功率实测（用户暂不关心）。
7. 确认新版可用后删除 `xcode-prep/` 旧目录；真机验证 SideStore 自动续签路径（免费账号限 3 个 App：OSVIA、TSTZ-M、SideStore）。

## 约定
- 每次改代码后等 CI，读 `ios/ci/build-errors.txt`；空文件 + 最新运行 success 才算编译通过（`gh_api GET /repos/…/actions/runs?per_page=1&branch=main`，输出很大，只看 `conclusion` 和 `head_sha`）。
- Swift 用 `SWIFT_VERSION 5.0`，冗余协议声明、`??` 与字符串拼接的优先级是此前踩过的坑。
- 本轮对话用过连接器后，记忆写入被系统禁用，所以进度只存在这份文件和仓库里。
