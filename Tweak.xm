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
    [WSLogger warning:@"URLSession BACKGROUND config in %@ id=%@", [[NSProcessInfo processInfo] processName], identifier ?: @"?"];
    return %orig;
}

- (NSArray *)protocolClasses {
    NSArray *classes = %orig;
    if (!classes) classes = @[];
    Class protocolClass = [WSWeatherURLProtocol class];
    if (![classes containsObject:protocolClass]) {
        return [classes arrayByAddingObject:protocolClass];
    }
    return classes;
}

%end

%hook NSURLSession

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completionHandler {
    if (WSIsWeatherRequest(request) && !WSIsForwardedRequest(request)) {
        [WSLogger info:@"NSURLSession completion task in %@: %@ %@",
                      [[NSProcessInfo processInfo] processName], request.HTTPMethod, request.URL.path];
    }
    return %orig;
}

- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    if (WSIsWeatherRequest(request) && !WSIsForwardedRequest(request)) {
        [WSLogger info:@"NSURLSession delegate task in %@: %@ %@",
                      [[NSProcessInfo processInfo] processName], request.HTTPMethod, request.URL.path];
    }
    return %orig;
}

%end

%ctor {
    @autoreleasepool {
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
