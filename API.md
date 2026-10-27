# 接口契约（第一版）

Worker 域名占位：`https://tugou-hanshuang-jiaoben-app.<你的 Cloudflare 子域>.workers.dev`
（正式域名在 Cloudflare 新建 Worker 时确定，不写死在这里。）

## GET /api/token?chain=&address=
- chain：`bsc | eth | base | solana | robinhood`
- 成功：价格、流动性、24h 量、涨跌 + `tradeLinks.ave / .gmgn / .dexscreener`
- 风险字段：EVM 链优先走 GoPlus，GoPlus 从 Worker 出口 IP 返回 4029 时改走 honeypot.is 兜底（蜜罐、买卖税、持仓人数、开源/代理）；Solana 走 RugCheck（风险分、风险项、增发权限、LP 锁定）；池子年龄走 Dexscreener 最深池子的 pairCreatedAt（天数，WETH 实测 1807.3 天、Base USDC 实测 784.7 天）。
- 已证实的上游 IP 限制（不是代码 bug，实测见 bsError）：Blockscout 新版接口从 Worker 出口 IP 返回 429（ETH）、403（Base），老版接口同样 429/403；BSC 没有 Blockscout 实例（404），BSC 的浏览器是 BscScan。Etherscan V2 要求 API Key，无 Key 返回 Missing/Invalid API Key。
- Etherscan V2 免费 Key 实测（2026-10-27，Muse 侧已接通验证）：源码接口三链都通，源码扫描为启发式、非审计结论，代理合约扫实现合约源码；ETH 的创建者接口通，Base/BSC 的创建者接口在免费档返回 Free API access is not supported for this chain；持仓列表和代币信息接口在免费档是 Pro 专用，拿不到。GeckoTerminal API v2 没有 /holders 端点（实测 404），不要再走这条路。
- Worker 代码已接 Etherscan V2（读 env.ETHERSCAN_API_KEY，不写 Key 进代码）：有 Key 时增发、黑名单、ETH 创建者能填，Top10 占比仍填不上，Base/BSC 创建者仍填不上，失败原因见 `etherscanError`。Worker 线上实测仍返回 missing_env_ETHERSCAN_API_KEY，说明 Key 还没放进 Cloudflare Worker Secrets，Muse 安全存储里的 Key Worker 读不到；要在 Cloudflare 控制台 Workers & Pages > tugou-hanshuang-jiaoben-app > Settings > Variables 里加一个 Secret，名字 ETHERSCAN_API_KEY，值就是同一把 Key，加完再重测。Top10 占比、LP 锁定在免费路径下仍留空，`riskSource` 为 `goplus` / `honeypot_is` / `rugcheck` / `pending`，失败原因见 `securityError` / `bsError` / `etherscanError`。
- 风险灯规则：蜜罐、买卖税 ≥50%、隐藏所有者、可改余额、可自毁为红；增发、黑名单、可暂停、代理、可改滑点为黄；其余有数据为绿，这只是扫描信号不是安全保证。注意：上游从 Worker 出口 IP 间歇限流时价格也可能偶发为 null，属上游限流不是编数问题。

## POST /api/holdings
请求：`{"wallets":[{"chain":"bsc","address":"0x…","label":"主钱包"}]}`
返回：`wallets`（校验通过的）、`invalid`（格式不对的）、`byChain`、`totalUsd`、`balanceSource`
- 第一版 `balanceSource: "pending"`，余额源接通前不返回假余额。
- App 侧钱包列表变了，就用新列表重新调这个接口聚合。

## GET /api/sources
返回 Ave、GMGN、X、Dexscreener、GeckoTerminal、Blockscout 的角色与跳转链接。

## 安全
- 请求里不带私钥、交易所 Key、游戏账号密码。
- 交易所只读 Key、Blockscout Key 等只放 Cloudflare Secrets / GitHub Secrets，Worker 从 env 读。

## 2026-10-27 16:04 全链扩展（Jon 定：Solana + 所有热门链）
- 链列表（Worker 适配器，不按链重做）：BSC、ETH、Base、Solana、Robinhood、Arbitrum、Optimism、Polygon。现货信息统一走 /api/token：价格、流动性、24h 量、涨跌、池子年龄、Ave/GMGN/Dexscreener 跳转。
- 钱包监控：POST /api/holdings，入参 wallets（链+公开地址+备注）与 tokens（自选代币列表），只读公开地址不碰私钥；原生与自选代币余额走公开 RPC（多地址轮询，ETH 主用 Cloudflare ETH 网关），现货价走 Dexscreener/GeckoTerminal；未定价余额不计入 totalUsd。实测：ETH WETH 合约原生余额 2221715.155948026 ETH，价 2313.88 美元，合计约 51.4 亿美元，balanceSource 为 rpc。
- 自动分析未完成：胜率、盈亏、聪明钱画像、自己钱包复盘需要交易历史，属第二阶段；交易历史在部分链上仍受 Blockscout/Etherscan 免费档限制，不在这里编数。
- Tron、Sui、Aptos 等非 EVM 链不在本轮适配器内，地址体系和数据源不同，需单独适配，不记为已接。

