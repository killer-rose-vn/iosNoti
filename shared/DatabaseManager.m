//
//  DatabaseManager.m
//

#import "DatabaseManager.h"
#import "IosNotiPaths.h"
#import "IosNotiLog.h"
#import <sqlite3.h>

static const NSInteger kCurrentSchemaVersion = 2;

static NSString * const kSQLCreateTable =
    @"CREATE TABLE IF NOT EXISTS charge_records ("
    @"  row_id        INTEGER PRIMARY KEY AUTOINCREMENT,"
    @"  id            TEXT NOT NULL DEFAULT '',"
    @"  app_id        TEXT NOT NULL DEFAULT '',"
    @"  sender        TEXT NOT NULL DEFAULT '',"
    @"  message       TEXT NOT NULL DEFAULT '',"
    @"  time          TEXT NOT NULL DEFAULT '',"
    @"  tracking_code TEXT NOT NULL DEFAULT '',"
    @"  signature     TEXT NOT NULL DEFAULT '',"
    @"  sim           TEXT NOT NULL DEFAULT '',"
    @"  type          TEXT NOT NULL DEFAULT 'NOTIFICATION',"
    @"  http_status   INTEGER NOT NULL DEFAULT 0,"
    @"  response_body TEXT NOT NULL DEFAULT '',"
    @"  payload_json  TEXT NOT NULL DEFAULT '',"
    @"  created_at    REAL NOT NULL DEFAULT 0"
    @");";

static NSString * const kSQLCreateIndexCreatedAt =
    @"CREATE INDEX IF NOT EXISTS idx_charge_created_at ON charge_records (created_at DESC);";
static NSString * const kSQLCreateIndexTracking =
    @"CREATE INDEX IF NOT EXISTS idx_charge_tracking ON charge_records (tracking_code);";
static NSString * const kSQLCreateIndexStatus =
    @"CREATE INDEX IF NOT EXISTS idx_charge_status ON charge_records (http_status);";

static NSString * const kColumns =
    @"row_id, id, app_id, sender, message, time, tracking_code, signature, sim, "
    @"type, http_status, response_body, payload_json, created_at";

#pragma mark - sqlite helpers

static BOOL INExecSQL(sqlite3 *db, NSString *sql) {
    char *errmsg = NULL;
    int rc = sqlite3_exec(db, sql.UTF8String, NULL, NULL, &errmsg);
    if (rc != SQLITE_OK) {
        INLog(@"sqlite exec failed (%d): %s | sql=%@", rc, errmsg ?: "", sql);
        if (errmsg) {
            sqlite3_free(errmsg);
        }
        return NO;
    }
    return YES;
}

static void INBindText(sqlite3_stmt *stmt, int index, NSString *value) {
    NSString *text = [value isKindOfClass:[NSString class]] ? value : @"";
    sqlite3_bind_text(stmt, index, text.UTF8String, -1, SQLITE_TRANSIENT);
}

static NSString *INColumnText(sqlite3_stmt *stmt, int index) {
    const unsigned char *raw = sqlite3_column_text(stmt, index);
    return raw ? [NSString stringWithUTF8String:(const char *)raw] : @"";
}

static ChargeRecord *INRecordFromStatement(sqlite3_stmt *stmt) {
    ChargeRecord *record = [[ChargeRecord alloc] init];
    record.rowID        = (NSInteger)sqlite3_column_int64(stmt, 0);
    record.recordID     = INColumnText(stmt, 1);
    record.appID        = INColumnText(stmt, 2);
    record.sender       = INColumnText(stmt, 3);
    record.message      = INColumnText(stmt, 4);
    record.time         = INColumnText(stmt, 5);
    record.trackingCode = INColumnText(stmt, 6);
    record.signature    = INColumnText(stmt, 7);
    record.sim          = INColumnText(stmt, 8);
    record.type         = INColumnText(stmt, 9);
    record.httpStatus   = (NSInteger)sqlite3_column_int64(stmt, 10);
    record.responseBody = INColumnText(stmt, 11);
    record.payloadJSON  = INColumnText(stmt, 12);
    record.createdAt    = sqlite3_column_double(stmt, 13);
    if (record.type.length == 0) {
        record.type = @"NOTIFICATION";
    }
    return record;
}

