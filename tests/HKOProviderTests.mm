#import <Foundation/Foundation.h>
#import "WSHKOProvider.h"
#import "WSHTTPClient.h"
#import "WSLogger.h"
#import "WSCondition.h"
#import "WSProviderRegistry.h"
#import "WSWeatherResponsePatcher.h"
#import <math.h>

static NSUInteger checks = 0;
static void Check(BOOL result, NSString *message) {
    checks++;
    if (!result) { NSLog(@"FAIL: %@", message); exit(1); }
}

static NSMutableDictionary *Fixture(NSString *name) {
    NSString *path = [NSString stringWithFormat:@"tests/fixtures/%@.json", name];
    NSData *data = [NSData dataWithContentsOfFile:path];
    Check(data != nil, [@"fixture exists: " stringByAppendingString:path]);
    return [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
}

static NSDate *Date(NSString *value) {
    return [[NSISO8601DateFormatter new] dateFromString:value];
}

static WSWeatherSnapshot *Parse(id current, id forecast) {
    return [WSHKOProvider snapshotWithCurrent:current forecast:forecast latitude:22.38361 longitude:114.10778 referenceDate:Date(@"2026-10-26T21:10:00+08:00")];
}

// Only HTTP and logging are replaced. The provider, registry, models and patcher
// below are the same implementations shipped in the tweak.
static NSDictionary *httpResults;
static NSUInteger httpRequests;
@implementation WSHTTPClient
+ (instancetype)shared { static WSHTTPClient *client; static dispatch_once_t once; dispatch_once(&once, ^{ client = [WSHTTPClient new]; }); return client; }
- (void)GETJSON:(NSURL *)url headers:(NSDictionary *)headers completion:(WSHTTPJSONCompletion)completion {
    httpRequests++;
    Check([url.scheme isEqual:@"https"] && [url.host isEqual:@"data.weather.gov.hk"], @"only send requests to official HTTPS API");
    NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSMutableDictionary *query = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *item in parts.queryItems) query[item.name] = item.value;
    Check([query[@"lang"] isEqual:@"en"], @"stable English station identifiers for every UI locale");
    Check(query.count == 2 && headers.count == 0, @"HKO needs neither a key nor user coordinates");
    id result = httpResults[query[@"dataType"]];
    if ([result isKindOfClass:[NSError class]]) completion(nil, nil, nil, result);
    else completion(result, nil, nil, nil);
}
@end

@implementation WSLogger
+ (void)logLevel:(WSLogLevel)level format:(NSString *)format, ... {}
+ (void)error:(NSString *)format, ... {}
+ (void)warning:(NSString *)format, ... {}
+ (void)info:(NSString *)format, ... {}
+ (void)debug:(NSString *)format, ... {}
+ (NSString *)logFilePath { return @"/dev/null"; }
+ (NSArray *)logFilePaths { return @[]; }
+ (void)clearFileLog {}
@end

static void TestObservations(void) {
    WSWeatherSnapshot *snapshot = Parse(Fixture(@"hko-current"), Fixture(@"hko-forecast"));
    Check([snapshot.providerID isEqual:@"hko"] && snapshot.hasAnyData, @"HKO snapshot is usable");
    Check(snapshot.current.temperature.intValue == 24, @"use nearest available station, including Tsuen Wan Ho Koon alias");
    Check(snapshot.current.humidity.intValue == 75, @"use official humidity observation");
    Check(snapshot.current.conditionCode.intValue == WSWeatherConditionMostlyClear, @"night icon survives independent update schedule");
    Check(snapshot.current.uvIndex == nil, @"empty nighttime UV remains absent");
    Check(snapshot.hourly.count == 0 && snapshot.current.precipitationChance == nil && snapshot.current.precipitationAmount1h == nil, @"do not invent hourly data or turn district rainfall maxima into point observations");
    Check(snapshot.current.apparentTemperature == nil && snapshot.current.windSpeed == nil, @"unsupported current measurements stay absent");
    Check(snapshot.daily.count == 9 && snapshot.daily[0].temperatureMax.intValue == 30, @"parse nine-day maximum temperature");
    Check(snapshot.daily[0].temperatureMin.intValue == 25 && snapshot.daily[0].humidityMax.intValue == 85 && snapshot.daily[0].humidityMin.intValue == 55, @"retain actual forecast extrema");
    Check(snapshot.daily[0].timestamp.doubleValue == Date(@"2026-10-26T16:00:00Z").timeIntervalSince1970, @"forecast day starts at Hong Kong midnight");
    Check(snapshot.daily[0].precipitationChance == nil && snapshot.daily[0].humidity == nil, @"categorical PSR and humidity ranges do not become invented numeric values");
    WSWeatherSnapshot *cached = [WSWeatherSnapshot fromDictionary:snapshot.dictionaryRepresentation];
    Check(cached.daily.count == 9 && cached.current.temperature.intValue == 24 && cached.hourly.count == 0 && cached.requiresForecastTimestamps, @"HKO survives shared cache serialization including date-matching policy");

    NSMutableDictionary *current = Fixture(@"hko-current");
    current[@"temperature"][@"data"] = @[@{@"place": @"Unknown Station", @"value": @1, @"unit": @"C"}, @{@"place": @"Hong Kong Observatory", @"value": @28, @"unit": @"C"}];
    Check(Parse(current, nil).current.temperature.intValue == 28, @"unknown nearest-station metadata cannot override a known observation");
    current[@"uvindex"] = @{@"data": @[@{@"place": @"King's Park", @"value": @4, @"desc": @"Moderate"}]};
    Check(Parse(current, nil).current.uvIndex.intValue == 4, @"daytime UV is supported");
    current[@"temperature"][@"recordTime"] = @"2026-10-26T21:00:00.000+08:00";
    Check(Parse(current, nil).current.temperature.intValue == 28, @"fractional timestamp accepted");
}

