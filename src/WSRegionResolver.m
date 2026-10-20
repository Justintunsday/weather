#import "WSRegionResolver.h"

static BOOL WSInBox(double lat, double lon, double minLat, double maxLat, double minLon, double maxLon) {
    return lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;
}

@implementation WSRegionResolver

+ (NSString *)normalizedCountryCode:(NSString *)country {
    if (![country isKindOfClass:[NSString class]]) return nil;
    NSString *code = [[country stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] uppercaseString];
    if (code.length != 2) return nil;
    return code;
}

+ (NSString *)regionForLatitude:(double)latitude
                      longitude:(double)longitude
                 countryFromURL:(NSString *)countryFromURL {
    NSString *geometry = WS_REGION_OTHER;

    if (WSInBox(latitude, longitude, 22.13, 22.60, 113.80, 114.52)) {
        geometry = WS_REGION_HK;
    } else if (WSInBox(latitude, longitude, 22.05, 22.24, 113.50, 113.62)) {
        geometry = WS_REGION_MO;
    } else if (WSInBox(latitude, longitude, 21.70, 25.50, 119.20, 122.20)) {
        geometry = WS_REGION_TW;
    } else if (WSInBox(latitude, longitude, 24.0, 49.5, -125.0, -66.0) ||
               WSInBox(latitude, longitude, 51.0, 72.0, -170.0, -129.0) ||
               WSInBox(latitude, longitude, 18.5, 22.5, -161.0, -154.0)) {
        geometry = WS_REGION_US;
    } else if (WSInBox(latitude, longitude, 33.0, 39.5, 124.0, 132.0)) {
        geometry = WS_REGION_KR;
    } else if (WSInBox(latitude, longitude, 24.0, 46.0, 122.0, 146.0)) {
        geometry = WS_REGION_JP;
    } else if (WSInBox(latitude, longitude, 18.0, 54.0, 73.0, 135.5)) {
        geometry = WS_REGION_CN;
    }

    // Hong Kong, Macau and Taiwan must win over a mainland/other storefront
    // country value, because coordinates are the stronger signal for these
    // special administrative and customs regions.
    if ([geometry isEqualToString:WS_REGION_HK] ||
        [geometry isEqualToString:WS_REGION_MO] ||
        [geometry isEqualToString:WS_REGION_TW]) {
        return geometry;
    }

    NSString *country = [self normalizedCountryCode:countryFromURL];
    if ([country isEqualToString:@"CN"]) return WS_REGION_CN;
    if ([country isEqualToString:@"HK"]) return WS_REGION_HK;
    if ([country isEqualToString:@"MO"]) return WS_REGION_MO;
    if ([country isEqualToString:@"TW"]) return WS_REGION_TW;
    if ([country isEqualToString:@"US"]) return WS_REGION_US;
    if ([country isEqualToString:@"JP"]) return WS_REGION_JP;
    if ([country isEqualToString:@"KR"]) return WS_REGION_KR;

    // If the URL country says something else (GB, DE, ...), use the
    // coordinate-derived region only when it is one of the supported
    // regions; otherwise keep the generic bucket.
    if (![geometry isEqualToString:WS_REGION_OTHER]) return geometry;
    return WS_REGION_OTHER;
}

@end
