# TSTZ-M 交接说明（新对话先读这个）

不含任何密钥。令牌、Groq、Helius、Alchemy 等密钥都在用户手里或 Worker 加密库/Secret 里，不要写进仓库。

## 项目目标
免费原生 iOS App「TSTZ-M」，Mac 开发，日常使用脱离电脑。**优先交易方向**：钱包交易记录分析判断、代币交易记录分析、持仓人分析；自己的钱包可多个添加、多选删除，能看具体交易记录和持仓。铁律：**数据必须客观真实，查不到写「未知」，每条结论给出依据**。用户不要和其他交易所/平台重复的功能。寒霜启示录先不管。
用户不会写代码：方案要自动执行；回答极度简洁、简体中文、无客套、无结尾总结。

## 架构（全部免费）
- 仓库：`frommhy-prog/tugou-hanshuang-jiaoben-app`（已公开）。新工程在 `ios/`（XcodeGen：`project.yml`，源码 `App/ Shared/ Widget/`）。旧的 `xcode-prep/` 是半成品，待用户确认新版可用后再删。
- **引擎源码在仓库 `worker-engine/`（worker.js + evm.js）**，部署：`gh_deploy`（repo、path=`worker-engine/worker.js`、extra_paths=`["worker-engine/evm.js"]`、root=`worker-engine/`、script=`tstzm-engine`、compat_date=`2026-10-27`），绑定（D1、DO、服务绑定、Secret）自动保留。改引擎 = 改仓库文件再 `gh_deploy`，不要直接在 Cloudflare 改。
- 云编译：`.github/workflows/ios-build.yml`（macOS runner，约 2 分钟）。编译结果读 `ios/ci/build-result.txt`、`ios/ci/build-errors.txt`、`ios/ci/build-tail.txt`；成功后发布 Release `latest` 的 `TSTZ-M.ipa`，并更新 `sidestore/source.json`（SideStore 源：`https://raw.githubusercontent.com/frommhy-prog/tugou-hanshuang-jiaoben-app/main/sidestore/source.json`）。连续推送会取消前一次运行。**判断是否编译通过：`gh_api GET /repos/<repo>/actions/runs/<run_id>/jobs` 看 conclusion（输出小）。不要用 `gh_runs`、`gh_commits`（输出巨大，会撑爆上下文）。**
- 推送文件用 `gh_put`（原样文本，不要传 `branch` 参数，传了会报 malformed）。只能整文件覆盖，没有局部补丁。
- Bundle ID `com.Hao-Yi-Miao.TSTZ-M`，小组件 `.Widget`，App Group `group.com.Hao-Yi-Miao.TSTZ-M`，iOS 17+，URL scheme `tstzm://`（`setup?token=`、`frost?code=`）。图标由 `ios/tools/make_icon.swift` 在 CI 绘制（白底、海军蓝金圈 logo）。
- Cloudflare（账号 workers 子域 `from-mhy`）：
  - `tstzm-api`：App 主网关。Bearer 令牌鉴权，转发旧 Worker 的 `/api/*`，加密密钥库（D1 `vault`，主密钥 Secret `VAULT_KEY`），提醒 CRUD，寒霜新码检测，额度，Durable Object `Scheduler` 闹钟（每 5 分钟检查提醒、每 30 分钟检测新码）。账号 5 个 Cron 名额已被 `kuaishou-data-monitor`(1) 和 `tstz-im-gateway`(4) 占满，不要动它们，所以用 DO 闹钟。密钥白名单 `PROVIDERS` 里目前没有 `alchemy`（要在 App 内绑定就得加，重发整份代码；代码用 `cf_worker_code tstzm-api` 读）。
  - `tstzm-engine`（v4）：分析引擎。App 直接请求，同一个 Bearer 令牌。路由 `/e/sol/token|wallet|holder|pool`、`/e/evm/chains|wallet|holder|token|_sim`、`/e/ai`。所有计算在 Durable Object `Job` 里（普通 Worker 免费档只有 10ms CPU，别在里面做重计算）。
  - 旧 Worker `tugou-hanshuang-jiaoben-app`（Muse 做的，源码在仓库 `worker/src/index.js` 约 97KB，线上是否一致未核对）：仍提供 `/api/token`、`/api/wallet-portfolio`、`/api/token-deep`、`/api/fx`、`/api/wos-codes`、`/api/feedback`、`/api/rpc-test` 等，经服务绑定被调用。它的 Secret 里有 `ALCHEMY_API_KEY`、`ETHERSCAN_API_KEY`、`BLOCKSCOUT_API_KEY`（读不出来，不能复制给别的 Worker）。
  - D1 `tstzm`（id `7c59261f-fbe3-4ae7-b428-21b5d14c3a1e`）：表 `kv vault alerts quota usage selftest wos_codes cache`。Queue `tstzm-jobs`（id `26998799521b4a35832fd73df7b77b03`，消费者是 `tstzm-engine`）。
