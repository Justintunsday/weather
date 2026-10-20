#import "WSFetchCoordinator.h"
#import "WSProviderRegistry.h"
#import "WSSettings.h"
#import "WSCache.h"
#import "WSLogger.h"

@interface WSFetchCoordinator ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<WSFetchCompletion> *> *inFlight;
@end

@implementation WSFetchCoordinator

+ (instancetype)shared {
    static WSFetchCoordinator *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[WSFetchCoordinator alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _queue = dispatch_queue_create("com.weathersource.fetch", DISPATCH_QUEUE_SERIAL);
        _inFlight = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSString *)cacheKeyForProvider:(NSString *)providerID latitude:(double)latitude longitude:(double)longitude {
    return [NSString stringWithFormat:@"snapshot-%@-%.2f-%.2f", providerID, latitude, longitude];
}

- (void)fetchSnapshotForProviderID:(NSString *)providerID
                         latitude:(double)latitude
                        longitude:(double)longitude
                           locale:(NSString *)locale
                       completion:(WSFetchCompletion)completion {
    if (!completion) return;
    if (!providerID.length || [providerID isEqualToString:@"apple"]) {
        completion(nil, nil);
        return;
    }
    id<WSWeatherProvider> provider = [WSProviderRegistry providerForIdentifier:providerID];
    if (!provider || ![provider isAvailable]) {
        completion(nil, WSProviderError(-20, [NSString stringWithFormat:@"Provider %@ is unavailable", providerID]));
        return;
    }

    WSSettings *settings = [WSSettings shared];
    NSString *cacheKey = [self cacheKeyForProvider:providerID latitude:latitude longitude:longitude];
    WSCache *cache = [WSCache shared];

    if ([cache hasFreshDataForKey:cacheKey ttl:settings.cacheTTL]) {
        NSDictionary *dictionary = [cache JSONForKey:cacheKey];
        WSWeatherSnapshot *snapshot = [WSWeatherSnapshot fromDictionary:dictionary];
        if (snapshot.hasAnyData) {
            snapshot.fromCache = YES;
            [WSLogger debug:@"Cache hit %@", cacheKey];
            completion(snapshot, nil);
            return;
        }
    }

    dispatch_async(self.queue, ^{
        NSMutableArray<WSFetchCompletion> *waiters = self.inFlight[cacheKey];
        if (waiters) {
            [waiters addObject:[completion copy]];
            return;
        }
        waiters = [NSMutableArray arrayWithObject:[completion copy]];
        self.inFlight[cacheKey] = waiters;

        NSTimeInterval started = [NSDate timeIntervalSinceReferenceDate];
        [WSLogger info:@"Fetching %@ provider for %.3f,%.3f", providerID, latitude, longitude];
        [provider fetchSnapshotForLatitude:latitude
                                  longitude:longitude
                                     locale:locale
                                 completion:^(WSWeatherSnapshot *snapshot, NSError *error) {
            NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - started;
            if (snapshot.hasAnyData) {
                snapshot.fromCache = NO;
                [cache setJSON:[snapshot dictionaryRepresentation] forKey:cacheKey];
                [WSLogger info:@"Provider %@ returned %@ in %.2fs", providerID, [snapshot summary], elapsed];
            } else {
                NSTimeInterval age = [cache ageForKey:cacheKey];
                NSDictionary *stale = [cache JSONForKey:cacheKey];
                WSWeatherSnapshot *staleSnapshot = [WSWeatherSnapshot fromDictionary:stale];
                if (staleSnapshot.hasAnyData && age <= MAX(settings.cacheTTL * 6.0, 1800.0)) {
                    staleSnapshot.fromCache = YES;
                    [WSLogger warning:@"Provider %@ failed (%@); using %.0fs old cache", providerID,
                                     error.localizedDescription ?: @"unknown", age];
                    snapshot = staleSnapshot;
                    error = nil;
                } else {
                    [WSLogger warning:@"Provider %@ failed: %@", providerID, error.localizedDescription ?: @"unknown"];
                }
            }

            dispatch_async(self.queue, ^{
                NSArray<WSFetchCompletion> *callbacks = [self.inFlight[cacheKey] copy];
                [self.inFlight removeObjectForKey:cacheKey];
                dispatch_async(dispatch_get_main_queue(), ^{
                    for (WSFetchCompletion callback in callbacks) {
                        callback(snapshot, error);
                    }
                });
            });
        }];
    });
}

@end
