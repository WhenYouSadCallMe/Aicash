//
//  CAReverseToolsDownload — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class OS_dispatch_semaphore;

@class NSError;
@class NSString;

@interface CAReverseToolsDownload : NSObject
    - (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location;
    - (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite;
    - (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error;
    - (NSString *)destination;
    - (id)done;
    - (NSError *)error;
    - (double)lastProgressTime;
    - (id)progress;
    - (void)setDestination:(id)arg1;
    - (void)setDone:(id)arg1;
    - (void)setError:(id)arg1;
    - (void)setLastProgressTime:(id)arg1;
    - (void)setProgress:(id)arg1;
    - (void)setSuccess:(id)arg1;
    - (bool)success;

@end

NS_ASSUME_NONNULL_END
