#import "WSWeatherResponsePatcher.h"
#import "WSCondition.h"
#import "WSFlatBuffer.h"
#import "WSSettings.h"
#import "WSLogger.h"

#import <float.h>
#import <math.h>

static NSMutableDictionary *WSMutableDictionary(id value) {
    if ([value isKindOfClass:[NSMutableDictionary class]]) return value;
    if ([value isKindOfClass:[NSDictionary class]]) return [value mutableCopy];
    return nil;
}

static NSMutableArray *WSMutableArray(id value) {
    if ([value isKindOfClass:[NSMutableArray class]]) return value;
    if ([value isKindOfClass:[NSArray class]]) return [value mutableCopy];
    return nil;
}

static double WSTimestampFromJSONValue(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value doubleValue];
    if (![value isKindOfClass:[NSString class]]) return NAN;
    NSString *string = value;
    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    NSDate *date = [formatter dateFromString:string];
    if (!date) {
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime | NSISO8601DateFormatWithFractionalSeconds;
        date = [formatter dateFromString:string];
    }
    if (date) return date.timeIntervalSince1970;
    NSScanner *scanner = [NSScanner scannerWithString:string];
    double number = 0;
    if ([scanner scanDouble:&number] && scanner.isAtEnd) return number;
    return NAN;
}

static BOOL WSSetJSONNumber(NSMutableDictionary *dictionary, NSString *key, NSNumber *value) {
    if (!value || !dictionary || !key) return NO;
    id existing = dictionary[key];
    if (!existing) return NO;
    if ([existing isKindOfClass:[NSNumber class]] || existing == [NSNull null]) {
        dictionary[key] = value;
        return YES;
    }
    if ([existing isKindOfClass:[NSString class]]) {
        NSScanner *scanner = [NSScanner scannerWithString:existing];
        double parsed = 0;
        if ([scanner scanDouble:&parsed] && scanner.isAtEnd) {
            dictionary[key] = [value stringValue];
            return YES;
        }
    }
    return NO;
}

static BOOL WSSetJSONBool(NSMutableDictionary *dictionary, NSString *key, BOOL value) {
    if (!dictionary || !key) return NO;
    id existing = dictionary[key];
    if (!existing) return NO;
    if ([existing isKindOfClass:[NSNumber class]] || existing == [NSNull null]) {
        dictionary[key] = @(value);
        return YES;
    }
    if ([existing isKindOfClass:[NSString class]]) {
        dictionary[key] = value ? @"true" : @"false";
        return YES;
    }
    return NO;
}

static BOOL WSSetJSONCondition(NSMutableDictionary *dictionary, int conditionCode) {
    if (!dictionary || conditionCode < 0) return NO;
    id existing = dictionary[@"conditionCode"];
    if (!existing) return NO;
    dictionary[@"conditionCode"] = [WSCondition JSONValueForCondition:conditionCode existingValue:existing];
    return YES;
}

static BOOL WSSetJSONTime(NSMutableDictionary *dictionary, NSString *key, NSTimeInterval timestamp) {
    if (!dictionary || !key || timestamp <= 0) return NO;
    id existing = dictionary[key];
    if (!existing) return NO;
    if ([existing isKindOfClass:[NSNumber class]]) {
        dictionary[key] = @((long long)timestamp);
        return YES;
    }
    if ([existing isKindOfClass:[NSString class]]) {
        NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
        formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime;
        dictionary[key] = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]];
        return YES;
    }
    return NO;
}

static WSHourlyWeather *WSMatchHour(NSArray<WSHourlyWeather *> *hours, double target, NSUInteger fallbackIndex) {
    if (!hours.count) return nil;
    if (!isnan(target)) {
        WSHourlyWeather *best = nil;
        double bestDelta = DBL_MAX;
        for (WSHourlyWeather *hour in hours) {
            if (!hour.timestamp) continue;
            double delta = fabs(hour.timestamp.doubleValue - target);
            if (delta < bestDelta) {
                bestDelta = delta;
                best = hour;
            }
        }
        if (best && bestDelta <= 1800.0) return best;
    }
    if (fallbackIndex < hours.count) return hours[fallbackIndex];
    return nil;
}

