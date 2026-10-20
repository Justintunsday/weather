#import <Foundation/Foundation.h>

@interface WSCurrentWeather : NSObject
@property (nonatomic, strong) NSNumber *timestamp;
@property (nonatomic, strong) NSNumber *temperature;
@property (nonatomic, strong) NSNumber *apparentTemperature;
@property (nonatomic, strong) NSNumber *dewPoint;
@property (nonatomic, strong) NSNumber *humidity;
@property (nonatomic, strong) NSNumber *pressure;
@property (nonatomic, strong) NSNumber *windSpeed;
@property (nonatomic, strong) NSNumber *windGust;
@property (nonatomic, strong) NSNumber *windDirection;
@property (nonatomic, strong) NSNumber *uvIndex;
@property (nonatomic, strong) NSNumber *visibility;
@property (nonatomic, strong) NSNumber *cloudCover;
@property (nonatomic, strong) NSNumber *precipitationAmount1h;
@property (nonatomic, strong) NSNumber *precipitationChance;
@property (nonatomic, strong) NSNumber *snowfallAmount1h;
@property (nonatomic, strong) NSNumber *conditionCode;
@property (nonatomic, strong) NSNumber *daylight;

- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)fromDictionary:(NSDictionary *)dictionary;
@end

@interface WSHourlyWeather : NSObject
@property (nonatomic, strong) NSNumber *timestamp;
@property (nonatomic, strong) NSNumber *temperature;
@property (nonatomic, strong) NSNumber *apparentTemperature;
@property (nonatomic, strong) NSNumber *dewPoint;
@property (nonatomic, strong) NSNumber *humidity;
@property (nonatomic, strong) NSNumber *pressure;
@property (nonatomic, strong) NSNumber *windSpeed;
@property (nonatomic, strong) NSNumber *windGust;
@property (nonatomic, strong) NSNumber *windDirection;
@property (nonatomic, strong) NSNumber *uvIndex;
@property (nonatomic, strong) NSNumber *visibility;
@property (nonatomic, strong) NSNumber *cloudCover;
@property (nonatomic, strong) NSNumber *precipitationChance;
@property (nonatomic, strong) NSNumber *precipitationAmount;
@property (nonatomic, strong) NSNumber *snowfallAmount;
@property (nonatomic, strong) NSNumber *conditionCode;
@property (nonatomic, strong) NSNumber *daylight;

- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)fromDictionary:(NSDictionary *)dictionary;
@end

@interface WSDailyWeather : NSObject
@property (nonatomic, strong) NSNumber *timestamp;
@property (nonatomic, strong) NSNumber *endTimestamp;
@property (nonatomic, strong) NSNumber *temperatureMax;
@property (nonatomic, strong) NSNumber *temperatureMin;
@property (nonatomic, strong) NSNumber *humidityMax;
@property (nonatomic, strong) NSNumber *humidityMin;
@property (nonatomic, strong) NSNumber *maxUvIndex;
@property (nonatomic, strong) NSNumber *precipitationChance;
@property (nonatomic, strong) NSNumber *precipitationAmount;
@property (nonatomic, strong) NSNumber *snowfallAmount;
@property (nonatomic, strong) NSNumber *windSpeedMax;
@property (nonatomic, strong) NSNumber *windGustSpeedMax;
@property (nonatomic, strong) NSNumber *windSpeedAvg;
@property (nonatomic, strong) NSNumber *apparentTemperatureMax;
@property (nonatomic, strong) NSNumber *apparentTemperatureMin;
@property (nonatomic, strong) NSNumber *humidity;
@property (nonatomic, strong) NSNumber *uvIndex;
@property (nonatomic, strong) NSNumber *windSpeed;
@property (nonatomic, strong) NSNumber *windGust;
@property (nonatomic, strong) NSNumber *windDirection;
@property (nonatomic, strong) NSNumber *pressure;
@property (nonatomic, strong) NSNumber *visibility;
@property (nonatomic, strong) NSNumber *conditionCode;

- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)fromDictionary:(NSDictionary *)dictionary;
@end

@interface WSWeatherSnapshot : NSObject
@property (nonatomic, strong) WSCurrentWeather *current;
@property (nonatomic, copy) NSArray<WSHourlyWeather *> *hourly;
@property (nonatomic, copy) NSArray<WSDailyWeather *> *daily;
@property (nonatomic, copy) NSString *providerID;
@property (nonatomic, copy) NSString *providerName;
@property (nonatomic) NSTimeInterval fetchedAt;
@property (nonatomic) BOOL fromCache;

- (BOOL)hasAnyData;
- (NSString *)summary;
- (NSDictionary *)dictionaryRepresentation;
+ (instancetype)fromDictionary:(NSDictionary *)dictionary;
@end
