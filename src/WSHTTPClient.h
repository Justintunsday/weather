#import <Foundation/Foundation.h>

typedef void (^WSHTTPJSONCompletion)(id _Nullable json,
                                     NSData * _Nullable data,
                                     NSHTTPURLResponse * _Nullable response,
                                     NSError * _Nullable error);

@interface WSHTTPClient : NSObject

+ (instancetype)shared;

- (void)GETJSON:(NSURL *)url
        headers:(NSDictionary<NSString *, NSString *> *)headers
     completion:(WSHTTPJSONCompletion)completion;

@end