static void TestInvalidAndStaleData(void) {
    Check(!Parse(nil, nil).hasAnyData && !Parse((id)@[], (id)@"bad").hasAnyData, @"missing or malformed roots return no data");
    NSMutableDictionary *current = Fixture(@"hko-current");
    current[@"temperature"][@"recordTime"] = @"2026-10-26T17:00:00+08:00";
    current[@"humidity"][@"recordTime"] = @"2026-10-26T23:00:00+08:00";
    current[@"iconUpdateTime"] = @"2026-10-25T18:00:00+08:00";
    Check(!Parse(current, nil).hasAnyData, @"reject old temperature and icons, and future-dated humidity");
    current = Fixture(@"hko-current");
    current[@"temperature"][@"data"] = @[@{@"place": @"Tsuen Wan Ho Koon", @"value": @YES, @"unit": @"C"}, @{@"place": @"King's Park", @"value": @300, @"unit": @"C"}, @{@"place": @"Hong Kong Observatory", @"value": @27, @"unit": @"F"}, @"bad"];
    current[@"humidity"][@"data"] = @[@{@"place": @"Hong Kong Observatory", @"value": @101, @"unit": @"percent"}];
    current[@"icon"] = @[@999];
    current[@"uvindex"] = @{@"data": @[@{@"place": @"King's Park", @"value": [NSNull null]}]};
    Check(!Parse(current, nil).hasAnyData, @"invalid units, booleans, ranges, icon and null UV never produce a snapshot");
    for (NSNumber *icon in @[@81, @82, @90, @91, @92, @93]) {
        current[@"icon"] = @[icon];
        Check(Parse(current, nil).current.conditionCode == nil, @"thermal/dry/humid icons do not imply clear skies");
    }
    current = Fixture(@"hko-current");
    current[@"temperature"] = [NSNull null]; current[@"humidity"] = @"";
    current[@"icon"] = @[]; current[@"uvindex"] = @"";
    Check(!Parse(current, nil).hasAnyData, @"optional empty and null measurements are safe");

    NSMutableDictionary *forecast = Fixture(@"hko-forecast");
    forecast[@"updateTime"] = @"2026-10-23T16:30:00+08:00";
    Check(!Parse(nil, forecast).hasAnyData, @"stale forecast ignored");
    forecast = Fixture(@"hko-forecast");
    NSMutableDictionary *badDay = [forecast[@"weatherForecast"][0] mutableCopy];
    badDay[@"forecastDate"] = @"20260230";
    NSMutableDictionary *past = [forecast[@"weatherForecast"][0] mutableCopy]; past[@"forecastDate"] = @"20261025";
    NSMutableDictionary *far = [forecast[@"weatherForecast"][0] mutableCopy]; far[@"forecastDate"] = @"20261120";
    NSMutableArray *days = [forecast[@"weatherForecast"] mutableCopy];
    [days addObjectsFromArray:@[badDay, past, far, days[0], [NSNull null]]];
    [days exchangeObjectAtIndex:0 withObjectAtIndex:8]; forecast[@"weatherForecast"] = days;
    WSWeatherSnapshot *snapshot = Parse(nil, forecast);
    Check(snapshot.daily.count == 9 && snapshot.daily[0].temperatureMax.intValue == 30, @"reject invalid, past, distant and duplicate days, then sort dates");
    NSMutableDictionary *inverted = [days[0] mutableCopy];
    inverted[@"forecastMaxtemp"] = @{@"value": @10, @"unit": @"C"};
    inverted[@"forecastMintemp"] = @{@"value": @30, @"unit": @"C"};
    inverted[@"forecastMaxrh"] = @{@"value": @20, @"unit": @"percent"};
    inverted[@"forecastMinrh"] = @{@"value": @90, @"unit": @"percent"};
    forecast[@"weatherForecast"] = @[inverted];
    snapshot = Parse(nil, forecast);
    Check(snapshot.daily[0].temperatureMax == nil && snapshot.daily[0].humidityMax == nil && snapshot.daily[0].conditionCode != nil, @"reject inverted extrema while preserving independently valid fields");
    for (NSArray *location in @[@[@31.2, @121.5], @[@(NAN), @114.1], @[@22.3, @(INFINITY)]]) {
        Check(![WSHKOProvider snapshotWithCurrent:Fixture(@"hko-current") forecast:Fixture(@"hko-forecast") latitude:[location[0] doubleValue] longitude:[location[1] doubleValue] referenceDate:Date(@"2026-10-26T21:10:00+08:00")].hasAnyData, @"never apply Hong Kong observations outside coverage");
    }
}

