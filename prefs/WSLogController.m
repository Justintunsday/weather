#import "WSLogController.h"
#import "WSSettings.h"

@interface WSLogController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *entries;
@end

@implementation WSLogController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"WeatherSource 日志";
    self.tableView.rowHeight = 64.0;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"刷新"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(reloadEntries)];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空"
                                                                             style:UIBarButtonItemStylePlain
                                                                            target:self
                                                                            action:@selector(clear)];
    [self reloadEntries];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadEntries];
}

- (void)reloadEntries {
    NSArray<NSDictionary *> *entries = [[WSSettings shared] logEntries];
    self.entries = [[entries reverseObjectEnumerator] allObjects];
    [self.tableView reloadData];
    if (self.entries.count == 0) {
        UILabel *label = [[UILabel alloc] init];
        label.text = @"暂无日志\n\n打开天气 App 并刷新后，这里会出现请求记录。";
        label.numberOfLines = 0;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor secondaryLabelColor];
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        self.tableView.backgroundView = label;
    } else {
        self.tableView.backgroundView = nil;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"LogCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"LogCell"];
    }
    NSDictionary *entry = self.entries[(NSUInteger)indexPath.row];
    NSString *message = [entry[@"message"] isKindOfClass:[NSString class]] ? entry[@"message"] : @"";
    cell.textLabel.text = message;
    cell.textLabel.numberOfLines = 2;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];

    NSTimeInterval timestamp = [entry[@"time"] doubleValue];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"MM-dd HH:mm:ss";
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *time = timestamp > 0 ? [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:timestamp]] : @"--";
    NSInteger level = [entry[@"level"] integerValue];
    NSString *levelName = level == 0 ? @"ERROR" : level == 1 ? @"WARN" : level == 3 ? @"DEBUG" : @"INFO";
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", time, levelName];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *entry = self.entries[(NSUInteger)indexPath.row];
    NSString *message = [entry[@"message"] isKindOfClass:[NSString class]] ? entry[@"message"] : @"";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"日志详情"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)clear {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空日志"
                                                                   message:@"确认删除所有日志？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[WSSettings shared] clearLog];
        [[NSFileManager defaultManager] removeItemAtPath:@"/tmp/WeatherSource.log" error:nil];
        [weakSelf reloadEntries];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
