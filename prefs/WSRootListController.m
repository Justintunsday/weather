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
                                                             detail:nil
                                                               cell:PSButtonCell
                                                               edit:nil];
    specifier.buttonAction = @selector(chooseProvider:);
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:WS_PREF_DOMAIN forKey:@"defaults"];
    [specifier setProperty:WSProviderValues() forKey:@"values"];
    [specifier setProperty:WSProviderTitles() forKey:@"titles"];
    [specifier setProperty:WSProviderValues() forKey:@"validValues"];
    specifier.titleDictionary = [NSDictionary dictionaryWithObjects:WSProviderTitles() forKeys:WSProviderValues()];
    [specifier setProperty:WS_PROVIDER_AUTO forKey:@"default"];
    return specifier;
}

static PSSpecifier *WSTextSpecifier(NSString *name, NSString *key, NSString *placeholder, id defaultValue, id target) {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:name
                                                             target:target
                                                                set:@selector(setPreferenceValue:specifier:)
                                                                get:@selector(readPreferenceValue:)
                                                             detail:nil
                                                               cell:([key hasSuffix:@"Key"] ? PSSecureEditTextCell : PSEditTextCell)
                                                               edit:nil];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:WS_PREF_DOMAIN forKey:@"defaults"];
    [specifier setProperty:placeholder ?: @"" forKey:@"placeholder"];
    [specifier setProperty:defaultValue ?: @"" forKey:@"default"];
    [specifier setProperty:@NO forKey:@"autoCaps"];
    [specifier setProperty:@NO forKey:@"autoCorrection"];
    [specifier setProperty:@YES forKey:@"noAutoCorrect"];
    [specifier setProperty:@(UIKeyboardTypeASCIICapable) forKey:@"keyboard"];
    return specifier;
}

@implementation WSRootListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"天气数据源";
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[WSSettings shared] invalidateCache];
    [self reloadSpecifiers];
}

