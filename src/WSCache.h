#import <Foundation/Foundation.h>

@interface WSCache : NSObject

+ (instancetype)shared;

- (BOOL)hasFreshDataForKey:(NSString *)key ttl:(NSTimeInterval)ttl;
- (NSTimeInterval)ageForKey:(NSString *)key;
- (NSData *)dataForKey:(NSString *)key;
- (void)setData:(NSData *)data forKey:(NSString *)key;
- (id)JSONForKey:(NSString *)key;
- (void)setJSON:(id)json forKey:(NSString *)key;
- (void)removeDataForKey:(NSString *)key;
- (void)removeAll;

@end
