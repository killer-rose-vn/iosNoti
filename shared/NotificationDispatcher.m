//
//  NotificationDispatcher.m
//

#import "NotificationDispatcher.h"
#import "NotificationPayloadBuilder.h"
#import "NetworkManager.h"
#import "DatabaseManager.h"
#import "ConfigManager.h"
#import "SignatureHelper.h"
#import "IosNotiLog.h"

static const NSInteger kDefaultMaxRecords = 2000;
static const NSInteger kDefaultMaxRetries = 2;
static const NSUInteger kDedupCapacity     = 256;
static const double    kRetryDelaySeconds  = 2.0;

#pragma mark - Safe KVC

static id INSafeValue(id object, NSString *key) {
    if (object == nil) {
        return nil;
    }
    @try {
        if ([object respondsToSelector:NSSelectorFromString(key)]) {
            return [object valueForKey:key];
        }
    } @catch (__unused NSException *exception) {
        // Bulletin có thể là class khác (BBBulletin vs BBBulletinRequest) — bỏ qua.
    }
    return nil;
}

static NSString *INSafeStringValue(id object, NSString *key) {
    id value = INSafeValue(object, key);
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];
    }
    return nil;
}

#pragma mark -

@interface NotificationDispatcher ()
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *recentIDs;
- (BOOL)isDuplicate:(NSString *)recordID;
- (void)sendPayload:(NSDictionary *)payload
              rowID:(NSInteger)rowID
            attempt:(NSInteger)attempt
         completion:(IosNotiSendCompletion)completion;
@end

@implementation NotificationDispatcher

+ (instancetype)sharedDispatcher {
    static NotificationDispatcher *dispatcher = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatcher = [[NotificationDispatcher alloc] init];
    });
    return dispatcher;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _maxRecords = kDefaultMaxRecords;
        _maxRetries = kDefaultMaxRetries;
        _workQueue = dispatch_queue_create("com.iosnoti.dispatcher", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_workQueue, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
        _recentIDs = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - Entry points (tweak)

- (void)handleBulletin:(id)bulletin {
    if (bulletin == nil) {
        return;
    }

    NSString *sectionID  = INSafeStringValue(bulletin, @"sectionID");
    NSString *bulletinID = INSafeStringValue(bulletin, @"bulletinID");
    NSString *title      = INSafeStringValue(bulletin, @"title");
    NSString *subtitle   = INSafeStringValue(bulletin, @"subtitle");
    NSString *message    = INSafeStringValue(bulletin, @"message");

    if (sectionID.length == 0) {
        sectionID = INSafeStringValue(bulletin, @"section");
    }
    if (sectionID.length == 0 && bulletinID.length == 0) {
        return;   // không phải notification thật
    }

    [self handleSectionID:sectionID
               bulletinID:bulletinID
                    title:title
                 subtitle:subtitle
                  message:message];
}

- (void)handleSectionID:(NSString *)sectionID
              bulletinID:(NSString *)bulletinID
                   title:(NSString *)title
                subtitle:(NSString *)subtitle
                 message:(NSString *)message {
    NSString *timeMS = [SignatureHelper currentTimestampMillisecondsString];

    // sender = title, fallback subtitle.
    NSString *sender = title.length > 0 ? title : subtitle;

    // id = bulletinID nếu có, ngược lại dùng chính timeMS.
    NSString *recordID = bulletinID.length > 0 ? bulletinID : timeMS;

    if ([self isDuplicate:recordID]) {
        INLog(@"skip duplicate bulletin id=%@", recordID);
        return;
    }

    NSDictionary *payload = [NotificationPayloadBuilder payloadWithAppID:sectionID
                                                                  sender:sender
                                                                 message:message
                                                                recordID:recordID
                                                                  timeMS:timeMS];

    INLog(@"captured app=%@ id=%@ sender=%.80@ msg=%.120@",
          payload[@"app_id"], payload[@"id"], payload[@"sender"], payload[@"message"]);

    [self submitPayload:payload completion:nil];
}

#pragma mark - Dedup

- (BOOL)isDuplicate:(NSString *)recordID {
    if (recordID.length == 0) {
        return NO;
    }
    @synchronized (self.recentIDs) {
        if (self.recentIDs[recordID] != nil) {
            return YES;
        }
        if (self.recentIDs.count >= kDedupCapacity) {
            [self.recentIDs removeAllObjects];   // đơn giản: xoá sạch khi đầy
        }
        self.recentIDs[recordID] = @([[NSDate date] timeIntervalSince1970]);
    }
    return NO;
}

#pragma mark - Public send API (dùng chung cho tweak và app)

- (void)submitPayload:(NSDictionary *)payload completion:(IosNotiSendCompletion)completion {
    if (![payload isKindOfClass:[NSDictionary class]]) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(0, @"payload không hợp lệ", 0, NO); });
        }
        return;
    }

    // Ghi bản ghi pending TRƯỚC khi gửi → app thấy ngay, không mất dữ liệu nếu bị kill.
    ChargeRecord *record = [NotificationPayloadBuilder recordFromPayload:payload
                                                            responseBody:@""
                                                              httpStatus:IosNotiHTTPStatusPending
                                                               createdAt:[[NSDate date] timeIntervalSince1970]];
    DatabaseManager *db = [DatabaseManager sharedManager];
    if (![db insertRecord:record]) {
        INLog(@"WARNING: insert pending record failed, vẫn gửi lên server");
    }

    dispatch_async(self.workQueue, ^{
        [self sendPayload:payload rowID:record.rowID attempt:0 completion:completion];
    });
}

