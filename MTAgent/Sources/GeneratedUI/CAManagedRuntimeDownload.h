//
//  CAManagedRuntimeDownload — 受管 codex 运行时归档下载（清单条目 → 缓存路径 → CAUpdateDownload）
//  选择器原型取自 SPEC/method_types.json（delegate 三连 + destination/progress/error/success/done）
//  行为：按 CARuntimePaths.archiveCachePathForEntry:sha256: 落盘，进度透传 CAUpdateDownload
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class OS_dispatch_semaphore;

@class CAUpdateDownload;
@class CAUpdateProgress;
@class CARuntimeCatalogEntry;
@class NSError;
@class NSString;

@interface CAManagedRuntimeDownload : NSObject
    - (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location;
    - (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite;
    - (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error;
    - (NSString *)destination;
    - (id)done;
    - (NSError *)error;
    - (id)progress;
    - (void)setDestination:(id)arg1;
    - (void)setDone:(id)arg1;
    - (void)setError:(id)arg1;
    - (void)setProgress:(id)arg1;
    - (void)setSuccess:(bool)arg1;
    - (bool)success;

#pragma mark - 使用面（外壳补全）

@property (nonatomic, copy, readonly, nullable) NSString *runtimeID;

/// 字节级进度回调（主线程派发）
@property (nonatomic, copy, nullable) void (^progressHandler)(CAUpdateProgress *progress);

- (instancetype)initWithEntry:(CARuntimeCatalogEntry *)entry;
- (instancetype)initWithRuntimeID:(NSString *)runtimeID
                       archiveURL:(NSString *)archiveURL
                           sha256:(nullable NSString *)sha256;

/// 下载清单条目归档到运行时下载缓存目录；已存在且 SHA256 命中时直接返回 YES
- (BOOL)downloadWithProgress:(nullable void (^)(CAUpdateProgress *progress))progress
                       error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
