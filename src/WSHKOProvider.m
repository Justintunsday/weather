#import "WSHKOProvider.h"
#import "WSHTTPClient.h"
#import "WSCondition.h"
#import "WSLogger.h"
#import "WSShared.h"
#import <math.h>
#import <float.h>

static NSDictionary *HKDictionary(id value) {
    return [value isKindOfClass:[NSDictionary class]] ? value : nil;
}
static NSArray *HKArray(id value) {
    return [value isKindOfClass:[NSArray class]] ? value : @[];
}
static NSNumber *HKNumber(id value, double low, double high) {
    if (![value isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return nil;
    double number = [value doubleValue];
    return isfinite(number) && number >= low && number <= high ? @(number) : nil;
}
static NSDate *HKDate(id value) {
    if (![value isKindOfClass:[NSString class]]) return nil;
    NSISO8601DateFormatter *formatter = [NSISO8601DateFormatter new];
    NSDate *date = [formatter dateFromString:value];
    if (!date) {
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        date = [formatter dateFromString:value];
    }
    return date;
}
static BOOL HKSupportsLocation(double latitude, double longitude) {
    return isfinite(latitude) && isfinite(longitude) &&
           latitude >= 22.13 && latitude <= 22.60 && longitude >= 113.80 && longitude <= 114.52;
}
static BOOL HKFresh(id value, NSDate *now, NSTimeInterval maximumAge) {
    NSDate *date = HKDate(value);
    if (!date) return NO;
    NSTimeInterval age = [now timeIntervalSinceDate:date];
    return age >= -600 && age <= maximumAge;
}

// HKO station coordinates: https://www.hko.gov.hk/en/cis/stn.htm
// English API aliases are retained for stations whose full metadata names differ.
#define HKD(d,m,s) ((d) + (m)/60.0 + (s)/3600.0)
static NSDictionary *HKStations(void) {
    static NSDictionary *stations;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        stations = @{
            @"Hong Kong Observatory": @[@(HKD(22,18,7)), @(HKD(114,10,27))],
            @"King's Park": @[@(HKD(22,18,43)), @(HKD(114,10,22))],
            @"Wong Chuk Hang": @[@(HKD(22,14,52)), @(HKD(114,10,25))],
            @"Ta Kwu Ling": @[@(HKD(22,31,43)), @(HKD(114,9,24))],
            @"Lau Fau Shan": @[@(HKD(22,28,8)), @(HKD(113,59,1))],
            @"Tai Po": @[@(HKD(22,26,54)), @(HKD(114,10,38))],
            @"Tai Po (Yuen Chau Tsai Park)": @[@(HKD(22,26,54)), @(HKD(114,10,38))],
            @"Sha Tin": @[@(HKD(22,24,9)), @(HKD(114,12,36))],
            @"Tuen Mun": @[@(HKD(22,23,9)), @(HKD(113,57,51))],
            @"Tseung Kwan O": @[@(HKD(22,18,57)), @(HKD(114,15,20))],
            @"Sai Kung": @[@(HKD(22,22,32)), @(HKD(114,16,28))],
            @"Cheung Chau": @[@(HKD(22,12,4)), @(HKD(114,1,36))],
            @"Chek Lap Kok": @[@(HKD(22,18,34)), @(HKD(113,55,19))],
            @"Tsing Yi": @[@(HKD(22,20,39)), @(HKD(114,6,36))],
            @"Shek Kong": @[@(HKD(22,26,10)), @(HKD(114,5,5))],
            @"Tsuen Wan Shing Mun Valley": @[@(HKD(22,22,32)), @(HKD(114,7,36))],
            @"Tsuen Wan Ho Koon": @[@(HKD(22,23,1)), @(HKD(114,6,28))],
            @"Tsuen Wan": @[@(HKD(22,23,1)), @(HKD(114,6,28))],
            @"Hong Kong Park": @[@(HKD(22,16,42)), @(HKD(114,9,44))],
            @"Shau Kei Wan": @[@(HKD(22,16,54)), @(HKD(114,14,10))],
            @"Kowloon City": @[@(HKD(22,20,6)), @(HKD(114,11,5))],
            @"Happy Valley": @[@(HKD(22,16,14)), @(HKD(114,11,1))],
            @"Wong Tai Sin": @[@(HKD(22,20,22)), @(HKD(114,12,19))],
            @"Stanley": @[@(HKD(22,12,51)), @(HKD(114,13,7))],
            @"Kwun Tong": @[@(HKD(22,19,7)), @(HKD(114,13,29))],
            @"Sham Shui Po": @[@(HKD(22,20,9)), @(HKD(114,8,13))],
            @"Kai Tak Runway Park": @[@(HKD(22,18,18)), @(HKD(114,13,1))],
            @"Yuen Long Park": @[@(HKD(22,26,27)), @(HKD(114,1,6))],
            @"Tai Mei Tuk": @[@(HKD(22,28,31)), @(HKD(114,14,15))]
        };
    });
    return stations;
}

