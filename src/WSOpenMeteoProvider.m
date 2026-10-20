#import "WSOpenMeteoProvider.h"
#import "WSHTTPClient.h"
#import "WSLogger.h"
#import "WSCondition.h"
#import <math.h>
#import <float.h>

NSErrorDomain const WSProviderErrorDomain = @"com.weathersource.provider";

static NSNumber *WSNumberValue(NSDictionary *dictionary, NSString *key) {
    id value = dictionary[key];
    if ([value isKindOfClass:[NSNumber class]]) return value;
    if ([value isKindOfClass:[NSString class]]) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        double number = 0;
        if ([scanner scanDouble:&number] && scanner.isAtEnd) return @(number);
    }
    return nil;
}

static NSNumber *WSArrayNumber(NSArray *array, NSUInteger index) {
    if (![array isKindOfClass:[NSArray class]] || index >= array.count) return nil;
    id value = array[index];
    if ([value isKindOfClass:[NSNumber class]]) return value;
    if ([value isKindOfClass:[NSString class]]) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        double number = 0;
        if ([scanner scanDouble:&number] && scanner.isAtEnd) return @(number);
    }
    return nil;
}

static NSInteger WSNearestHourlyIndex(NSArray *times, double target) {
    if (![times isKindOfClass:[NSArray class]] || times.count == 0) return NSNotFound;
    NSInteger best = NSNotFound;
    double bestDelta = DBL_MAX;
    for (NSUInteger i = 0; i < times.count; i++) {
        NSNumber *time = WSArrayNumber(times, i);
        if (!time) continue;
        double delta = fabs(time.doubleValue - target);
        if (delta < bestDelta) {
            bestDelta = delta;
            best = (NSInteger)i;
        }
    }
    if (best == NSNotFound || bestDelta > 3600.0 * 2.0) return NSNotFound;
    return best;
}

static NSNumber *WSNormalizedWindDirection(NSNumber *value) {
    if (!value) return nil;
    double degrees = fmod(value.doubleValue, 360.0);
    if (degrees < 0) degrees += 360.0;
    return @((int)llround(degrees) % 360);
}

static NSNumber *WSClampedInteger(NSNumber *value, int minimum, int maximum) {
    if (!value) return nil;
    int number = (int)llround(value.doubleValue);
    if (number < minimum) number = minimum;
    if (number > maximum) number = maximum;
    return @(number);
}

static NSNumber *WSSnowfallMillimeters(NSNumber *centimeters) {
    if (!centimeters) return nil;
    return @(centimeters.doubleValue * 10.0);
}

@implementation WSOpenMeteoProvider

- (NSString *)identifier { return @"openmeteo"; }
- (NSString *)displayName { return @"Open-Meteo"; }
- (BOOL)isAvailable { return YES; }

- (NSURL *)URLForLatitude:(double)latitude longitude:(double)longitude {
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://api.open-meteo.com/v1/forecast"];
    NSArray *query = @[
        [NSURLQueryItem queryItemWithName:@"latitude" value:[NSString stringWithFormat:@"%.5f", latitude]],
        [NSURLQueryItem queryItemWithName:@"longitude" value:[NSString stringWithFormat:@"%.5f", longitude]],
        [NSURLQueryItem queryItemWithName:@"current" value:@"temperature_2m,relative_humidity_2m,apparent_temperature,dew_point_2m,is_day,precipitation,rain,showers,snowfall,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m"],
        [NSURLQueryItem queryItemWithName:@"hourly" value:@"temperature_2m,relative_humidity_2m,apparent_temperature,dew_point_2m,precipitation_probability,precipitation,snowfall,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,visibility,is_day"],
        [NSURLQueryItem queryItemWithName:@"daily" value:@"weather_code,temperature_2m_max,temperature_2m_min,apparent_temperature_max,apparent_temperature_min,uv_index_max,precipitation_sum,snowfall_sum,precipitation_probability_max,wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant,relative_humidity_2m_max,relative_humidity_2m_min"],
        [NSURLQueryItem queryItemWithName:@"timezone" value:@"auto"],
        [NSURLQueryItem queryItemWithName:@"timeformat" value:@"unixtime"],
        [NSURLQueryItem queryItemWithName:@"temperature_unit" value:@"celsius"],
        [NSURLQueryItem queryItemWithName:@"wind_speed_unit" value:@"kmh"],
        [NSURLQueryItem queryItemWithName:@"precipitation_unit" value:@"mm"],
        [NSURLQueryItem queryItemWithName:@"forecast_days" value:@"10"],
    ];
    components.queryItems = query;
    return components.URL;
}

