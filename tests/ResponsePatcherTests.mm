#import <Foundation/Foundation.h>
#import "WSWeatherResponsePatcher.h"
#import <math.h>

static void Check(BOOL result, NSString *message) {
    if (!result) { NSLog(@"FAIL: %@", message); exit(1); }
}

int main(void) {
    @autoreleasepool {
        NSDictionary *past = @{@"forecastStart": @"2026-10-19T14:00:00Z", @"temperature": @10, @"humidity": @0.8};
        NSDictionary *present = @{@"forecastStart": @"2026-10-20T14:00:00Z", @"temperature": @11, @"humidity": @0.8, @"cloudCover": @0.3, @"precipitationChance": @0.2};
        NSDictionary *oldDay = @{@"forecastStart": @"2026-10-18T16:00:00Z", @"temperatureMax": @10};
        NSDictionary *today = @{@"forecastStart": @"2026-10-19T16:00:00Z", @"temperatureMax": @12, @"humidityMax": @0.8, @"precipitationChance": @0.2, @"sunrise": @"unchanged"};
        NSDictionary *input = @{
            @"currentWeather": @{@"temperature": @10, @"humidity": @0.8, @"cloudCover": @0.3},
            @"forecastHourly": @{@"hours": @[past, present]},
            @"forecastDaily": @{@"days": @[oldDay, today]},
            @"airQuality": @{@"value": @42}
        };
        WSWeatherSnapshot *snapshot = [WSWeatherSnapshot new];
        snapshot.current = [WSCurrentWeather new];
        snapshot.current.temperature = @25;
        snapshot.current.humidity = @88;
        snapshot.current.cloudCover = @3;
        snapshot.current.pressure = @1000; // Absent Apple fields must stay absent.
        WSHourlyWeather *hour = [WSHourlyWeather new];
        hour.timestamp = @1792504800; // 2026-10-20 14:00 UTC
        hour.temperature = @26;
        hour.humidity = @90;
        hour.cloudCover = @25;
        hour.precipitationChance = @28;
        snapshot.hourly = @[hour];
        WSDailyWeather *day = [WSDailyWeather new];
        day.timestamp = @1792425600; // 2026-10-19 16:00 UTC
        day.temperatureMax = @30;
        day.humidityMax = @95;
        day.precipitationChance = @40;
        snapshot.daily = @[day];
        NSData *data = [NSJSONSerialization dataWithJSONObject:input options:0 error:nil];
        NSInteger changed = 0;
        NSError *error = nil;
        NSData *output = [WSWeatherResponsePatcher patchData:data contentType:@"application/json" snapshot:snapshot changedFields:&changed error:&error];
        Check(output != nil && error == nil && changed > 0, @"patch must succeed");
        NSDictionary *result = [NSJSONSerialization JSONObjectWithData:output options:0 error:nil];
        Check(fabs([result[@"currentWeather"][@"humidity"] doubleValue] - 0.88) < 1e-6, @"humidity is fractional");
        Check(fabs([result[@"currentWeather"][@"cloudCover"] doubleValue] - 0.03) < 1e-6, @"cloud cover is fractional");
        Check(result[@"currentWeather"][@"pressure"] == nil, @"do not introduce fields");
        NSArray *hours = result[@"forecastHourly"][@"hours"];
        Check([hours[0] isEqual:past], @"unmatched historical hour stays unchanged");
        Check([hours[1][@"temperature"] intValue] == 26, @"hour matches timestamp");
        Check(fabs([hours[1][@"precipitationChance"] doubleValue] - 0.28) < 1e-6, @"hourly probability is fractional");
        NSArray *days = result[@"forecastDaily"][@"days"];
        Check([days[0] isEqual:oldDay], @"unmatched historical day stays unchanged");
        Check([days[1][@"temperatureMax"] intValue] == 30, @"day matches timestamp");
        Check(fabs([days[1][@"humidityMax"] doubleValue] - 0.95) < 1e-6, @"daily humidity is fractional");
        Check([days[1][@"sunrise"] isEqual:@"unchanged"], @"retain Apple sunrise");
        Check([result[@"airQuality"] isEqual:input[@"airQuality"]], @"retain Apple air quality");
        NSLog(@"JSON response regression checks passed (%ld fields)", (long)changed);
    }
    return 0;
}
