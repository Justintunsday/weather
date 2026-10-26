#import <Foundation/Foundation.h>
#import "WSHKOProvider.h"
#import "WSProviderRegistry.h"
#import "WSWeatherResponsePatcher.h"
#import "WSSettings.h"
#import "WSShared.h"
#import <stdlib.h>
#import <string.h>

static void Fail(NSString *message) {
    fprintf(stderr, "%s\n", message.UTF8String);
    exit(1);
}

static void WriteJSON(id object, NSString *path) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:&error];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:&error]) Fail(error.localizedDescription ?: @"Cannot write result");
}

static NSArray<NSString *> *TestSettingKeys(void) {
    return @[@"enabled", @"autoRegion", @"logLevel", WSRegionProviderKey(WS_REGION_HK)];
}

static void RestoreSettings(NSDictionary *backup) {
    WSSettings *settings = [WSSettings shared];
    if (backup.count < TestSettingKeys().count) Fail(@"Invalid test settings backup");
    for (NSString *key in TestSettingKeys()) if (!backup[key]) Fail(@"Incomplete test settings backup");
    for (NSString *key in backup) {
        if (![TestSettingKeys() containsObject:key] && ![key hasPrefix:@"ov_"]) Fail(@"Unexpected setting in backup");
        NSDictionary *entry = backup[key];
        if (![entry isKindOfClass:[NSDictionary class]]) Fail(@"Invalid test settings backup");
        id value = [entry[@"present"] boolValue] ? entry[@"value"] : nil;
        if (![settings saveSharedObject:value forKey:key]) Fail([@"Could not restore " stringByAppendingString:key]);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc == 3 && strcmp(argv[1], "--restore-settings") == 0) {
            RestoreSettings([NSDictionary dictionaryWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]]);
            puts("Original routing and log level restored");
            return 0;
        }
        if (argc == 5 && strcmp(argv[1], "--test-hko") == 0) {
            WSSettings *settings = [WSSettings shared];
            char *latitudeEnd = NULL, *longitudeEnd = NULL;
            double latitude = strtod(argv[3], &latitudeEnd), longitude = strtod(argv[4], &longitudeEnd);
            if (!argv[3][0] || *latitudeEnd || !argv[4][0] || *longitudeEnd || !isfinite(latitude) || !isfinite(longitude) || latitude < 22.13 || latitude > 22.60 || longitude < 113.80 || longitude > 114.52) Fail(@"HKO test requires Hong Kong coordinates");
            NSString *overrideKey = WSOverrideKey(latitude, longitude);
            NSArray *keys = [TestSettingKeys() arrayByAddingObject:overrideKey];
            NSString *backupPath = [NSString stringWithUTF8String:argv[2]];
            if ([[NSFileManager defaultManager] fileExistsAtPath:backupPath]) Fail(@"Backup already exists; restore it before another test");
            NSMutableDictionary *backup = [NSMutableDictionary dictionary];
            for (NSString *key in keys) {
                id value = [settings objectForKey:key default:nil];
                backup[key] = value ? @{@"present": @YES, @"value": value} : @{@"present": @NO};
            }
            if (![backup writeToFile:backupPath atomically:YES]) Fail(@"Cannot save original settings");
            [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:backupPath error:nil];
            NSDictionary *testValues = @{@"enabled": @YES, @"autoRegion": @YES, @"logLevel": @3, WSRegionProviderKey(WS_REGION_HK): WS_PROVIDER_HKO, overrideKey: WS_PROVIDER_HKO};
            for (NSString *key in keys) {
                if (![settings saveSharedObject:testValues[key] forKey:key]) {
                    RestoreSettings(backup);
                    Fail([@"Cannot enable HKO test setting " stringByAppendingString:key]);
                }
            }
            puts("HKO enabled temporarily for Hong Kong; original settings saved");
            return 0;
        }
        if (argc == 2 && strcmp(argv[1], "--settings") == 0) {
            // Report only non-sensitive routing settings, never credentials.
            WSSettings *settings = [WSSettings shared];
            NSDictionary *result = @{@"enabled": @(settings.enabled), @"autoRegion": @(settings.autoRegion), @"globalProvider": settings.globalProvider, @"hongKongProvider": [settings providerForRegion:WS_REGION_HK], @"logLevel": @(settings.logLevel), @"hongKongResolution": [WSProviderRegistry resolutionForLatitude:22.301944 longitude:114.174167 countryFromURL:nil]};
            NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:nil];
            puts([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
            return 0;
        }
        if (argc != 4 && argc != 6) {
            fprintf(stderr, "Usage: hko-device-probe latitude longitude snapshot.json [apple.json patched.json]\n       hko-device-probe --settings\n       hko-device-probe --test-hko backup.plist latitude longitude\n       hko-device-probe --restore-settings backup.plist\n");
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
