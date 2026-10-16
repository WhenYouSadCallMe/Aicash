//
//  CAReverseToolsDownload — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAReverseToolsDownload : NSObject
    - (void)URLSession:(id)arg1 downloadTask:(id)arg2 didFinishDownloadingToURL:(id)arg3;
    - (void)URLSession:(id)arg1 downloadTask:(id)arg2 didWriteData:(id)arg3 totalBytesWritten:(id)arg4 totalBytesExpectedToWrite:(id)arg5;
    - (void)URLSession:(id)arg1 task:(id)arg2 didCompleteWithError:(id)arg3;
    - (NSString *)destination;
    - (OS_dispatch_semaphore *)done;
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
