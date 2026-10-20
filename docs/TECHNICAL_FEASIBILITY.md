# 技术可行性分析

本文记录在 iPhone SE 2（iPhone12,8）iOS 16.1.1（20B101）上的静态分析结果、设计方案，以及截至当前 **已确认** 与 **尚未验证** 的部分。不要把“静态分析确认”当成“真机运行确认”。

## 1. 目标环境确认

通过 SSH 连接到目标设备后确认：

- 设备：`iPhone12,8`，Darwin `22.1.0`，iOS 16.1.1。
- 越狱：Dopamine Rootless，jailbreak 前缀 `/var/jb`。
- 注入框架：ElleKit（目标环境已安装）。
- 天气 App：`com.apple.weather`，可执行文件 `Weather`，版本 3.1 / 307.6。
- 天气小组件：`com.apple.weather.widget`，可执行文件 `WeatherWidget`，WidgetKit 扩展。
- 相关框架：
  - `/System/Library/Frameworks/WeatherKit.framework`
  - `/System/Library/PrivateFrameworks/Weather.framework`
  - `/System/Library/PrivateFrameworks/WeatherDaemon.framework`
  - `/System/Library/PrivateFrameworks/WeatherCore.framework`
  - `/System/Library/PrivateFrameworks/WeatherUI.framework`
  - `/System/Library/PrivateFrameworks/WeatherMaps.framework`
- 守护进程：`/System/Library/PrivateFrameworks/WeatherDaemon.framework/weatherd`，由 `com.apple.weatherd.plist` 启动，Mach service 包含 `com.apple.weatherd.weatherkit`。

天气 App 的 `Info.plist` 与小组件 `Info.plist` 是实际从设备读取的，不是猜测。

## 2. App 实际数据流（静态分析）

对 `Weather.app/Weather` 的 Mach-O 符号分析确认：

- App 直接导入 `WeatherKit.WeatherService`、`WeatherKit.WDSEndpoint`、`WeatherKit.WeatherCondition`、`CurrentWeather`、`HourWeather`、`DayWeather` 等模型。
- App 导入 `WeatherDaemon.WDSAuthenticatorFactory`、`WDSEndpoint`，用于构造 WeatherKit 服务和 JWT 认证。
- App 内部有 `WeatherDataUpdater`、`WeatherDataStoreObserver`、`weatherService`、`highPriorityWeatherService` 等符号，说明预报由 App/扩展侧的 WeatherKit 服务拉取并写入本地 `WeatherData` 状态。
- `weatherd` 负责通知、地理编码、数据库维护、天气预警通知等；它包含 `JSONDecoder` / `JSONEncoder` 与 `WeatherData` 相关符号，但不能据此断定所有预报请求都在 daemon 内完成。
- 小组件字符串中包含 `https://weather-data.apple.com/legal-attribution.html` 与 `https://weather-data.apple.com/assets/branding/...`，说明 Apple 天气品牌资源与天气数据域名相关。
- 公开资料与 WeatherKit 生态项目（NSRingo/WeatherKit）确认预报端点形态为：
  - `https://weatherkit.apple.com/api/v1/weather/{locale}/{latitude}/{longitude}?country=...&dataSets=...`
  - `https://weatherkit.apple.com/api/v2/weather/{locale}/{latitude}/{longitude}?country=...&dataSets=...`
  - 响应可能是 JSON，也可能是 `application/vnd.apple.flatbuffer`（WeatherKit v2）。

**未确认**：iOS 16.1.1 上天气 App 实际请求的是 `v1` JSON 还是 `v2` FlatBuffer，或两者混用。插件因此同时实现两条解析路径。

## 3. 为什么不用 Hook 单一网络请求替换全部数据

不可行的原因：

1. `WeatherKit.WeatherService` 是 Swift async API，直接 Hook 需要处理 Swift async 调用约定、上下文和 `Measurement` 等值类型，脆弱且版本敏感。
2. 天气数据模型字段多、存在可选/新增字段；伪造完整响应容易在系统升级后解码失败。
3. 预警、AQI、分钟级降水、日出日落、地图等数据集并不都由同一个 provider 提供，不能用一个 JSON 全部替换。
4. App/Widget/daemon 可能共享缓存，直接替换某一层网络响应未必覆盖所有 UI。

本项目的选择是：**保留 Apple 请求和响应，只覆盖响应中已存在且 provider 能可靠提供的标量字段**。这样：

- 原生 UI、Widget、锁屏 Widget 不需要改。
- 未支持的字段保留原生值，不伪造。
- schema 不匹配时补丁字段数为 0，直接透传。
- 不需要构造 WeatherKit Swift 对象。

## 4. 注入点与 Hook 设计

### 4.1 进程

`WeatherSource.plist` 过滤器：

```text
com.apple.weather
com.apple.weather.widget
com.apple.weather.poster
```

`weatherd` 暂不注入：预报请求在 App/扩展侧，MVP 先覆盖 UI 与小组件。若真机日志证明请求由 `weatherd` 发起，可增加 `com.apple.weatherd` 过滤器并在 daemon 中注册同一个 URLProtocol。

