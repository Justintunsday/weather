#import "WSQWeatherProvider.h"
#import "WSHTTPClient.h"
#import "WSSettings.h"
#import "WSLogger.h"
#import "WSCondition.h"
#import <math.h>

static NSNumber *QNumber(NSDictionary *dictionary, NSString *key) {
    id value = dictionary[key];
    if ([value isKindOfClass:[NSNumber class]]) return value;
    if ([value isKindOfClass:[NSString class]]) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        double number = 0;
        if ([scanner scanDouble:&number] && scanner.isAtEnd) return @(number);
    }
    return nil;
}

static NSNumber *QClampedInteger(NSNumber *value, int minimum, int maximum) {
    if (!value) return nil;
    int number = (int)llround(value.doubleValue);
    if (number < minimum) number = minimum;
    if (number > maximum) number = maximum;
    return @(number);
}

static NSNumber *QWindDirection(NSNumber *value) {
    if (!value) return nil;
    double degrees = fmod(value.doubleValue, 360.0);
    if (degrees < 0) degrees += 360.0;
    return @((int)llround(degrees) % 360);
}

static NSDate *QDateFromISO8601(NSString *string) {
    if (![string isKindOfClass:[NSString class]] || !string.length) return nil;
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    NSDate *date = [formatter dateFromString:string];
    if (date) return date;
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
    return [formatter dateFromString:string];
}

static NSNumber *QDateFromDayString(NSString *string) {
    if (![string isKindOfClass:[NSString class]] || !string.length) return nil;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    formatter.dateFormat = @"yyyy-MM-dd";
    NSDate *date = [formatter dateFromString:string];
    return date ? @([date timeIntervalSince1970]) : nil;
}

@implementation WSQWeatherProvider

- (NSString *)identifier { return @"qweather"; }
- (NSString *)displayName { return @"鍜岄澶╂皵 QWeather"; }
- (BOOL)isAvailable { return [WSSettings shared].qweatherKey.length > 0; }

- (NSURL *)URLForPath:(NSString *)path latitude:(double)latitude longitude:(double)longitude locale:(NSString *)locale {
    WSSettings *settings = [WSSettings shared];
    NSString *host = settings.qweatherHost;
    NSString *key = settings.qweatherKey;
    if (!key.length) return nil;

    NSString *language = [locale.lowercaseString hasPrefix:@"zh"] ? @"zh" : @"en";
    NSURLComponents *components = [NSURLComponents componentsWithString:
        [NSString stringWithFormat:@"https://%@/%@", host, path]];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"location" value:[NSString stringWithFormat:@"%.4f,%.4f", longitude, latitude]],
        [NSURLQueryItem queryItemWithName:@"key" value:key],
        [NSURLQueryItem queryItemWithName:@"lang" value:language],
        [NSURLQueryItem queryItemWithName:@"unit" value:@"m"],
    ];
    return components.URL;
}

