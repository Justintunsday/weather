#import <Foundation/Foundation.h>
#import "WSWeatherProvider.h"

@interface WSProviderRegistry : NSObject

+ (id<WSWeatherProvider>)providerForIdentifier:(NSString *)identifier;
+ (BOOL)isProviderAvailable:(NSString *)identifier;
+ (NSDictionary<NSString *, NSString *> *)resolutionForLatitude:(double)latitude
                                                       longitude:(double)longitude
                                                  countryFromURL:(NSString *)countryFromURL;

@end
