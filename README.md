# WeatherSource

按天气 App 当前查询地点，自动选择天气数据源的 iOS 16 Rootless 越狱插件。

![Build](https://github.com/Justintunsday/weather/actions/workflows/build.yml/badge.svg)

> **状态：MVP / 运行时尚未在目标设备完成验证。**
> 目标设备 iPhone SE 2（iPhone12,8）iOS 16.1.1 在开发过程中重启并失去越狱 SSH，因此本仓库暂未完成真机运行测试。源码、构建脚本和 FlatBuffer/JSON 适配层已实现；请以 GitHub Actions 的编译结果和实际安装日志为准。插件在识别失败、schema 不匹配、请求超时或数据源不可用时始终回退到 Apple 原生数据，不会伪造字段。

## 下载

- [GitHub Release v0.1.1（rootless .deb）](https://github.com/Justintunsday/weather/releases/tag/v0.1.1)
- GitHub Actions 制品：`WeatherSource-rootless-deb`
- 最近一次成功构建：见 GitHub Actions（v0.1.1）

## 它做什么

Apple 天气 App 在 iOS 16 通过 `weatherkit.apple.com` 拉取预报。WeatherSource 不替换 App 界面，而是在天气 App / 天气小组件进程内拦截 `/api/v1|v2/weather/...` 响应：

1. 从请求 URL 读取经纬度、语言、国家与 `dataSets`。
2. 按经纬度 + 国家判断地区；再按地区默认值或城市级覆盖选择数据源。
3. 并行向 Open-Meteo / QWeather 拉取数据，统一转换为 WeatherKit 的字段和单位。
4. 解析 Apple 响应（JSON 或 v2 FlatBuffer），**只覆盖响应中已经存在的字段**。
5. 预警、空气质量、分钟级降水、日出日落等插件未提供的字段保留 Apple 原生值。
6. 成功后继续交给 WeatherKit / 原生 UI / 小组件渲染，因此界面、锁屏小组件和主屏小组件保持原生。

请求失败、超时、数据源无 Key、FlatBuffer 结构无法识别时，直接返回 Apple 原始响应。`/tmp/WeatherSource.log` 与设置页日志会记录实际使用的数据源和失败原因。

## 已实现的数据源

| Provider | 状态 | Key | 说明 |
|---|---|---|---|
| Apple Weather | 原生直通 | 不需要 | 关闭插件或选择“Apple Weather（原生）”时使用 |
| Open-Meteo | **已实现（MVP）** | 不需要 | 全球覆盖；current / hourly / daily、温度、体感、湿度、气压、风、阵风、风向、UV、能见度、云量、降水概率/量、天气现象 |
| QWeather 和风天气 | **已实现（需 Key，未完成真机联调）** | 需要 | 中国大陆优先；now / 24h / 10d；需要用户自己申请 Key |
| HKO / SMG / CWA / NWS / JMA / KMA | 预留 | — | 尚未接入；选择后会回退 Open-Meteo，并在日志中标注 |

> Open-Meteo 不是中国大陆的本地权威气象机构。若需要“本地权威”数据，请配置 QWeather Key，或等待后续接入对应机构。请遵守各数据源的许可、署名和调用频率要求。

## 安装

1. 从 GitHub Actions 下载 `WeatherSource-rootless-deb` 制品，或从 Release 下载 `.deb`。
2. 用 Sileo / Zebra 安装。包为 `iphoneos-arm64`，安装到 `/var/jb`。
3. 安装后会自动尝试结束 `Weather` / `WeatherWidget`；若天气 App 仍在运行，请手动上滑关闭再打开。
4. 打开“设置 → 天气数据源”，确认插件已启用。

依赖：Dopamine Rootless、ElleKit、iOS 16.0+。目标验证环境为 iPhone12,8 / iOS 16.1.1 / Dopamine / ElleKit。

## 设置

- 启用 / 禁用插件
- 自动地区识别
- 中国大陆、香港、澳门、台湾、美国、日本、韩国、其他地区的默认数据源
- 已发现位置列表（天气 App 请求过的经纬度）与逐城市覆盖
- 手动添加位置（纬度、经度、名称）
- 和风天气 Key / Host，预留 CWA / KMA Key
- 缓存时间、请求超时、最小刷新间隔、备用数据源
- 查看 / 清空 API 与异常日志

设置页中的 Key 保存在越狱偏好 plist（`/var/mobile/Library/Preferences/com.weathersource.tweak.plist`），没有硬编码进源码。日志会隐藏完整 Key；但这不是 Keychain 级安全存储，请勿在共享设备上使用付费 Key。

## 构建

GitHub Actions 会自动构建 rootless `.deb`。本地构建需要 Theos、`ldid`、`dpkg` 和 iPhoneOS 16.5 SDK：

```bash
export THEOS=$HOME/theos
make package FINALPACKAGE=1
```

产物：`packages/com.weathersource.tweak_0.1.1_iphoneos-arm64.deb`。

## 技术路线（简述）

- **注入进程**：`com.apple.weather`（Weather App）、`com.apple.weather.widget`（小组件/锁屏小组件）、`com.apple.weather.poster`，以及 `weatherd`（`Executables`，iOS 16.1.1 的获取/缓存进程）。核心 tweak 只链 Foundation，避免向 daemon 加载 UIKit。
- **Hook 点**：`+[NSURLProtocol registerClass:]` + `NSURLSessionConfiguration.protocolClasses`，匹配 `weather-data.apple.com/v3/weather/{locale}/{lat}/{lon}`（iOS 16.1.1 已静态确认）及 `weatherkit.apple.com/api/v*/weather/...` 兼容路径；不直接 Hook Swift async `WeatherKit.WeatherService`。
- **响应格式**：iOS 16.1.1 静态确认使用 `application/json`（WeatherDaemon/WeatherCore）；同时保留 `application/vnd.apple.flatbuffer` 路径以覆盖其他 iOS 版本。
- **FlatBuffer**：只做原位标量写入，不重建 buffer，不改变数组长度和字符串。字段索引见 [docs/TECHNICAL_FEASIBILITY.md](docs/TECHNICAL_FEASIBILITY.md)。
- **单位**：WeatherKit 的数值字段按米制处理：°C、km/h、mm、hPa、m、百分比 0–100、风向 0–359°。QWeather 的 km 能见度会转换成米。
- **稳定性**：8 秒请求超时（可调）、最多 2 次重试、串行去重、10 分钟 provider 缓存、请求失败回退 Apple 原生数据、补丁字段数为 0 时原样透传。

> iOS 16.1.1 补充（2026-10-20）：WeatherCore 已确认 `weatherDataEndpointUrl = https://weather-data.apple.com`，路径 `/v3/weather/{lang}/{latitude}/{longitude}`，`dataSets` 含 `currentWeather / forecastDaily / forecastHourly / severeWeather` 等；WeatherDaemon 使用 `application/json` 与 `weather-data.db` 缓存。v0.1.1 已加入 `weatherd` 注入与 iOS 16 日预报 `temperatureHigh/Low` 字段适配。

更完整的分析、已验证事实和未验证项见 [docs/TECHNICAL_FEASIBILITY.md](docs/TECHNICAL_FEASIBILITY.md)；限制见 [docs/LIMITATIONS.md](docs/LIMITATIONS.md)。

## 当前限制

- 未完成 iPhone12,8 / iOS 16.1.1 真机运行验证；无法保证该固件的 WeatherKit 响应格式与字段索引完全一致。
- 只覆盖 current / hourly / daily 的数值与天气现象。天气预警、AQI、分钟级降水、Apple 归属文案、地图图层保持原生。
- HKO / SMG / CWA / NWS / JMA / KMA 尚未接入，选择后会回退。
- 如果 WeatherKit 使用绕过 `NSURLProtocol` 的网络栈，拦截不会生效；日志中会只出现 `NSURLSession task:` 调试记录而没有 `Weather request`。
- 天气 App 底部的归属信息仍可能显示 Apple Weather；插件不修改原生归属 UI。
- Open-Meteo 在中国大陆的网络可达性、QWeather 的套餐权限和商用许可需用户自行确认。

## 隐私

- 插件只把经纬度发送给用户选择的数据源（Open-Meteo / QWeather）以及 Apple 原有的请求。
- 不采集设备标识，不接入分析服务，不硬编码任何 API Key。
- 日志只记录请求路径、坐标、地区、数据源和错误，不记录 Authorization/JWT/完整 Key。

## 致谢

- [NSRingo/WeatherKit](https://github.com/NSRingo/WeatherKit)（Apache-2.0）：WeatherKit v2 FlatBuffer 字段结构、响应字段语义与接入思路的重要参考。
- [Open-Meteo](https://open-meteo.com/)：免费全球预报 API。
- [和风天气 QWeather](https://www.qweather.com/)：中国大陆预报 API。
- [Theos](https://github.com/theos/theos)、[ElleKit](https://github.com/evelyneee/ellekit)。

## License

MIT。第三方数据、接口与商标归各自权利人所有。