/// Trả về YES nếu bảng đã có cột tên `column`.
static BOOL INColumnExists(sqlite3 *db, NSString *table, NSString *column) {
    NSString *sql = [NSString stringWithFormat:@"PRAGMA table_info(%@);", table];
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
        return NO;
    }
    BOOL found = NO;
    while (sqlite3_step(stmt) == SQLITE_ROW) {
        const unsigned char *name = sqlite3_column_text(stmt, 1);
        if (name && strcmp((const char *)name, column.UTF8String) == 0) {
            found = YES;
            break;
        }
    }
    sqlite3_finalize(stmt);
    return found;
}

/// Nâng cấp DB tạo bởi Bước 1 (thiếu type/payload_json).
static BOOL INMigrateSchema(sqlite3 *db) {
    BOOL ok = YES;
    if (!INColumnExists(db, @"charge_records", @"type")) {
        ok = INExecSQL(db, @"ALTER TABLE charge_records ADD COLUMN type TEXT NOT NULL DEFAULT 'NOTIFICATION';") && ok;
    }
    if (!INColumnExists(db, @"charge_records", @"payload_json")) {
        ok = INExecSQL(db, @"ALTER TABLE charge_records ADD COLUMN payload_json TEXT NOT NULL DEFAULT '';") && ok;
    }
    return ok;
}

#pragma mark -

@interface DatabaseManager () {
    sqlite3 *_db;
    dispatch_queue_t _queue;
}
- (BOOL)openDatabaseLocked;
- (ChargeRecord *)recordWithColumn:(NSString *)column value:(NSString *)value;
- (NSInteger)scalarForSQL:(NSString *)sql;
- (BOOL)executeUpdateWithSQL:(NSString *)sql bind:(void (^)(sqlite3_stmt *stmt))binder;
@end

@implementation DatabaseManager

+ (instancetype)sharedManager {
    static DatabaseManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[DatabaseManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _db = NULL;
        _queue = dispatch_queue_create("com.iosnoti.database", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)dealloc {
    [self closeDatabase];
}

- (NSString *)databasePath {
    return [IosNotiPaths databaseFilePath];
}

#pragma mark - Open / Close

- (BOOL)openDatabase {
    __block BOOL ok = NO;
    dispatch_sync(_queue, ^{
        ok = [self openDatabaseLocked];
    });
    return ok;
}

/// Phải gọi trong queue.
- (BOOL)openDatabaseLocked {
    if (_db != NULL) {
        return YES;
    }

    NSString *path = [self databasePath];
    [IosNotiPaths ensureDirectoryAtPath:[IosNotiPaths sharedPreferencesDirectory]];

    sqlite3 *db = NULL;
    int rc = sqlite3_open_v2(path.UTF8String,
                             &db,
                             SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                             NULL);
    if (rc != SQLITE_OK || db == NULL) {
        INLog(@"open db failed (%d) at %@: %s", rc, path, db ? sqlite3_errmsg(db) : "n/a");
        if (db) {
            sqlite3_close(db);
        }
        return NO;
    }

    _db = db;
    sqlite3_busy_timeout(_db, 3000);
    INExecSQL(_db, @"PRAGMA journal_mode=WAL;");
    INExecSQL(_db, @"PRAGMA synchronous=NORMAL;");
    INExecSQL(_db, @"PRAGMA foreign_keys=ON;");
    INExecSQL(_db, [NSString stringWithFormat:@"PRAGMA user_version=%ld;", (long)kDefaultSchemaVersion]);

    BOOL ok = INExecSQL(_db, kSQLCreateTable)
           && INExecSQL(_db, kSQLCreateIndexCreatedAt)
           && INExecSQL(_db, kSQLCreateIndexTracking)
           && INExecSQL(_db, kSQLCreateIndexStatus);

    if (!ok) {
        INLog(@"create schema failed at %@", path);
        sqlite3_close(_db);
        _db = NULL;
        return NO;
    }

    // File DB nằm trong /var/mobile/Library/Preferences: 0644 để app/tweak cùng đọc.
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0644}
                                     ofItemAtPath:path
                                            error:NULL];

    INLog(@"db ready: %@", path);
    return YES;
}

