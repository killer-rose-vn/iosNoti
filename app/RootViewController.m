//
//  RootViewController.m
//

#import "RootViewController.h"
#import "DetailViewController.h"
#import "ConfigManager.h"
#import "DatabaseManager.h"
#import "ChargeRecord.h"
#import "IosNotiPaths.h"
#import "IosNotiLog.h"

static NSDateFormatter *INDateFormatter(void) {
    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"MM-dd HH:mm:ss";
    });
    return formatter;
}

@interface RootViewController ()
@property (nonatomic, copy) NSArray<ChargeRecord *> *records;
@end

@implementation RootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"IosNoti";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 72.0;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self
                                                      action:@selector(reloadData)];
    [self reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadData];
}

- (void)reloadData {
    [[ConfigManager sharedManager] reload];
    self.records = [[DatabaseManager sharedManager] recordsWithLimit:200 offset:0];
    [self.tableView reloadData];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return @"Cấu hình";
    }
    return [NSString stringWithFormat:@"Lịch sử (%lu)", (unsigned long)self.records.count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 4 : (NSInteger)self.records.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:cellID];
    }
    cell.detailTextLabel.numberOfLines = 3;
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (indexPath.section == 0) {
        ConfigManager *config = [ConfigManager sharedManager];
        NSArray *titles = @[@"server_url", @"app_id", @"sim_id", @"secret_key"];
        NSArray *values = @[config.serverURL ?: @"", config.appID ?: @"",
                            config.simID ?: @"", config.secretKey ?: @""];
        NSInteger row = indexPath.row;
        cell.textLabel.text = titles[row];
        cell.detailTextLabel.text = row == 3 && values[row].length > 0 ? @"••••••" : values[row];
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        cell.textLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        ChargeRecord *record = self.records[indexPath.row];
        NSString *status = record.httpStatus == IosNotiHTTPStatusPending
            ? @"pending"
            : [@(record.httpStatus) stringValue];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@", record.sender, status];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@\n%@ · %@",
                                     record.message ?: @"",
                                     [INDateFormatter() stringFromDate:record.createdDate],
                                     record.sim ?: @""];
        cell.textLabel.textColor = record.httpStatus >= 200 && record.httpStatus < 300
            ? [UIColor systemGreenColor]
            : (record.httpStatus == IosNotiHTTPStatusPending
                ? [UIColor labelColor]
                : [UIColor systemRedColor]);
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1 || indexPath.row >= (NSInteger)self.records.count) {
        return;
    }
    DetailViewController *detail = [[DetailViewController alloc] initWithRecord:self.records[indexPath.row]];
    [self.navigationController pushViewController:detail animated:YES];
}

@end