- 免费档限制：Worker 免费档单次 10ms CPU、50 个外部子请求；KV 每天 1000 次写；Helius 免费档会 429 限速（引擎已做退避和翻页间隔 450ms）；Alchemy 免费 3000 万 CU/月，吞吐约 300 CU/s，`eth_getLogs` 只能扫 10 个块（所以不用它），`alchemy_getAssetTransfers` 可用；publicnode 公共 RPC 从 Worker 出口 IP 经常 429，不可依赖。

## 我这边的远程调试方法（很有用）
没有网络直连时，用队列当"远程控制台"：
1. `cf_api POST /queues/26998799521b4a35832fd73df7b77b03/messages`，body 为 `{"body": {"name": "任意名", "op": "api", "path": "/e/evm/_sim", "max": 6000}, "content_type": "json"}`。要带 POST 体就加 `"method":"POST","body":{…}`。也可不带 `op` 直接探测第三方（`url` 里用 `{{helius}}`、`{{groq}}`、`{{alchemy}}` 自动代入密钥，输出里的 Alchemy 密钥会被抹成 ***；主机白名单见引擎 `HOSTS`）。
2. 等 20–40 秒，`cf_d1_query` 读 `SELECT name, json_extract(out,'$.status'), substr(json_extract(out,'$.head'),1,3000) FROM selftest WHERE name='…' ORDER BY ts DESC LIMIT 1`。
3. 用户应用内反馈存在旧 Worker 的 KV（namespace `a2682f9a6b074a508afdc16ff74c1bfb`，键 `feedback:*`，图片很大，读取前先用 `feedback:index` 看列表）。

## 已完成
- App：代币页（顶部切 Solana / EVM）、钱包页（一次粘贴多个、多选删除、详情含持仓/交易记录/分析）、寒霜页（手动一键跳转并预填、自动兑换引擎含本机验证码识别，未实测）、提醒页、设置页（主题三档、计价货币、连接令牌、API 密钥与额度含 Groq 真实剩余和倒计时、反馈）、小组件和灵动岛（只在 App 前台更新）。
- 引擎 Solana（已用真实数据测过）：`/e/sol/token`（链上读 mint 权限、最大 20 个账户并分类、集中度）、`/e/sol/wallet`（Helius SWAP 历史 → 链上余额变化提取买卖 → 平均成本法盈亏、胜率、持仓时间、风格标签，每个标签附判定规则和数值）、`/e/sol/holder`、`/e/sol/pool`、`/e/ai`（Groq 只解读已算出的 facts，模型动态挑选，现为 `openai/gpt-oss-120b`；facts 已截断到 8000 字符）。
- **引擎 EVM（2026-10-31 新增，代码已部署、合成数据自检通过、尚未用真实数据测过）**：`worker-engine/evm.js`。
  - 链：bsc、eth、base、arbitrum、optimism、polygon（Alchemy 网络 bnb/eth/base/arb/opt/polygon-mainnet）。Robinhood、X Layer、OKTC 暂不支持（Alchemy 的 Robinhood 网络名未核实；X Layer/OKTC 无 Alchemy）。
  - `/e/evm/wallet?chain=&address=&pages=`：`alchemy_getAssetTransfers`（按 from、to 两个方向各翻 pages 页，每页 1000 条，新到旧；external+internal+erc20，该链不支持 internal 时自动去掉）→ 按交易哈希汇总本钱包净变化 → 恰好一个非报价代币 + 原生币/稳定币对手腿 = 一笔买/卖 → 平均成本盈亏。WETH/WBNB/WPOL 视同原生币；稳定币按链内置地址表。原生币计价与 USD 计价分开统计不折算，不含 gas。窗口取两个方向都读到的公共区间。
  - 不含 internal 的链（预计 BSC/Arbitrum/Optimism）：「转出代币但没看到收款」的记录，用区块前后 `eth_getBalance` 差额 + 回执 gas 反推卖出所得，标 `approx:true`，每次最多解析 60 笔，余额读取失败（非归档）记为未解析并在 notes 说明；这是最需要真实数据验证的部分。
  - `/e/evm/holder?chain=&token=&owner=`：对 owner 跑钱包流水，取该币的成本/盈亏/交易 + 整体风格。
  - `/e/evm/token?chain=&token=&pages=`：该合约全部 ERC20 转账从头累加得到余额（只有读完才给榜单，否则明说未知），前 20 大持有人用 `eth_getCode` 分类 钱包/合约/池子，给集中度、首次铸造地址、销毁占比。**iOS 代币页尚未接这个接口。**
  - 输出字段：交易 `tx/t/token/side/qty/amt/q('NATIVE'|'USD')/approx/sym`，持仓 `token/sym/q/...`，`native` 为原生币符号，`stats` 含 `realizedNative/realizedUsd/medBuyNative` 等。
  - `/e/evm/chains` 返回支持的链和 `keyPresent`；没密钥时各接口返回 200 + `{"error":"no_alchemy_key"}`。
  - `/e/evm/_sim` 合成数据自检（买 1 ETH 卖两笔得 1.3 ETH 盈亏、USDC 计价 +50、转出归为候选），当前通过。
  - 密钥来源：加密库 `alchemy`，或 `tstzm-engine` 的 Secret `ALCHEMY_API_KEY`（`cf_secret_put`）。**当前两处都没有，`keyPresent=false`。**
