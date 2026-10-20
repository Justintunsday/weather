#import <Foundation/Foundation.h>
#import "WSWeatherModel.h"

typedef void (^WSProviderCompletion)(WSWeatherSnapshot * _Nullable snapshot, NSError * _Nullable error);

@protocol WSWeatherProvider <NSObject>
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *displayName;
- (BOOL)isAvailable;
- (void)fetchSnapshotForLatitude:(double)latitude
                       longitude:(double)longitude
                          locale:(NSString *)locale
                      completion:(WSProviderCompletion)completion;
@end

FOUNDATION_EXPORT NSErrorDomain const WSProviderErrorDomain;

static inline NSError *WSProviderError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:WSProviderErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"Provider error"}];
}