static void TestIcons(void) {
    NSDictionary *mapping = @{@50:@(WSWeatherConditionClear), @51:@(WSWeatherConditionMostlyClear), @52:@(WSWeatherConditionPartlyCloudy), @53:@(WSWeatherConditionRain), @54:@(WSWeatherConditionRain), @60:@(WSWeatherConditionMostlyCloudy), @61:@(WSWeatherConditionCloudy), @62:@(WSWeatherConditionRain), @63:@(WSWeatherConditionRain), @64:@(WSWeatherConditionHeavyRain), @65:@(WSWeatherConditionThunderstorms), @70:@(WSWeatherConditionClear), @75:@(WSWeatherConditionClear), @76:@(WSWeatherConditionMostlyCloudy), @77:@(WSWeatherConditionMostlyClear), @80:@(WSWeatherConditionWindy), @83:@(WSWeatherConditionFoggy), @84:@(WSWeatherConditionFoggy), @85:@(WSWeatherConditionHaze)};
    for (NSNumber *icon in mapping) {
        NSMutableDictionary *report = Fixture(@"hko-current"); report[@"icon"] = @[icon];
        Check([Parse(report, nil).current.conditionCode isEqual:mapping[icon]], [NSString stringWithFormat:@"map official HKO icon %@", icon]);
    }
}

static void TestResponseIntegration(void) {
    NSDictionary *today = @{@"date": @"2026-10-25T16:00:00Z", @"temperatureHigh": @11};
    NSDictionary *tomorrow = @{@"date": @"2026-10-26T16:00:00Z", @"temperatureHigh": @12, @"temperatureLow": @9, @"humidityMax": @0.5, @"precipitationChance": @0.23, @"windSpeed": @18, @"sunrise": @"retain", @"conditionCode": @"Cloudy"};
    NSDictionary *input = @{@"currentWeather": @{@"temperature": @10, @"humidity": @0.4, @"uvIndex": @0, @"windSpeed": @15, @"conditionCode": @"Cloudy"}, @"forecastDaily": @{@"days": @[today, tomorrow]}, @"forecastHourly": @{@"hours": @[@{@"date": @"2026-10-26T14:00:00Z", @"temperature": @21}]}, @"airQuality": @{@"value": @42}, @"weatherAlerts": @[@{@"id": @"apple-alert"}]};
    NSData *data = [NSJSONSerialization dataWithJSONObject:input options:0 error:nil];
    NSInteger changed = 0; NSError *error = nil;
    NSData *output = [WSWeatherResponsePatcher patchData:data contentType:@"application/json" snapshot:Parse(Fixture(@"hko-current"), Fixture(@"hko-forecast")) changedFields:&changed error:&error];
    Check(output && !error && changed > 0, @"HKO snapshot patches real response implementation");
    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:output options:0 error:nil];
    Check([result[@"currentWeather"][@"temperature"] intValue] == 24 && fabs([result[@"currentWeather"][@"humidity"] doubleValue] - 0.75) < 1e-6, @"HKO units convert correctly to Apple JSON");
    Check([result[@"currentWeather"][@"windSpeed"] intValue] == 15, @"unavailable current wind remains Apple");
    NSArray *days = result[@"forecastDaily"][@"days"];
    Check([days[0] isEqual:today] && [days[1][@"temperatureHigh"] intValue] == 30 && [days[1][@"temperatureLow"] intValue] == 25, @"nine-day forecast starts tomorrow without overwriting today");
    Check(fabs([days[1][@"humidityMax"] doubleValue] - 0.85) < 1e-6 && fabs([days[1][@"precipitationChance"] doubleValue] - 0.23) < 1e-6, @"forecast humidity converts and categorical PSR leaves Apple probability intact");
    Check([days[1][@"sunrise"] isEqual:@"retain"] && [days[1][@"windSpeed"] intValue] == 18, @"retain unsupported daily measurements");
    for (NSString *key in @[@"forecastHourly", @"airQuality", @"weatherAlerts"]) Check([result[key] isEqual:input[key]], [@"retain Apple dataset " stringByAppendingString:key]);
    NSDictionary *unknownDay = @{@"temperatureHigh": @17};
    NSData *undatedData = [NSJSONSerialization dataWithJSONObject:@{@"forecastDaily": @{@"days": @[unknownDay]}} options:0 error:nil];
    NSData *undatedOutput = [WSWeatherResponsePatcher patchData:undatedData contentType:@"application/json" snapshot:Parse(nil, Fixture(@"hko-forecast")) changedFields:&changed error:&error];
    NSDictionary *undatedResult = [NSJSONSerialization JSONObjectWithData:undatedOutput options:0 error:nil];
    Check([undatedResult[@"forecastDaily"][@"days"][0] isEqual:unknownDay], @"partial forecast never aligns by array index when Apple dates are missing");
}

