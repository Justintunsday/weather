#import <Foundation/Foundation.h>

@interface WSSettings : NSObject

+ (instancetype)shared;

- (void)invalidateCache;

- (id)objectForKey:(NSString *)key default:(id)defaultValue;
- (BOOL)boolForKey:(NSString *)key default:(BOOL)defaultValue;
- (NSInteger)integerForKey:(NSString *)key default:(NSInteger)defaultValue;
- (double)doubleForKey:(NSString *)key default:(double)defaultValue;
- (NSString *)stringForKey:(NSString *)key default:(NSString *)defaultValue;
- (NSArray *)arrayForKey:(NSString *)key default:(NSArray *)defaultValue;
- (NSDictionary *)dictionaryForKey:(NSString *)key default:(NSDictionary *)defaultValue;

- (void)setObject:(id)value forKey:(NSString *)key;
- (void)setObject:(id)value forKey:(NSString *)key notify:(BOOL)notify;
- (BOOL)saveSharedObject:(id)value forKey:(NSString *)key;

- (BOOL)enabled;
- (BOOL)autoRegion;
- (double)cacheTTL;
- (double)requestTimeout;
- (double)minRefreshInterval;
- (NSInteger)logLevel;
- (NSString *)fallbackProvider;
- (NSString *)globalProvider;

- (NSString *)providerForRegion:(NSString *)region;
- (NSString *)overrideProviderForLatitude:(double)latitude longitude:(double)longitude;
- (NSString *)qweatherKey;
- (NSString *)qweatherHost;
- (NSString *)cwaKey;
- (NSString *)kmaKey;

- (NSArray<NSDictionary *> *)recentLocations;
- (void)recordLocationLatitude:(double)latitude
                     longitude:(double)longitude
                       country:(NSString *)country
                      provider:(NSString *)provider
                          name:(NSString *)name;
- (void)clearRecentLocations;

- (NSArray<NSDictionary *> *)logEntries;
- (void)appendLogEntry:(NSDictionary *)entry;
- (void)clearLog;

@end
