#import "WSSettings.h"
#import "WSShared.h"

#import <CoreFoundation/CoreFoundation.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>

static NSString *const kWSSettingsCacheNotification = @"WSSettingsCacheNotification";
static NSString *const kWSSharedSettingsPath = @"/var/mobile/Library/Weather/WeatherSource-config.plist";

static BOOL WSUsesSharedSettings(NSString *key) {
    // High-volume diagnostic entries stay local; user settings and locations are shared.
    return ![key isEqualToString:@"logEntries"];
}

static BOOL WSWriteSharedSetting(NSString *key, id value) {
    NSString *lockPath = [kWSSharedSettingsPath stringByAppendingString:@".lock"];
    int fd = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
    if (fd < 0) return NO;
    if (flock(fd, LOCK_EX) != 0) { close(fd); return NO; }
    NSMutableDictionary *dictionary = [[NSDictionary dictionaryWithContentsOfFile:kWSSharedSettingsPath] mutableCopy];
    if (!dictionary) dictionary = [NSMutableDictionary dictionary];
    if (value) dictionary[key] = value;
    else [dictionary removeObjectForKey:key];
    BOOL success = [dictionary writeToFile:kWSSharedSettingsPath atomically:YES];
    if (success) [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:kWSSharedSettingsPath error:nil];
    flock(fd, LOCK_UN);
    close(fd);
    return success;
}

static void WSSettingsDarwinCallback(CFNotificationCenterRef center,
                                     void *observer,
                                     CFStringRef name,
                                     const void *object,
                                     CFDictionaryRef userInfo) {
    (void)center;
    (void)object;
    (void)userInfo;
    if (name) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kWSSettingsCacheNotification object:nil];
    }
}

@interface WSSettings () {
    NSMutableDictionary<NSString *, id> *_cache;
    NSTimeInterval _cacheTime;
    dispatch_queue_t _writeQueue;
}
@end

@implementation WSSettings

+ (instancetype)shared {
    static WSSettings *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[WSSettings alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSMutableDictionary dictionary];
        _cacheTime = 0;
        _writeQueue = dispatch_queue_create("com.weathersource.settings.write", DISPATCH_QUEUE_SERIAL);
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleCacheNotification:)
                                                     name:kWSSettingsCacheNotification
                                                   object:nil];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        WSSettingsDarwinCallback,
                                        CFSTR(WS_NOTIFY_SETTINGS_CHANGED),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                       (__bridge const void *)self,
                                       CFSTR(WS_NOTIFY_SETTINGS_CHANGED),
                                       NULL);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleCacheNotification:(NSNotification *)notification {
    (void)notification;
    [self invalidateCache];
}

- (void)invalidateCache {
    @synchronized (self) {
        [_cache removeAllObjects];
        _cacheTime = 0;
    }
}

- (id)objectForKey:(NSString *)key default:(id)defaultValue {
    if (!key) return defaultValue;

    @synchronized (self) {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (now - _cacheTime > 2.0) {
            [_cache removeAllObjects];
            _cacheTime = now;
        }
        if (_cache[key]) {
            id cached = _cache[key];
            return [cached isKindOfClass:[NSNull class]] ? defaultValue : cached;
        }
    }

    NSDictionary *sharedPrefs = WSUsesSharedSettings(key) ? [NSDictionary dictionaryWithContentsOfFile:kWSSharedSettingsPath] : nil;
    if (sharedPrefs) {
        id result = sharedPrefs[key] ?: defaultValue;
        @synchronized (self) { _cache[key] = result ?: [NSNull null]; }
        return result;
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)WS_PREF_DOMAIN);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                        (__bridge CFStringRef)WS_PREF_DOMAIN);
    id result = nil;
    if (value) {
        result = (__bridge_transfer id)value;
    } else {
        NSString *prefsPath = [@"/var/mobile/Library/Preferences/" stringByAppendingString:
            [WS_PREF_DOMAIN stringByAppendingString:@".plist"]];
        NSDictionary *filePrefs = [NSDictionary dictionaryWithContentsOfFile:prefsPath];
        result = filePrefs[key];
    }
    if (!result) result = defaultValue;

    @synchronized (self) {
        _cache[key] = result ?: [NSNull null];
    }
    return result;
}