### 4.2 网络拦截

- 在 `%ctor` 中注册 `WSWeatherURLProtocol`。
- Hook `NSURLSessionConfiguration -protocolClasses`，确保天气 App 自定义的 session 也包含该 protocol。
- `canInitWithRequest:` 只接受：
  - host 为 `weatherkit.apple.com` 或 `weather-data.apple.com`
  - path 中包含 `weather` 组件
  - path 中能找到两个合法经纬度
- 对 `weatherAlerts`、`availability`、品牌资源等路径不拦截。
- 转发请求保留原始 Header（包括 Apple 的 Authorization/JWT），只额外加一个 `X-WeatherSource-Forwarded` 内部标记，防止 URLProtocol 递归拦截。Apple 服务端会忽略未知 Header。
- 响应通过 `NSURLProtocolClient` 返回给 WeatherKit；去掉 `Content-Encoding`/`Content-Length` 后重新设置长度，避免二次解压。

### 4.3 并发与超时

- Apple 请求与 provider 请求并行。
- Apple 响应到达后，最多再等 provider 2.5 秒；超时则返回 Apple 原始数据。
- provider 请求自身有 8 秒超时、最多 2 次重试；失败后尝试最近缓存（最多约 30 分钟）。
- 同一 provider + 经纬度的并发请求会合并，避免多个 widget 同时打 API。

## 5. WeatherKit 数据字段

### 5.1 单位约定

从 WeatherKit v2 FlatBuffer 绑定和生态项目的 provider 映射确认，WeatherKit 数值字段按米制：

| 字段 | 单位 |
|---|---|
| temperature / apparent / dewPoint | °C |
| humidity / cloudCover / precipitationChance / humidityMax/Min | 0–100 |
| pressure | hPa |
| windSpeed / windGust | km/h |
| windDirection | 0–359° |
| visibility | 米 |
| precipitationAmount | mm |
| snowfallAmount | mm |
| uvIndex | 整数 |
| forecastStart / reportedTime / readTime / expireTime | Unix 秒（Int32） |

Open-Meteo 请求使用 `temperature_unit=celsius`、`wind_speed_unit=kmh`、`precipitation_unit=mm`、`timeformat=unixtime`、`timezone=auto`；能见度原生为米。QWeather 使用 `unit=m`，能见度 km×1000。

### 5.2 v2 FlatBuffer 表与字段索引

以下索引来自 WeatherKit v2 生成的 FlatBuffer 绑定（NSRingo/WeatherKit v3.1.0 response bundle）。FlatBuffers 字段只追加，因此这些索引在旧版本中通常保持稳定；但仍需在 iOS 16.1.1 真机确认。

根表 `Weather`：

| 字段 | 索引 |
|---|---|
| airQuality | 0 |
| currentWeather | 1 |
| forecastDaily | 2 |
| forecastHourly | 3 |
| forecastNextHour | 4 |
| news | 5 |
| weatherAlerts | 6 |
| weatherChanges | 7 |
| historicalComparisons | 8 |
| locationInfo | 9 |

`CurrentWeatherData`：

| 字段 | 索引 | 类型 |
|---|---|---|
| metadata | 0 | table |
| asOf | 1 | int32 |
| cloudCover | 2 | int8 |
| conditionCode | 6 | int8 |
| daylight | 7 | int8 |
| humidity | 8 | int8 |
| precipitationAmount1h | 10 | float32 |
| pressure | 23 | float32 |
| snowfallAmount1h | 25 | float32 |
| temperature | 31 | float32 |
| temperatureApparent | 32 | float32 |
| temperatureDewPoint | 34 | float32 |
| uvIndex | 35 | int8 |
| visibility | 36 | float32 |
| windDirection | 37 | int16 |
| windGust | 38 | float32 |
| windSpeed | 39 | float32 |

`HourWeatherConditions`：

| 字段 | 索引 | 类型 |
|---|---|---|
| forecastStart | 0 | int32 |
| cloudCover | 1 | int8 |
| conditionCode | 5 | int8 |
| daylight | 6 | int8 |
| humidity | 7 | int8 |
| precipitationAmount | 9 | float32 |
| precipitationChance | 11 | int8 |
| pressure | 13 | float32 |
| snowfallAmount | 15 | float32 |
| temperature | 17 | float32 |
| temperatureApparent | 18 | float32 |
| temperatureDewPoint | 20 | float32 |
| uvIndex | 21 | int8 |
| visibility | 22 | float32 |
| windDirection | 23 | int16 |
| windGust | 24 | float32 |
| windSpeed | 25 | float32 |

`DayWeatherConditions`：

| 字段 | 索引 | 类型 |
|---|---|---|
| forecastStart | 0 | int32 |
| forecastEnd | 1 | int32 |
| conditionCode | 2 | int8 |
| humidityMax / humidityMin | 3 / 4 | int8 |
| maxUvIndex | 5 | int8 |
| precipitationAmount | 9 | float32 |
| precipitationChance | 11 | int8 |
| snowfallAmount | 13 | float32 |
| temperatureMax / temperatureMin | 24 / 26 | float32 |
| windGustSpeedMax | 28 | float32 |
| windSpeedAvg | 29 | float32 |
| windSpeedMax | 30 | float32 |

