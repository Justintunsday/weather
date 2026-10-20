#import <Foundation/Foundation.h>
#import "WSWeatherModel.h"

typedef void (^WSFetchCompletion)(WSWeatherSnapshot * _Nullable snapshot, NSError * _Nullable error);

@interface WSFetchCoordinator : NSObject

+ (instancetype)shared;

- (void)fetchSnapshotForProviderID:(NSString *)providerID
                         latitude:(double)latitude
                        longitude:(double)longitude
                           locale:(NSString *)locale
                       completion:(WSFetchCompletion)completion;

@end
