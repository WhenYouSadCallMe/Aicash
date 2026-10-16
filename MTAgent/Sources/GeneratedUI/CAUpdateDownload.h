//
//  CAUpdateDownload — 运行时归档下载器（NSURLSession + 代理候选 + 字节级进度）
//  选择器原型取自 SPEC/method_types.json：delegate 三连 + destination/progress/error/success/done/lastProgressTime
//  行为：GitHub 直连失败时按 gh-proxy 前缀重试（CADownloadProxyPrefixes），完成后把临时文件移动到 destination
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class OS_dispatch_semaphore;

@class CAUpdateProgress;
@class NSError;
@class NSString;

@interface CAUpdateDownload : NSObject
    - (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location;
    - (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite;
    - (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error;
    - (NSString *)destination;
    - (id)done;
    - (id)progress;
    - (NSArray<NSString *> *)downloadCandidatesForGitHubURLString:(NSString *)urlString;
    - (NSError *)error;
    - (double)lastProgressTime;
    - (void)setDestination:(NSString *)arg1;
    - (void)setDone:(id)arg1;
    - (void)setError:(NSError *)arg1;
    - (void)setLastProgressTime:(double)arg1;
    - (void)setProgress:(id)arg1;
    - (void)setSuccess:(bool)arg1;
    - (bool)success;

#pragma mark - 使用面（外壳补全）

/// 候选地址（缺省为 GitHub 直连 + 代理前缀），可在 downloadFromCandidatesWithProgress:error: 前替换
@property (nonatomic, copy, nullable) NSArray<NSString *> *candidateURLStrings;

/// 字节级进度回调（主线程派发）
@property (nonatomic, copy, nullable) void (^progressHandler)(CAUpdateProgress *progress);

- (instancetype)initWithURLString:(NSString *)urlString destination:(NSString *)destination;

/// 依次尝试候选地址，全部失败时返回 NO 并给出最后一个错误
- (BOOL)downloadFromCandidatesWithProgress:(nullable void (^)(CAUpdateProgress *progress))progress
                                     error:(NSError **)error;

/// 单地址下载（候选已在 candidateURLStrings 内）
- (BOOL)downloadWithProgress:(nullable void (^)(CAUpdateProgress *progress))progress
                       error:(NSError **)error;

/// 阻塞等待当前任务结束（同步下载用）
- (BOOL)waitUntilFinished:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END
