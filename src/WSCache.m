#import "WSCache.h"
#import <float.h>

@implementation WSCache

+ (instancetype)shared {
    static WSCache *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[WSCache alloc] init];
    });
    return shared;
}

- (NSString *)cacheDirectory {
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"WeatherSourceCache"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return directory;
}

- (NSString *)pathForKey:(NSString *)key {
    NSString *safe = [key stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    safe = [safe stringByReplacingOccurrencesOfString:@":" withString:@"_"];
    safe = [safe stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    safe = [safe stringByAppendingFormat:@"-%lu.cache", (unsigned long)key.hash];
    return [[self cacheDirectory] stringByAppendingPathComponent:safe];
}

- (BOOL)hasFreshDataForKey:(NSString *)key ttl:(NSTimeInterval)ttl {
    NSString *path = [self pathForKey:key];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (!attributes) return NO;
    NSDate *modified = attributes[NSFileModificationDate];
    if (!modified) return NO;
    return -[modified timeIntervalSinceNow] <= ttl;
}

- (NSTimeInterval)ageForKey:(NSString *)key {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[self pathForKey:key] error:nil];
    NSDate *modified = attributes[NSFileModificationDate];
    return modified ? -[modified timeIntervalSinceNow] : DBL_MAX;
}

- (NSData *)dataForKey:(NSString *)key {
    return [NSData dataWithContentsOfFile:[self pathForKey:key]];
}

- (void)setData:(NSData *)data forKey:(NSString *)key {
    if (!key) return;
    if (!data) {
        [self removeDataForKey:key];
        return;
    }
    [data writeToFile:[self pathForKey:key] options:NSDataWritingAtomic error:nil];
}

- (id)JSONForKey:(NSString *)key {
    NSData *data = [self dataForKey:key];
    if (!data) return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
}

- (void)setJSON:(id)json forKey:(NSString *)key {
    if (!json) {
        [self removeDataForKey:key];
        return;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:nil];
    [self setData:data forKey:key];
}

- (void)removeDataForKey:(NSString *)key {
    [[NSFileManager defaultManager] removeItemAtPath:[self pathForKey:key] error:nil];
}

- (void)removeAll {
    [[NSFileManager defaultManager] removeItemAtPath:[self cacheDirectory] error:nil];
}

@end