- (void)setObject:(id)value forKey:(NSString *)key {
    [self setObject:value forKey:key notify:YES];
}

- (void)setObject:(id)value forKey:(NSString *)key notify:(BOOL)notify {
    if (!key) return;
    id safeValue = value ?: [NSNull null];
    @synchronized (self) {
        _cache[key] = safeValue;
    }
    dispatch_async(_writeQueue, ^{
        BOOL sharedWrite = !WSUsesSharedSettings(key) || WSWriteSharedSetting(key, value);
        if (!sharedWrite) NSLog(@"[WeatherSource] Shared settings write failed for key %@", key);
        if (value) {
            CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                     (__bridge CFPropertyListRef)value,
                                     (__bridge CFStringRef)WS_PREF_DOMAIN);
        } else {
            CFPreferencesSetAppValue((__bridge CFStringRef)key,
                                     NULL,
                                     (__bridge CFStringRef)WS_PREF_DOMAIN);
        }
        CFPreferencesAppSynchronize((__bridge CFStringRef)WS_PREF_DOMAIN);
        if (notify) {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 CFSTR(WS_NOTIFY_SETTINGS_CHANGED),
                                                 NULL, NULL, true);
        }
    });
}

- (BOOL)boolForKey:(NSString *)key default:(BOOL)defaultValue {
    id value = [self objectForKey:key default:@(defaultValue)];
    if ([value respondsToSelector:@selector(boolValue)]) return [value boolValue];
    return defaultValue;
}

- (NSInteger)integerForKey:(NSString *)key default:(NSInteger)defaultValue {
    id value = [self objectForKey:key default:@(defaultValue)];
    if ([value respondsToSelector:@selector(integerValue)]) return [value integerValue];
    return defaultValue;
}

- (double)doubleForKey:(NSString *)key default:(double)defaultValue {
    id value = [self objectForKey:key default:@(defaultValue)];
    if ([value respondsToSelector:@selector(doubleValue)]) return [value doubleValue];
    return defaultValue;
}

- (NSString *)stringForKey:(NSString *)key default:(NSString *)defaultValue {
    id value = [self objectForKey:key default:defaultValue];
    return [value isKindOfClass:[NSString class]] ? value : defaultValue;
}

- (NSArray *)arrayForKey:(NSString *)key default:(NSArray *)defaultValue {
    id value = [self objectForKey:key default:defaultValue];
    return [value isKindOfClass:[NSArray class]] ? value : defaultValue;
}

- (NSDictionary *)dictionaryForKey:(NSString *)key default:(NSDictionary *)defaultValue {
    id value = [self objectForKey:key default:defaultValue];
    return [value isKindOfClass:[NSDictionary class]] ? value : defaultValue;
}

- (BOOL)enabled {
    return [self boolForKey:@"enabled" default:YES];
}

- (BOOL)autoRegion {
    return [self boolForKey:@"autoRegion" default:YES];
}

- (double)cacheTTL {
    double value = [self doubleForKey:@"cacheTTL" default:WS_DEFAULT_CACHE_TTL];
    return MAX(30.0, MIN(value, 21600.0));
}

- (double)requestTimeout {
    double value = [self doubleForKey:@"requestTimeout" default:WS_DEFAULT_REQUEST_TIMEOUT];
    return MAX(2.0, MIN(value, 30.0));
}

- (double)minRefreshInterval {
    double value = [self doubleForKey:@"minRefreshInterval" default:WS_DEFAULT_MIN_REFRESH_INTERVAL];
    return MAX(10.0, MIN(value, 3600.0));
}

- (NSInteger)logLevel {
    return MAX(0, MIN([self integerForKey:@"logLevel" default:2], 3));
}

- (NSString *)fallbackProvider {
    NSString *value = [self stringForKey:@"fallbackProvider" default:WS_DEFAULT_FALLBACK_PROVIDER];
    return value.length ? value : WS_DEFAULT_FALLBACK_PROVIDER;
}