static WSDailyWeather *WSMatchDay(NSArray<WSDailyWeather *> *days, double target, NSUInteger fallbackIndex) {
    if (!days.count) return nil;
    if (!isnan(target)) {
        WSDailyWeather *best = nil;
        double bestDelta = DBL_MAX;
        for (WSDailyWeather *day in days) {
            if (!day.timestamp) continue;
            double delta = fabs(day.timestamp.doubleValue - target);
            if (delta < bestDelta) {
                bestDelta = delta;
                best = day;
            }
        }
        if (best && bestDelta <= 43200.0) return best;
    }
    if (fallbackIndex < days.count) return days[fallbackIndex];
    return nil;
}

static NSInteger WSPatchMetadataDictionary(NSMutableDictionary *container, NSTimeInterval now, NSTimeInterval ttl) {
    NSMutableDictionary *metadata = WSMutableDictionary(container[@"metadata"]);
    if (!metadata) return 0;
    NSInteger changed = 0;
    if (WSSetJSONTime(metadata, @"reportedTime", now)) changed++;
    if (WSSetJSONTime(metadata, @"readTime", now)) changed++;
    if (WSSetJSONTime(metadata, @"expireTime", now + ttl)) changed++;
    container[@"metadata"] = metadata;
    return changed;
}

static NSInteger WSPatchCurrentDictionary(NSMutableDictionary *current, WSCurrentWeather *source, NSTimeInterval now, NSTimeInterval ttl) {
    if (!current || !source) return 0;
    NSInteger changed = 0;
    if (WSSetJSONNumber(current, @"temperature", source.temperature)) changed++;
    if (WSSetJSONNumber(current, @"temperatureApparent", source.apparentTemperature)) changed++;
    if (WSSetJSONNumber(current, @"temperatureDewPoint", source.dewPoint)) changed++;
    if (WSSetJSONNumber(current, @"humidity", source.humidity)) changed++;
    if (WSSetJSONNumber(current, @"pressure", source.pressure)) changed++;
    if (WSSetJSONNumber(current, @"windSpeed", source.windSpeed)) changed++;
    if (WSSetJSONNumber(current, @"windGust", source.windGust)) changed++;
    if (WSSetJSONNumber(current, @"windDirection", source.windDirection)) changed++;
    if (WSSetJSONNumber(current, @"uvIndex", source.uvIndex)) changed++;
    if (WSSetJSONNumber(current, @"visibility", source.visibility)) changed++;
    if (WSSetJSONNumber(current, @"cloudCover", source.cloudCover)) changed++;
    if (WSSetJSONNumber(current, @"precipitationAmount1h", source.precipitationAmount1h)) changed++;
    if (WSSetJSONNumber(current, @"precipitationChance", source.precipitationChance)) changed++;
    if (WSSetJSONNumber(current, @"snowfallAmount1h", source.snowfallAmount1h)) changed++;
    if (source.conditionCode && WSSetJSONCondition(current, source.conditionCode.intValue)) changed++;
    if (source.daylight) {
        if (WSSetJSONBool(current, @"daylight", source.daylight.boolValue)) changed++;
        if (WSSetJSONBool(current, @"isDaylight", source.daylight.boolValue)) changed++;
    }
    if (source.timestamp) {
        if (WSSetJSONTime(current, @"asOf", source.timestamp.doubleValue)) changed++;
    }
    changed += WSPatchMetadataDictionary(current, now, ttl);
    return changed;
}

