# 接口契约（第一版）

Worker 域名占位：`https://tugou-hanshuang-jiaoben-app.<你的 Cloudflare 子域>.workers.dev`
（正式域名在 Cloudflare 新建 Worker 时确定，不写死在这里。）

## GET /api/token?chain=&address=
- chain：`bsc | eth | base | solana | robinhood`
- 成功：价格、流动性、24h 量、涨跌 + `tradeLinks.ave / .gmgn / .dexscreener`
- 风险字段：EVM 链优先走 GoPlus，GoPlus 从 Worker 出口 IP 返回 4029 时改走 honeypot.is 兜底（蜜罐、买卖税、持仓人数、开源/代理）；Solana 走 RugCheck（风险分、风险项、增发权限、LP 锁定）；池子年龄走 Dexscreener 最深池子的 pairCreatedAt（天数，WETH 实测 1807.3 天、Base USDC 实测 784.7 天）。
- 已证实的上游 IP 限制（不是代码 bug，实测见 bsError）：Blockscout 新版接口从 Worker 出口 IP 返回 429（ETH）、403（Base），老版接口同样 429/403；BSC 没有 Blockscout 实例（404），BSC 的浏览器是 BscScan。Etherscan V2 要求 API Key，无 Key 返回 Missing/Invalid API Key。
- 因此 Top10 占比、增发、黑名单、创建者、权限丢弃、LP 锁定在无 Key 的 Worker 路径下暂时留空，`riskSource` 为 `goplus` / `honeypot_is` / `rugcheck` / `pending`，失败原因见 `securityError` / `bsError`。要彻底填满这些字段的办法：用一个免费 Etherscan API Key（一个 Key 覆盖 ETH/BSC/Base，免费档，不用付费），走安全入口交 Worker Secrets，Worker 改走 Etherscan V2 的 tokenholderlist / getsourcecode / getcontractcreation；不要把 Key 写进代码或聊天。
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
