# 接口契约（第一版）

Worker 域名占位：`https://tugou-hanshuang-jiaoben-app.<你的 Cloudflare 子域>.workers.dev`
（正式域名在 Cloudflare 新建 Worker 时确定，不写死在这里。）

## GET /api/token?chain=&address=
- chain：`bsc | eth | base | solana | robinhood`
- 成功：价格、流动性、24h 量、涨跌 + `tradeLinks.ave / .gmgn / .dexscreener`
- 风险字段：EVM 链优先走 GoPlus（持仓人数、Top10 占比、买卖税、蜜罐、权限丢弃、增发、黑名单），GoPlus 从 Worker 出口 IP 返回 4029 时改走 honeypot.is 兜底（只给蜜罐、买卖税、持仓人数、开源/代理，增发、黑名单、Top 占比留空）；Solana 走 RugCheck（风险分、风险项、增发权限、LP 锁定）；查不到的字段保持 null，`riskSource` 为 `goplus` / `honeypot_is` / `rugcheck` / `pending`，失败原因见 `securityError`；池子年龄、创建者历史仍为 null，EVM 的 LP 锁定仍为 null，不编数。风险灯规则：蜜罐、买卖税 ≥50%、隐藏所有者、可改余额、可自毁为红；增发、黑名单、可暂停、代理、可改滑点为黄；其余有数据为绿，这只是扫描信号不是安全保证。注意：上游从 Worker 出口 IP 间歇限流时价格也可能偶发为 null，属上游限流不是编数问题。

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