static NSInteger WSPatchHourlyDictionary(NSMutableDictionary *hourly, NSArray<WSHourlyWeather *> *source, NSTimeInterval now, NSTimeInterval ttl) {
    if (!hourly || !source.count) return 0;
    NSMutableArray *items = WSMutableArray(hourly[@"hours"]);
    if (!items) return 0;
    NSInteger changed = 0;
    for (NSUInteger i = 0; i < items.count; i++) {
        NSMutableDictionary *item = WSMutableDictionary(items[i]);
        if (!item) continue;
        double target = WSTimestampFromJSONValue(item[@"forecastStart"]);
        WSHourlyWeather *hour = WSMatchHour(source, target, i);
        if (hour) {
            if (WSSetJSONNumber(item, @"temperature", hour.temperature)) changed++;
            if (WSSetJSONNumber(item, @"temperatureApparent", hour.apparentTemperature)) changed++;
            if (WSSetJSONNumber(item, @"temperatureDewPoint", hour.dewPoint)) changed++;
            if (WSSetJSONNumber(item, @"humidity", hour.humidity)) changed++;
            if (WSSetJSONNumber(item, @"pressure", hour.pressure)) changed++;
            if (WSSetJSONNumber(item, @"windSpeed", hour.windSpeed)) changed++;
            if (WSSetJSONNumber(item, @"windGust", hour.windGust)) changed++;
            if (WSSetJSONNumber(item, @"windDirection", hour.windDirection)) changed++;
            if (WSSetJSONNumber(item, @"uvIndex", hour.uvIndex)) changed++;
            if (WSSetJSONNumber(item, @"visibility", hour.visibility)) changed++;
            if (WSSetJSONNumber(item, @"cloudCover", hour.cloudCover)) changed++;
            if (WSSetJSONNumber(item, @"precipitationChance", hour.precipitationChance)) changed++;
            if (WSSetJSONNumber(item, @"precipitationAmount", hour.precipitationAmount)) changed++;
            if (WSSetJSONNumber(item, @"snowfallAmount", hour.snowfallAmount)) changed++;
            if (hour.conditionCode && WSSetJSONCondition(item, hour.conditionCode.intValue)) changed++;
            if (hour.daylight) {
                if (WSSetJSONBool(item, @"daylight", hour.daylight.boolValue)) changed++;
                if (WSSetJSONBool(item, @"isDaylight", hour.daylight.boolValue)) changed++;
            }
        }
        items[i] = item;
    }
    hourly[@"hours"] = items;
    changed += WSPatchMetadataDictionary(hourly, now, ttl);
    return changed;
}

static NSInteger WSPatchDailyDictionary(NSMutableDictionary *daily, NSArray<WSDailyWeather *> *source, NSTimeInterval now, NSTimeInterval ttl) {
    if (!daily || !source.count) return 0;
    NSMutableArray *items = WSMutableArray(daily[@"days"]);
    if (!items) return 0;
    NSInteger changed = 0;
    for (NSUInteger i = 0; i < items.count; i++) {
        NSMutableDictionary *item = WSMutableDictionary(items[i]);
        if (!item) continue;
        double target = WSTimestampFromJSONValue(item[@"forecastStart"]);
        WSDailyWeather *day = WSMatchDay(source, target, i);
        if (day) {
            if (WSSetJSONNumber(item, @"temperatureMax", day.temperatureMax)) changed++;
            if (WSSetJSONNumber(item, @"temperatureMin", day.temperatureMin)) changed++;
            if (WSSetJSONNumber(item, @"humidityMax", day.humidityMax)) changed++;
            if (WSSetJSONNumber(item, @"humidityMin", day.humidityMin)) changed++;
            if (WSSetJSONNumber(item, @"maxUvIndex", day.maxUvIndex)) changed++;
            if (WSSetJSONNumber(item, @"uvIndexMax", day.maxUvIndex)) changed++;
            if (WSSetJSONNumber(item, @"precipitationChance", day.precipitationChance)) changed++;
            if (WSSetJSONNumber(item, @"precipitationAmount", day.precipitationAmount)) changed++;
            if (WSSetJSONNumber(item, @"snowfallAmount", day.snowfallAmount)) changed++;
            if (WSSetJSONNumber(item, @"windSpeedMax", day.windSpeedMax)) changed++;
            if (WSSetJSONNumber(item, @"windGustSpeedMax", day.windGustSpeedMax)) changed++;
            if (WSSetJSONNumber(item, @"windGust", day.windGustSpeedMax)) changed++;
            if (WSSetJSONNumber(item, @"windSpeedAvg", day.windSpeedAvg)) changed++;
            if (day.conditionCode && WSSetJSONCondition(item, day.conditionCode.intValue)) changed++;
        }
        items[i] = item;
    }
    daily[@"days"] = items;
    changed += WSPatchMetadataDictionary(daily, now, ttl);
    return changed;
}