- (NSMutableArray *)specifiers {
    if (_specifiers) return _specifiers;
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
                                                            cell:PSSwitchCell
                                                            edit:nil];
    [enabled setProperty:@"enabled" forKey:@"key"];
    [enabled setProperty:@YES forKey:@"default"];
    [specifiers addObject:enabled];

    PSSpecifier *autoRegion = [PSSpecifier preferenceSpecifierNamed:@"自动识别地区"
                                                             target:self
                                                                set:@selector(setPreferenceValue:specifier:)
                                                                get:@selector(readPreferenceValue:)
                                                             detail:nil
                                                               cell:PSSwitchCell
                                                               edit:nil];
    [autoRegion setProperty:@"autoRegion" forKey:@"key"];
    [autoRegion setProperty:@YES forKey:@"default"];
    [specifiers addObject:autoRegion];

    PSSpecifier *global = WSProviderSpecifier(@"全局数据源", @"globalProvider", self);
    [global setProperty:WS_PROVIDER_OPEN_METEO forKey:@"default"];
    [global setProperty:@(!settings.autoRegion) forKey:@"enabled"];
    [specifiers addObject:global];

    PSSpecifier *regionGroup = [PSSpecifier groupSpecifierWithName:@"地区默认数据源"];
    [regionGroup setProperty:@"开启自动地区时使用地区默认值；关闭时使用全局数据源。城市覆盖始终优先。中国大陆配置 QWeather Key 后自动优先和风天气。"
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
        [specifiers addObject:WSProviderSpecifier(label, WSRegionProviderKey(region), self)];
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
        [specifiers addObject:WSProviderSpecifier(label, WSOverrideKey(latitude, longitude), self)];
    }

    PSSpecifier *addLocation = [PSSpecifier preferenceSpecifierNamed:@"手动添加位置"
                                                              target:self
                                                                 set:nil
                                                                 get:nil
                                                              detail:nil
                                                                cell:PSButtonCell
                                                                edit:nil];
    addLocation.buttonAction = @selector(addLocation);
    [specifiers addObject:addLocation];

    PSSpecifier *advanced = [PSSpecifier groupSpecifierWithName:@"高级"];
    [advanced setProperty:@"缓存时间与请求超时单位为秒。缩短缓存可更快看到新数据，但会增加 API 调用。"
                forKey:@"footerText"];
    [specifiers addObject:advanced];
    [specifiers addObject:WSTextSpecifier(@"缓存时间（秒）", @"cacheTTL", @"600", @"600", self)];
    [specifiers addObject:WSTextSpecifier(@"请求超时（秒）", @"requestTimeout", @"8", @"8", self)];

    PSSpecifier *fallback = WSProviderSpecifier(@"备用数据源", @"fallbackProvider", self);
    [fallback setProperty:WS_PROVIDER_OPEN_METEO forKey:@"default"];
    [specifiers addObject:fallback];

    PSSpecifier *refresh = [PSSpecifier preferenceSpecifierNamed:@"清除缓存并立即生效"
                                                          target:self
                                                             set:nil
                                                             get:nil
                                                          detail:nil
                                                            cell:PSButtonCell
                                                            edit:nil];
    refresh.buttonAction = @selector(refreshTweak);
    [specifiers addObject:refresh];

    PSSpecifier *keys = [PSSpecifier groupSpecifierWithName:@"API Key"];
    [keys setProperty:@"Key 保存在共享配置文件中。输入完成后按键盘完成或轻点其他行保存；保存失败会提示。Host 只填域名，不含 https:// 或路径。"
             forKey:@"footerText"];
    [specifiers addObject:keys];
    [specifiers addObject:WSTextSpecifier(@"和风天气 Key", @"qweatherKey", @"QWeather API Key", @"", self)];
    [specifiers addObject:WSTextSpecifier(@"和风天气 Host", @"qweatherHost", @"devapi.qweather.com", @"devapi.qweather.com", self)];
    [specifiers addObject:WSTextSpecifier(@"台湾 CWA Key（预留）", @"cwaKey", @"CWA API Key", @"", self)];
    [specifiers addObject:WSTextSpecifier(@"韩国 KMA Key（预留）", @"kmaKey", @"KMA API Key", @"", self)];

    PSSpecifier *logs = [PSSpecifier groupSpecifierWithName:@"日志"];
    [logs setProperty:@"显示天气 App 与小组件的共享日志。调试级别会保存包含查询位置的响应文件；日常使用建议选择普通。"
            forKey:@"footerText"];
    [specifiers addObject:logs];

    PSSpecifier *level = WSProviderSpecifier(@"日志级别", @"logLevel", self);
    NSArray *levels = @[@0, @1, @2, @3];
    NSArray *levelTitles = @[@"关闭", @"错误与警告", @"普通", @"调试（保存响应）"];
    [level setProperty:levels forKey:@"values"];
    [level setProperty:levels forKey:@"validValues"];
    [level setProperty:levelTitles forKey:@"titles"];
    level.titleDictionary = [NSDictionary dictionaryWithObjects:levelTitles forKeys:levels];
    [level setProperty:@2 forKey:@"default"];
    [specifiers addObject:level];

    PSSpecifier *viewLogs = [PSSpecifier preferenceSpecifierNamed:@"查看 API / 异常日志"
                                                           target:self
                                                              set:nil
                                                              get:nil
                                                           detail:nil
                                                             cell:PSButtonCell
                                                             edit:nil];
    viewLogs.buttonAction = @selector(openLogs);
    [specifiers addObject:viewLogs];

    PSSpecifier *clearLogs = [PSSpecifier preferenceSpecifierNamed:@"清空日志"
                                                            target:self
                                                               set:nil
                                                               get:nil
                                                            detail:nil
                                                              cell:PSButtonCell
                                                              edit:nil];
    clearLogs.buttonAction = @selector(confirmClearLog);
    [specifiers addObject:clearLogs];

    PSSpecifier *about = [PSSpecifier groupSpecifierWithName:@"关于与限制"];
    [about setProperty:@"WeatherSource " @WS_VERSION @"：已接入 Open-Meteo 与可选 QWeather；HKO/SMG/CWA/NWS/JMA/KMA 尚未接入，选择后会回退。天气预警、空气质量、分钟级降水与 Apple 原生归属信息保留。"
             forKey:@"footerText"];
    [specifiers addObject:about];

    for (PSSpecifier *item in specifiers) {
        NSArray *values = [item propertyForKey:@"values"];
        if (!values.count || [item.name containsString:@"·"]) continue;
        id selected = [self readPreferenceValue:item];
        NSString *title = item.titleDictionary[selected];
        if (title.length) item.name = [NSString stringWithFormat:@"%@ · %@", item.name, title];
    }
    _specifiers = specifiers;
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    WSSettings *settings = [WSSettings shared];
    if ([key isEqualToString:@"enabled"]) return @([settings enabled]);
    if ([key isEqualToString:@"autoRegion"]) return @([settings autoRegion]);
    id value = [settings objectForKey:key default:[specifier propertyForKey:@"default"] ?: @""];
    if (specifier.cellType == PSEditTextCell || specifier.cellType == PSSecureEditTextCell) return [value description];
    return value;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    if ([value isKindOfClass:[NSString class]]) value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSDictionary *ranges = @{@"cacheTTL": @[@30, @21600], @"requestTimeout": @[@2, @30], @"minRefreshInterval": @[@10, @3600]};
    NSArray *range = ranges[key];
    if (range) {
        NSScanner *scanner = [NSScanner scannerWithString:[value description]];
        double number = 0;
        if (![scanner scanDouble:&number] || !scanner.isAtEnd || !isfinite(number) || number < [range[0] doubleValue] || number > [range[1] doubleValue]) {
            [self showConfigurationError:[NSString stringWithFormat:@"请输入 %@ 到 %@ 之间的秒数。", range[0], range[1]]];
            [self reloadSpecifier:specifier];
            return;
        }
        value = @(number);
    }
    if ([key isEqualToString:@"qweatherHost"] && [value length]) {
        NSURLComponents *host = [NSURLComponents componentsWithString:[@"https://" stringByAppendingString:value]];
        if (!host.host.length || host.path.length || host.query.length || host.fragment.length || host.user.length || host.port) {
            [self showConfigurationError:@"Host 只填写域名，例如 abc.qweatherapi.com，不含协议、端口或路径。"];
            [self reloadSpecifier:specifier];
            return;
        }
    }
    if (![[WSSettings shared] saveSharedObject:value forKey:key]) {
            [self showConfigurationError:@"无法保存配置，请确认 Cephei 已安装并在越狱状态下重新打开设置。"];
        [self reloadSpecifier:specifier];
        return;
    }
    if ([key isEqualToString:@"enabled"] || [key isEqualToString:@"autoRegion"]) {
        [self reloadSpecifiers];
    }
}

