# 已知限制

1. **尚未完成 iPhone12,8 / iOS 16.1.1 真机运行验证。** 目标设备在开发过程中重启，Dopamine 越狱与 SSH 未恢复。当前只能确认静态分析、代码实现和 CI 编译，不能声称运行成功。
2. **只覆盖 current / hourly / daily 的部分字段。** 天气预警、空气质量、分钟级降水、日出日落、月相、地图图层、Apple 原生归属信息保持原样。
3. **地区机构尚未全部接入。** HKO、SMG、CWA、NWS、JMA、KMA 只有设置项和 Provider 架构，选择后会回退 Open-Meteo。Open-Meteo 不是中国大陆的本地权威机构；中国大陆建议配置 QWeather Key。
4. **依赖 Apple 原始响应。** 插件只修改 Apple 已返回的响应；如果 Apple 请求失败或离线，插件无法单独生成完整 WeatherKit 响应。provider 缓存只能覆盖已缓存位置。
5. **单位假设为米制。** 如果某地区 WeatherKit 返回英制，数值会不一致。当前未实现按 locale 自适应单位。
6. **归属信息可能仍显示 Apple Weather。** 插件不修改原生归属 UI；实际 provider 可在设置页和日志中查看。
7. **API Key 存储在越狱偏好 plist，不是 Keychain。** 日志会隐藏完整 Key，但请勿在共享设备上使用付费 Key。
8. **QWeather 字段/套餐未联调。** 免费套餐、商用许可、字段可用性以 QWeather 官方为准。
9. **NSURLProtocol 可能被绕过。** 如果 WeatherKit 使用不经过 URLSession/NSURLProtocol 的网络栈，拦截不会生效。日志中的 `NSURLSession task:` 可用于判断。
10. **FlatBuffer 索引基于 WeatherKit v2 绑定。** 不同 iOS 版本可能新增字段；插件只写响应中已存在的字段，不匹配时透传，但可能无法覆盖。
11. **城市覆盖按两位小数经纬度匹配。** 约 1 km 粒度，适合城市/地点，不适合精确到街道的覆盖。
12. **不修改系统定位权限、TCC 或隐私设置。** 插件只使用天气 App 已获得的查询坐标。
13. **天气预警来源未替换。** 如果 provider 有本地预警，当前仍显示 Apple 的预警；这是“保留真实来源”的保守选择，不是完整的数据源切换。