- (void)closeDatabase {
    dispatch_sync(_queue, ^{
        if (self->_db != NULL) {
            sqlite3_close(self->_db);
            self->_db = NULL;
        }
    });
}

#pragma mark - Insert / Update

- (BOOL)insertRecord:(ChargeRecord *)record {
    if (record == nil) {
        return NO;
    }
    __block BOOL ok = NO;
    dispatch_sync(_queue, ^{
        if (![self openDatabaseLocked]) {
            return;
        }
        static const char *sql =
            "INSERT INTO charge_records "
            "(id, app_id, sender, message, time, tracking_code, signature, sim, "
            " type, http_status, response_body, payload_json, created_at) "
            "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?);";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) {
            INLog(@"insert prepare failed: %s", sqlite3_errmsg(self->_db));
            return;
        }

        double createdAt = record.createdAt > 0
            ? record.createdAt
            : [[NSDate date] timeIntervalSince1970];

        INBindText(stmt, 1, record.recordID);
        INBindText(stmt, 2, record.appID);
        INBindText(stmt, 3, record.sender);
        INBindText(stmt, 4, record.message);
        INBindText(stmt, 5, record.time);
        INBindText(stmt, 6, record.trackingCode);
        INBindText(stmt, 7, record.signature);
        INBindText(stmt, 8, record.sim);
        INBindText(stmt, 9, record.type.length > 0 ? record.type : @"NOTIFICATION");
        sqlite3_bind_int64(stmt, 10, (sqlite3_int64)record.httpStatus);
        INBindText(stmt, 11, record.responseBody);
        INBindText(stmt, 12, record.payloadJSON);
        sqlite3_bind_double(stmt, 13, createdAt);

        int rc = sqlite3_step(stmt);
        if (rc == SQLITE_DONE) {
            ok = YES;
            record.rowID = (NSInteger)sqlite3_last_insert_rowid(self->_db);
            record.createdAt = createdAt;
        } else {
            INLog(@"insert failed (%d): %s", rc, sqlite3_errmsg(self->_db));
        }
        sqlite3_finalize(stmt);
    });
    return ok;
}

- (BOOL)updateHTTPStatus:(NSInteger)status
            responseBody:(NSString *)responseBody
                forRowID:(NSInteger)rowID {
    __block BOOL ok = NO;
    dispatch_sync(_queue, ^{
        if (![self openDatabaseLocked]) {
            return;
        }
        static const char *sql =
            "UPDATE charge_records SET http_status = ?, response_body = ? WHERE row_id = ?;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) {
            INLog(@"update prepare failed: %s", sqlite3_errmsg(self->_db));
            return;
        }
        sqlite3_bind_int64(stmt, 1, (sqlite3_int64)status);
        INBindText(stmt, 2, responseBody);
        sqlite3_bind_int64(stmt, 3, (sqlite3_int64)rowID);
        ok = (sqlite3_step(stmt) == SQLITE_DONE);
        if (!ok) {
            INLog(@"update failed: %s", sqlite3_errmsg(self->_db));
        }
        sqlite3_finalize(stmt);
    });
    return ok;
}

- (BOOL)updateHTTPStatus:(NSInteger)status
            responseBody:(NSString *)responseBody
        forTrackingCode:(NSString *)trackingCode {
    __block BOOL ok = NO;
    dispatch_sync(_queue, ^{
        if (![self openDatabaseLocked]) {
            return;
        }
        static const char *sql =
            "UPDATE charge_records SET http_status = ?, response_body = ? "
            "WHERE tracking_code = ? AND tracking_code <> '';";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) {
            return;
        }
        sqlite3_bind_int64(stmt, 1, (sqlite3_int64)status);
        INBindText(stmt, 2, responseBody);
        INBindText(stmt, 3, trackingCode);
        ok = (sqlite3_step(stmt) == SQLITE_DONE);
        sqlite3_finalize(stmt);
    });
    return ok;
}