- (void)repostRecord:(ChargeRecord *)record completion:(IosNotiSendCompletion)completion {
    if (record == nil) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(0, @"record rỗng", 0, NO); });
        }
        return;
    }

    // Dựng lại đúng gói tin đã lưu (signature/tracking giữ nguyên).
    NSDictionary *payload = [record payloadDictionary];
    INLog(@"repost row=%ld id=%@", (long)record.rowID, record.recordID);

    dispatch_async(self.workQueue, ^{
        [self sendPayload:payload rowID:record.rowID attempt:0 completion:completion];
    });
}

#pragma mark - Send

- (void)sendPayload:(NSDictionary *)payload
              rowID:(NSInteger)rowID
            attempt:(NSInteger)attempt
         completion:(IosNotiSendCompletion)completion {
    // Config có thể đã bị sửa bên App → đọc lại nếu file thay đổi.
    [[ConfigManager sharedManager] reloadIfChanged];
    NSString *url = [ConfigManager sharedManager].serverURL;

    INLog(@"POST attempt %ld/%ld -> %@",
          (long)attempt + 1, (long)(self.maxRetries + 1), url);

    NetworkResult *result = [[NetworkManager sharedManager] POSTJSONSynchronously:payload
                                                                           toURL:url];

    // Lỗi mạng (không có HTTP response): thử lại sau 2s, cùng rowID.
    if (result.statusCode == 0 && attempt < self.maxRetries) {
        INLog(@"network error, retry after %.0fs: %@", kRetryDelaySeconds, result.errorMessage);
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(kRetryDelaySeconds * NSEC_PER_SEC)),
                       self.workQueue, ^{
            [weakSelf sendPayload:payload rowID:rowID attempt:attempt + 1 completion:completion];
        });
        return;
    }

    NSInteger status = result.statusCode;
    if (status == 0) {
        status = IosNotiHTTPStatusNetworkError;   // -1
    }

    NSString *responseBody = result.body ?: @"";
    if (result.errorMessage.length > 0) {
        responseBody = [responseBody stringByAppendingFormat:@"\n[error] %@", result.errorMessage];
    }

    DatabaseManager *db = [DatabaseManager sharedManager];
    NSInteger finalRowID = rowID;
    if (rowID > 0) {
        [db updateHTTPStatus:status responseBody:responseBody forRowID:rowID];
    } else {
        ChargeRecord *fallback = [NotificationPayloadBuilder recordFromPayload:payload
                                                                  responseBody:responseBody
                                                                    httpStatus:status
                                                                     createdAt:[[NSDate date] timeIntervalSince1970]];
        [db insertRecord:fallback];
        finalRowID = fallback.rowID;
    }

    INLog(@"result status=%ld success=%d row=%ld body=%.160@",
          (long)status, result.success, (long)finalRowID, responseBody);

    [db trimToMaxRecords:self.maxRecords];

    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(status, responseBody, finalRowID, result.success);
        });
    }
}

#pragma mark - Resend

- (void)resendPendingRecords {
    dispatch_async(self.workQueue, ^{
        [[ConfigManager sharedManager] reloadIfChanged];
        DatabaseManager *db = [DatabaseManager sharedManager];
        NSArray<ChargeRecord *> *pending = [db recordsWithStatus:IosNotiHTTPStatusPending limit:20];
        if (pending.count == 0) {
            return;
        }
        INLog(@"resending %lu pending record(s)", (unsigned long)pending.count);

        for (ChargeRecord *record in pending) {
            NSDictionary *payload = [record payloadDictionary];
            NetworkResult *result = [[NetworkManager sharedManager] POSTJSONSynchronously:payload
                                                                                   toURL:[ConfigManager sharedManager].serverURL];
            NSInteger status = result.statusCode > 0 ? result.statusCode : IosNotiHTTPStatusNetworkError;
            NSString *body = result.body ?: result.errorMessage ?: @"";
            [db updateHTTPStatus:status responseBody:body forRowID:record.rowID];
            INLog(@"resend id=%@ -> %ld", record.recordID, (long)status);
        }
    });
}

@end