static WSWeatherSnapshot *Fetch(double latitude, NSError **errorOut) {
    __block WSWeatherSnapshot *result; __block NSError *failure;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [[WSHKOProvider new] fetchSnapshotForLatitude:latitude longitude:114.10778 locale:@"zh-Hant" completion:^(WSWeatherSnapshot *snapshot, NSError *error) {
        result = snapshot; failure = error; dispatch_semaphore_signal(done);
    }];
    Check(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5*NSEC_PER_SEC)) == 0, @"fetch always completes");
    if (errorOut) *errorOut = failure;
    return result;
}

static void TestFetchingAndRegistry(void) {
    Check([[WSProviderRegistry providerForIdentifier:@"hko"] isKindOfClass:[WSHKOProvider class]] && [WSProviderRegistry isProviderAvailable:@"hko"], @"HKO registered and usable without credentials");
    Check([[WSProviderRegistry automaticProviderForRegion:@"HK"] isEqual:@"hko"] && [[WSProviderRegistry automaticProviderForRegion:@"US"] isEqual:@"open-meteo"], @"Hong Kong defaults to HKO without changing other regions");
    NSString *now = [[NSISO8601DateFormatter new] stringFromDate:[NSDate date]];
    NSMutableDictionary *current = Fixture(@"hko-current");
    current[@"updateTime"] = now; current[@"iconUpdateTime"] = now;
    current[@"temperature"][@"recordTime"] = now; current[@"humidity"][@"recordTime"] = now;
    NSError *offline = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
    httpRequests = 0; httpResults = @{@"rhrread": current, @"fnd": offline};
    NSError *error = nil; WSWeatherSnapshot *snapshot = Fetch(22.38361, &error);
    Check(snapshot.current.temperature.intValue == 24 && snapshot.daily.count == 0 && error == nil && httpRequests == 2, @"forecast outage still yields usable observations");

    NSMutableDictionary *forecast = Fixture(@"hko-forecast"); forecast[@"updateTime"] = now;
    NSCalendar *calendar = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]; calendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Hong_Kong"];
    NSDateFormatter *formatter = [NSDateFormatter new]; formatter.calendar = calendar; formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]; formatter.timeZone = calendar.timeZone; formatter.dateFormat = @"yyyyMMdd";
    NSMutableDictionary *day = [forecast[@"weatherForecast"][0] mutableCopy]; day[@"forecastDate"] = [formatter stringFromDate:[calendar dateByAddingUnit:NSCalendarUnitDay value:1 toDate:[NSDate date] options:0]];
    forecast[@"weatherForecast"] = @[day]; httpResults = @{@"rhrread": offline, @"fnd": forecast};
    snapshot = Fetch(22.38361, &error);
    Check(!snapshot.current && snapshot.daily.count == 1 && !error, @"observation outage still yields forecast");
    httpResults = @{@"rhrread": offline, @"fnd": offline};
    Check(Fetch(22.38361, &error) == nil && error.code == NSURLErrorTimedOut, @"total failure propagates error for Apple passthrough");
    httpResults = @{@"rhrread": @[], @"fnd": @"invalid"};
    Check(Fetch(22.38361, &error) == nil && error.code == -41, @"malformed success responses also fall back");
    NSUInteger before = httpRequests;
    Check(Fetch(31.2, &error) == nil && error.code == -40 && httpRequests == before, @"outside coverage fails without any network requests");
}

int main(void) {
    // Keep the main queue live while exercising production asynchronous callbacks.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        @autoreleasepool {
            TestObservations(); TestInvalidAndStaleData(); TestIcons();
            TestResponseIntegration(); TestFetchingAndRegistry();
            NSLog(@"HKO regression checks passed (%lu assertions)", (unsigned long)checks);
            exit(0);
        }
    });
    dispatch_main();
}
