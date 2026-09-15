# IOTA Monitor — macOS 菜单栏监控小组件

实时监控本机 **IOTA Train at Home**（Macrocosmos Bittensor SN9）训练状态的菜单栏应用。
UI 架构移植自 [exelban/stats](https://github.com/exelban/stats)（MIT 协议，见 `Sources/IotaMonitorCore/Vendor/STATS-LICENSE`）。

## 功能

- **菜单栏组件**（可像 stats 一样在设置中开关/排序）：今日收益（α + USD/CNY 折算 + 迷你曲线）、训练吞吐 tokens/h、网络速度、整机功率（SMC PSTR 实测瓦特）、吞吐折线图
- **点击弹窗**（纵向卡片流，失焦自动关闭，拖动可钉住）：
  - 训练状态：phase / layer / epoch / run_id / TAH App 存活与运行时长（心跳字段缺失时自动降级显示）
  - 训练进度：loss、tokens 总进度、每层 train/upload/merge 分数、当前训练阶段及耗时（本地 8009 事件流）、MPS 显存
  - 今日统计：tokens、上行/下行流量、电量 kWh/Wh
  - 实时：GPU / CPU / 瓦特 / 双向网速曲线（后台持续采集，打开即有历史）
  - 收益：今日 IOTA、累计/已付/待付/冻结、下次打款倒计时、全网排名与贡献、币价
  - 历史图表：收益（跟随货币设置自动折算）/ tokens / 流量 / 功耗 × 7 天 / 30 天 × 每日 / 累计
- **历史数据**：SQLite（`~/Library/Application Support/IotaMonitor/history.sqlite`），5 秒采样保留 14 天，日汇总永久保留；历史收益从官方 API 自动回填

## 数据源

| 来源 | 用途 |
|---|---|
| `https://iota-web.api.macrocosmos.ai/mainnet`（官方 App 同款公开 API） | 进度、阶段分数、矿工排名、收益、打款时间 |
| `http://127.0.0.1:8009`（TAH 本地遥测） | 训练阶段事件、显存 |
| `http://127.0.0.1:8010/health`（只读） | App 存活检查 |
| `~/Library/Logs/IOTA Train at Home/<今天>-cli.log` | heartbeat（phase/epoch/layer）、完整 hotkey |
| `nettop` / `ioreg` / `ps` / AppleSMC `PSTR` | 带宽、GPU%、CPU%、整机瓦特 |
| CoinGecko `simple/price`（iota-2 / bittensor） | α 与 TAO 币价（可手动覆盖） |

## 构建与安装

```bash
make test      # 46 项自测（无 Xcode 环境也可跑）
make build     # swift build -c release
make app       # 打包 "IOTA Monitor.app"
make install   # 安装到 /Applications
open "/Applications/IOTA Monitor.app"
```

直接跑调试版：`make run`。

## 设置（弹窗底部"设置"按钮）

- 组件开关与顺序；货币 USD/CNY；α 手动币价（0=自动）；USD/CNY 汇率兜底；电价 ¥/kWh；hotkey（留空自动探测）；开机自启（需从 .app 运行）

## 说明

- **只读承诺**：本应用对 IOTA Train at Home 及其训练进程零干预——所有 HTTP 请求均为 GET（含 8010 只读 `/health`），子进程仅 nettop/ioreg/ps/curl 等只读工具，SMC 只读功耗键，日志只读；不使用 8010 的任何写接口，也不会启动/停止/重启 IOTA
- 官方 API 域名偶发 IPv6/HTTP2 超时，内置 `curl -4 --http1.1` 回退
- TAH App 未运行时组件灰显"–"，60 秒自动重探
- 今日收益 = 官方累计收益 − 当日零点基线（基线每日自动重置，并有"不超过累计总额"的硬性钳制）；日收益明细以官方 payout 记录为准
- 收益折算货币可选 IOTA / USD / CNY；历史收益图表跟随货币设置自动折算（按当前币价）