- (void)fetchSnapshotForLatitude:(double)latitude
                       longitude:(double)longitude
                          locale:(NSString *)locale
                      completion:(WSProviderCompletion)completion {
    (void)locale;
    NSURL *url = [self URLForLatitude:latitude longitude:longitude];
    if (!url) {
        completion(nil, WSProviderError(-1, @"Unable to build Open-Meteo URL"));
        return;
    }
    [WSLogger debug:@"Open-Meteo request lat=%.4f lon=%.4f", latitude, longitude];
    [[WSHTTPClient shared] GETJSON:url headers:nil completion:^(id json, NSData *data, NSHTTPURLResponse *response, NSError *error) {
        (void)data;
        if (error) {
            completion(nil, error);
            return;
        }
        if (![json isKindOfClass:[NSDictionary class]]) {
            completion(nil, WSProviderError(-2, @"Open-Meteo returned a non-JSON object"));
            return;
        }
        NSDictionary *root = (NSDictionary *)json;
        if (root[@"error"]) {
            NSString *reason = root[@"reason"] ?: @"Open-Meteo returned an error";
            completion(nil, WSProviderError(-3, reason));
            return;
        }
        WSWeatherSnapshot *snapshot = [self snapshotFromJSON:root];
        if (!snapshot.hasAnyData) {
            completion(nil, WSProviderError(-4, @"Open-Meteo returned no usable weather data"));
            return;
        }
        completion(snapshot, nil);
    }];
}

