#import <Foundation/Foundation.h>
#import "WSWeatherModel.h"

typedef NS_ENUM(NSInteger, WSResponseFormat) {
    WSResponseFormatUnknown = 0,
    WSResponseFormatJSON,
    WSResponseFormatFlatBuffer,
};

@interface WSWeatherResponsePatcher : NSObject

+ (WSResponseFormat)formatForData:(NSData *)data contentType:(NSString *)contentType;

+ (NSData *)patchData:(NSData *)data
          contentType:(NSString *)contentType
             snapshot:(WSWeatherSnapshot *)snapshot
        changedFields:(NSInteger *)changedFields
                error:(NSError **)error;

@end
