#import "WSWeatherProvider.h"

@interface WSHKOProvider : NSObject <WSWeatherProvider>
// Parse partial reports independently; unsupported or stale fields stay nil.
+ (WSWeatherSnapshot *)snapshotWithCurrent:(NSDictionary *)current
                                 forecast:(NSDictionary *)forecast
                                 latitude:(double)latitude
                                longitude:(double)longitude
                            referenceDate:(NSDate *)referenceDate;
@end