#pragma mark - Query

- (NSArray<ChargeRecord *> *)recordsWithLimit:(NSInteger)limit offset:(NSInteger)offset {
    NSMutableArray<ChargeRecord *> *result = [NSMutableArray array];
    dispatch_sync(_queue, ^{
        if (![self openDatabaseLocked]) {
            return;
        }
        NSString *sql = [NSString stringWithFormat:
            @"SELECT %@ FROM charge_records ORDER BY created_at DESC, row_id DESC LIMIT ? OFFSET ?;",
            kColumns];
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
            INLog(@"select prepare failed: %s", sqlite3_errmsg(self->_db));
            return;
        }
        NSInteger safeLimit  = (limit  > 0) ? limit  : -1;
        NSInteger safeOffset = (offset > 0) ? offset : 0;
        sqlite3_bind_int64(stmt, 1, (sqlite3_int64)safeLimit);
        sqlite3_bind_int64(stmt, 2, (sqlite3_int64)safeOffset);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [result addObject:INRecordFromStatement(stmt)];
        }
        sqlite3_finalize(stmt);
    });
    return result;
}

- (NSArray<ChargeRecord *> *)recordsWithStatus:(NSInteger)status limit:(NSInteger)limit {
    NSMutableArray<ChargeRecord *> *result = [NSMutableArray array];
    dispatch_sync(_queue, ^{
        if (![self openDatabaseLocked]) {
            return;
        }
        NSString *sql = [NSString stringWithFormat:
            @"SELECT %@ FROM charge_records WHERE http_status = ? "
            @"ORDER BY created_at ASC, row_id ASC LIMIT ?;", kColumns];
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
            return;
        }
        sqlite3_bind_int64(stmt, 1, (sqlite3_int64)status);
        sqlite3_bind_int64(stmt, 2, (sqlite3_int64)((limit > 0) ? limit : -1));

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            [result addObject:INRecordFromStatement(stmt)];
        }
        sqlite3_finalize(stmt);
    });
    return result;
}

- (ChargeRecord *)recordWithRowID:(NSInteger)rowID {
    if (rowID <= 0) {
        return nil;
    }
    __block ChargeRecord *found = nil;
    dispatch_sync(_queue, ^{
        if (![self openDatabaseLocked]) {
            return;
        }
        NSString *sql = [NSString stringWithFormat:
            @"SELECT %@ FROM charge_records WHERE row_id = ? LIMIT 1;", kColumns];
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
            return;
        }
        sqlite3_bind_int64(stmt, 1, (sqlite3_int64)rowID);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            found = INRecordFromStatement(stmt);
        }
        sqlite3_finalize(stmt);
    });
    return found;
}

- (ChargeRecord *)recordWithTrackingCode:(NSString *)trackingCode {
    return [self recordWithColumn:@"tracking_code" value:trackingCode];
}

- (ChargeRecord *)recordWithRecordID:(NSString *)recordID {
    return [self recordWithColumn:@"id" value:recordID];
}

- (ChargeRecord *)recordWithColumn:(NSString *)column value:(NSString *)value {
    if (value.length == 0) {
        return nil;
    }
    __block ChargeRecord *found = nil;
    dispatch_sync(_queue, ^{
        if (![self openDatabaseLocked]) {
            return;
        }
        NSString *sql = [NSString stringWithFormat:
            @"SELECT %@ FROM charge_records WHERE %@ = ? ORDER BY row_id DESC LIMIT 1;",
            kColumns, column];
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
            return;
        }
        INBindText(stmt, 1, value);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            found = INRecordFromStatement(stmt);
        }
        sqlite3_finalize(stmt);
    });
    return found;
}

- (NSInteger)recordCount {
    return [self scalarForSQL:@"SELECT COUNT(*) FROM charge_records;"];
}