static NSData *WSPatchJSON(NSData *data, WSWeatherSnapshot *snapshot, NSInteger *changedFields, NSError **error) {
    NSError *jsonError = nil;
    id rootObject = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&jsonError];
    if (!rootObject || ![rootObject isKindOfClass:[NSMutableDictionary class]]) {
        if (error) *error = jsonError ?: [NSError errorWithDomain:@"com.weathersource.patch" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"WeatherKit JSON root object is invalid"}];
        return nil;
    }
    NSMutableDictionary *root = rootObject;
    NSInteger changed = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval ttl = [WSSettings shared].cacheTTL;

    if (snapshot.current) {
        NSMutableDictionary *current = WSMutableDictionary(root[@"currentWeather"]);
        if (current) {
            changed += WSPatchCurrentDictionary(current, snapshot.current, now, ttl);
            root[@"currentWeather"] = current;
        }
    }
    if (snapshot.hourly.count) {
        NSMutableDictionary *hourly = WSMutableDictionary(root[@"forecastHourly"]);
        if (hourly) {
            changed += WSPatchHourlyDictionary(hourly, snapshot.hourly, now, ttl);
            root[@"forecastHourly"] = hourly;
        }
    }
    if (snapshot.daily.count) {
        NSMutableDictionary *daily = WSMutableDictionary(root[@"forecastDaily"]);
        if (daily) {
            changed += WSPatchDailyDictionary(daily, snapshot.daily, now, ttl);
            root[@"forecastDaily"] = daily;
        }
    }

    if (changedFields) *changedFields = changed;
    if (changed == 0) return data;
    NSData *serialized = [NSJSONSerialization dataWithJSONObject:root options:0 error:&jsonError];
    if (!serialized) {
        if (error) *error = jsonError;
        return nil;
    }
    return serialized;
}

// WeatherKit v2 FlatBuffer field indices. They are append-only across iOS
// releases; see docs/TECHNICAL_FEASIBILITY.md for the schema source.
enum {
    FBWeatherAirQuality = 0,
    FBWeatherCurrent = 1,
    FBWeatherDaily = 2,
    FBWeatherHourly = 3,
};

static BOOL WSSetFBFloat(WSFlatBuffer table, int index, NSNumber *value, NSInteger *changed) {
    if (!value) return NO;
    if (!table.fieldExists(index)) return NO;
    if (table.setF32(index, value.floatValue)) {
        (*changed)++;
        return YES;
    }
    return NO;
}

static BOOL WSSetFBInt8(WSFlatBuffer table, int index, NSNumber *value, NSInteger *changed) {
    if (!value) return NO;
    if (!table.fieldExists(index)) return NO;
    int number = (int)llround(value.doubleValue);
    if (table.setI8(index, (int8_t)number)) {
        (*changed)++;
        return YES;
    }
    return NO;
}

static BOOL WSSetFBInt16(WSFlatBuffer table, int index, NSNumber *value, NSInteger *changed) {
    if (!value) return NO;
    if (!table.fieldExists(index)) return NO;
    int number = (int)llround(value.doubleValue);
    if (table.setI16(index, (int16_t)number)) {
        (*changed)++;
        return YES;
    }
    return NO;
}

static void WSPatchFBMetadata(WSFlatBuffer table, NSTimeInterval now, NSTimeInterval ttl, NSInteger *changed) {
    WSFlatBuffer metadata = table.table(0);
    if (!metadata.valid()) return;
    if (metadata.fieldExists(1) && metadata.setI32(1, (int32_t)(now + ttl))) (*changed)++;
    if (metadata.fieldExists(7) && metadata.setI32(7, (int32_t)now)) (*changed)++;
    if (metadata.fieldExists(8) && metadata.setI32(8, (int32_t)now)) (*changed)++;
}

static NSInteger WSPatchFBCurrent(WSFlatBuffer current, WSCurrentWeather *source, NSTimeInterval now, NSTimeInterval ttl) {
    if (!current.valid() || !source) return 0;
    NSInteger changed = 0;
    WSSetFBFloat(current, 31, source.temperature, &changed);            // temperature
    WSSetFBFloat(current, 32, source.apparentTemperature, &changed);     // temperatureApparent
    WSSetFBFloat(current, 34, source.dewPoint, &changed);                // temperatureDewPoint
    WSSetFBInt8(current, 8, source.humidity, &changed);                  // humidity
    WSSetFBFloat(current, 23, source.pressure, &changed);                // pressure
    WSSetFBFloat(current, 39, source.windSpeed, &changed);               // windSpeed
    WSSetFBFloat(current, 38, source.windGust, &changed);                // windGust
    WSSetFBInt16(current, 37, source.windDirection, &changed);           // windDirection
    WSSetFBInt8(current, 35, source.uvIndex, &changed);                  // uvIndex
    WSSetFBFloat(current, 36, source.visibility, &changed);              // visibility
    WSSetFBInt8(current, 2, source.cloudCover, &changed);                // cloudCover
    WSSetFBFloat(current, 10, source.precipitationAmount1h, &changed);   // precipitationAmount1h
    WSSetFBFloat(current, 25, source.snowfallAmount1h, &changed);        // snowfallAmount1h
    WSSetFBInt8(current, 6, source.conditionCode, &changed);             // conditionCode
    WSSetFBInt8(current, 7, source.daylight, &changed);                  // daylight
    WSPatchFBMetadata(current, now, ttl, &changed);
    return changed;
}

