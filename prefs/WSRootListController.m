#import "WSRootListController.h"
#import "WSLogController.h"
#import "WSSettings.h"
#import "WSShared.h"
#import <CoreFoundation/CoreFoundation.h>

static NSArray<NSString *> *WSProviderValues(void) {
    return @[WS_PROVIDER_AUTO, WS_PROVIDER_APPLE, WS_PROVIDER_OPEN_METEO, WS_PROVIDER_QWEATHER,
             WS_PROVIDER_HKO, WS_PROVIDER_SMG, WS_PROVIDER_CWA, WS_PROVIDER_NWS, WS_PROVIDER_JMA,
             WS_PROVIDER_KMA];
}

static NSArray<NSString *> *WSProviderTitles(void) {
    return @[@"自动", @"Apple Weather（原生）", @"Open-Meteo", @"和风天气 QWeather",
             @"香港天文台 HKO（尚未接入）", @"澳门 SMG（尚未接入）", @"台湾 CWA（尚未接入）",
             @"美国 NOAA/NWS（尚未接入）", @"日本气象厅 JMA（尚未接入）", @"韩国气象厅 KMA（尚未接入）"];
}

static PSSpecifier *WSProviderSpecifier(NSString *name, NSString *key, id target) {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                             target:target
                                                                set:nil
                                                                get:nil
                                                             detail:[PSListItemsController class]
                                                               cell:@"PSLinkCell"
                                                               edit:nil];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:WS_PREF_DOMAIN forKey:@"defaults"];
    [specifier setProperty:WSProviderValues() forKey:@"values"];
    [specifier setProperty:WSProviderTitles() forKey:@"titles"];
    [specifier setProperty:WS_PROVIDER_AUTO forKey:@"default"];
    return specifier;
}

static PSSpecifier *WSTextSpecifier(NSString *name, NSString *key, NSString *placeholder, id defaultValue) {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                             target:nil
                                                                set:nil
                                                                get:nil
                                                             detail:nil
                                                               cell:@"PSEditTextCell"
                                                               edit:nil];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:WS_PREF_DOMAIN forKey:@"defaults"];
    [specifier setProperty:placeholder ?: @"" forKey:@"placeholder"];
    [specifier setProperty:defaultValue ?: @"" forKey:@"default"];
    return specifier;
}

@implementation WSRootListController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

