# tugou-hanshuang-jiaoben-app

土狗寒霜脚本app：第一阶段脚手架。


App：土狗寒霜脚本app；仓库：frommhy-prog/tugou-hanshuang-jiaoben-app；Cloudflare 项目名：tugou-hanshuang-jiaoben-app。
黑色硬核风格。私钥、账号密码、API Key 绝不写进代码，一律放 Secrets。

## 已定设计（2026-10-27）
- 链：BSC、ETH、Base、Solana、Robinhood Chain（Chain ID 4663，Arbitrum L2，Gas ETH）。
- 交易所持仓：币安、欧易、Gate，只读 Key，尚未提供，接口先留空，Key 到后再接。
- Ave、GMGN、推特（X）：按数据源 / 跳转接，不按交易所持仓接。第一版不假装有它们的免费公开 API：
  数据先走 Dexscreener / GeckoTerminal，Ave / GMGN / X 以跳转链接 + 信号来源字段出现，
  之后有免费或自有 Key 再在 Worker 里接对应适配器。
- 钱包：用户在 App 内随时添加、编辑、删除，可同时多个、不同链混加；只存公开地址 + 链 + 备注名，不存私钥。
- 寒霜兑换号（第三阶段）：[ONE]卡皮巴拉，ID 726154631，所在王国 4124，初始王国 4186，联盟 ONE。

## 目录
- `worker/`：Cloudflare Worker 统一网关。App 和小组件只读它返回的缓存 JSON，不直连上游。
- `app/`：SwiftUI App 外壳 + 小组件源码骨架（黑色主题、钱包管理、合约体检、持仓页）。
- `API.md`：接口契约。

## Worker 接口（第一版）
- `GET /health`：存活检查。
- `GET /api/token?chain=<链>&address=<合约>`：合约体检的价格/流动性部分，来自 Dexscreener。
  持仓人数、买卖税、蜜罐、权限、LP 锁定等字段第一版返回 `null + source: "pending"`，不编数据；
  第二阶段再接 GoPlus / RugCheck / Blockscout 等适配器。
- `POST /api/holdings`：`{"wallets":[{"chain":"bsc","address":"0x...","label":"主钱包"}]}`，
  返回按钱包、按链、汇总的持仓骨架；余额来源未接通前如实返回 `balanceSource: "pending"`，
  价格部分用 Dexscreener 查得到就填，查不到就空，不估算假数。
- `GET /api/sources`：Ave / GMGN / X / Dexscreener / GeckoTerminal 的跳转与来源说明。

## 还没做的事（需要你按次审批后才动）
- 推到 GitHub 仓库 frommhy-prog/tugou-hanshuang-jiaoben-app（写操作会弹审批卡）。
- 在 Cloudflare 新建 Worker / KV，项目名 tugou-hanshuang-jiaoben-app（新建操作会弹审批卡）。
- 真机编译：需要 Mac / Xcode 或 GitHub Actions macOS 环境，到编译时再确认。
