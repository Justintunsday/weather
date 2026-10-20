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

%hook NSURLSessionConfiguration

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
    if ([[WSSettings shared] logLevel] >= 3 && request.URL.host.length) {
        NSString *host = request.URL.host.lowercaseString;
        if ([host containsString:@"weather"]) {
            [WSLogger debug:@"NSURLSession task: %@ %@", request.HTTPMethod, request.URL.path];
        }
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