- (NSInteger)countWithStatus:(NSInteger)status {
    __block NSInteger count = 0;
    dispatch_sync(_queue, ^{
        if (![self openDatabaseLocked]) {
            return;
        }
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db,
                               "SELECT COUNT(*) FROM charge_records WHERE http_status = ?;",
                               -1, &stmt, NULL) != SQLITE_OK) {
            return;
        }
        sqlite3_bind_int64(stmt, 1, (sqlite3_int64)status);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            count = (NSInteger)sqlite3_column_int64(stmt, 0);
        }
        sqlite3_finalize(stmt);
    });
    return count;
}

- (NSInteger)scalarForSQL:(NSString *)sql {
    __block NSInteger value = 0;
    dispatch_sync(_queue, ^{
        if (![self openDatabaseLocked]) {
            return;
        }
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
            return;
        }
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            value = (NSInteger)sqlite3_column_int64(stmt, 0);
        }
        sqlite3_finalize(stmt);
    });
    return value;
}

- (NSArray<NSDictionary *> *)dictionariesWithLimit:(NSInteger)limit offset:(NSInteger)offset {
    NSArray<ChargeRecord *> *records = [self recordsWithLimit:limit offset:offset];
    NSMutableArray<NSDictionary *> *result = [NSMutableArray arrayWithCapacity:records.count];
    for (ChargeRecord *record in records) {
        [result addObject:[record dictionaryRepresentation]];
    }
    return result;
}

#pragma mark - Delete

- (BOOL)deleteRecordWithRowID:(NSInteger)rowID {
    return [self executeUpdateWithSQL:@"DELETE FROM charge_records WHERE row_id = ?;"
                                bind:^(sqlite3_stmt *stmt) {
                                    sqlite3_bind_int64(stmt, 1, (sqlite3_int64)rowID);
                                }];
}

- (BOOL)deleteRecordsWithStatus:(NSInteger)status {
    return [self executeUpdateWithSQL:@"DELETE FROM charge_records WHERE http_status = ?;"
                                bind:^(sqlite3_stmt *stmt) {
                                    sqlite3_bind_int64(stmt, 1, (sqlite3_int64)status);
                                }];
}

- (BOOL)deleteRecordsOlderThan:(NSTimeInterval)timestamp {
    return [self executeUpdateWithSQL:@"DELETE FROM charge_records WHERE created_at < ?;"
                                bind:^(sqlite3_stmt *stmt) {
                                    sqlite3_bind_double(stmt, 1, timestamp);
                                }];
}

- (BOOL)deleteAllRecords {
    return [self executeUpdateWithSQL:@"DELETE FROM charge_records;"
                                bind:^(sqlite3_stmt *stmt) { (void)stmt; }];
}

- (BOOL)trimToMaxRecords:(NSInteger)maxRecords {
    if (maxRecords <= 0) {
        return NO;
    }
    return [self executeUpdateWithSQL:
            @"DELETE FROM charge_records WHERE row_id NOT IN ("
            @"  SELECT row_id FROM charge_records "
            @"  ORDER BY created_at DESC, row_id DESC LIMIT ?"
            @");"
                                bind:^(sqlite3_stmt *stmt) {
                                    sqlite3_bind_int64(stmt, 1, (sqlite3_int64)maxRecords);
                                }];
}

- (BOOL)executeUpdateWithSQL:(NSString *)sql bind:(void (^)(sqlite3_stmt *stmt))binder {
    __block BOOL ok = NO;
    dispatch_sync(_queue, ^{
        if (![self openDatabaseLocked]) {
            return;
        }
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql.UTF8String, -1, &stmt, NULL) != SQLITE_OK) {
            INLog(@"delete/update prepare failed: %s", sqlite3_errmsg(self->_db));
            return;
        }
        if (binder) {
            binder(stmt);
        }
        ok = (sqlite3_step(stmt) == SQLITE_DONE);
        if (!ok) {
            INLog(@"delete/update failed: %s", sqlite3_errmsg(self->_db));
        }
        sqlite3_finalize(stmt);
    });
    return ok;
}

@end