- (NSArray *)specifiers {
    WSSettings *settings = [WSSettings shared];
    NSMutableArray *specifiers = [NSMutableArray array];

    PSSpecifier *intro = [PSSpecifier groupSpecifierWithName:@"WeatherSource"];
    [intro setProperty:@"根据天气 App 当前查询地点的经纬度，自动选择 Open-Meteo / QWeather 等数据源。"
             forKey:@"footerText"];
    [specifiers addObject:intro];

    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"启用插件"
                                                          target:self
                                                             set:@selector(setPreferenceValue:specifier:)
                                                             get:@selector(readPreferenceValue:)
                                                          detail:nil
                                                            cell:@"PSSwitchCell"
                                                            edit:nil];
    [enabled setProperty:@"enabled" forKey:@"key"];
    [enabled setProperty:@YES forKey:@"default"];
    [specifiers addObject:enabled];

    PSSpecifier *autoRegion = [PSSpecifier preferenceSpecifierNamed:@"自动识别地区"
                                                             target:self
                                                                set:@selector(setPreferenceValue:specifier:)
                                                                get:@selector(readPreferenceValue:)
                                                             detail:nil
                                                               cell:@"PSSwitchCell"
                                                               edit:nil];
    [autoRegion setProperty:@"autoRegion" forKey:@"key"];
    [autoRegion setProperty:@YES forKey:@"default"];
    [specifiers addObject:autoRegion];

    PSSpecifier *regionGroup = [PSSpecifier groupSpecifierWithName:@"地区默认数据源"];
    [regionGroup setProperty:@"当没有城市级覆盖时使用。中国大陆在配置 QWeather Key 后默认使用和风天气，否则回退 Open-Meteo。"
                   forKey:@"footerText"];
    [specifiers addObject:regionGroup];

    NSArray<NSString *> *regions = @[WS_REGION_CN, WS_REGION_HK, WS_REGION_MO, WS_REGION_TW,
                                     WS_REGION_US, WS_REGION_JP, WS_REGION_KR, WS_REGION_OTHER];
    for (NSString *region in regions) {
        NSString *configured = [settings providerForRegion:region];
        NSString *shortName = [configured isEqualToString:WS_PROVIDER_AUTO]
            ? @"自动"
            : WSProviderShortName(configured);
        NSString *label = [NSString stringWithFormat:@"%@  ·  %@", WSRegionDisplayName(region), shortName];
        [specifiers addObject:WSProviderSpecifier(label, WSRegionProviderKey(region), nil)];
    }

    PSSpecifier *locationGroup = [PSSpecifier groupSpecifierWithName:@"已发现位置"];
    [locationGroup setProperty:@"天气 App 请求过的位置会出现在这里。可对单个城市覆盖数据源；未列出的位置请先打开天气 App 刷新一次。"
                     forKey:@"footerText"];
    [specifiers addObject:locationGroup];

    NSArray<NSDictionary *> *locations = [settings recentLocations];
    for (NSDictionary *entry in locations) {
        double latitude = [entry[@"lat"] doubleValue];
        double longitude = [entry[@"lon"] doubleValue];
        NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : @"";
        if (!name.length) name = [NSString stringWithFormat:@"%.2f, %.2f", latitude, longitude];
        NSString *provider = [entry[@"provider"] isKindOfClass:[NSString class]] ? entry[@"provider"] : @"";
        NSString *providerName = provider.length ? WSProviderShortName(provider) : @"未知";
        NSString *label = [NSString stringWithFormat:@"%@  ·  %@", name, providerName];
        [specifiers addObject:WSProviderSpecifier(label, WSOverrideKey(latitude, longitude), nil)];
    }

    PSSpecifier *addLocation = [PSSpecifier preferenceSpecifierNamed:@"手动添加位置"
                                                              target:self
                                                                 set:nil
                                                                 get:nil
                                                              detail:nil
                                                                cell:@"PSButtonCell"
                                                                edit:nil];
    [addLocation setProperty:NSStringFromSelector(@selector(addLocation)) forKey:@"action"];
    [specifiers addObject:addLocation];

    PSSpecifier *advanced = [PSSpecifier groupSpecifierWithName:@"高级"];
    [advanced setProperty:@"缓存时间与请求超时单位为秒。缩短缓存可更快看到新数据，但会增加 API 调用。"
                forKey:@"footerText"];
    [specifiers addObject:advanced];
    [specifiers addObject:WSTextSpecifier(@"缓存时间（秒）", @"cacheTTL", @"600", @"600")];
    [specifiers addObject:WSTextSpecifier(@"请求超时（秒）", @"requestTimeout", @"8", @"8")];
    [specifiers addObject:WSTextSpecifier(@"最小刷新间隔（秒）", @"minRefreshInterval", @"60", @"60")];

    PSSpecifier *fallback = WSProviderSpecifier(@"备用数据源", @"fallbackProvider", nil);
    [fallback setProperty:WS_PROVIDER_OPEN_METEO forKey:@"default"];
    [specifiers addObject:fallback];

    PSSpecifier *refresh = [PSSpecifier preferenceSpecifierNamed:@"清除缓存并立即生效"
                                                          target:self
                                                             set:nil
                                                             get:nil
                                                          detail:nil
                                                            cell:@"PSButtonCell"
                                                            edit:nil];
    [refresh setProperty:NSStringFromSelector(@selector(refreshTweak)) forKey:@"action"];
    [specifiers addObject:refresh];

    PSSpecifier *keys = [PSSpecifier groupSpecifierWithName:@"API Key"];
    [keys setProperty:@"Key 保存在越狱偏好设置 plist 中，未硬编码进源码；请勿在共享设备上使用付费 Key。日志不会记录完整 Key。"
             forKey:@"footerText"];
    [specifiers addObject:keys];
    [specifiers addObject:WSTextSpecifier(@"和风天气 Key", @"qweatherKey", @"QWeather API Key", @"")];
    [specifiers addObject:WSTextSpecifier(@"和风天气 Host", @"qweatherHost", @"devapi.qweather.com", @"devapi.qweather.com")];
    [specifiers addObject:WSTextSpecifier(@"台湾 CWA Key（预留）", @"cwaKey", @"CWA API Key", @"")];
    [specifiers addObject:WSTextSpecifier(@"韩国 KMA Key（预留）", @"kmaKey", @"KMA API Key", @"")];

    PSSpecifier *logs = [PSSpecifier groupSpecifierWithName:@"日志"];
    [logs setProperty:@"记录每次请求的位置、地区、实际数据源与补丁字段数。日志文件：/tmp/WeatherSource.log"
            forKey:@"footerText"];
    [specifiers addObject:logs];

    PSSpecifier *viewLogs = [PSSpecifier preferenceSpecifierNamed:@"查看 API / 异常日志"
                                                           target:self
                                                              set:nil
                                                              get:nil
                                                           detail:nil
                                                             cell:@"PSButtonCell"
                                                             edit:nil];
    [viewLogs setProperty:NSStringFromSelector(@selector(openLogs)) forKey:@"action"];
    [specifiers addObject:viewLogs];

    PSSpecifier *clearLogs = [PSSpecifier preferenceSpecifierNamed:@"清空日志"
                                                            target:self
                                                               set:nil
                                                               get:nil
                                                            detail:nil
                                                              cell:@"PSButtonCell"
                                                              edit:nil];
    [clearLogs setProperty:NSStringFromSelector(@selector(confirmClearLog)) forKey:@"action"];
    [specifiers addObject:clearLogs];

    PSSpecifier *about = [PSSpecifier groupSpecifierWithName:@"关于与限制"];
    [about setProperty:@"v0.1.5 MVP：已接入 Open-Meteo 与可选 QWeather；HKO/SMG/CWA/NWS/JMA/KMA 尚未验证接入，选择后会回退。天气预警、空气质量、分钟级降水与 Apple 原生归属信息默认保留。"
             forKey:@"footerText"];
    [specifiers addObject:about];

    return specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    WSSettings *settings = [WSSettings shared];
    if ([key isEqualToString:@"enabled"]) return @([settings enabled]);
    if ([key isEqualToString:@"autoRegion"]) return @([settings autoRegion]);
    return [settings objectForKey:key default:[specifier propertyForKey:@"default"] ?: @""];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    [[WSSettings shared] setObject:value forKey:key];
    if ([key isEqualToString:@"enabled"] || [key isEqualToString:@"autoRegion"]) {
        [self reloadSpecifiers];
    }
}

