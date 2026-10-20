#import "WSWeatherURLProtocol.h"
#import "WSWeatherResponsePatcher.h"
#import "WSProviderRegistry.h"
#import "WSFetchCoordinator.h"
#import "WSRegionResolver.h"
#import "WSSettings.h"
#import "WSLogger.h"
#import "WSShared.h"

#import <math.h>
#import <stdlib.h>
#import <unistd.h>

static NSString *const WSForwardedPropertyKey = @"com.weathersource.forwarded";
static NSString *const WSForwardedHeader = @"X-WeatherSource-Forwarded";

static BOOL WSParseCoordinate(NSString *string, double *value) {
    if (![string isKindOfClass:[NSString class]] || !string.length) return NO;
    const char *cString = string.UTF8String;
    if (!cString) return NO;
    char *end = NULL;
    double parsed = strtod(cString, &end);
    if (end == cString || (end && *end != '\0') || !isfinite(parsed)) return NO;
    *value = parsed;
    return YES;
}

static NSDictionary *WSParseWeatherURL(NSURL *url) {
    if (![url isKindOfClass:[NSURL class]]) return nil;
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"https"] && ![scheme isEqualToString:@"http"]) return nil;
    NSString *host = url.host.lowercaseString;
    if (![host isEqualToString:@"weatherkit.apple.com"] && ![host isEqualToString:@"weather-data.apple.com"]) return nil;

    NSMutableArray<NSString *> *components = [NSMutableArray array];
    for (NSString *component in url.pathComponents) {
        if (component.length && ![component isEqualToString:@"/"]) [components addObject:component];
    }
    NSUInteger weatherIndex = NSNotFound;
    for (NSUInteger i = 0; i < components.count; i++) {
        if ([components[i] isEqualToString:@"weather"]) {
            weatherIndex = i;
            break;
        }
    }
    if (weatherIndex == NSNotFound) return nil;

    NSMutableArray<NSNumber *> *numeric = [NSMutableArray array];
    NSMutableArray<NSNumber *> *numericIndexes = [NSMutableArray array];
    for (NSUInteger i = weatherIndex + 1; i < components.count; i++) {
        double value = 0;
        if (WSParseCoordinate(components[i], &value)) {
            [numeric addObject:@(value)];
            [numericIndexes addObject:@(i)];
        }
    }
    if (numeric.count < 2) return nil;
    double latitude = numeric[numeric.count - 2].doubleValue;
    double longitude = numeric[numeric.count - 1].doubleValue;
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return nil;

    NSUInteger firstCoordinateIndex = numericIndexes[numeric.count - 2].unsignedIntegerValue;
    NSString *locale = nil;
    if (firstCoordinateIndex > weatherIndex + 1) {
        NSString *candidate = components[firstCoordinateIndex - 1];
        double ignored = 0;
        if (!WSParseCoordinate(candidate, &ignored)) locale = candidate;
    }

    NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *country = nil;
    NSArray<NSString *> *dataSets = @[];
    for (NSURLQueryItem *item in urlComponents.queryItems) {
        if ([item.name isEqualToString:@"country"] && item.value.length) country = item.value.uppercaseString;
        if ([item.name isEqualToString:@"dataSets"] && item.value.length) {
            dataSets = [item.value componentsSeparatedByString:@","];
        }
    }

    // Locale describes presentation language, not the queried city's country.
    // For example, en-US is also used when requesting mainland Chinese cities.

    NSString *version = nil;
    if (weatherIndex > 0) {
        NSString *candidate = components[weatherIndex - 1];
        if ([candidate.lowercaseString hasPrefix:@"v"]) version = candidate.lowercaseString;
    }

    return @{
        @"latitude": @(latitude),
        @"longitude": @(longitude),
        @"locale": locale ?: @"en",
        @"country": country ?: @"",
        @"version": version ?: @"",
        @"dataSets": dataSets,
    };
}

@interface WSWeatherURLProtocol ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, strong) dispatch_queue_t deliveryQueue;
@property (nonatomic, strong) dispatch_semaphore_t providerSemaphore;
@property (nonatomic, strong) WSWeatherSnapshot *providerSnapshot;
@property (nonatomic) BOOL stopped;
@property (nonatomic, copy) NSString *providerID;
@end

@implementation WSWeatherURLProtocol

