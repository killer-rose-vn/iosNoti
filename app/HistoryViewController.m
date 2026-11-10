//
//  HistoryViewController.m
//

#import "HistoryViewController.h"
#import "DetailViewController.h"
#import "RecordStatus.h"
#import "DatabaseManager.h"
#import "ChargeRecord.h"
#import "IosNotiLog.h"

@interface HistoryViewController ()
@property (nonatomic, copy) NSArray<ChargeRecord *> *records;
@end

@implementation HistoryViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Lịch sử";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 76.0;

    UIRefreshControl *refresh = [[UIRefreshControl alloc] init];
    [refresh addTarget:self action:@selector(handleRefresh:) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refresh;

    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash
                                                      target:self
                                                      action:@selector(confirmClearAll)];

    [self reloadRecords];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadRecords];
}

#pragma mark - Loading

- (void)reloadRecords {
    self.records = [[DatabaseManager sharedManager] recordsWithLimit:500 offset:0];
    [self.tableView reloadData];
    [self updateEmptyState];
}

- (void)updateEmptyState {
    if (self.records.count > 0) {
        self.tableView.backgroundView = nil;
        return;
    }
    UILabel *label = [[UILabel alloc] init];
    label.text = @"Chưa có bản ghi nào.\nThông báo bắt được và các lần gửi thử sẽ hiện ở đây.";
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = [UIColor secondaryLabelColor];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.tableView.backgroundView = label;
}

- (void)handleRefresh:(UIRefreshControl *)refresh {
    [self reloadRecords];
    [refresh endRefreshing];
}

#pragma mark - Actions

- (void)confirmClearAll {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Xoá toàn bộ lịch sử?"
                                            message:@"Không thể hoàn tác."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Xoá"
                                             style:UIAlertActionStyleDestructive
                                           handler:^(UIAlertAction *action) {
        [[DatabaseManager sharedManager] deleteAllRecords];
        [weakSelf reloadRecords];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.records.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"HistoryCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:cellID];
        cell.detailTextLabel.numberOfLines = 2;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    ChargeRecord *record = self.records[indexPath.row];
    NSString *appID = record.appID.length > 0 ? record.appID : @"(không rõ app)";
    NSString *time = IosNotiDisplayTime(record.time, record.createdAt);
    NSString *status = IosNotiStatusText(record.httpStatus);

    cell.textLabel.text = [NSString stringWithFormat:@"%@  ·  %@", appID, time];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    cell.textLabel.numberOfLines = 1;

    NSString *summary = record.message.length > 0 ? record.message : record.sender;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  —  %@", status, summary ?: @""];
    cell.detailTextLabel.textColor = IosNotiStatusColor(record.httpStatus);
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.records.count) {
        return;
    }
    ChargeRecord *record = self.records[indexPath.row];
    __weak typeof(self) weakSelf = self;
    DetailViewController *detail =
        [[DetailViewController alloc] initWithRecord:record
                                            onResend:^(ChargeRecord *updated) {
        [weakSelf reloadRecords];
    }];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
