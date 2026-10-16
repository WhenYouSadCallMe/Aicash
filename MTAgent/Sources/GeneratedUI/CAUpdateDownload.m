//
//  CAUpdateDownload.m — 运行时归档下载器实现（HTTP 状态检查 + 代理候选 + 字节级进度）
//

#import "CAUpdateDownload.h"
#import "CAUpdateProgress.h"
#import "CARuntimePaths.h"
#import "CACommon.h"
#import "CALogger.h"

/// 进度派发节流（秒）
static const NSTimeInterval kCAUpdateDownloadProgressInterval = 0.1;
/// 单个候选地址的下载上限（秒）
static const NSTimeInterval kCAUpdateDownloadTimeout = 300.0;

@interface CAUpdateDownload ()

- (void)publishProgress;
- (void)finishWithSuccess:(BOOL)success;

@end

@implementation CAUpdateDownload {
    NSString *_destination;
    NSString *_sourceURLString;
    NSString *_currentCandidate;
    dispatch_semaphore_t _doneSemaphore;
    CAUpdateProgress *_progressObject;
    NSError *_error;
    BOOL _success;
    BOOL _finished;
    double _lastProgressTime;
    NSURLSession *_session;
    NSURLSessionDownloadTask *_task;
}

#pragma mark - 构造

- (instancetype)initWithURLString:(NSString *)urlString destination:(NSString *)destination
{
    if ((self = [super init])) {
        _sourceURLString = [urlString copy];
        _destination = [destination copy];
        _currentCandidate = [urlString copy];
        _candidateURLStrings = [self downloadCandidatesForGitHubURLString:urlString];
        _doneSemaphore = dispatch_semaphore_create(0);
        _progressObject = [CAUpdateProgress progressWithStage:CAUpdateStageDownload fraction:0.0 status:@"准备下载"];
    }
    return self;
}

#pragma mark - 声明选择器

- (NSString *)destination { return _destination; }

- (void)setDestination:(NSString *)arg1 { _destination = [arg1 copy]; }

- (id)done { return (id)_doneSemaphore; }

- (void)setDone:(id)arg1 { _doneSemaphore = (dispatch_semaphore_t)arg1; }

- (id)progress { return _progressObject; }

- (void)setProgress:(id)arg1
{
    if (!arg1) {
        _progressObject = nil;
        return;
    }
    if ([arg1 isKindOfClass:CAUpdateProgress.class]) {
        _progressObject = arg1;
        return;
    }
    _progressObject = [CAUpdateProgress progressWithStage:CAUpdateStageDownload fraction:0.0 status:[arg1 description]];
}

- (NSError *)error { return _error; }

- (void)setError:(NSError *)arg1 { _error = arg1; }

- (bool)success { return _success ? YES : NO; }

- (void)setSuccess:(bool)arg1 { _success = arg1 ? YES : NO; }

- (double)lastProgressTime { return _lastProgressTime; }

- (void)setLastProgressTime:(double)arg1 { _lastProgressTime = arg1; }

#pragma mark - 候选地址

- (NSArray<NSString *> *)downloadCandidatesForGitHubURLString:(NSString *)urlString
{
    if (!urlString.length) return [NSArray array];
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    BOOL isGitHub = [urlString hasPrefix:@"https://github.com/"] || [urlString hasPrefix:@"https://raw.githubusercontent.com/"];
    if (isGitHub) {
        for (NSString *prefix in CADownloadProxyPrefixes()) {
            if (prefix.length > 0) [candidates addObject:[prefix stringByAppendingString:urlString]];
        }
    }
    [candidates addObject:urlString];
    return candidates;
}

#pragma mark - 下载