+ (void)patchResponseData:(NSData *)data
                 response:(NSHTTPURLResponse *)response
                  request:(NSURLRequest *)request
               completion:(void (^)(NSData *, NSURLResponse *))completion {
    NSDictionary *info = WSParseWeatherURL(request.URL);
    if (!info || !data.length || response.statusCode < 200 || response.statusCode >= 300 ||
        [response valueForHTTPHeaderField:@"X-WeatherSource-Provider"].length || ![WSSettings shared].enabled) {
        completion(data, response);
        return;
    }
    double latitude = [info[@"latitude"] doubleValue];
    double longitude = [info[@"longitude"] doubleValue];
    NSDictionary *resolution = [WSProviderRegistry resolutionForLatitude:latitude longitude:longitude countryFromURL:info[@"country"]];
    NSString *provider = resolution[@"provider"];
    if ([provider isEqualToString:WS_PROVIDER_APPLE]) {
        completion(data, response);
        return;
    }
    [WSLogger info:@"Completion fallback %@ region=%@ provider=%@ bytes=%lu type=%@",
                  request.URL.path, resolution[@"region"], provider, (unsigned long)data.length, response.MIMEType];
    NSObject *guard = [NSObject new];
    __block BOOL delivered = NO;
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_UTILITY, 0);
    void (^finish)(WSWeatherSnapshot *) = ^(WSWeatherSnapshot *snapshot) {
        @synchronized (guard) {
            if (delivered) return;
            delivered = YES;
        }
        dispatch_async(queue, ^{
            NSInteger changed = 0;
            NSError *error = nil;
            NSData *patched = snapshot.hasAnyData ? [WSWeatherResponsePatcher patchData:data contentType:response.MIMEType snapshot:snapshot changedFields:&changed error:&error] : nil;
            if (patched && changed > 0 && [WSSettings shared].enabled) {
                NSMutableDictionary *headers = [response.allHeaderFields mutableCopy];
                for (NSString *key in [headers.allKeys copy]) {
                    NSString *lower = key.lowercaseString;
                    if ([lower isEqualToString:@"content-length"] || [lower isEqualToString:@"content-encoding"] || [lower isEqualToString:@"transfer-encoding"]) [headers removeObjectForKey:key];
                }
                headers[@"Content-Length"] = @(patched.length).stringValue;
                headers[@"X-WeatherSource-Provider"] = provider;
                NSHTTPURLResponse *updated = [[NSHTTPURLResponse alloc] initWithURL:response.URL statusCode:response.statusCode HTTPVersion:@"HTTP/1.1" headerFields:headers];
                [WSLogger info:@"Patched completion %@: %ld fields via %@", request.URL.path, (long)changed, provider];
                completion(patched, updated);
            } else {
                [WSLogger warning:@"Completion fallback unchanged %@: %@", request.URL.path, error.localizedDescription ?: (snapshot ? @"no matching fields" : @"provider unavailable or deadline")];
                completion(data, response);
            }
        });
    };
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), queue, ^{ finish(nil); });
    [[WSFetchCoordinator shared] fetchSnapshotForProviderID:provider latitude:latitude longitude:longitude locale:info[@"locale"] completion:^(WSWeatherSnapshot *snapshot, NSError *error) {
        finish(snapshot);
    }];
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (!request || !request.URL) return NO;
    if ([NSURLProtocol propertyForKey:WSForwardedPropertyKey inRequest:request]) return NO;
    if ([[request valueForHTTPHeaderField:WSForwardedHeader] length]) return NO;
    BOOL result = WSParseWeatherURL(request.URL) != nil;
    NSString *host = request.URL.host.lowercaseString;
    if ([host isEqualToString:@"weather-data.apple.com"] || [host isEqualToString:@"weatherkit.apple.com"]) {
        [WSLogger info:@"canInit host=%@ path=%@ result=%d", host, request.URL.path, result];
    }
    return result;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (instancetype)initWithRequest:(NSURLRequest *)request
                 cachedResponse:(NSCachedURLResponse *)cachedResponse
                         client:(id<NSURLProtocolClient>)client {
    self = [super initWithRequest:request cachedResponse:cachedResponse client:client];
    if (self) {
        _deliveryQueue = dispatch_queue_create("com.weathersource.urlprotocol", DISPATCH_QUEUE_SERIAL);
        _stopped = NO;
    }
    return self;
}