static NSDictionary *HKNearest(NSDictionary *measurement, double latitude, double longitude, NSString *unit, double low, double high) {
    NSDictionary *nearest = nil;
    double best = DBL_MAX;
    for (id raw in HKArray(measurement[@"data"])) {
        NSDictionary *item = HKDictionary(raw);
        NSString *place = [item[@"place"] isKindOfClass:[NSString class]] ? item[@"place"] : nil;
        NSArray *position = place ? HKStations()[place] : nil;
        if (!position || ![item[@"unit"] isEqual:unit] || !HKNumber(item[@"value"], low, high)) continue;
        double dy = latitude - [position[0] doubleValue];
        double dx = (longitude - [position[1] doubleValue]) * cos(latitude * M_PI / 180.0);
        double distance = dx*dx + dy*dy;
        if (distance < best) { best = distance; nearest = item; }
    }
    return nearest;
}

static NSNumber *HKCondition(id raw) {
    NSNumber *number = HKNumber(raw, 0, 999);
    if (!number || number.doubleValue != number.intValue) return nil;
    // https://www.weather.gov.hk/en/textonly/explain/wxicon.htm
    switch (number.intValue) {
        case 50: case 70: case 71: case 72: case 73: case 74: case 75: return @(WSWeatherConditionClear);
        case 51: case 77: return @(WSWeatherConditionMostlyClear);
        case 52: return @(WSWeatherConditionPartlyCloudy);
        case 53: case 54: case 62: case 63: return @(WSWeatherConditionRain);
        case 60: return @(WSWeatherConditionMostlyCloudy);
        case 61: return @(WSWeatherConditionCloudy);
        case 64: return @(WSWeatherConditionHeavyRain);
        case 65: return @(WSWeatherConditionThunderstorms);
        case 76: return @(WSWeatherConditionMostlyCloudy);
        case 80: return @(WSWeatherConditionWindy);
        case 83: case 84: return @(WSWeatherConditionFoggy);
        case 85: return @(WSWeatherConditionHaze);
        // Dry/humid/hot/warm/cool/cold do not specify cloud or precipitation.
        default: return nil;
    }
}

@implementation WSHKOProvider
- (NSString *)identifier { return WS_PROVIDER_HKO; }
- (NSString *)displayName { return @"Hong Kong Observatory"; }
- (BOOL)isAvailable { return YES; }