- (NSString *)globalProvider {
    NSString *value = [self stringForKey:@"globalProvider" default:WS_PROVIDER_OPEN_METEO];
    return value.length ? value : WS_PROVIDER_OPEN_METEO;
}

- (NSString *)providerForRegion:(NSString *)region {
    if (!region.length) region = WS_REGION_OTHER;
    NSString *value = [self stringForKey:WSRegionProviderKey(region) default:WS_PROVIDER_AUTO];
    return value.length ? value : WS_PROVIDER_AUTO;
}

- (NSString *)overrideProviderForLatitude:(double)latitude longitude:(double)longitude {
    NSString *key = WSOverrideKey(latitude, longitude);
    NSString *value = [self stringForKey:key default:@""];
    return value.length ? value : nil;
}

- (NSString *)qweatherKey {
    return [self stringForKey:@"qweatherKey" default:@""];
}

- (NSString *)qweatherHost {
    NSString *host = [self stringForKey:@"qweatherHost" default:@"devapi.qweather.com"];
    host = [host stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!host.length) host = @"devapi.qweather.com";
    return host;
}

- (NSString *)cwaKey {
    return [self stringForKey:@"cwaKey" default:@""];
}

- (NSString *)kmaKey {
    return [self stringForKey:@"kmaKey" default:@""];
}

- (NSArray<NSDictionary *> *)recentLocations {
    NSArray *locations = [self arrayForKey:@"recentLocations" default:@[]];
    NSMutableArray *valid = [NSMutableArray array];
    for (id item in locations) {
        if ([item isKindOfClass:[NSDictionary class]]) [valid addObject:item];
    }
    return valid;
}

- (void)recordLocationLatitude:(double)latitude
                     longitude:(double)longitude
                       country:(NSString *)country
                      provider:(NSString *)provider
                          name:(NSString *)name {
    NSString *identity = [NSString stringWithFormat:@"%.2f,%.2f", latitude, longitude];
    NSMutableArray *locations = [[self recentLocations] mutableCopy];
    NSMutableDictionary *entry = [@{
        @"lat": @(latitude),
        @"lon": @(longitude),
        @"country": country ?: @"",
        @"provider": provider ?: @"",
        @"name": name.length ? name : identity,
        @"updated": @([[NSDate date] timeIntervalSince1970]),
    } mutableCopy];

    NSUInteger existing = NSNotFound;
    for (NSUInteger i = 0; i < locations.count; i++) {
        NSDictionary *item = locations[i];
        double lat = [item[@"lat"] doubleValue];
        double lon = [item[@"lon"] doubleValue];
        if (fabs(lat - latitude) < 0.011 && fabs(lon - longitude) < 0.011) {
            existing = i;
            if ([item[@"name"] isKindOfClass:[NSString class]] &&
                [item[@"name"] length] &&
                ![item[@"name"] isEqualToString:identity]) {
                entry[@"name"] = item[@"name"];
            }
            break;
        }
    }
    if (existing != NSNotFound) [locations removeObjectAtIndex:existing];
    [locations insertObject:entry atIndex:0];
    while (locations.count > WS_MAX_RECENT_LOCATIONS) [locations removeLastObject];
    [self setObject:locations forKey:@"recentLocations" notify:NO];
}

- (void)clearRecentLocations {
    [self setObject:@[] forKey:@"recentLocations" notify:NO];
}

- (NSArray<NSDictionary *> *)logEntries {
    NSArray *entries = [self arrayForKey:@"logEntries" default:@[]];
    NSMutableArray *valid = [NSMutableArray array];
    for (id item in entries) {
        if ([item isKindOfClass:[NSDictionary class]]) [valid addObject:item];
    }
    return valid;
}

- (void)appendLogEntry:(NSDictionary *)entry {
    if (!entry) return;
    NSMutableArray *entries = [[self logEntries] mutableCopy];
    [entries addObject:entry];
    while (entries.count > WS_MAX_LOG_ENTRIES) [entries removeObjectAtIndex:0];
    [self setObject:entries forKey:@"logEntries" notify:NO];
}

- (void)clearLog {
    [self setObject:@[] forKey:@"logEntries" notify:NO];
}

@end
