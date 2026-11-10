//
//  NetworkManager.m
//

#import "NetworkManager.h"
#import "IosNotiLog.h"

static const NSUInteger kMaxBodyLength = 8192;
static const NSTimeInterval kDefaultTimeout = 15.0;

#pragma mark - NetworkResult

@implementation NetworkResult

- (BOOL)success {
    return self.statusCode >= 200 && self.statusCode < 300;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<NetworkResult status=%ld error=%@ body=%.120@>",
            (long)self.statusCode, self.errorMessage ?: @"-", self.body ?: @""];
}

@end

#pragma mark - NetworkManager

@interface NetworkManager ()
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation NetworkManager

+ (instancetype)sharedManager {
    static NetworkManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[NetworkManager alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _timeoutInterval = kDefaultTimeout;
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        config.timeoutIntervalForRequest  = kDefaultTimeout;
        config.timeoutIntervalForResource = kDefaultTimeout * 2;
        config.waitsForConnectivity       = NO;
        config.HTTPAdditionalHeaders      = @{@"User-Agent": @"IosNoti/1.0 (iOS)"};
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

#pragma mark - Request building

- (NSURLRequest *)requestWithJSON:(NSDictionary *)json urlString:(NSString *)urlString error:(NSError **)error {
    if (urlString.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"IosNotiNetwork"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"server_url rỗng"}];
        }
        return nil;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (error) {
            *error = [NSError errorWithDomain:@"IosNotiNetwork"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"server_url không hợp lệ"}];
        }
        return nil;
    }

    NSData *body = [NSJSONSerialization dataWithJSONObject:json options:0 error:error];
    if (!body) {
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    request.timeoutInterval = self.timeoutInterval > 0 ? self.timeoutInterval : kDefaultTimeout;
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)body.length]
   forHTTPHeaderField:@"Content-Length"];
    return request;
}

#pragma mark - Public

- (void)POSTJSON:(NSDictionary *)json
           toURL:(NSString *)urlString
      completion:(NetworkCompletion)completion {
    NSError *buildError = nil;
    NSURLRequest *request = [self requestWithJSON:json urlString:urlString error:&buildError];

    if (!request) {
        INLog(@"POST build failed: %@", buildError.localizedDescription);
        NetworkResult *result = [[NetworkResult alloc] init];
        result.errorMessage = buildError.localizedDescription ?: @"build request failed";
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
        }
        return;
    }

    NSDate *start = [NSDate date];
    NSURLSessionDataTask *task =
        [self.session dataTaskWithRequest:request
                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NetworkResult *result = [[NetworkResult alloc] init];
        result.duration = [[NSDate date] timeIntervalSinceDate:start];

        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            result.statusCode = ((NSHTTPURLResponse *)response).statusCode;
        }
        if (data.length > 0) {
            NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!body) {
                body = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
            }
            if (body.length > kMaxBodyLength) {
                body = [[body substringToIndex:kMaxBodyLength] stringByAppendingString:@"…(truncated)"];
            }
            result.body = body ?: @"";
        } else {
            result.body = @"";
        }
        if (error) {
            result.errorMessage = [NSString stringWithFormat:@"%@ (%ld)", error.localizedDescription, (long)error.code];
            INLog(@"POST error: %@", result.errorMessage);
        } else {
            INLog(@"POST %ld (%.2fs) body=%.200@", (long)result.statusCode, result.duration, result.body);
        }

        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
        }
    }];
    [task resume];
}

- (NetworkResult *)POSTJSONSynchronously:(NSDictionary *)json toURL:(NSString *)urlString {
    NSError *buildError = nil;
    NSURLRequest *request = [self requestWithJSON:json urlString:urlString error:&buildError];
    NetworkResult *result = [[NetworkResult alloc] init];

    if (!request) {
        result.errorMessage = buildError.localizedDescription ?: @"build request failed";
        return result;
    }

    NSDate *start = [NSDate date];
    __block NSData *responseData = nil;
    __block NSURLResponse *responseRef = nil;
    __block NSError *requestError = nil;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task =
        [self.session dataTaskWithRequest:request
                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        responseData = data;
        responseRef = response;
        requestError = error;
        dispatch_semaphore_signal(sema);
    }];
    [task resume];
    dispatch_semaphore_wait(sema, dispatch_time(DISPATCH_TIME_NOW,
                                                (int64_t)((self.timeoutInterval + 5.0) * NSEC_PER_SEC)));

    result.duration = [[NSDate date] timeIntervalSinceDate:start];
    if ([responseRef isKindOfClass:[NSHTTPURLResponse class]]) {
        result.statusCode = ((NSHTTPURLResponse *)responseRef).statusCode;
    }
    if (responseData.length > 0) {
        NSString *body = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
        if (body.length > kMaxBodyLength) {
            body = [[body substringToIndex:kMaxBodyLength] stringByAppendingString:@"…(truncated)"];
        }
        result.body = body ?: @"";
    } else {
        result.body = @"";
    }
    if (requestError) {
        result.errorMessage = requestError.localizedDescription;
    } else if (responseData.length == 0 && [responseRef isKindOfClass:[NSHTTPURLResponse class]] == NO) {
        result.errorMessage = @"timeout";
    }
    return result;
}

@end