- (void)fetchSnapshotForLatitude:(double)latitude longitude:(double)longitude locale:(NSString *)locale completion:(WSProviderCompletion)completion {
    if (!completion) return;
    if (!HKSupportsLocation(latitude, longitude)) {
        completion(nil, WSProviderError(-40, @"HKO only covers Hong Kong"));
        return;
    }
    // Fixed English response keys allow stable station-name lookup for every UI locale.
    (void)locale;
    dispatch_group_t group = dispatch_group_create();
    NSObject *guard = [NSObject new];
    __block NSDictionary *current = nil, *forecast = nil;
    __block NSError *lastError = nil;
    for (NSString *type in @[@"rhrread", @"fnd"]) {
        dispatch_group_enter(group);
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=%@&lang=en", type]];
        [[WSHTTPClient shared] GETJSON:url headers:nil completion:^(id json, NSData *data, NSHTTPURLResponse *response, NSError *error) {
            @synchronized (guard) {
                if (error) {
                    lastError = error;
                    [WSLogger warning:@"HKO %@ request failed: %@", type, error.localizedDescription];
                }
                else if ([type isEqualToString:@"rhrread"]) current = HKDictionary(json);
                else forecast = HKDictionary(json);
            }
            dispatch_group_leave(group);
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        WSWeatherSnapshot *snapshot = [[self class] snapshotWithCurrent:current forecast:forecast latitude:latitude longitude:longitude referenceDate:[NSDate date]];
        if (snapshot.hasAnyData) {
            NSDictionary *temperature = HKDictionary(current[@"temperature"]);
            NSDictionary *station = snapshot.current.temperature ? HKNearest(temperature, latitude, longitude, @"C", -80, 65) : nil;
            [WSLogger info:@"HKO station=%@ current=%@ daily=%lu (hourly and unavailable fields retain Apple)", station[@"place"] ?: @"unavailable", snapshot.current.temperature ?: @"unavailable", (unsigned long)snapshot.daily.count];
            completion(snapshot, nil);
        }
        else completion(nil, lastError ?: WSProviderError(-41, @"HKO returned no fresh usable observations or forecast"));
    });
}

+ (WSWeatherSnapshot *)snapshotWithCurrent:(NSDictionary *)current forecast:(NSDictionary *)forecast latitude:(double)latitude longitude:(double)longitude referenceDate:(NSDate *)now {
    WSWeatherSnapshot *snapshot = [WSWeatherSnapshot new];
    snapshot.providerID = WS_PROVIDER_HKO;
    snapshot.providerName = @"Hong Kong Observatory";
    snapshot.requiresForecastTimestamps = YES;
    snapshot.fetchedAt = now.timeIntervalSince1970;
    if (!HKSupportsLocation(latitude, longitude)) return snapshot;
    current = HKDictionary(current);
    forecast = HKDictionary(forecast);
    WSCurrentWeather *weather = [WSCurrentWeather new];
    NSDictionary *temperature = HKDictionary(current[@"temperature"]);
    if (HKFresh(temperature[@"recordTime"], now, 7200)) {
        NSDictionary *station = HKNearest(temperature, latitude, longitude, @"C", -80, 65);
        weather.temperature = HKNumber(station[@"value"], -80, 65);
        if (weather.temperature) weather.timestamp = @(HKDate(temperature[@"recordTime"]).timeIntervalSince1970);
    }
    NSDictionary *humidity = HKDictionary(current[@"humidity"]);
    if (HKFresh(humidity[@"recordTime"], now, 7200)) weather.humidity = HKNumber(HKNearest(humidity, latitude, longitude, @"percent", 0, 100)[@"value"], 0, 100);
    // Icons have a separate update time and can legitimately be older than
    // the hourly observations. Require a fresh report as well as a bounded icon age.
    if (HKFresh(current[@"updateTime"], now, 7200) && HKFresh(current[@"iconUpdateTime"], now, 6*3600)) {
        weather.conditionCode = HKCondition(HKArray(current[@"icon"]).firstObject);
    }
    NSDictionary *uv = HKDictionary(current[@"uvindex"]);
    if (HKFresh(current[@"updateTime"], now, 3600)) {
        for (id raw in HKArray(uv[@"data"])) {
            NSDictionary *item = HKDictionary(raw);
            if ([item[@"place"] isEqual:@"King's Park"]) { weather.uvIndex = HKNumber(item[@"value"], 0, 30); break; }
        }
    }
    if (weather.temperature || weather.humidity || weather.conditionCode || weather.uvIndex) snapshot.current = weather;

    NSMutableArray *days = [NSMutableArray array];
    if (HKFresh(forecast[@"updateTime"], now, 48*3600)) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Hong_Kong"];
        formatter.dateFormat = @"yyyyMMdd";
        formatter.lenient = NO;
        NSDate *today = [formatter dateFromString:[formatter stringFromDate:now]];
        NSMutableSet *seen = [NSMutableSet set];
        for (id raw in HKArray(forecast[@"weatherForecast"])) {
            NSDictionary *item = HKDictionary(raw);
            NSString *dateString = [item[@"forecastDate"] isKindOfClass:[NSString class]] ? item[@"forecastDate"] : nil;
            NSDate *date = dateString.length == 8 ? [formatter dateFromString:dateString] : nil;
            if (!date || ![[formatter stringFromDate:date] isEqual:dateString] || [seen containsObject:dateString] || [date timeIntervalSinceDate:today] < 0 || [date timeIntervalSinceDate:today] > 10*86400) continue;
            WSDailyWeather *day = [WSDailyWeather new];
            day.timestamp = @(date.timeIntervalSince1970);
            day.endTimestamp = @([date timeIntervalSince1970] + 86400);
            NSDictionary *high = HKDictionary(item[@"forecastMaxtemp"]), *low = HKDictionary(item[@"forecastMintemp"]);
            if ([high[@"unit"] isEqual:@"C"]) day.temperatureMax = HKNumber(high[@"value"], -80, 65);
            if ([low[@"unit"] isEqual:@"C"]) day.temperatureMin = HKNumber(low[@"value"], -80, 65);
            if (day.temperatureMax && day.temperatureMin && day.temperatureMax.doubleValue < day.temperatureMin.doubleValue) { day.temperatureMax = nil; day.temperatureMin = nil; }
            NSDictionary *rhHigh = HKDictionary(item[@"forecastMaxrh"]), *rhLow = HKDictionary(item[@"forecastMinrh"]);
            if ([rhHigh[@"unit"] isEqual:@"percent"]) day.humidityMax = HKNumber(rhHigh[@"value"], 0, 100);
            if ([rhLow[@"unit"] isEqual:@"percent"]) day.humidityMin = HKNumber(rhLow[@"value"], 0, 100);
            if (day.humidityMax && day.humidityMin && day.humidityMax.doubleValue < day.humidityMin.doubleValue) { day.humidityMax = nil; day.humidityMin = nil; }
            day.conditionCode = HKCondition(item[@"ForecastIcon"]);
            // PSR is categorical significant-rain likelihood; never invent a numeric probability.
            if (day.temperatureMax || day.temperatureMin || day.humidityMax || day.humidityMin || day.conditionCode) { [days addObject:day]; [seen addObject:dateString]; }
        }
    }
    [days sortUsingComparator:^NSComparisonResult(WSDailyWeather *a, WSDailyWeather *b) { return [a.timestamp compare:b.timestamp]; }];
    snapshot.daily = days.count > 9 ? [days subarrayWithRange:NSMakeRange(0, 9)] : days;
    return snapshot;
}
@end
