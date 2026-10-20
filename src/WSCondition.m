#import "WSCondition.h"

@implementation WSCondition

+ (int)conditionForWMOWeatherCode:(int)code {
    switch (code) {
        case 0: return WSWeatherConditionClear;
        case 1: return WSWeatherConditionMostlyClear;
        case 2: return WSWeatherConditionPartlyCloudy;
        case 3: return WSWeatherConditionCloudy;
        case 45:
        case 48: return WSWeatherConditionFoggy;
        case 51:
        case 53:
        case 55: return WSWeatherConditionDrizzle;
        case 56:
        case 57: return WSWeatherConditionFreezingDrizzle;
        case 61:
        case 63: return WSWeatherConditionRain;
        case 65: return WSWeatherConditionHeavyRain;
        case 66:
        case 67: return WSWeatherConditionFreezingDrizzle;
        case 71:
        case 73: return WSWeatherConditionSnow;
        case 75: return WSWeatherConditionHeavySnow;
        case 77: return WSWeatherConditionFlurries;
        case 80:
        case 81: return WSWeatherConditionRain;
        case 82: return WSWeatherConditionHeavyRain;
        case 85: return WSWeatherConditionSnow;
        case 86: return WSWeatherConditionHeavySnow;
        case 95:
        case 96:
        case 99: return WSWeatherConditionThunderstorms;
        default: return -1;
    }
}

+ (int)conditionForQWeatherIcon:(NSString *)icon {
    int code = [icon intValue];
    if (code <= 0) return -1;
    if (code == 100 || code == 150) return WSWeatherConditionClear;
    if (code == 102 || code == 152) return WSWeatherConditionMostlyClear;
    if (code == 101 || code == 103 || code == 151 || code == 153) return WSWeatherConditionPartlyCloudy;
    if (code == 104 || code == 154) return WSWeatherConditionCloudy;

    if (code == 302 || code == 303 || code == 304) return WSWeatherConditionThunderstorms;
    if (code == 305 || code == 309) return WSWeatherConditionDrizzle;
    if (code == 313) return WSWeatherConditionFreezingDrizzle;
    if (code == 300 || code == 301 || code == 306 || code == 314 || code == 315) return WSWeatherConditionRain;
    if (code == 307 || code == 308 || code == 310 || code == 311 || code == 312 ||
        code == 316 || code == 317 || code == 318 || code == 399) {
        return WSWeatherConditionHeavyRain;
    }

    if (code == 400 || code == 407 || code == 408) return WSWeatherConditionFlurries;
    if (code == 401 || code == 409) return WSWeatherConditionSnow;
    if (code == 402 || code == 403 || code == 410 || code == 499) return WSWeatherConditionHeavySnow;
    if (code == 404 || code == 405 || code == 406) return WSWeatherConditionWintryMix;

    if (code == 500 || code == 501 || code == 507 || code == 508 ||
        code == 509 || code == 510 || code == 514 || code == 515) {
        return WSWeatherConditionFoggy;
    }
    if (code == 502 || code == 503 || code == 504 || code == 505 ||
        code == 506 || code == 511 || code == 512 || code == 513) {
        return WSWeatherConditionHaze;
    }

    if (code == 900 || code == 901) return WSWeatherConditionClear;
    return -1;
}

+ (NSString *)nameForCondition:(int)condition {
    switch (condition) {
        case WSWeatherConditionClear: return @"CLEAR";
        case WSWeatherConditionBlizzard: return @"BLIZZARD";
        case WSWeatherConditionPrecipitation: return @"PRECIPITATION";
        case WSWeatherConditionCloudy: return @"CLOUDY";
        case WSWeatherConditionDrizzle: return @"DRIZZLE";
        case WSWeatherConditionFlurries: return @"FLURRIES";
        case WSWeatherConditionFoggy: return @"FOGGY";
        case WSWeatherConditionHaze: return @"HAZE";
        case WSWeatherConditionHeavyRain: return @"HEAVY_RAIN";
        case WSWeatherConditionHeavySnow: return @"HEAVY_SNOW";
        case WSWeatherConditionIsolatedThunderstorms: return @"ISOLATED_THUNDERSTORMS";
        case WSWeatherConditionMostlyClear: return @"MOSTLY_CLEAR";
        case WSWeatherConditionMostlyCloudy: return @"MOSTLY_CLOUDY";
        case WSWeatherConditionPartlyCloudy: return @"PARTLY_CLOUDY";
        case WSWeatherConditionRain: return @"RAIN";
        case WSWeatherConditionSnow: return @"SNOW";
        case WSWeatherConditionFreezingDrizzle: return @"FREEZING_DRIZZLE";
        case WSWeatherConditionThunderstorms: return @"THUNDERSTORMS";
        case WSWeatherConditionWindy: return @"WINDY";
        case WSWeatherConditionWintryMix: return @"WINTRY_MIX";
        default: return @"UNKNOWN";
    }
}

+ (NSString *)stringForCondition:(int)condition {
    NSString *upper = [self nameForCondition:condition];
    NSArray<NSString *> *parts = [upper componentsSeparatedByString:@"_"];
    NSMutableString *result = [NSMutableString string];
    for (NSString *part in parts) {
        if (!part.length) continue;
        NSString *lower = [part lowercaseString];
        [result appendString:[lower substringToIndex:1].uppercaseString];
        if (lower.length > 1) [result appendString:[lower substringFromIndex:1]];
    }
    return result.length ? result : @"Unknown";
}

+ (id)JSONValueForCondition:(int)condition existingValue:(id)existingValue {
    if ([existingValue isKindOfClass:[NSNumber class]]) return @(condition);
    NSString *name = [self nameForCondition:condition];
    if (![existingValue isKindOfClass:[NSString class]]) return [self stringForCondition:condition];

    NSString *existing = (NSString *)existingValue;
    if (existing.length == 0) return [self stringForCondition:condition];
    NSCharacterSet *lower = [NSCharacterSet lowercaseLetterCharacterSet];
    if ([existing rangeOfCharacterFromSet:lower].location != NSNotFound) {
        // Mixed-case / lower-case values from the public REST API.
        if ([existing isEqualToString:existing.lowercaseString]) {
            NSString *first = [name substringToIndex:1].lowercaseString;
            return [first stringByAppendingString:[name substringFromIndex:1].lowercaseString];
        }
        return [self stringForCondition:condition];
    }
    return name;
}

@end
