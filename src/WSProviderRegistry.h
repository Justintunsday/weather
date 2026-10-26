#import <Foundation/Foundation.h>
#import "WSWeatherProvider.h"

@interface WSProviderRegistry : NSObject
+ (NSString *)automaticProviderForRegion:(NSString *)region;

+ (id<WSWeatherProvider>)providerForIdentifier:(NSString *)identifier;
+ (BOOL)isProviderAvailable:(NSString *)identifier;
+ (NSDictionary<NSString *, NSString *> *)resolutionForLatitude:(double)latitude
                                                       longitude:(double)longitude
                                                  countryFromURL:(NSString *)countryFromURL;

@end
