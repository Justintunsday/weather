#import <Foundation/Foundation.h>
#import "WSShared.h"

@interface WSRegionResolver : NSObject

+ (NSString *)regionForLatitude:(double)latitude
                      longitude:(double)longitude
                 countryFromURL:(NSString *)countryFromURL;

+ (NSString *)normalizedCountryCode:(NSString *)country;

@end