static NSInteger WSPatchFBHourly(WSFlatBuffer hourly, NSArray<WSHourlyWeather *> *source, NSTimeInterval now, NSTimeInterval ttl) {
    uint32_t count = 0;
    if (!hourly.valid() || !hourly.vectorLength(1, count) || !source.count) return 0;
    NSInteger changed = 0;
    for (uint32_t i = 0; i < count; i++) {
        WSFlatBuffer item = hourly.vectorTable(1, i);
        if (!item.valid()) continue;
        int32_t start = 0;
        if (!item.getI32(0, start)) continue;
        WSHourlyWeather *hour = WSMatchHour(source, (double)start, i);
        if (!hour) continue;
        WSSetFBFloat(item, 17, hour.temperature, &changed);
        WSSetFBFloat(item, 18, hour.apparentTemperature, &changed);
        WSSetFBFloat(item, 20, hour.dewPoint, &changed);
        WSSetFBInt8(item, 7, hour.humidity, &changed);
        WSSetFBFloat(item, 13, hour.pressure, &changed);
        WSSetFBFloat(item, 25, hour.windSpeed, &changed);
        WSSetFBFloat(item, 24, hour.windGust, &changed);
        WSSetFBInt16(item, 23, hour.windDirection, &changed);
        WSSetFBInt8(item, 21, hour.uvIndex, &changed);
        WSSetFBFloat(item, 22, hour.visibility, &changed);
        WSSetFBInt8(item, 1, hour.cloudCover, &changed);
        WSSetFBInt8(item, 11, hour.precipitationChance, &changed);
        WSSetFBFloat(item, 9, hour.precipitationAmount, &changed);
        WSSetFBFloat(item, 15, hour.snowfallAmount, &changed);
        WSSetFBInt8(item, 5, hour.conditionCode, &changed);
        WSSetFBInt8(item, 6, hour.daylight, &changed);
    }
    WSPatchFBMetadata(hourly, now, ttl, &changed);
    return changed;
}

static NSInteger WSPatchFBDaily(WSFlatBuffer daily, NSArray<WSDailyWeather *> *source, NSTimeInterval now, NSTimeInterval ttl) {
    uint32_t count = 0;
    if (!daily.valid() || !daily.vectorLength(1, count) || !source.count) return 0;
    NSInteger changed = 0;
    for (uint32_t i = 0; i < count; i++) {
        WSFlatBuffer item = daily.vectorTable(1, i);
        if (!item.valid()) continue;
        int32_t start = 0;
        if (!item.getI32(0, start)) continue;
        WSDailyWeather *day = WSMatchDay(source, (double)start, i);
        if (!day) continue;
        WSSetFBFloat(item, 24, day.temperatureMax, &changed);
        WSSetFBFloat(item, 26, day.temperatureMin, &changed);
        WSSetFBInt8(item, 3, day.humidityMax, &changed);
        WSSetFBInt8(item, 4, day.humidityMin, &changed);
        WSSetFBInt8(item, 5, day.maxUvIndex, &changed);
        WSSetFBInt8(item, 11, day.precipitationChance, &changed);
        WSSetFBFloat(item, 9, day.precipitationAmount, &changed);
        WSSetFBFloat(item, 13, day.snowfallAmount, &changed);
        WSSetFBFloat(item, 30, day.windSpeedMax, &changed);
        WSSetFBFloat(item, 28, day.windGustSpeedMax, &changed);
        WSSetFBFloat(item, 29, day.windSpeedAvg, &changed);
        WSSetFBInt8(item, 2, day.conditionCode, &changed);
    }
    WSPatchFBMetadata(daily, now, ttl, &changed);
    return changed;
}