- iOS EVM：`ios/App/EvmWallet.swift`（模型、`EvmDetailVM`、链选择条、交易记录列表、统计、风格标签、AI 解读、按币盈亏），`WalletsView.swift` 的钱包详情对 EVM 钱包接入「交易记录」「分析」两栏。CI 编译通过（run 13，commit d1eb555）。
- 新码检测：6 个社区站点多站共识 + 旧 Worker 名单，首次只建基线不推送；新码推送到 Telegram/Bark（Bark 点开直接进寒霜页）。
- 已知真实发现：旧数据源对 Solana 没有持有人数据；Helius 解析后的单笔交易约 12KB，100 笔一页约 1.2MB；Etherscan V2 免费档不含 Base/Optimism/BSC（2025-11 起），Blockscout 免费档 2026-10-01 起移除 Base/Polygon，所以 EVM 走 Alchemy；Alchemy 的 getAssetTransfers 在 BSC 可用（别人实测），`internal` 类别官方只列 Ethereum/Polygon/Base。

## 待办（按优先级）
1. **配 Alchemy 密钥后做 EVM 真实数据实测**：用户提供密钥 → `cf_secret_put script=tstzm-engine name=ALCHEMY_API_KEY`；再用队列探测核对：(a) BSC 带 `internal` 是否被接受；(b) 一个 BSC 土狗钱包的买卖配对、approx 卖出是否合理（对照区块浏览器）；(c) 归档余额是否可读；(d) bsc/eth/base 的稳定币和包装币地址（arbitrum/optimism/polygon 已用 symbol() 核对，bsc/eth/base 因公共 RPC 429 未核对，改用 `{{alchemy}}` 探测 `eth_call 0x95d89b41`）。有问题再改 `worker-engine/evm.js`。
2. iOS 代币页（EVM）接 `/e/evm/token` 持有人榜单与 `/e/evm/holder` 单个持有人分析（现在 EVM 代币页走旧 Worker 的 `/api/token`，持有人数据不全）。
3. 让用户在真机上试 Solana 与 EVM 钱包详情，按反馈修界面和口径。
4. 在 App 设置里能绑定 Alchemy 密钥：`tstzm-api` 的 `PROVIDERS` 加 `alchemy`，并确认设置页能显示。
5. 持有人资金来源聚类（同源资金的钱包簇）、更早历史的深度加载、更多 DEX 归属的覆盖统计；Robinhood、X Layer、OKTC 的 EVM 数据源。
6. Helius 额度与限速：核实免费档积分，必要时降低每次分析的翻页数，并在界面显示进度。
7. 寒霜：服务端验证码识别方案、自动兑换成功率实测（用户暂不关心）。
8. 确认新版可用后删除 `xcode-prep/` 旧目录；真机验证 SideStore 自动续签路径（免费账号限 3 个 App：OSVIA、TSTZ-M、SideStore）。

## 约定
- 每次改代码后等 CI，读 `ios/ci/build-errors.txt`；空文件 + 对应运行 jobs 的 conclusion 为 success 才算编译通过。
- Swift 用 `SWIFT_VERSION 5.0`，冗余协议声明、`??` 与字符串拼接的优先级是此前踩过的坑。
- 本轮对话用过连接器后，记忆写入被系统禁用，所以进度只存在这份文件和仓库里。
