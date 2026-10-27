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
