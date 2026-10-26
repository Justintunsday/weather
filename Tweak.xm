#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

#import "WSWeatherURLProtocol.h"
#import "WSLogger.h"
#import "WSSettings.h"
#import "WSCache.h"
#import "WSShared.h"

static void WSRefreshNotificationCallback(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;
    [[WSCache shared] removeAll];
}

static BOOL WSIsWeatherRequest(NSURLRequest *request) {
    NSString *host = request.URL.host.lowercaseString;
    if (!host.length) return NO;
    if ([host isEqualToString:@"weather-data.apple.com"] || [host isEqualToString:@"weatherkit.apple.com"]) return YES;
    return [host containsString:@"weather-data.apple.com"] || [host containsString:@"weatherkit.apple.com"];
}

static BOOL WSIsForwardedRequest(NSURLRequest *request) {
    if ([NSURLProtocol propertyForKey:@"com.weathersource.forwarded" inRequest:request]) return YES;
    return [[request valueForHTTPHeaderField:@"X-WeatherSource-Forwarded"] length] > 0;
}

static void WSAddProtocolToConfiguration(NSURLSessionConfiguration *configuration) {
    if (!configuration) return;
    NSMutableArray *classes = [[configuration protocolClasses] mutableCopy];
    if (!classes) classes = [NSMutableArray array];
    Class protocolClass = [WSWeatherURLProtocol class];
    [classes removeObject:protocolClass];
    [classes insertObject:protocolClass atIndex:0];
    // The getter hook can synthesize the class without updating the backing config.
    // Always persist the returned list before NSURLSession copies its internals.
    configuration.protocolClasses = classes;
    [WSLogger info:@"Prepared URLSession config in %@ classes=%lu",
                  [[NSProcessInfo processInfo] processName], (unsigned long)configuration.protocolClasses.count];
}

%hook NSURLSessionConfiguration

+ (NSURLSessionConfiguration *)defaultSessionConfiguration {
    NSURLSessionConfiguration *configuration = %orig;
    [WSLogger info:@"URLSession default config created in %@", [[NSProcessInfo processInfo] processName]];
    return configuration;
}

+ (NSURLSessionConfiguration *)ephemeralSessionConfiguration {
    NSURLSessionConfiguration *configuration = %orig;
    [WSLogger info:@"URLSession ephemeral config created in %@", [[NSProcessInfo processInfo] processName]];
    return configuration;
}

+ (NSURLSessionConfiguration *)backgroundSessionConfigurationWithIdentifier:(NSString *)identifier {
    if (![[WSSettings shared] boolForKey:@"debugConvertBackgroundSessions" default:NO]) return %orig;
    [WSLogger warning:@"Converting BACKGROUND URLSession in %@ id=%@ to ephemeral", [[NSProcessInfo processInfo] processName], identifier ?: @"?"];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 20.0;
    configuration.timeoutIntervalForResource = 60.0;
    configuration.HTTPShouldSetCookies = NO;
    configuration.HTTPCookieStorage = nil;
    return configuration;
}

- (NSArray *)protocolClasses {
    NSArray *classes = %orig;
    if (!classes) classes = @[];
    Class protocolClass = [WSWeatherURLProtocol class];
    NSMutableArray *ordered = [classes mutableCopy];
    [ordered removeObject:protocolClass];
    [ordered insertObject:protocolClass atIndex:0];
    return ordered;
}

%end

%hook NSURLSession

+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration {
    WSAddProtocolToConfiguration(configuration);
    return %orig;
}

+ (NSURLSession *)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration
                                  delegate:(id)delegate
                             delegateQueue:(NSOperationQueue *)queue {
    WSAddProtocolToConfiguration(configuration);
    return %orig;
}

- (instancetype)initWithConfiguration:(NSURLSessionConfiguration *)configuration
                             delegate:(id)delegate
                        delegateQueue:(NSOperationQueue *)queue {
    WSAddProtocolToConfiguration(configuration);
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (WSIsWeatherRequest(request) && !WSIsForwardedRequest(request)) {
        [WSLogger info:@"NSURLSession completion task in %@: %@ host=%@ path=%@",
                      [[NSProcessInfo processInfo] processName], request.HTTPMethod, request.URL.host, request.URL.path];
        if (completionHandler) {
            void (^originalCompletion)(NSData *, NSURLResponse *, NSError *) = [completionHandler copy];
            return %orig(request, ^(NSData *data, NSURLResponse *response, NSError *error) {
                if (error || ![response isKindOfClass:[NSHTTPURLResponse class]]) {
                    originalCompletion(data, response, error);
                    return;
                }
                [WSWeatherURLProtocol patchResponseData:data response:(NSHTTPURLResponse *)response request:request completion:^(NSData *patched, NSURLResponse *updated) {
                    originalCompletion(patched, updated, nil);
                }];
            });
        }
    }
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (WSIsWeatherRequest(request) && !WSIsForwardedRequest(request)) {
        [WSLogger info:@"NSURLSession delegate task in %@: %@ host=%@ path=%@",
                      [[NSProcessInfo processInfo] processName], request.HTTPMethod, request.URL.host, request.URL.path];
    }
    return %orig;
}

%end

%ctor {
    @autoreleasepool {
        NSString *processName = [[NSProcessInfo processInfo] processName] ?: @"?";
        NSLog(@"[WeatherSource] CTOR pid=%d process=%@ version=%@", getpid(), processName, @WS_VERSION);
        NSString *marker = [NSString stringWithFormat:@"pid=%d process=%@ version=%@ date=%@\n",
                            getpid(), processName, @WS_VERSION, [NSDate date]];
        NSArray<NSString *> *markerPaths = @[
            @"/var/mobile/Library/Weather/WeatherSource-ctor.txt",
            [NSTemporaryDirectory() stringByAppendingPathComponent:@"WeatherSource-ctor.txt"] ?: @"/tmp/WeatherSource-ctor.txt"
        ];
        for (NSString *path in markerPaths) {
            [marker writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        [NSURLProtocol registerClass:[WSWeatherURLProtocol class]];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        WSRefreshNotificationCallback,
                                        CFSTR(WS_NOTIFY_SETTINGS_CHANGED),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        WSRefreshNotificationCallback,
                                        CFSTR(WS_NOTIFY_REFRESH_REQUESTED),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        [WSLogger info:@"WeatherSource %@ loaded in %@", @WS_VERSION,
                       [[NSProcessInfo processInfo] processName]];
    }
}