- (void)fetchSnapshotForLatitude:(double)latitude
                       longitude:(double)longitude
                          locale:(NSString *)locale
                      completion:(WSProviderCompletion)completion {
    WSSettings *settings = [WSSettings shared];
    if (!settings.qweatherKey.length) {
        completion(nil, WSProviderError(-10, @"鏈厤缃拰椋庡ぉ姘?API Key"));
        return;
    }

    NSURL *nowURL = [self URLForPath:@"v7/weather/now" latitude:latitude longitude:longitude locale:locale];
    NSURL *hourlyURL = [self URLForPath:@"v7/weather/24h" latitude:latitude longitude:longitude locale:locale];
    NSURL *dailyURL = [self URLForPath:@"v7/weather/10d" latitude:latitude longitude:longitude locale:locale];
    if (!nowURL || !hourlyURL || !dailyURL) {
        completion(nil, WSProviderError(-11, @"鏃犳硶鏋勯€犲拰椋庡ぉ姘旇姹?));
        return;
    }

    __block NSDictionary *nowJSON = nil;
    __block NSDictionary *hourlyJSON = nil;
    __block NSDictionary *dailyJSON = nil;
    __block NSError *nowError = nil;
    __block NSError *hourlyError = nil;
    __block NSError *dailyError = nil;
    __block NSInteger remaining = 3;

    void (^finishIfReady)(void) = ^{
        if (--remaining > 0) return;
        WSWeatherSnapshot *snapshot = [self snapshotWithNow:nowJSON hourly:hourlyJSON daily:dailyJSON];
        if (snapshot.hasAnyData) {
            completion(snapshot, nil);
        } else {
            NSError *error = nowError ?: hourlyError ?: dailyError ?: WSProviderError(-12, @"鍜岄澶╂皵鏈繑鍥炲彲鐢ㄦ暟鎹?);
            completion(nil, error);
        }
    };

    void (^request)(NSURL *, NSString *, void (^)(NSDictionary *, NSError *)) = ^(NSURL *url, NSString *label, void (^done)(NSDictionary *, NSError *)) {
        [[WSHTTPClient shared] GETJSON:url headers:nil completion:^(id json, NSData *data, NSHTTPURLResponse *response, NSError *error) {
            (void)data;
            (void)response;
            NSDictionary *dictionary = [json isKindOfClass:[NSDictionary class]] ? json : nil;
            NSString *code = dictionary[@"code"] ? [dictionary[@"code"] description] : nil;
            if (!error && dictionary && code && ![code isEqualToString:@"200"]) {
                error = WSProviderError(code.integerValue, [NSString stringWithFormat:@"鍜岄澶╂皵 %@ 杩斿洖 code=%@", label, code]);
            }
            if (!error && !dictionary) {
                error = WSProviderError(-13, [NSString stringWithFormat:@"鍜岄澶╂皵 %@ 杩斿洖鏍煎紡閿欒", label]);
            }
            done(dictionary, error);
        }];
    };

    request(nowURL, @"now", ^(NSDictionary *json, NSError *error) {
        nowJSON = json;
        nowError = error;
        finishIfReady();
    });

    request(hourlyURL, @"24h", ^(NSDictionary *json, NSError *error) {
        hourlyJSON = json;
        hourlyError = error;
        finishIfReady();
    });

    request(dailyURL, @"10d", ^(NSDictionary *json, NSError *error) {
        dailyJSON = json;
        dailyError = error;
        finishIfReady();
    });
}

- (WSWeatherSnapshot *)snapshotWithNow:(NSDictionary *)nowJSON
                                hourly:(NSDictionary *)hourlyJSON
                                 daily:(NSDictionary *)dailyJSON {
    WSWeatherSnapshot *snapshot = [[WSWeatherSnapshot alloc] init];
    snapshot.providerID = self.identifier;
    snapshot.providerName = self.displayName;
    snapshot.fetchedAt = [[NSDate date] timeIntervalSince1970];

    NSArray *hourlyItems = [hourlyJSON[@"hourly"] isKindOfClass:[NSArray class]] ? hourlyJSON[@"hourly"] : @[];
    NSMutableArray<WSHourlyWeather *> *hours = [NSMutableArray array];
    for (NSDictionary *item in hourlyItems) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        WSHourlyWeather *hour = [[WSHourlyWeather alloc] init];
        NSDate *date = QDateFromISO8601(item[@"fxTime"]);
        hour.timestamp = date ? @([date timeIntervalSince1970]) : nil;
        hour.temperature = QNumber(item, @"temp");
        hour.humidity = QClampedInteger(QNumber(item, @"humidity"), 0, 100);
        hour.pressure = QNumber(item, @"pressure");
        hour.windSpeed = QNumber(item, @"windSpeed");
        hour.windDirection = QWindDirection(QNumber(item, @"wind360"));
        hour.cloudCover = QClampedInteger(QNumber(item, @"cloud"), 0, 100);
        hour.precipitationChance = QClampedInteger(QNumber(item, @"pop"), 0, 100);
        hour.precipitationAmount = QNumber(item, @"precip");
        hour.dewPoint = QNumber(item, @"dew");
        NSNumber *hourVisibilityKm = QNumber(item, @"vis");
        hour.visibility = hourVisibilityKm ? @(hourVisibilityKm.doubleValue * 1000.0) : nil;
        hour.uvIndex = QClampedInteger(QNumber(item, @"uvIndex"), 0, 20);
        int condition = [WSCondition conditionForQWeatherIcon:[item[@"icon"] description]];
        if (condition >= 0) hour.conditionCode = @(condition);
        if (hour.temperature || hour.conditionCode) [hours addObject:hour];
    }
    snapshot.hourly = hours;

    NSArray *dailyItems = [dailyJSON[@"daily"] isKindOfClass:[NSArray class]] ? dailyJSON[@"daily"] : @[];
    NSMutableArray<WSDailyWeather *> *days = [NSMutableArray array];
    for (NSDictionary *item in dailyItems) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        WSDailyWeather *day = [[WSDailyWeather alloc] init];
        day.timestamp = QDateFromDayString(item[@"fxDate"]);
        day.temperatureMax = QNumber(item, @"tempMax");
        day.temperatureMin = QNumber(item, @"tempMin");
        day.maxUvIndex = QClampedInteger(QNumber(item, @"uvIndex"), 0, 20);
        day.precipitationAmount = QNumber(item, @"precip");
        day.precipitationChance = QClampedInteger(QNumber(item, @"pop"), 0, 100);
        day.windSpeedAvg = QNumber(item, @"windSpeedDay");
        day.windGustSpeedMax = QNumber(item, @"windGustDay");
        int condition = [WSCondition conditionForQWeatherIcon:[item[@"iconDay"] description]];
        if (condition >= 0) day.conditionCode = @(condition);
        if (day.temperatureMax || day.temperatureMin || day.conditionCode) [days addObject:day];
    }
    snapshot.daily = days;

    NSDictionary *now = [nowJSON[@"now"] isKindOfClass:[NSDictionary class]] ? nowJSON[@"now"] : nil;
    if (now) {
        WSCurrentWeather *current = [[WSCurrentWeather alloc] init];
        NSDate *date = QDateFromISO8601(now[@"obsTime"]);
        current.timestamp = date ? @([date timeIntervalSince1970]) : nil;
        current.temperature = QNumber(now, @"temp");
        current.apparentTemperature = QNumber(now, @"feelsLike");
        current.humidity = QClampedInteger(QNumber(now, @"humidity"), 0, 100);
        current.pressure = QNumber(now, @"pressure");
        current.windSpeed = QNumber(now, @"windSpeed");
        current.windDirection = QWindDirection(QNumber(now, @"wind360"));
        NSNumber *currentVisibilityKm = QNumber(now, @"vis");
        current.visibility = currentVisibilityKm ? @(currentVisibilityKm.doubleValue * 1000.0) : nil;
        current.cloudCover = QClampedInteger(QNumber(now, @"cloud"), 0, 100);
        current.precipitationAmount1h = QNumber(now, @"precip");
        current.dewPoint = QNumber(now, @"dew");
        current.uvIndex = QClampedInteger(QNumber(now, @"uvIndex"), 0, 20);
        int condition = [WSCondition conditionForQWeatherIcon:[now[@"icon"] description]];
        if (condition >= 0) current.conditionCode = @(condition);
        if (!current.conditionCode || !current.temperature) {
            // Leave the snapshot current object; the patcher writes only available values.
        }
        snapshot.current = current;
    }

    return snapshot;
}

@end