- (WSWeatherSnapshot *)snapshotFromJSON:(NSDictionary *)root {
    WSWeatherSnapshot *snapshot = [[WSWeatherSnapshot alloc] init];
    snapshot.providerID = self.identifier;
    snapshot.providerName = self.displayName;
    snapshot.fetchedAt = [[NSDate date] timeIntervalSince1970];

    NSDictionary *hourly = [root[@"hourly"] isKindOfClass:[NSDictionary class]] ? root[@"hourly"] : nil;
    NSDictionary *daily = [root[@"daily"] isKindOfClass:[NSDictionary class]] ? root[@"daily"] : nil;
    NSDictionary *current = [root[@"current"] isKindOfClass:[NSDictionary class]] ? root[@"current"] : nil;

    NSArray *hourlyTimes = [hourly[@"time"] isKindOfClass:[NSArray class]] ? hourly[@"time"] : @[];

    NSMutableArray<WSHourlyWeather *> *hours = [NSMutableArray array];
    for (NSUInteger i = 0; i < hourlyTimes.count; i++) {
        WSHourlyWeather *hour = [[WSHourlyWeather alloc] init];
        hour.timestamp = WSArrayNumber(hourlyTimes, i);
        hour.temperature = WSArrayNumber(hourly[@"temperature_2m"], i);
        hour.apparentTemperature = WSArrayNumber(hourly[@"apparent_temperature"], i);
        hour.dewPoint = WSArrayNumber(hourly[@"dew_point_2m"], i);
        hour.humidity = WSClampedInteger(WSArrayNumber(hourly[@"relative_humidity_2m"], i), 0, 100);
        hour.pressure = WSArrayNumber(hourly[@"pressure_msl"], i);
        hour.windSpeed = WSArrayNumber(hourly[@"wind_speed_10m"], i);
        hour.windGust = WSArrayNumber(hourly[@"wind_gusts_10m"], i);
        hour.windDirection = WSNormalizedWindDirection(WSArrayNumber(hourly[@"wind_direction_10m"], i));
        hour.uvIndex = WSClampedInteger(WSArrayNumber(hourly[@"uv_index"], i), 0, 20);
        hour.visibility = WSArrayNumber(hourly[@"visibility"], i);
        hour.cloudCover = WSClampedInteger(WSArrayNumber(hourly[@"cloud_cover"], i), 0, 100);
        hour.precipitationChance = WSClampedInteger(WSArrayNumber(hourly[@"precipitation_probability"], i), 0, 100);
        hour.precipitationAmount = WSArrayNumber(hourly[@"precipitation"], i);
        hour.snowfallAmount = WSSnowfallMillimeters(WSArrayNumber(hourly[@"snowfall"], i));
        hour.daylight = WSArrayNumber(hourly[@"is_day"], i);
        NSNumber *weatherCode = WSArrayNumber(hourly[@"weather_code"], i);
        if (weatherCode) {
            int condition = [WSCondition conditionForWMOWeatherCode:weatherCode.intValue];
            if (condition >= 0) hour.conditionCode = @(condition);
        }
        if (hour.timestamp && (hour.temperature || hour.conditionCode)) [hours addObject:hour];
    }
    snapshot.hourly = hours;

    NSArray *dailyTimes = [daily[@"time"] isKindOfClass:[NSArray class]] ? daily[@"time"] : @[];
    NSMutableArray<WSDailyWeather *> *days = [NSMutableArray array];
    for (NSUInteger i = 0; i < dailyTimes.count; i++) {
        WSDailyWeather *day = [[WSDailyWeather alloc] init];
        day.timestamp = WSArrayNumber(dailyTimes, i);
        day.temperatureMax = WSArrayNumber(daily[@"temperature_2m_max"], i);
        day.temperatureMin = WSArrayNumber(daily[@"temperature_2m_min"], i);
        day.humidityMax = WSClampedInteger(WSArrayNumber(daily[@"relative_humidity_2m_max"], i), 0, 100);
        day.humidityMin = WSClampedInteger(WSArrayNumber(daily[@"relative_humidity_2m_min"], i), 0, 100);
        day.maxUvIndex = WSClampedInteger(WSArrayNumber(daily[@"uv_index_max"], i), 0, 20);
        day.precipitationChance = WSClampedInteger(WSArrayNumber(daily[@"precipitation_probability_max"], i), 0, 100);
        day.precipitationAmount = WSArrayNumber(daily[@"precipitation_sum"], i);
        day.snowfallAmount = WSSnowfallMillimeters(WSArrayNumber(daily[@"snowfall_sum"], i));
        day.windSpeedMax = WSArrayNumber(daily[@"wind_speed_10m_max"], i);
        day.windGustSpeedMax = WSArrayNumber(daily[@"wind_gusts_10m_max"], i);
        NSNumber *weatherCode = WSArrayNumber(daily[@"weather_code"], i);
        if (weatherCode) {
            int condition = [WSCondition conditionForWMOWeatherCode:weatherCode.intValue];
            if (condition >= 0) day.conditionCode = @(condition);
        }
        if (day.timestamp && (day.temperatureMax || day.temperatureMin || day.conditionCode)) [days addObject:day];
    }
    snapshot.daily = days;

    if (current) {
        WSCurrentWeather *now = [[WSCurrentWeather alloc] init];
        now.timestamp = WSNumberValue(current, @"time");
        now.temperature = WSNumberValue(current, @"temperature_2m");
        now.apparentTemperature = WSNumberValue(current, @"apparent_temperature");
        now.dewPoint = WSNumberValue(current, @"dew_point_2m");
        now.humidity = WSClampedInteger(WSNumberValue(current, @"relative_humidity_2m"), 0, 100);
        now.pressure = WSNumberValue(current, @"pressure_msl");
        now.windSpeed = WSNumberValue(current, @"wind_speed_10m");
        now.windGust = WSNumberValue(current, @"wind_gusts_10m");
        now.windDirection = WSNormalizedWindDirection(WSNumberValue(current, @"wind_direction_10m"));
        now.cloudCover = WSClampedInteger(WSNumberValue(current, @"cloud_cover"), 0, 100);
        now.precipitationAmount1h = WSNumberValue(current, @"precipitation");
        now.snowfallAmount1h = WSSnowfallMillimeters(WSNumberValue(current, @"snowfall"));
        now.daylight = WSNumberValue(current, @"is_day");
        NSNumber *weatherCode = WSNumberValue(current, @"weather_code");
        if (weatherCode) {
            int condition = [WSCondition conditionForWMOWeatherCode:weatherCode.intValue];
            if (condition >= 0) now.conditionCode = @(condition);
        }

        NSInteger index = WSNearestHourlyIndex(hourlyTimes, now.timestamp.doubleValue);
        if (index != NSNotFound) {
            if (!now.uvIndex) now.uvIndex = WSClampedInteger(WSArrayNumber(hourly[@"uv_index"], (NSUInteger)index), 0, 20);
            if (!now.visibility) now.visibility = WSArrayNumber(hourly[@"visibility"], (NSUInteger)index);
            if (!now.precipitationChance) now.precipitationChance = WSClampedInteger(WSArrayNumber(hourly[@"precipitation_probability"], (NSUInteger)index), 0, 100);
            if (!now.daylight) now.daylight = WSArrayNumber(hourly[@"is_day"], (NSUInteger)index);
            if (!now.conditionCode) {
                NSNumber *hourCode = WSArrayNumber(hourly[@"weather_code"], (NSUInteger)index);
                if (hourCode) {
                    int condition = [WSCondition conditionForWMOWeatherCode:hourCode.intValue];
                    if (condition >= 0) now.conditionCode = @(condition);
                }
            }
        }
        snapshot.current = now;
    }

    return snapshot;
}

@end

