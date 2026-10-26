# 接口契约（第一版）

Worker 域名占位：`https://tugou-hanshuang-jiaoben-app.<你的 Cloudflare 子域>.workers.dev`
（正式域名在 Cloudflare 新建 Worker 时确定，不写死在这里。）

## GET /api/token?chain=&address=
- chain：`bsc | eth | base | solana | robinhood`
- 成功：价格、流动性、24h 量、涨跌 + `tradeLinks.ave / .gmgn / .dexscreener`
- 风险字段第一版为 null，`riskSource: "pending"`，不编数。

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
