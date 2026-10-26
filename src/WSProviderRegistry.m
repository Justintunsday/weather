#import "WSProviderRegistry.h"
#import "WSOpenMeteoProvider.h"
#import "WSQWeatherProvider.h"
#import "WSHKOProvider.h"
#import "WSRegionResolver.h"
#import "WSSettings.h"
#import "WSLogger.h"
#import "WSShared.h"

@implementation WSProviderRegistry

+ (id<WSWeatherProvider>)providerForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:WS_PROVIDER_OPEN_METEO]) return [[WSOpenMeteoProvider alloc] init];
    if ([identifier isEqualToString:WS_PROVIDER_QWEATHER]) return [[WSQWeatherProvider alloc] init];
    if ([identifier isEqualToString:WS_PROVIDER_HKO]) return [[WSHKOProvider alloc] init];
    return nil;
}

+ (BOOL)isProviderAvailable:(NSString *)identifier {
    if ([identifier isEqualToString:WS_PROVIDER_APPLE]) return YES;
    id<WSWeatherProvider> provider = [self providerForIdentifier:identifier];
    return provider ? [provider isAvailable] : NO;
}

+ (NSString *)automaticProviderForRegion:(NSString *)region {
    WSSettings *settings = [WSSettings shared];
    if ([region isEqualToString:WS_REGION_HK]) return WS_PROVIDER_HKO;
    if ([region isEqualToString:WS_REGION_CN]) {
        if (settings.qweatherKey.length > 0) return WS_PROVIDER_QWEATHER;
        return WS_PROVIDER_OPEN_METEO;
    }
    // More regional authorities will be added as their adapters are verified.
    // Until then, use the global Open-Meteo adapter rather than a stale or
    // fabricated local value.
    return WS_PROVIDER_OPEN_METEO;
}

+ (NSDictionary<NSString *, NSString *> *)resolutionForLatitude:(double)latitude
                                                       longitude:(double)longitude
                                                  countryFromURL:(NSString *)countryFromURL {
    WSSettings *settings = [WSSettings shared];
    NSString *region = [WSRegionResolver regionForLatitude:latitude
                                                 longitude:longitude
                                            countryFromURL:countryFromURL];

    if (!settings.enabled) {
        return @{@"provider": WS_PROVIDER_APPLE, @"region": region, @"requested": @"disabled", @"fallback": @""};
    }

    NSString *requested = [settings overrideProviderForLatitude:latitude longitude:longitude];
    if (!requested.length) {
        if (settings.autoRegion) {
            requested = [settings providerForRegion:region];
        } else {
            requested = settings.globalProvider;
        }
    }
    if (!requested.length || [requested isEqualToString:WS_PROVIDER_AUTO]) {
        requested = [self automaticProviderForRegion:region];
    }

    NSString *selected = requested;
    NSString *fallback = @"";
    if ([selected isEqualToString:WS_PROVIDER_APPLE]) {
        return @{@"provider": WS_PROVIDER_APPLE, @"region": region, @"requested": requested, @"fallback": @""};
    }
    if (![self isProviderAvailable:selected]) {
        NSString *guard = settings.fallbackProvider;
        fallback = [NSString stringWithFormat:@"%@ unavailable", selected];
        if (guard.length && ![guard isEqualToString:selected] && [self isProviderAvailable:guard]) {
            selected = guard;
        } else if ([self isProviderAvailable:WS_PROVIDER_OPEN_METEO]) {
            selected = WS_PROVIDER_OPEN_METEO;
        } else {
            selected = WS_PROVIDER_APPLE;
        }
        [WSLogger warning:@"Provider %@ unavailable, using %@ (region %@)", requested, selected, region];
    }

    return @{@"provider": selected, @"region": region, @"requested": requested, @"fallback": fallback};
}

@end