- (void)startLoading {
    NSURLRequest *originalRequest = self.request;
    NSDictionary *info = WSParseWeatherURL(originalRequest.URL);
    if (!info) {
        [self.client URLProtocol:self didFailWithError:WSProviderError(-30, @"Not a weather request")];
        return;
    }

    double latitude = [info[@"latitude"] doubleValue];
    double longitude = [info[@"longitude"] doubleValue];
    NSString *country = info[@"country"];
    NSString *locale = info[@"locale"];
    NSDictionary *resolution = [WSProviderRegistry resolutionForLatitude:latitude
                                                              longitude:longitude
                                                         countryFromURL:country];
    NSString *providerID = resolution[@"provider"] ?: WS_PROVIDER_APPLE;
    NSString *region = resolution[@"region"] ?: WS_REGION_OTHER;
    self.providerID = providerID;

    static NSMutableDictionary<NSString *, NSNumber *> *lastRecorded = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ lastRecorded = [NSMutableDictionary dictionary]; });
    NSString *recordKey = [NSString stringWithFormat:@"%@-%.2f-%.2f", providerID, latitude, longitude];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    BOOL shouldRecord = NO;
    @synchronized (lastRecorded) {
        NSTimeInterval last = [lastRecorded[recordKey] doubleValue];
        if (now - last > 600.0) {
            lastRecorded[recordKey] = @(now);
            shouldRecord = YES;
        }
    }
    if (shouldRecord) {
        [[WSSettings shared] recordLocationLatitude:latitude
                                          longitude:longitude
                                            country:region
                                           provider:providerID
                                               name:nil];
    }
    [WSLogger info:@"Weather request %@ region=%@ requested=%@ provider=%@",
                  originalRequest.URL.path, region, resolution[@"requested"] ?: @"", providerID];

    self.providerSemaphore = dispatch_semaphore_create(0);

    if (![providerID isEqualToString:WS_PROVIDER_APPLE]) {
        __weak typeof(self) weakSelf = self;
        [[WSFetchCoordinator shared] fetchSnapshotForProviderID:providerID
                                                       latitude:latitude
                                                      longitude:longitude
                                                         locale:locale
                                                     completion:^(WSWeatherSnapshot *snapshot, NSError *error) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (error && !snapshot) {
                [WSLogger warning:@"Provider %@ failed for %.3f,%.3f: %@", providerID, latitude, longitude,
                                  error.localizedDescription ?: @"unknown"];
            }
            @synchronized (strongSelf) {
                strongSelf.providerSnapshot = snapshot;
            }
            dispatch_semaphore_signal(strongSelf.providerSemaphore);
        }];
    } else {
        dispatch_semaphore_signal(self.providerSemaphore);
    }

    NSMutableURLRequest *forward = [originalRequest mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:WSForwardedPropertyKey inRequest:forward];
    [forward setValue:@"1" forHTTPHeaderField:WSForwardedHeader];

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = [WSSettings shared].requestTimeout;
    configuration.timeoutIntervalForResource = [WSSettings shared].requestTimeout + 5.0;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.HTTPShouldSetCookies = NO;
    configuration.HTTPCookieStorage = nil;

    self.session = [NSURLSession sessionWithConfiguration:configuration];
    __weak typeof(self) weakSelf = self;
    self.task = [self.session dataTaskWithRequest:forward completionHandler:^(NSData *data,
                                                                               NSURLResponse *response,
                                                                               NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.stopped) return;
        if (error) {
            [strongSelf finishWithError:error];
            return;
        }
        if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
            [strongSelf deliverResponse:response data:data providerID:nil changed:0];
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if ([[WSSettings shared] logLevel] >= 3 && data.length) {
            static NSInteger dumpCount = 0;
            NSInteger dumpIndex = -1;
            @synchronized ([WSWeatherURLProtocol class]) {
                if (dumpCount < 3) {
                    dumpIndex = dumpCount;
                    dumpCount++;
                }
            }
            if (dumpIndex >= 0) {
                NSString *base = [NSString stringWithFormat:@"/var/mobile/Library/Weather/WeatherSource-response-%d-%ld", getpid(), (long)dumpIndex];
                [data writeToFile:[base stringByAppendingString:@".bin"] atomically:YES];
                [httpResponse.MIMEType writeToFile:[base stringByAppendingString:@".type.txt"]
                                        atomically:YES
                                          encoding:NSUTF8StringEncoding
                                             error:nil];
                [httpResponse.URL.absoluteString writeToFile:[base stringByAppendingString:@".url.txt"]
                                                 atomically:YES
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
                [WSLogger info:@"Dumped response %ld (%lu bytes, type=%@) to %@.bin",
                              (long)dumpIndex, (unsigned long)data.length, httpResponse.MIMEType, base];
            }
        }
        dispatch_async(strongSelf.deliveryQueue, ^{
            if (strongSelf.stopped) return;
            WSWeatherSnapshot *snapshot = nil;
            if (![strongSelf.providerID isEqualToString:WS_PROVIDER_APPLE]) {
                dispatch_semaphore_wait(strongSelf.providerSemaphore,
                                        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)));
                @synchronized (strongSelf) {
                    snapshot = strongSelf.providerSnapshot;
                }
            }
            if (strongSelf.stopped) return;

            NSInteger changed = 0;
            NSData *patched = data;
            if (snapshot.hasAnyData) {
                NSError *patchError = nil;
                NSData *candidate = [WSWeatherResponsePatcher patchData:data
                                                           contentType:httpResponse.MIMEType
                                                              snapshot:snapshot
                                                         changedFields:&changed
                                                                 error:&patchError];
                if (candidate && changed > 0) {
                    patched = candidate;
                    [WSLogger info:@"Patched %@: %ld fields via %@", httpResponse.URL.path, (long)changed,
                                  snapshot.providerID];
                } else if (patchError) {
                    [WSLogger warning:@"Patch skipped for %@: %@", httpResponse.URL.path,
                                      patchError.localizedDescription];
                } else {
                    [WSLogger warning:@"Patch produced no changes for %@ (schema mismatch?)", httpResponse.URL.path];
                }
            }
            [strongSelf deliverResponse:httpResponse
                                   data:patched
                             providerID:(changed > 0 ? strongSelf.providerID : nil)
                                changed:changed];
        });
    }];
    [self.task resume];
}