- (BOOL)downloadFromCandidatesWithProgress:(void (^)(CAUpdateProgress *))progress error:(NSError **)error
{
    NSArray<NSString *> *candidates = self.candidateURLStrings;
    if (!candidates.count) candidates = [self downloadCandidatesForGitHubURLString:_sourceURLString];
    if (!candidates.count) {
        if (error) {
            *error = [NSError errorWithDomain:@"CodexApp.Update" code:400
                                     userInfo:@{ NSLocalizedDescriptionKey: @"download url missing" }];
        }
        return NO;
    }

    NSError *lastError = nil;
    for (NSString *candidate in candidates) {
        _currentCandidate = [candidate copy];
        if ([self downloadWithProgress:progress error:&lastError]) return YES;
        CALog(CALogLevelWarn, @"UPDATE", @"download candidate failed url=%@ error=%@",
              _currentCandidate, lastError.localizedDescription ?: @"(unknown)");
    }
    if (error) {
        *error = lastError ?: [NSError errorWithDomain:@"CodexApp.Update" code:500
                                              userInfo:@{ NSLocalizedDescriptionKey: @"all download candidates failed" }];
    }
    return NO;
}

- (BOOL)downloadWithProgress:(void (^)(CAUpdateProgress *))progress error:(NSError **)error
{
    if (!_destination.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"CodexApp.Update" code:400
                                     userInfo:@{ NSLocalizedDescriptionKey: @"download destination missing" }];
        }
        return NO;
    }
    if (!_currentCandidate.length) _currentCandidate = _sourceURLString;
    NSURL *url = [NSURL URLWithString:_currentCandidate];
    if (!url || ![url.scheme.lowercaseString isEqualToString:@"https"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"CodexApp.Update" code:400
                                     userInfo:@{ NSLocalizedDescriptionKey: @"download url rejected (https required)" }];
        }
        return NO;
    }

    [CARuntimePaths ensureDirectory:_destination.stringByDeletingLastPathComponent mode:0700 error:NULL];

    _finished = NO;
    _success = NO;
    _error = nil;
    _lastProgressTime = 0.0;
    _doneSemaphore = dispatch_semaphore_create(0);
    _progressObject = [CAUpdateProgress progressWithStage:CAUpdateStageDownload fraction:0.0 status:@"开始下载"];
    self.progressHandler = progress;

    CALog(CALogLevelInfo, @"UPDATE", @"download start url=%@ destination=%@", _currentCandidate, _destination);
    [self publishProgress];

    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
    configuration.timeoutIntervalForRequest = 30.0;
    configuration.timeoutIntervalForResource = kCAUpdateDownloadTimeout;
    configuration.HTTPAdditionalHeaders = @{ @"User-Agent": CAUserAgent };
    _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    _task = [_session downloadTaskWithURL:url];
    [_task resume];

    BOOL completed = [self waitUntilFinished:kCAUpdateDownloadTimeout];
    [_session invalidateAndCancel];
    _session = nil;
    _task = nil;

    if (_success) {
        CALog(CALogLevelInfo, @"UPDATE", @"download ok url=%@ bytes=%lld", _currentCandidate, _progressObject.completedBytes);
        return YES;
    }
    if (!completed && !_error) {
        _error = [NSError errorWithDomain:@"CodexApp.Update" code:408
                                 userInfo:@{ NSLocalizedDescriptionKey: @"download timed out" }];
    }
    CALog(CALogLevelError, @"UPDATE", @"download failed url=%@ error=%@",
          _currentCandidate, _error.localizedDescription ?: @"(unknown)");
    if (error) {
        *error = _error ?: [NSError errorWithDomain:@"CodexApp.Update" code:500
                                           userInfo:@{ NSLocalizedDescriptionKey: @"download failed" }];
    }
    return NO;
}

- (BOOL)waitUntilFinished:(NSTimeInterval)timeout
{
    if (_finished) return YES;
    dispatch_semaphore_t semaphore = _doneSemaphore;
    if (!semaphore) return NO;
    dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(timeout, 1.0) * NSEC_PER_SEC));
    long waited = dispatch_semaphore_wait(semaphore, deadline);
    if (waited != 0 && !_finished) {
        [_task cancel];
        return NO;
    }
    return YES;
}

#pragma mark - 进度派发

- (void)publishProgress
{
    void (^handler)(CAUpdateProgress *) = self.progressHandler;
    if (!handler || !_progressObject) return;
    CAUpdateProgress *snapshot = _progressObject;
    dispatch_async(dispatch_get_main_queue(), ^{
        handler(snapshot);
    });
}

