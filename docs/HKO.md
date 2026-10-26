# 香港天文台数据源

v0.1.15 新增 `hko` Provider；香港地区的“自动”选择优先使用 HKO，也支持地区、全局、逐城市手动选择。其他地区的默认策略保持不变。

## 接口与来源

- [实时天气报告 rhrread](https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=rhrread&lang=en)
- [九天天气预报 fnd](https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=fnd&lang=en)
- [官方 API 说明](https://data.weather.gov.hk/weatherAPI/doc/HKO_Open_Data_API_Documentation.pdf)
- [气象站位置](https://www.hko.gov.hk/en/cis/stn.htm)
- [天气图标定义](https://www.weather.gov.hk/en/textonly/explain/wxicon.htm)

请求固定使用 `lang=en` 以稳定匹配气象站名称，与 Apple 界面语言无关。无需 Key，也不向 HKO 发送用户经纬度。气象站选择在设备本地完成；只从响应中已返回、单位和数值有效且有已知位置的站点中选择最近者。温度与湿度分别选择可用站点，湿度通常来自天文台总部，不代表每个查询地点都有独立湿度观测。

## 字段映射

| HKO 字段 | 内部字段 | 处理 |
|---|---|---|
| temperature | current.temperature / timestamp | 最近可用站，摄氏度，按 recordTime 校验 |
| humidity | current.humidity | 百分比；Apple JSON 写为 0–1 |
| uvindex | current.uvIndex | 京士柏观测；夜间空值保留 Apple |
| icon | current.conditionCode | 按官方图标语义映射，干燥/潮湿/冷暖不推断晴雨 |
| forecastMaxtemp / forecastMintemp | daily.temperatureMax / Min | 保留实际极值 |
| forecastMaxrh / forecastMinrh | daily.humidityMax / Min | 百分比，不虚构平均湿度 |
| ForecastIcon | daily.conditionCode | 同上 |
| forecastDate | daily.timestamp | 香港时区午夜，按日期匹配 Apple 条目 |

九天预报通常从明天开始，今天与没有匹配日期的 Apple 日预报保持原样；Apple 条目没有可识别日期时也保持原样，不按数组下标套用明天的数据。该匹配策略随 snapshot 缓存保存。缺失、非数值、布尔、非有限值、错误单位、倒置极值及重复/无效日期均跳过。

温湿度最多接受两小时内的记录；UV 要求报告一小时内更新。天气图标与温度独立更新，要求报告两小时内、图标六小时内更新；最多容忍十分钟的设备时钟偏差。九天预报要求报告在 48 小时内更新，只接收今天起十天内的条目，排序去重后最多保留九天。

## 回退与边界

两个接口并行请求、独立解析；一个接口失败时仍可使用另一份有效报告。全部失败或没有可用字段时，由现有缓存/透传机制保留 Apple 响应。HKO 只用于当前香港粗略坐标框（22.13–22.60°N，113.80–114.52°E），范围外直接返回错误，不发请求。该框不能精确表示行政区边界。

本适配不提供逐小时预报、体感、露点、风、气压、能见度、数值降水概率/降水量、预警或 AQI。`PSR` 是显著降雨概率等级，`rainfall` 是地区雨量范围，不能直接当作查询点的概率或雨量。上述字段保留 Apple，设置页注明数据来自香港天文台；原生 Apple 归属界面仍保留。

## 验证

`tests/HKOProviderTests.mm` 使用代表性 HKO 响应固定样本，验证气象站、图标、香港日期、失效数据过滤、部分请求失败、注册和缓存，并调用实际 response patcher 检查比例单位及 Apple 未支持字段保留。网络与日志使用测试替身，测试不依赖实时天气数值。GitHub Actions 运行此测试和原 JSON 回归检查，然后编译 rootless `.deb`。真机验收结果另记于 `DEVICE_VERIFICATION.md`。

Actions 也生成独立的 `WeatherSource-device-tools` 制品。签名后的 `hko-device-probe` 需放在 rootless jailbreak 可执行目录（例如 `/var/jb/tmp/WeatherSource-0.1.15/`），不能直接从 iOS Media 目录运行。它使用实际 Provider/HTTP client/patcher，可输出实时 snapshot、对本地 Apple JSON 做补丁，并通过 `--settings` 只查看非敏感路由项。

`--test-hko backup.plist latitude longitude` 仅用于真机验收：先保存启用开关、地区路由、指定位置覆盖和日志级别，再临时启用 HKO/Debug；`--restore-settings backup.plist` 恢复这些项目。备份不含 API Key，权限为 0600，不要提交到仓库。响应和 snapshot 同样只保存在本地。
