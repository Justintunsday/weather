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
    if ([provider isEqualToString:WS_PROVIDER_APPLE]) return @"Apple Weather锛堝師鐢燂級";
    if ([provider isEqualToString:WS_PROVIDER_OPEN_METEO]) return @"Open-Meteo";
    if ([provider isEqualToString:WS_PROVIDER_QWEATHER]) return @"鍜岄澶╂皵 QWeather";
    if ([provider isEqualToString:WS_PROVIDER_HKO]) return @"棣欐腐澶╂枃鍙?HKO";
    if ([provider isEqualToString:WS_PROVIDER_SMG]) return @"婢抽棬鍦扮悆鐗╃悊姘旇薄灞€ SMG";
    if ([provider isEqualToString:WS_PROVIDER_CWA]) return @"鍙版咕涓ぎ姘旇薄缃?CWA";
    if ([provider isEqualToString:WS_PROVIDER_NWS]) return @"缇庡浗 NOAA / NWS";
    if ([provider isEqualToString:WS_PROVIDER_JMA]) return @"鏃ユ湰姘旇薄鍘?JMA";
    if ([provider isEqualToString:WS_PROVIDER_KMA]) return @"闊╁浗姘旇薄鍘?KMA";
    return @"鑷姩";
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
    if ([region isEqualToString:WS_REGION_CN]) return @"涓浗澶ч檰";
    if ([region isEqualToString:WS_REGION_HK]) return @"棣欐腐";
    if ([region isEqualToString:WS_REGION_MO]) return @"婢抽棬";
    if ([region isEqualToString:WS_REGION_TW]) return @"鍙版咕";
    if ([region isEqualToString:WS_REGION_US]) return @"缇庡浗";
    if ([region isEqualToString:WS_REGION_JP]) return @"鏃ユ湰";
    if ([region isEqualToString:WS_REGION_KR]) return @"闊╁浗";
    return @"鍏朵粬鍦板尯";
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

