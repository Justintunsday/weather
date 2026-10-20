#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, WSLogLevel) {
    WSLogLevelError = 0,
    WSLogLevelWarning = 1,
    WSLogLevelInfo = 2,
    WSLogLevelDebug = 3,
};

@interface WSLogger : NSObject

+ (void)logLevel:(WSLogLevel)level format:(NSString *)format, ... NS_FORMAT_FUNCTION(2, 3);
+ (void)error:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
+ (void)warning:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
+ (void)info:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
+ (void)debug:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

+ (NSString *)logFilePath;
+ (void)clearFileLog;

@end
