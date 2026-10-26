# 真机验证

## HKO：2026-10-26

- v0.1.15 已通过 GitHub Actions 的原 JSON 回归检查、HKO 134 项断言及 rootless `.deb` 编译，并已安装到目标 iPhone SE 2 / iOS 16.1.1。
- 真机诊断工具调用与插件相同的 HKO Provider、HTTP client 和 response patcher，成功请求官方 `rhrread` 与 `fnd`。
- 22:03（香港时间）香港查询返回最近可用站打鼓岭 25°C、湿度 75%、九天预报；与独立取得的官方接口逐项比较温度、湿度及九天最高/最低温，一致。
- 用该实时 snapshot 补丁一份本地保存的 Apple JSON 响应，成功替换 25 个字段。这是独立诊断工具的补丁结果，不等同于已经在运行中的 App/Widget 拦截成功。
- 对比原始/补丁 JSON，逐小时、预警、天气变化、AQI 与分钟级降水数据保持语义一致（浮点序列化误差容差 1e-9）。
- `weatherd` 已确认加载 v0.1.15。App/Widget 尚未启动，自动打开未触发前台进程，需要解锁后手动打开香港天气页面，暂不能声称原生 App/Widget 的 HKO 拦截已通过。
- 临时 HKO 路由与 Debug 设置已恢复，读回确认日志级别为 2、香港仍为用户原先的 Apple 选择。独立诊断工具的成功不改变用户原有数据源。

## 原有验证：2026-10-20

## Settings 配置后续更新

- v0.1.14，代码 `7ce8c8a`，[成功构建及回归检查 39444363489](https://github.com/Justintunsday/weather/actions/runs/39444363489)，已安装到设备。
- 原入口缺少 `isController`。补齐后，用户已确认“天气数据源 · WeatherSource”入口出现、主页面能打开。
- 已修复单元格类型 ABI、设置控件读写绑定和按钮 action，增加全局数据源、日志级别、数值校验、Key 遮挡及 Host 校验。
- 用户确认 v0.1.11 直接写 Weather 共享目录保存失败。v0.1.13 起改用设备已安装的 Cephei 2.0 偏好服务，优先读取 `com.weathersource.shared`，旧文件回退。保存后会读回核对。
- v0.1.11 崩溃记录定位到 `PSListItemsController prepareSpecifiersMetadata`；v0.1.14 改为原生选项弹窗。
- **尚待确认**：用户从后台关闭 Settings 后重新打开最新版，保存缓存时间 601 并重进仍保留，以及数据源弹窗可用。目前不能声称保存链路已在 Settings 完整验证。

环境：iPhone SE 2（iPhone12,8），iOS 16.1.1，Dopamine rootless，ElleKit。

## 版本与构建

- v0.1.10，代码提交 `d48bf5e`。
- [成功构建及 JSON 回归检查：39439425316](https://github.com/Justintunsday/weather/actions/runs/39439425316)。
- 已安装到目标设备；App、Widget、weatherd 均记录加载新版本。

## 已确认

1. App 请求主机为 `weatherkit.apple.com`，Widget 为 `weather-data.apple.com`；两者使用 `/v3/weather/...` 与 JSON。
2. 自定义 URLProtocol 必须显式写入 session 配置，并位于协议列表首位。v0.1.7 起观察到 `canInit result=1` 和 `Weather request`。
3. v0.1.8/0.1.9 App 香港请求曾记录替换 4007 个字段，Widget 替换 519 个字段。字段计数只证明补丁执行，不代表全部字段验收；旧版本仍有百分比与时间匹配问题，建议使用 v0.1.10。
4. v0.1.9 成都请求正确解析为 `region=CN`，没有把 `en-US` 当作城市国家。
5. v0.1.10 Widget 响应补丁前后直接对比：温度 25.96 → 23.7°C，湿度 0.89 → 0.96，云量 0.03 → 0。保留 24 小时、10 日数组；小时比例字段没有超过 1 的值。
6. 原始及补丁后 JSON 的 `weatherAlerts`、`weatherChange` 递归比较相等；10 日的 sunrise、sunset、moonPhase 全部未改变。
7. 临时在共享配置中写入 `enabled=false` 后，App 和 Widget 均记录 `requested=disabled provider=apple`。测试结束已恢复默认启用，日志级别恢复为 2。
8. 运行中的 App/Widget 能写入共享位置记录；共享配置权限为 `0600`，文件锁和原子写入用于防止多进程覆盖其他键。
9. Open-Meteo 冷请求曾超时，Apple 原始响应正常透传；后续 provider 返回后观察到 `Patched completion ... 519 fields`，证明 completion 兜底实际执行。随后 URLProtocol 缓存命中再次正常补丁。

## 自动回归检查

CI 在 macOS 上编译并运行实际 `WSWeatherResponsePatcher`，检查 JSON 百分比转换、按时间匹配小时/日预报、保留没有匹配时间的历史条目、不添加缺失字段，以及保留 Apple AQI 和日出字段。

## 尚未验收

- 最终版本的完整 UI、逐字段显示与长期后台刷新。
- Settings 页面写入 Key、逐城市覆盖后跨进程生效；共享文件读取测试不等同于 Settings UI 验收。
- QWeather Key/套餐联调、其他机构适配、FlatBuffer 真机路径。
- 全球精确地区边界：当前仍使用粗略坐标框，不能代替行政区多边形或逆地理编码。
- 未替换日预报内嵌的 daytimeForecast / overnightForecast 等细分对象，可能与已替换的顶层日预报不一致。

原始/补丁响应与设备日志只保存于本地验证目录，没有提交到公开仓库。
