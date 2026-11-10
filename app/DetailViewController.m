//
//  DetailViewController.m
//

#import "DetailViewController.h"
#import "RecordStatus.h"
#import "ChargeRecord.h"
#import "DatabaseManager.h"
#import "NotificationDispatcher.h"

@interface DetailViewController ()
@property (nonatomic, strong) ChargeRecord *record;
@property (nonatomic, copy) void (^onResend)(ChargeRecord *updated);
@property (nonatomic, strong) UITextView *textView;
@property (nonatomic, strong) UIBarButtonItem *resendItem;
@end

@implementation DetailViewController

- (instancetype)initWithRecord:(ChargeRecord *)record
                      onResend:(void (^)(ChargeRecord *updated))onResend {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _record = record;
        _onResend = [onResend copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = self.record.appID.length > 0 ? self.record.appID : @"Chi tiết";

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                      target:self
                                                      action:@selector(showActions)];

    self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.textView.editable = NO;
    self.textView.alwaysBounceVertical = YES;
    self.textView.textContainerInset = UIEdgeInsetsMake(16, 16, 16, 16);
    self.textView.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    [self.view addSubview:self.textView];

    [self refreshText];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadRecordFromDB];
}

- (void)reloadRecordFromDB {
    ChargeRecord *fresh = [[DatabaseManager sharedManager] recordWithRowID:self.record.rowID];
    if (fresh) {
        self.record = fresh;
        [self refreshText];
    }
}

#pragma mark - Text

- (NSString *)jsonText {
    if (self.record.payloadJSON.length > 0) {
        return self.record.payloadJSON;
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject:[self.record payloadDictionary]
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:NULL];
    return json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"(không có)";
}

- (void)refreshText {
    ChargeRecord *r = self.record;
    NSMutableString *text = [NSMutableString string];

    [text appendFormat:@"TRẠNG THÁI: %@\n", IosNotiStatusText(r.httpStatus)];
    [text appendFormat:@"APP: %@\n", r.appID ?: @"-"];
    [text appendFormat:@"ID: %@\n", r.recordID ?: @"-"];
    [text appendFormat:@"THỜI GIAN: %@  (%@ ms)\n",
        IosNotiDisplayTime(r.time, r.createdAt), r.time ?: @"-"];
    [text appendFormat:@"SIM: %@\n", r.sim ?: @"-"];
    [text appendFormat:@"TRACKING: %@\n", r.trackingCode ?: @"-"];
    [text appendFormat:@"TYPE: %@\n", r.type ?: @"-"];
    [text appendFormat:@"SIGNATURE: %@\n", r.signature ?: @"-"];
    [text appendString:@"\n--- SENDER ---\n"];
    [text appendFormat:@"%@\n", r.sender ?: @""];
    [text appendString:@"\n--- MESSAGE ---\n"];
    [text appendFormat:@"%@\n", r.message ?: @""];
    [text appendString:@"\n--- JSON ĐÃ GỬI ---\n"];
    [text appendFormat:@"%@\n", [self jsonText]];
    [text appendString:@"\n--- SERVER TRẢ VỀ ---\n"];
    [text appendFormat:@"%@\n", r.responseBody.length > 0 ? r.responseBody : @"(rỗng)"];

    self.textView.text = text;
}

#pragma mark - Actions

- (void)showActions {
    UIAlertController *sheet =
        [UIAlertController alertControllerWithTitle:nil
                                            message:nil
                                     preferredStyle:UIAlertControllerStyleActionSheet];

    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"Gửi lại (Repost)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [weakSelf resend];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Copy JSON"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        [[UIPasteboard generalPasteboard] setString:[weakSelf jsonText]];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Huỷ"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)resend {
    __weak typeof(self) weakSelf = self;
    self.navigationItem.rightBarButtonItem.enabled = NO;
    self.title = @"Đang gửi…";

    [[NotificationDispatcher sharedDispatcher] repostRecord:self.record
                                                completion:^(NSInteger httpStatus,
                                                             NSString *responseBody,
                                                             NSInteger rowID,
                                                             BOOL success) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        strongSelf.navigationItem.rightBarButtonItem.enabled = YES;
        strongSelf.title = strongSelf.record.appID;
        [strongSelf reloadRecordFromDB];

        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:success ? @"Gửi thành công" : @"Gửi thất bại"
                                                message:[NSString stringWithFormat:
                                                         @"HTTP: %ld\n\n%@",
                                                         (long)httpStatus,
                                                         responseBody.length > 0 ? responseBody : @"(rỗng)"]
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [strongSelf presentViewController:alert animated:YES completion:nil];

        if (strongSelf.onResend) {
            strongSelf.onResend(strongSelf.record);
        }
    }];
}

@end