## 2026-10-27 18:54 Blockscout Pro 免费 Key 接通（Top10 终于有真实来源）
- Muse 侧已接通 custom.blockscout，助手脚本 bin/bs.py，统一接口 api.blockscout.com/{chain_id}/api/v2，不带 Key 返回 402，带 Key 通。
- 实测：ETH WETH 总供应 2222010091493531624966045、持仓人数 3359464、Top10 占比 60.03%；Robinhood SEND 总供应 1e28（100 亿，纠正了之前浏览器页 10 亿的说法）、持仓人数 113、Top10 占比 98.98%；ETH 创建者与创建交易与 Etherscan 一致。
- 链覆盖差异（实测）：ETH、Arbitrum、Optimism、Robinhood 的代币接口通；Base、Polygon 的代币接口 consistently 返回 402，Top10 仍未解；BSC 返回 404（BSC 无 Blockscout 实例，属预期）。
- Worker 已接 blockscoutProInfo，读 env.BLOCKSCOUT_API_KEY，填 holders、topHoldersPct、creatorHistory（Pro 优先于 Etherscan 与分站），失败写入 bsProError；Worker 已部署 etag 6d714e7a，现报 missing_env_BLOCKSCOUT_API_KEY，须 Jon 在 Cloudflare 控制台 Workers & Pages > tugou-hanshuang-jiaoben-app > Settings > Variables 里加 Secret BLOCKSCOUT_API_KEY（同把 Key），加完无需重新部署、再重测。

## 2026-10-27 19:08 必须解决 Base、Polygon、BSC：链上日志 + Alchemy 定案
- 已证死：Routescan Etherscan 兼容接口对 8453、56、137 均返回 chain not supported；BscScan V1 无 Key 只返回欢迎页，Basescan V1 已停用、V2 免费档不支持 Base/BSC；Chainbase 无 Key 返回 401；OKLink 免费限额未公开，不作为免费定案。
- 链上日志方案已写进 Worker（evmLogScan）：Transfer 日志聚合算 Top10，首笔 Transfer 所在区块找 to 为空且 receipt 合约地址等于本币的交易算创建者；大币（持仓人数 >500000）直接跳过，不编假 Top10；小币（土狗）才跑完整扫描，并带 complete/scannedLogs/error 诊断。
- 公开 RPC 从 Worker 调日志不可靠（已实测）：BlastAPI 日志上限 10 个块，mainnet.base.org 日志 429，publicnode 在 rpc-test 单测通、但在 /api/token 多次调用后仍间歇 429，属共享出口 IP 限流；另有 Worker 单次 50 次子请求上限，已通过价格去重、Pro Key 在时跳过分站 v1、日志单 RPC、250ms 节流、起始窗口 6 小时等方式压到限额内，但共享 IP 429 仍无法靠代码根治。
- 定案：Alchemy 免费 Key（$0、每月 3000 万 CU、约 116 万次调用、15 次/秒、不用绑卡、一个 Key 覆盖 100 多条链，eth_getLogs 一次 60 CU）走 Worker Secret ALCHEMY_API_KEY，Worker 有 Key 时日志扫描优先走 Alchemy 单 URL（base-mainnet、bnb-mainnet、polygon-mainnet、eth-mainnet、arb-mainnet、opt-mainnet），无 Key 时回退公开 RPC；Base 新币 CHUBBY（0x400fb523fbf8387f4be64bde85bcb1954e9c8200，池子 2026-10-27 11:07，24h 买卖 17/2）已用作日志扫描测试币，价格、持仓 18、增发 false、黑名单 false、风险绿已通，Top10 与创建者待 Alchemy Key 到位后重测。

## 2026-10-27 19:28 Alchemy 修正：日志改走 getAssetTransfers
- 前两轮 401 的根因不是 Key 值错，是 Muse 侧助手脚本 url_with_surrogate_path_segment 对 surrogate 做 URL 转义，转义后的 hsurr%3A... 无法被哨兵换回真 Key，Alchemy 返回 Must be authenticated；改用未转义 surrogate 直接放进 /v2/ 路径后，Base、ETH、BSC、Polygon、Arbitrum、Optimism 的 eth_blockNumber 全部通了。
- Alchemy 免费档 eth_getLogs 上限 10 个块，扫土狗全量不可行；改走增强接口 alchemy_getAssetTransfers（按合约过滤、asc 排序、maxCount 1000、pageKey 分页），Base CHUBBY 实测 71 笔、pageKey 为空（已全量）、持仓 17 人、Top10 95.9253%、创建者 0xa7ce2a9642c43e92d324b303c871f77b24ffd83d、创建交易 0x89fcdd3d7e6de05804eb5ffe877478e1da75449d2b6f439257b590edb7e84e08、时间戳 1793099203。
- Worker 已改为有 ALCHEMY_API_KEY 时日志扫描优先走 getAssetTransfers，无 Key 时回退 eth_getLogs；Worker 侧仍待 Jon 在 Cloudflare 控制台加 Secret ALCHEMY_API_KEY，加完无需重新部署再重测 CHUBBY。
