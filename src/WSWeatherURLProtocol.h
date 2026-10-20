#import <Foundation/Foundation.h>

@interface WSWeatherURLProtocol : NSURLProtocol
+ (void)patchResponseData:(NSData *)data
                 response:(NSHTTPURLResponse *)response
                  request:(NSURLRequest *)request
               completion:(void (^)(NSData *, NSURLResponse *))completion;
@end