static BOOL WSDetectRootTables(WSFlatBuffer root, int *currentIndex, int *dailyIndex, int *hourlyIndex) {
    *currentIndex = -1;
    *dailyIndex = -1;
    *hourlyIndex = -1;
    for (int i = 0; i < 12; i++) {
        if (!root.fieldExists(i)) continue;
        WSFlatBuffer table = root.table(i);
        if (!table.valid()) continue;

        if (*currentIndex < 0 &&
            table.fieldExists(31) && table.fieldExists(32) &&\r\n            (table.fieldExists(39) || table.fieldExists(23) || table.fieldExists(8))) {
            *currentIndex = i;
            continue;
        }

        uint32_t length = 0;
        if (!table.vectorLength(1, length) || length == 0) continue;
        WSFlatBuffer first = table.vectorTable(1, 0);
        if (!first.valid()) continue;
        if (*dailyIndex < 0 && first.fieldExists(24) && first.fieldExists(26)) {
            *dailyIndex = i;
        } else if (*hourlyIndex < 0 && first.fieldExists(17) && first.fieldExists(18)) {
            *hourlyIndex = i;
        }
    }
    return (*currentIndex >= 0) || (*dailyIndex >= 0) || (*hourlyIndex >= 0);
}

static NSData *WSPatchFlatBuffer(NSData *data, WSWeatherSnapshot *snapshot, NSInteger *changedFields, NSError **error) {
    NSMutableData *mutableData = [data mutableCopy];
    uint8_t *bytes = (uint8_t *)mutableData.mutableBytes;
    bool sizePrefixed = false;
    WSFlatBuffer root = WSFlatBuffer::root(bytes, mutableData.length, &sizePrefixed);
    if (!root.valid()) {
        if (error) *error = [NSError errorWithDomain:@"com.weathersource.patch" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"WeatherKit FlatBuffer root table is invalid"}];
        return nil;
    }

    int currentIndex = -1, dailyIndex = -1, hourlyIndex = -1;
    if (!WSDetectRootTables(root, &currentIndex, &dailyIndex, &hourlyIndex)) {
        if (error) *error = [NSError errorWithDomain:@"com.weathersource.patch" code:-3 userInfo:@{NSLocalizedDescriptionKey: @"WeatherKit FlatBuffer layout was not recognized"}];
        return nil;
    }

    NSInteger changed = 0;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval ttl = [WSSettings shared].cacheTTL;

    if (snapshot.current && currentIndex >= 0) {
        changed += WSPatchFBCurrent(root.table(currentIndex), snapshot.current, now, ttl);
    }
    if (snapshot.hourly.count && hourlyIndex >= 0) {
        changed += WSPatchFBHourly(root.table(hourlyIndex), snapshot.hourly, now, ttl);
    }
    if (snapshot.daily.count && dailyIndex >= 0) {
        changed += WSPatchFBDaily(root.table(dailyIndex), snapshot.daily, now, ttl);
    }

    if (changedFields) *changedFields = changed;
    if (changed == 0) return data;
    return [mutableData copy];
}

@implementation WSWeatherResponsePatcher

+ (WSResponseFormat)formatForData:(NSData *)data contentType:(NSString *)contentType {
    NSString *type = [contentType lowercaseString];
    if ([type containsString:@"json"]) return WSResponseFormatJSON;
    if ([type containsString:@"flatbuffer"] || [type containsString:@"octet-stream"] || [type containsString:@"protobuf"]) {
        return WSResponseFormatFlatBuffer;
    }
    if (data.length) {
        const uint8_t *bytes = (const uint8_t *)data.bytes;
        if (bytes[0] == '{' || bytes[0] == '[') return WSResponseFormatJSON;
    }
    return WSResponseFormatFlatBuffer;
}

+ (NSData *)patchData:(NSData *)data
          contentType:(NSString *)contentType
             snapshot:(WSWeatherSnapshot *)snapshot
        changedFields:(NSInteger *)changedFields
                error:(NSError **)error {
    if (changedFields) *changedFields = 0;
    if (!data.length || !snapshot.hasAnyData) return data;
    WSResponseFormat format = [self formatForData:data contentType:contentType];
    if (format == WSResponseFormatJSON) {
        return WSPatchJSON(data, snapshot, changedFields, error);
    }
    return WSPatchFlatBuffer(data, snapshot, changedFields, error);
}

@end