- (void)finishWithError:(NSError *)error {
    dispatch_async(self.deliveryQueue, ^{
        if (self.stopped) return;
        [self.client URLProtocol:self didFailWithError:error];
        self.stopped = YES;
        [self.session finishTasksAndInvalidate];
    });
}

- (void)deliverResponse:(NSURLResponse *)response data:(NSData *)data providerID:(NSString *)providerID changed:(NSInteger)changed {
    dispatch_async(self.deliveryQueue, ^{
        if (self.stopped) return;
        self.stopped = YES;

        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        NSMutableDictionary *headers = [NSMutableDictionary dictionary];
        if (http) {
            [headers addEntriesFromDictionary:http.allHeaderFields];
            [headers removeObjectForKey:@"Content-Encoding"];
            [headers removeObjectForKey:@"content-encoding"];
            [headers removeObjectForKey:@"Content-Length"];
            [headers removeObjectForKey:@"content-length"];
            [headers removeObjectForKey:@"Transfer-Encoding"];
            [headers removeObjectForKey:@"transfer-encoding"];
            if (!headers[@"Content-Type"] && !headers[@"content-type"]) {
                NSString *type = data.length && ((const uint8_t *)data.bytes)[0] == '{'
                    ? @"application/json"
                    : @"application/vnd.apple.flatbuffer";
                headers[@"Content-Type"] = type;
            }
            if (data.length) headers[@"Content-Length"] = [NSString stringWithFormat:@"%lu", (unsigned long)data.length];
            if (providerID.length && changed > 0) headers[@"X-WeatherSource-Provider"] = providerID;
        }

        NSURLResponse *deliveredResponse = http
            ? [[NSHTTPURLResponse alloc] initWithURL:http.URL
                                          statusCode:http.statusCode
                                         HTTPVersion:@"HTTP/1.1"
                                        headerFields:headers]
            : response;

        [self.client URLProtocol:self didReceiveResponse:deliveredResponse cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        if (data.length) [self.client URLProtocol:self didLoadData:data];
        [self.client URLProtocolDidFinishLoading:self];
        [self.session finishTasksAndInvalidate];
    });
}

- (void)stopLoading {
    self.stopped = YES;
    [self.task cancel];
    [self.session invalidateAndCancel];
    if (self.providerSemaphore) dispatch_semaphore_signal(self.providerSemaphore);
}

@end