- (void)showConfigurationError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"配置未保存" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)chooseProvider:(PSSpecifier *)specifier {
    NSArray *values = [specifier propertyForKey:@"values"];
    NSArray *titles = [specifier propertyForKey:@"titles"];
    if (!values.count || values.count != titles.count) return;
    id selected = [self readPreferenceValue:specifier];
    UIAlertController *picker = [UIAlertController alertControllerWithTitle:specifier.name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSUInteger index = 0; index < values.count; index++) {
        id value = values[index];
        NSString *title = [value isEqual:selected] ? [titles[index] stringByAppendingString:@" ✓"] : titles[index];
        [picker addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [weakSelf setPreferenceValue:value specifier:specifier];
            [weakSelf reloadSpecifiers];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    picker.popoverPresentationController.sourceView = self.view;
    picker.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)refreshTweak {
    [self.view endEditing:YES];
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
        NSScanner *latScanner = [NSScanner scannerWithString:alert.textFields[0].text ?: @""];
        NSScanner *lonScanner = [NSScanner scannerWithString:alert.textFields[1].text ?: @""];
        double latitude = NAN, longitude = NAN;
        BOOL valid = [latScanner scanDouble:&latitude] && latScanner.isAtEnd && [lonScanner scanDouble:&longitude] && lonScanner.isAtEnd;
        NSString *name = [alert.textFields[2].text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!valid || !isfinite(latitude) || !isfinite(longitude) || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
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