`Metadata`：

| 字段 | 索引 |
|---|---|
| expireTime | 1 |
| readTime | 7 |
| reportedTime | 8 |

插件只写这些字段中原本就存在的项。数组元素按 `forecastStart` 与 provider 时间做最近匹配（小时阈值 30 分钟，天阈值 12 小时）；匹配不到时按索引回退；仍不匹配则保留原值。

### 5.3 天气现象枚举

v2 FlatBuffer `WeatherCondition` 使用数值枚举。插件使用的值：

```text
CLEAR=0, BLIZZARD=1, PRECIPITATION=2, CLOUDY=5, DRIZZLE=6, FLURRIES=7,
FOGGY=8, HAZE=13, HEAVY_RAIN=14, HEAVY_SNOW=15, ISOLATED_THUNDERSTORMS=18,
MOSTLY_CLEAR=19, MOSTLY_CLOUDY=20, PARTLY_CLOUDY=21, RAIN=22, SNOW=26,
FREEZING_DRIZZLE=29, THUNDERSTORMS=30, WINDY=32, WINTRY_MIX=33
```

Open-Meteo 的 WMO `weather_code` 和 QWeather 的 `icon` 均映射到上述值；无法可靠映射时跳过，不覆盖原生天气现象。

## 6. 地区识别与覆盖

优先级：

1. 城市级覆盖：`ov_{lat2}_{lon2}` 偏好键（经纬度保留两位小数，约 1 km 粒度）。
2. 地区默认：`region_CN` / `region_HK` / `region_MO` / `region_TW` / `region_US` / `region_JP` / `region_KR` / `region_OTHER`。
3. 自动：
   - 中国大陆：有 QWeather Key 时用 QWeather，否则 Open-Meteo。
   - 其他地区：Open-Meteo（MVP）。
4. 不可用/无 Key：备用数据源 → Open-Meteo → Apple 原生。

地区判断同时使用请求 URL 的 `country` 参数和经纬度包围盒。香港、澳门、台湾的坐标优先于 `country`（例如 storefront 为 CN 但坐标在 HK 时按 HK 处理）。这不是精确的国界/行政区多边形，边境地区可能误判；日志会显示 region。

**不依赖设备 GPS**：插件只读取天气 App 自己请求的经纬度，因此用户切换城市时自然切换数据源；当前位置也走同一条路径。

## 7. 未验证项与风险

| 项目 | 状态 | 影响 / 缓解 |
|---|---|---|
| iOS 16.1.1 实际响应为 JSON 还是 FlatBuffer | **未验证** | 两条路径均已实现；失败时透传并记录 |
| FlatBuffer 字段索引在 16.1.1 是否一致 | **未验证** | 只写已存在字段；索引不匹配时 `changed=0`，透传 |
| `NSURLProtocol` 是否能拦截 WeatherKit 的 session | **未验证** | 已 Hook `protocolClasses`；日志会记录 `Weather request` 或仅 `NSURLSession task` |
| 请求是否由 `weatherd` 而非 App 发起 | **未验证** | 若真机日志证明，需要增加 daemon 注入 |
| 小组件进程是否复用 App 缓存 | **未验证** | 已注入 `com.apple.weather.widget`；仍以真机为准 |
| QWeather 实际字段/套餐权限 | **未验证** | 代码按公开文档实现；失败时回退 |
| 代码签名/rootless 路径 | **未验证** | GitHub Actions 使用 Theos rootless scheme 构建 |
| 数值单位 | 静态确认 + 生态项目一致 | 真机若显示异常，优先检查单位假设 |

## 8. 构建与验证建议

1. 推送代码，等待 GitHub Actions 的 `Build rootless deb` 通过。
2. 在 Dopamine 设备上安装 `.deb`，确认 `/var/jb/Library/MobileSubstrate/DynamicLibraries/WeatherSource.dylib` 和 `/var/jb/Library/PreferenceBundles/WeatherSourcePrefs.bundle` 存在。
3. 打开天气 App，日志级别设为 Debug，查看 `/tmp/WeatherSource.log`：
   - 出现 `Weather request ... provider=openmeteo`：URLProtocol 拦截成功。
   - 只有 `NSURLSession task:`：拦截未生效，需要换 Hook 点。
   - 出现 `Patch produced no changes`：schema 不匹配，需要根据真机响应调整字段索引/键名。
   - 出现 `Patched ... fields via openmeteo`：补丁成功，对比 UI 温度与 Open-Meteo 网页。
4. 切换不同城市，确认日志中的 provider 随 URL 经纬度变化；在设置页为某个位置选择 QWeather/Apple 后确认覆盖生效。
5. 断网/填错 Key，确认 UI 继续显示 Apple 原生数据而不是崩溃或空白。
