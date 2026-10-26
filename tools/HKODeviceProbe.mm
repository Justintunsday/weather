#import <Foundation/Foundation.h>
#import "WSHKOProvider.h"
#import "WSProviderRegistry.h"
#import "WSWeatherResponsePatcher.h"
#import "WSSettings.h"
#import "WSShared.h"
#import <stdlib.h>

static void Fail(NSString *message) {
    fprintf(stderr, "%s\n", message.UTF8String);
    exit(1);
}

static void WriteJSON(id object, NSString *path) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&error]) Fail(error.localizedDescription ?: @"Cannot write result");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--settings") == 0) {
            // Report only non-sensitive routing settings, never credentials.
            WSSettings *settings = [WSSettings shared];
            NSDictionary *result = @{@"enabled": @(settings.enabled), @"autoRegion": @(settings.autoRegion), @"globalProvider": settings.globalProvider, @"hongKongProvider": [settings providerForRegion:WS_REGION_HK], @"logLevel": @(settings.logLevel), @"hongKongResolution": [WSProviderRegistry resolutionForLatitude:22.485 longitude:114.141 countryFromURL:nil]};
            NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
            puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
            return 0;
        }
        if (argc != 4 && argc != 6) {
            fprintf(stderr, "Usage: hko-device-probe latitude longitude snapshot.json [apple.json patched.json]\n       hko-device-probe --settings\n");
            return 2;
        }
        char *endLatitude = NULL, *endLongitude = NULL;
        double latitude = strtod(argv[1], &endLatitude), longitude = strtod(argv[2], &endLongitude);
        if (!argv[1][0] || *endLatitude || !argv[2][0] || *endLongitude) Fail(@"Invalid coordinates");
        NSString *snapshotPath = [NSString stringWithUTF8String:argv[3]];
        NSString *applePath = argc == 6 ? [NSString stringWithUTF8String:argv[4]] : nil;
        NSString *patchedPath = argc == 6 ? [NSString stringWithUTF8String:argv[5]] : nil;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 45*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ Fail(@"HKO probe exceeded 45-second deadline"); });
        [[WSHKOProvider new] fetchSnapshotForLatitude:latitude longitude:longitude locale:@"zh-Hant" completion:^(WSWeatherSnapshot *snapshot, NSError *error) {
            if (!snapshot.hasAnyData) Fail(error.localizedDescription ?: @"No usable HKO data");
            WriteJSON(snapshot.dictionaryRepresentation, snapshotPath);
            NSLog(@"HKO live fetch: %@", snapshot.summary);
            if (applePath) {
                NSData *apple = [NSData dataWithContentsOfFile:applePath];
                if (!apple) Fail(@"Cannot read Apple response");
                NSInteger changed = 0; NSError *patchError = nil;
                NSData *patched = [WSWeatherResponsePatcher patchData:apple contentType:@"application/json" snapshot:snapshot changedFields:&changed error:&patchError];
                if (!patched || patchError || !changed) Fail(patchError.localizedDescription ?: @"Apple response had no matching HKO fields");
                if (![patched writeToFile:patchedPath options:NSDataWritingAtomic error:&patchError]) Fail(patchError.localizedDescription);
                NSLog(@"HKO live response patch: %ld fields", (long)changed);
            }
            exit(0);
        }];
    }
    dispatch_main();
}
