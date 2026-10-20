#import "WSWeatherModel.h"

static NSDictionary *WSDictionaryFromObject(id object, NSArray<NSString *> *keys) {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        id value = [object valueForKey:key];
        if (value && value != [NSNull null]) dictionary[key] = value;
    }
    return dictionary;
}

static void WSLoadObject(id object, NSDictionary *dictionary, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = dictionary[key];
        if (value && value != [NSNull null]) [object setValue:value forKey:key];
    }
}

static NSArray<NSString *> *WSCurrentKeys(void) {
    return @[@"timestamp", @"temperature", @"apparentTemperature", @"dewPoint", @"humidity",
             @"pressure", @"windSpeed", @"windGust", @"windDirection", @"uvIndex", @"visibility",
             @"cloudCover", @"precipitationAmount1h", @"precipitationChance", @"snowfallAmount1h",
             @"conditionCode", @"daylight"];
}

static NSArray<NSString *> *WSHourlyKeys(void) {
    return @[@"timestamp", @"temperature", @"apparentTemperature", @"dewPoint", @"humidity",
             @"pressure", @"windSpeed", @"windGust", @"windDirection", @"uvIndex", @"visibility",
             @"cloudCover", @"precipitationChance", @"precipitationAmount", @"snowfallAmount",
             @"conditionCode", @"daylight"];
}

static NSArray<NSString *> *WSDailyKeys(void) {
    return @[@"timestamp", @"endTimestamp", @"temperatureMax", @"temperatureMin", @"humidityMax",
             @"humidityMin", @"maxUvIndex", @"precipitationChance", @"precipitationAmount",
             @"snowfallAmount", @"windSpeedMax", @"windGustSpeedMax", @"windSpeedAvg", @"conditionCode"];
}

@implementation WSCurrentWeather
- (NSDictionary *)dictionaryRepresentation { return WSDictionaryFromObject(self, WSCurrentKeys()); }
+ (instancetype)fromDictionary:(NSDictionary *)dictionary {
    WSCurrentWeather *object = [[self alloc] init];
    WSLoadObject(object, dictionary, WSCurrentKeys());
    return object;
}
@end

@implementation WSHourlyWeather
- (NSDictionary *)dictionaryRepresentation { return WSDictionaryFromObject(self, WSHourlyKeys()); }
+ (instancetype)fromDictionary:(NSDictionary *)dictionary {
    WSHourlyWeather *object = [[self alloc] init];
    WSLoadObject(object, dictionary, WSHourlyKeys());
    return object;
}
@end

@implementation WSDailyWeather
- (NSDictionary *)dictionaryRepresentation { return WSDictionaryFromObject(self, WSDailyKeys()); }
+ (instancetype)fromDictionary:(NSDictionary *)dictionary {
    WSDailyWeather *object = [[self alloc] init];
    WSLoadObject(object, dictionary, WSDailyKeys());
    return object;
}
@end

@implementation WSWeatherSnapshot

- (instancetype)init {
    self = [super init];
    if (self) {
        _hourly = @[];
        _daily = @[];
        _fetchedAt = [[NSDate date] timeIntervalSince1970];
    }
    return self;
}

- (BOOL)hasAnyData {
    return self.current != nil || self.hourly.count > 0 || self.daily.count > 0;
}

- (NSString *)summary {
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"%@", self.providerID ?: @"?"];
    if (self.current) {
        [text appendFormat:@" current=%@°/%@°", self.current.temperature ?: @"?", self.current.apparentTemperature ?: @"?"];
    }
    [text appendFormat:@" hourly=%lu daily=%lu", (unsigned long)self.hourly.count, (unsigned long)self.daily.count];
    if (self.fromCache) [text appendString:@" (cache)"];
    return text;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    if (self.current) dictionary[@"current"] = [self.current dictionaryRepresentation];
    if (self.hourly.count) {
        NSMutableArray *hours = [NSMutableArray array];
        for (WSHourlyWeather *hour in self.hourly) [hours addObject:[hour dictionaryRepresentation]];
        dictionary[@"hourly"] = hours;
    }
    if (self.daily.count) {
        NSMutableArray *days = [NSMutableArray array];
        for (WSDailyWeather *day in self.daily) [days addObject:[day dictionaryRepresentation]];
        dictionary[@"daily"] = days;
    }
    if (self.providerID) dictionary[@"providerID"] = self.providerID;
    if (self.providerName) dictionary[@"providerName"] = self.providerName;
    dictionary[@"fetchedAt"] = @(self.fetchedAt);
    dictionary[@"fromCache"] = @(self.fromCache);
    return dictionary;
}

+ (instancetype)fromDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) return nil;
    WSWeatherSnapshot *snapshot = [[self alloc] init];
    if ([dictionary[@"current"] isKindOfClass:[NSDictionary class]]) {
        snapshot.current = [WSCurrentWeather fromDictionary:dictionary[@"current"]];
    }
    if ([dictionary[@"hourly"] isKindOfClass:[NSArray class]]) {
        NSMutableArray *hours = [NSMutableArray array];
        for (id item in dictionary[@"hourly"]) {
            if ([item isKindOfClass:[NSDictionary class]]) [hours addObject:[WSHourlyWeather fromDictionary:item]];
        }
        snapshot.hourly = hours;
    }
    if ([dictionary[@"daily"] isKindOfClass:[NSArray class]]) {
        NSMutableArray *days = [NSMutableArray array];
        for (id item in dictionary[@"daily"]) {
            if ([item isKindOfClass:[NSDictionary class]]) [days addObject:[WSDailyWeather fromDictionary:item]];
        }
        snapshot.daily = days;
    }
    if ([dictionary[@"providerID"] isKindOfClass:[NSString class]]) snapshot.providerID = dictionary[@"providerID"];
    if ([dictionary[@"providerName"] isKindOfClass:[NSString class]]) snapshot.providerName = dictionary[@"providerName"];
    if ([dictionary[@"fetchedAt"] respondsToSelector:@selector(doubleValue)]) {
        snapshot.fetchedAt = [dictionary[@"fetchedAt"] doubleValue];
    }
    if ([dictionary[@"fromCache"] respondsToSelector:@selector(boolValue)]) {
        snapshot.fromCache = [dictionary[@"fromCache"] boolValue];
    }
    return snapshot;
}

@end
