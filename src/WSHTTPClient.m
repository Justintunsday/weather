#import "WSHTTPClient.h"
#import "WSSettings.h"
#import "WSLogger.h"

@interface WSHTTPClient ()
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation WSHTTPClient

+ (instancetype)shared {
    static WSHTTPClient *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[WSHTTPClient alloc] init];
    });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        configuration.HTTPShouldSetCookies = NO;
        configuration.HTTPCookieStorage = nil;
        configuration.URLCache = [[NSURLCache alloc] initWithMemoryCapacity:0 diskCapacity:0 diskPath:nil];
        configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        configuration.waitsForConnectivity = NO;
        configuration.timeoutIntervalForRequest = 8.0;
        configuration.timeoutIntervalForResource = 12.0;
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (void)GETJSON:(NSURL *)url
        headers:(NSDictionary<NSString *, NSString *> *)headers
     completion:(WSHTTPJSONCompletion)completion {
    if (!url || !completion) return;
    [self performGETJSON:url headers:headers attempt:0 completion:completion];
}

- (void)performGETJSON:(NSURL *)url
               headers:(NSDictionary<NSString *, NSString *> *)headers
               attempt:(NSInteger)attempt
            completion:(WSHTTPJSONCompletion)completion {
    WSSettings *settings = [WSSettings shared];
    NSTimeInterval timeout = [settings requestTimeout];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:timeout];
    request.HTTPMethod = @"GET";
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"WeatherSource/0.1 (iOS)" forHTTPHeaderField:@"User-Agent"];
    for (NSString *key in headers) {
        [request setValue:headers[key] forHTTPHeaderField:key];
    }

    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                completionHandler:^(NSData *data,
                                                                    NSURLResponse *response,
                                                                    NSError *error) {
        NSHTTPURLResponse *http = [response isKindOfClass:[NSHTTPURLResponse class]] ? (NSHTTPURLResponse *)response : nil;
        NSInteger status = http.statusCode;
        BOOL retryable = (error != nil) || status == 429 || (status >= 500 && status <= 599);

        if (retryable && attempt < 2) {
            NSTimeInterval delay = (attempt == 0) ? 0.5 : 1.2;
            [WSLogger debug:@"HTTP retry %@ (attempt %ld, status %ld)", url.host, (long)(attempt + 1), (long)status];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                           dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                [self performGETJSON:url headers:headers attempt:attempt + 1 completion:completion];
            });
            return;
        }

        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, data, http, error); });
            return;
        }
        if (status < 200 || status >= 300) {
            NSError *statusError = [NSError errorWithDomain:@"com.weathersource.http"
                                                       code:status
                                                   userInfo:@{NSLocalizedDescriptionKey:
                                                                  [NSString stringWithFormat:@"HTTP %ld", (long)status]}];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, data, http, statusError); });
            return;
        }
        if (!data.length) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, data, http, nil); });
            return;
        }

        NSError *jsonError = nil;
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!json) {
                completion(nil, data, http, jsonError ?: [NSError errorWithDomain:@"com.weathersource.http"
                                                                              code:-1
                                                                          userInfo:@{NSLocalizedDescriptionKey: @"Invalid JSON"}]);
            } else {
                completion(json, data, http, nil);
            }
        });
    }];
    [task resume];
}

@end