- (void)refreshTweak {
    [[WSSettings shared] invalidateCache];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR(WS_NOTIFY_REFRESH_REQUESTED),
                                         NULL, NULL, true);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已发送刷新通知"
                                                                   message:@"请回到天气 App 下拉刷新或重新打开。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)addLocation {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"添加位置"
                                                                   message:@"输入纬度、经度和可选名称。添加后可在列表中为该位置单独选择数据源。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"纬度，例如 39.9042";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"经度，例如 116.4074";
        textField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"名称（可选），例如 北京";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        double latitude = alert.textFields[0].text.doubleValue;
        double longitude = alert.textFields[1].text.doubleValue;
        NSString *name = [alert.textFields[2].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
            UIAlertController *error = [UIAlertController alertControllerWithTitle:@"坐标无效"
                                                                          message:@"纬度需在 -90~90，经度需在 -180~180。"
                                                                   preferredStyle:UIAlertControllerStyleAlert];
            [error addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [strongSelf presentViewController:error animated:YES completion:nil];
            return;
        }
        [[WSSettings shared] recordLocationLatitude:latitude
                                          longitude:longitude
                                            country:@""
                                           provider:@""
                                               name:name.length ? name : nil];
        [strongSelf reloadSpecifiers];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)openLogs {
    WSLogController *controller = [[WSLogController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    if (self.navigationController) {
        [self.navigationController pushViewController:controller animated:YES];
    } else {
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
        [self presentViewController:navigation animated:YES completion:nil];
    }
}

- (void)confirmClearLog {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空日志"
                                                                   message:@"将删除偏好设置中的日志记录和 /tmp/WeatherSource.log。"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[WSSettings shared] clearLog];
        [[NSFileManager defaultManager] removeItemAtPath:@"/tmp/WeatherSource.log" error:nil];
        [self reloadSpecifiers];
    }]];
    alert.popoverPresentationController.sourceView = self.view;
    alert.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:alert animated:YES completion:nil];
}

@end
