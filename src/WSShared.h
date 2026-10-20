#import <Foundation/Foundation.h>
#import <math.h>

#define WS_PREF_DOMAIN @"com.weathersource.tweak"
#define WS_NOTIFY_SETTINGS_CHANGED "com.weathersource.settingsChanged"
#define WS_NOTIFY_REFRESH_REQUESTED "com.weathersource.refreshRequested"

#define WS_PROVIDER_AUTO @"auto"
#define WS_PROVIDER_APPLE @"apple"
#define WS_PROVIDER_OPEN_METEO @"openmeteo"
#define WS_PROVIDER_QWEATHER @"qweather"
#define WS_PROVIDER_HKO @"hko"
#define WS_PROVIDER_SMG @"smg"
#define WS_PROVIDER_CWA @"cwa"
#define WS_PROVIDER_NWS @"nws"
#define WS_PROVIDER_JMA @"jma"
#define WS_PROVIDER_KMA @"kma"

#define WS_REGION_CN @"CN"
#define WS_REGION_HK @"HK"
#define WS_REGION_MO @"MO"
#define WS_REGION_TW @"TW"
#define WS_REGION_US @"US"
#define WS_REGION_JP @"JP"
#define WS_REGION_KR @"KR"
#define WS_REGION_OTHER @"OTHER"

#define WS_DEFAULT_CACHE_TTL 600.0
#define WS_DEFAULT_REQUEST_TIMEOUT 8.0
#define WS_DEFAULT_MIN_REFRESH_INTERVAL 60.0
#define WS_DEFAULT_FALLBACK_PROVIDER WS_PROVIDER_OPEN_METEO
#define WS_MAX_LOG_ENTRIES 300
#define WS_MAX_RECENT_LOCATIONS 24

static inline NSString *WSProviderDisplayName(NSString *provider) {
    if ([provider isEqualToString:WS_PROVIDER_APPLE]) return @"Apple Weather（原生）";
    if ([provider isEqualToString:WS_PROVIDER_OPEN_METEO]) return @"Open-Meteo";
    if ([provider isEqualToString:WS_PROVIDER_QWEATHER]) return @"和风天气 QWeather";
    if ([provider isEqualToString:WS_PROVIDER_HKO]) return @"香港天文台 HKO";
    if ([provider isEqualToString:WS_PROVIDER_SMG]) return @"澳门地球物理气象局 SMG";
    if ([provider isEqualToString:WS_PROVIDER_CWA]) return @"台湾中央气象署 CWA";
    if ([provider isEqualToString:WS_PROVIDER_NWS]) return @"美国 NOAA / NWS";
    if ([provider isEqualToString:WS_PROVIDER_JMA]) return @"日本气象厅 JMA";
    if ([provider isEqualToString:WS_PROVIDER_KMA]) return @"韩国气象厅 KMA";
    return @"自动";
}

static inline NSString *WSProviderShortName(NSString *provider) {
    if ([provider isEqualToString:WS_PROVIDER_APPLE]) return @"Apple";
    if ([provider isEqualToString:WS_PROVIDER_OPEN_METEO]) return @"Open-Meteo";
    if ([provider isEqualToString:WS_PROVIDER_QWEATHER]) return @"QWeather";
    if ([provider isEqualToString:WS_PROVIDER_HKO]) return @"HKO";
    if ([provider isEqualToString:WS_PROVIDER_SMG]) return @"SMG";
    if ([provider isEqualToString:WS_PROVIDER_CWA]) return @"CWA";
    if ([provider isEqualToString:WS_PROVIDER_NWS]) return @"NWS";
    if ([provider isEqualToString:WS_PROVIDER_JMA]) return @"JMA";
    if ([provider isEqualToString:WS_PROVIDER_KMA]) return @"KMA";
    return @"Auto";
}

static inline NSString *WSRegionDisplayName(NSString *region) {
    if ([region isEqualToString:WS_REGION_CN]) return @"中国大陆";
    if ([region isEqualToString:WS_REGION_HK]) return @"香港";
    if ([region isEqualToString:WS_REGION_MO]) return @"澳门";
    if ([region isEqualToString:WS_REGION_TW]) return @"台湾";
    if ([region isEqualToString:WS_REGION_US]) return @"美国";
    if ([region isEqualToString:WS_REGION_JP]) return @"日本";
    if ([region isEqualToString:WS_REGION_KR]) return @"韩国";
    return @"其他地区";
}

static inline NSString *WSOverrideKey(double latitude, double longitude) {
    double lat = round(latitude * 100.0) / 100.0;
    double lon = round(longitude * 100.0) / 100.0;
    if (lat == 0.0) lat = 0.0;
    if (lon == 0.0) lon = 0.0;
    return [NSString stringWithFormat:@"ov_%.2f_%.2f", lat, lon];
}

static inline NSString *WSRegionProviderKey(NSString *region) {
    return [NSString stringWithFormat:@"region_%@", region];
}
