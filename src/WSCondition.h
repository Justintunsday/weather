#import <Foundation/Foundation.h>

// Numeric values are the WeatherKit v2 FlatBuffer WeatherCondition enum.
typedef NS_ENUM(int, WSWeatherCondition) {
    WSWeatherConditionClear = 0,
    WSWeatherConditionBlizzard = 1,
    WSWeatherConditionPrecipitation = 2,
    WSWeatherConditionCloudy = 5,
    WSWeatherConditionDrizzle = 6,
    WSWeatherConditionFlurries = 7,
    WSWeatherConditionFoggy = 8,
    WSWeatherConditionHaze = 13,
    WSWeatherConditionHeavyRain = 14,
    WSWeatherConditionHeavySnow = 15,
    WSWeatherConditionIsolatedThunderstorms = 18,
    WSWeatherConditionMostlyClear = 19,
    WSWeatherConditionMostlyCloudy = 20,
    WSWeatherConditionPartlyCloudy = 21,
    WSWeatherConditionRain = 22,
    WSWeatherConditionSnow = 26,
    WSWeatherConditionFreezingDrizzle = 29,
    WSWeatherConditionThunderstorms = 30,
    WSWeatherConditionWindy = 32,
    WSWeatherConditionWintryMix = 33,
};

@interface WSCondition : NSObject

+ (int)conditionForWMOWeatherCode:(int)code;
+ (int)conditionForQWeatherIcon:(NSString *)icon;
+ (NSString *)nameForCondition:(int)condition;
+ (NSString *)stringForCondition:(int)condition;
+ (id)JSONValueForCondition:(int)condition existingValue:(id)existingValue;

@end
