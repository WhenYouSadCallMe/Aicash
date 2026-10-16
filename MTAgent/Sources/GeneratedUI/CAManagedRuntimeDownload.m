//
//  CAManagedRuntimeDownload.m — 受管运行时归档下载实现（组合 CAUpdateDownload）
//

#import "CAManagedRuntimeDownload.h"
#import "CAUpdateDownload.h"
#import "CAUpdateProgress.h"
#import "CARuntimeCatalog.h"
#import "CARuntimePaths.h"
#import "CAUpdateManager.h"
#import "CACommon.h"
#import "CALogger.h"

@interface CAManagedRuntimeDownload ()

- (CAUpdateDownload *)makeInnerDownload;

@end

@implementation CAManagedRuntimeDownload {
    NSString *_destination;
    NSString *_archiveURLString;
    NSString *_sha256;
    CAUpdateDownload *_inner;
    CAUpdateProgress *_progressObject;
    NSError *_error;
    BOOL _success;
}

- (instancetype)initWithRuntimeID:(NSString *)runtimeID
                       archiveURL:(NSString *)archiveURL
                           sha256:(NSString *)sha256
{
    if ((self = [super init])) {
        _runtimeID = [runtimeID copy];
        _archiveURLString = [archiveURL copy];
        _sha256 = [sha256 copy];
        _destination = [[CARuntimePaths archiveCachePathForEntry:runtimeID sha256:sha256] copy];
    }
    return self;
}

- (instancetype)initWithEntry:(CARuntimeCatalogEntry *)entry
{
    return [self initWithRuntimeID:entry.runtimeID ?: @""
                        archiveURL:entry.archiveURL ?: @""
                            sha256:entry.archiveSHA256];
}

#pragma mark - 声明选择器

- (NSString *)destination { return _destination; }

- (void)setDestination:(id)arg1 { _destination = [arg1 copy]; }

- (id)done { return _inner ? [_inner done] : nil; }

- (void)setDone:(id)arg1
{
    if (!_inner) _inner = [self makeInnerDownload];
    [_inner setDone:arg1];
}

- (NSError *)error { return _error ?: [_inner error]; }

- (void)setError:(id)arg1
{
    _error = [arg1 isKindOfClass:NSError.class] ? arg1 : nil;
    if (_inner) [_inner setError:_error];
}

- (id)progress { return _progressObject ?: [_inner progress]; }

- (void)setProgress:(id)arg1
{
    if ([arg1 isKindOfClass:CAUpdateProgress.class]) _progressObject = arg1;
    if (_inner) [_inner setProgress:arg1];
}

- (bool)success { return _success ? YES : NO; }

- (void)setSuccess:(bool)arg1
{
    _success = arg1 ? YES : NO;
    if (_inner) [_inner setSuccess:arg1];
}

#pragma mark - 会话回调转发（保持与 CAUpdateDownload 同形，便于任一处挂为 delegate）

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location
{
    [_inner URLSession:session downloadTask:downloadTask didFinishDownloadingToURL:location];
    _success = _inner.success;
    _error = _inner.error;
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
     didWriteData:(int64_t)bytesWritten
totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    [_inner URLSession:session
          downloadTask:downloadTask
         didWriteData:bytesWritten
    totalBytesWritten:totalBytesWritten
totalBytesExpectedToWrite:totalBytesExpectedToWrite];
    _progressObject = [_inner progress];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    [_inner URLSession:session task:task didCompleteWithError:error];
    _success = _inner.success;
    _error = _inner.error;
}

#pragma mark - 下载

- (CAUpdateDownload *)makeInnerDownload
{
    CAUpdateDownload *inner = [[CAUpdateDownload alloc] initWithURLString:_archiveURLString
                                                             destination:_destination];
    inner.progressHandler = self.progressHandler;
    return inner;
}

- (BOOL)downloadWithProgress:(void (^)(CAUpdateProgress *))progress error:(NSError **)error
{
    if (!_archiveURLString.length || !_destination.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"CodexApp.Runtime" code:400
                                     userInfo:@{ NSLocalizedDescriptionKey: @"runtime archive url missing" }];
        }
        return NO;
    }

    if (_sha256.length &&
        [NSFileManager.defaultManager fileExistsAtPath:_destination] &&
        [[CAUpdateManager sharedManager] cachedPackageAtPath:_destination matchesSHA256:_sha256]) {
        _success = YES;
        _error = nil;
        _progressObject = [CAUpdateProgress progressWithStage:CAUpdateStageDownload fraction:1.0 status:@"使用已缓存归档"];
        if (progress) progress(_progressObject);
        CALog(CALogLevelInfo, @"RUNTIME", @"%@ archive cache hit path=%@", self.runtimeID ?: @"runtime", _destination);
        return YES;
    }

    self.progressHandler = progress;
    _inner = [self makeInnerDownload];
    _inner.progressHandler = progress;

    NSError *downloadError = nil;
    BOOL ok = [_inner downloadFromCandidatesWithProgress:progress error:&downloadError];
    _success = ok;
    _error = ok ? nil : downloadError;
    _progressObject = ok
        ? (CAUpdateProgress *)[_inner progress]
        : [CAUpdateProgress progressWithStage:CAUpdateStageDownload
                                    fraction:0.0
                                      status:downloadError.localizedDescription ?: @"下载失败"];
    CALog(ok ? CALogLevelInfo : CALogLevelError, @"RUNTIME", @"%@ archive download ok=%d path=%@ error=%@",
          self.runtimeID ?: @"runtime", ok, _destination, downloadError.localizedDescription ?: @"(none)");
    return ok;
}

@end
