#import "WSLogger.h"
#import "WSSettings.h"

@interface WSLogger ()
+ (void)appendLineToFile:(NSString *)line;
@end

static NSString *WSLogLevelName(WSLogLevel level) {
    switch (level) {
        case WSLogLevelError: return @"ERROR";
        case WSLogLevelWarning: return @"WARN";
        case WSLogLevelInfo: return @"INFO";
        case WSLogLevelDebug: return @"DEBUG";
    }
    return @"INFO";
}

@implementation WSLogger

+ (void)logLevel:(WSLogLevel)level format:(NSString *)format, ... {
    if (!format.length) return;
    WSSettings *settings = [WSSettings shared];
    if (level > [settings logLevel]) return;

    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSString *line = [NSString stringWithFormat:@"[%@] %@", WSLogLevelName(level), message];
    NSLog(@"[WeatherSource] %@", line);

    NSDictionary *entry = @{
        @"time": @([[NSDate date] timeIntervalSince1970]),
        @"level": @(level),
        @"message": message ?: @"",
    };
    [settings appendLogEntry:entry];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self appendLineToFile:line];
    });
}

+ (void)error:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logLevel:WSLogLevelError format:@"%@", message];
}

+ (void)warning:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logLevel:WSLogLevelWarning format:@"%@", message];
}

+ (void)info:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logLevel:WSLogLevelInfo format:@"%@", message];
}

+ (void)debug:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self logLevel:WSLogLevelDebug format:@"%@", message];
}

+ (NSString *)logFilePath {
    return @"/tmp/WeatherSource.log";
}

+ (void)appendLineToFile:(NSString *)line {
    NSString *path = [self logFilePath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        [fm createFileAtPath:path contents:[NSData data] attributes:nil];
    }
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    if ([attrs[NSFileSize] unsignedLongLongValue] > 512 * 1024) {
        [fm removeItemAtPath:path error:nil];
        [fm createFileAtPath:path contents:[NSData data] attributes:nil];
    }
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) return;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *stamped = [NSString stringWithFormat:@"%@ %@\n", [formatter stringFromDate:[NSDate date]], line];
    @try {
        [handle seekToEndOfFile];
        [handle writeData:[stamped dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    } @catch (__unused NSException *exception) {
        [handle closeFile];
    }
}

+ (void)clearFileLog {
    [[NSFileManager defaultManager] removeItemAtPath:[self logFilePath] error:nil];
}

@end

