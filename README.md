# TSTZ-M

免费原生 iOS App（仓库名沿用旧名 tugou-hanshuang-jiaoben-app）：土狗合约体检与分析、多链钱包与交易所只读持仓、到价提醒、盯盘看板、小组件与灵动岛。

## 目录
- `ios/`：App 源码（`App/`、`Shared/`、`Widget/`），`project.yml` 由 XcodeGen 生成工程；`ci/` 是每次构建的结果文件
- `worker-api/`：令牌鉴权 API（Cloudflare Worker `tstzm-api`）
- `worker-engine/`：分析引擎（Cloudflare Worker `tstzm-engine`）
- `sidestore/`：SideStore 源（`source.json`）与图标
- `.github/workflows/ios-build.yml`：云端编译 + 出 IPA + 更新 SideStore 源
- `.github/patches/`：编译前应用的源码补丁清单
- `docs/NEXT.md`：新对话接手清单（先读这个）；`docs/HANDOFF.md`、`API.md`：早期交接与接口说明

## 安装
- 日常：SideStore 添加本仓库的源（`sidestore/source.json`），安装 / 更新 TSTZ-M，自动续签。
- 开发：Xcode 打开 `ios/TSTZM.xcodeproj`，两个 target 的 Signing 选 Personal Team，用默认的 Run（Debug）。Debug 的应用标识会带上团队 ID，与 SideStore 重签后的标识一致，装上去覆盖的是同一个应用。