- (void)finishWithSuccess:(BOOL)success
{
    if (_finished) return;
    _finished = YES;
    _success = success;
    dispatch_semaphore_t semaphore = _doneSemaphore;
    if (semaphore) dispatch_semaphore_signal(semaphore);
}

#pragma mark - NSURLSession（delegateQueue 为串行后台队列）

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didWriteData:(int64_t)bytesWritten
totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    double fraction = totalBytesExpectedToWrite > 0
        ? (double)totalBytesWritten / (double)totalBytesExpectedToWrite
        : 0.0;
    if (!_progressObject) {
        _progressObject = [CAUpdateProgress progressWithStage:CAUpdateStageDownload fraction:0.0 status:@"下载中"];
    }
    [_progressObject applyStage:CAUpdateStageDownload
                       fraction:fraction
                 completedBytes:totalBytesWritten
                     totalBytes:totalBytesExpectedToWrite
                         status:@"下载中"];

    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (fraction < 1.0 && (now - _lastProgressTime) < kCAUpdateDownloadProgressInterval) return;
    _lastProgressTime = now;
    [self publishProgress];
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    NSHTTPURLResponse *http = [downloadTask.response isKindOfClass:NSHTTPURLResponse.class]
        ? (NSHTTPURLResponse *)downloadTask.response
        : nil;
    if (http && http.statusCode >= 400) {
        _error = [NSError errorWithDomain:@"CodexApp.Update" code:http.statusCode
                                 userInfo:@{ NSLocalizedDescriptionKey:
                                                 [NSString stringWithFormat:@"download http status=%ld", (long)http.statusCode] }];
        return;
    }
    if (!_destination.length) {
        _error = [NSError errorWithDomain:@"CodexApp.Update" code:400
                                 userInfo:@{ NSLocalizedDescriptionKey: @"download destination missing" }];
        return;
    }

    NSString *directory = _destination.stringByDeletingLastPathComponent;
    [CARuntimePaths ensureDirectory:directory mode:0700 error:NULL];
    if ([NSFileManager.defaultManager fileExistsAtPath:_destination]) {
        [NSFileManager.defaultManager removeItemAtPath:_destination error:NULL];
    }

    NSError *moveError = nil;
    if (![NSFileManager.defaultManager moveItemAtURL:location toURL:[NSURL fileURLWithPath:_destination] error:&moveError]) {
        _error = moveError;
        _success = NO;
        return;
    }
    chmod(_destination.fileSystemRepresentation, 0644);
    _success = YES;
    _error = nil;
    [_progressObject applyStage:CAUpdateStageDownload
                       fraction:1.0
                 completedBytes:_progressObject.totalBytes
                     totalBytes:_progressObject.totalBytes
                         status:@"下载完成"];
    _lastProgressTime = NSDate.date.timeIntervalSince1970;
    [self publishProgress];
}

- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    if (error && !_success) {
        _error = error;
    } else if (!_success && !_error) {
        NSHTTPURLResponse *http = [task.response isKindOfClass:NSHTTPURLResponse.class]
            ? (NSHTTPURLResponse *)task.response
            : nil;
        NSInteger status = http ? http.statusCode : 0;
        _error = [NSError errorWithDomain:@"CodexApp.Update" code:status > 0 ? status : 500
                                 userInfo:@{ NSLocalizedDescriptionKey:
                                                 [NSString stringWithFormat:@"download failed status=%ld", (long)status] }];
    }
    if (_success) {
        [_progressObject applyStage:CAUpdateStageDownload fraction:1.0
                     completedBytes:_progressObject.completedBytes
                         totalBytes:_progressObject.totalBytes
                             status:@"下载完成"];
    } else if (_progressObject) {
        [_progressObject applyStage:CAUpdateStageDownload fraction:-1.0
                     completedBytes:0 totalBytes:0
                             status:_error.localizedDescription ?: @"下载失败"];
    }
    [self publishProgress];
    [self finishWithSuccess:_success];
}

@end
