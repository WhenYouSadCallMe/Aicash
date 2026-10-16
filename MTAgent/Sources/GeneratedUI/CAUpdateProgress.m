//
//  CAUpdateProgress.m — 运行时更新进度模型实现
//

#import "CAUpdateProgress.h"

@implementation CAUpdateProgress {
    signed long long _stage;
    double _fraction;
    signed long long _completedBytes;
    signed long long _totalBytes;
    NSString *_status;
}

#pragma mark - 构造

+ (instancetype)progressWithStage:(CAUpdateStage)stage
                         fraction:(double)fraction
                           status:(NSString *)status
{
    CAUpdateProgress *progress = [[CAUpdateProgress alloc] init];
    [progress applyStage:stage fraction:fraction completedBytes:0 totalBytes:0 status:status];
    return progress;
}

#pragma mark - 声明选择器

- (signed long long)completedBytes { return _completedBytes; }

- (double)fraction { return _fraction; }

- (void)setCompletedBytes:(signed long long)arg1 { _completedBytes = arg1; }

- (void)setFraction:(double)arg1 { _fraction = arg1; }

- (void)setStage:(signed long long)arg1 { _stage = arg1; }

- (void)setStatus:(NSString *)arg1 { _status = [arg1 copy]; }

- (void)setTotalBytes:(signed long long)arg1 { _totalBytes = arg1; }

- (signed long long)stage { return _stage; }

- (NSString *)status { return _status ?: @""; }

- (signed long long)totalBytes { return _totalBytes; }

#pragma mark - 更新

- (void)applyStage:(CAUpdateStage)stage
          fraction:(double)fraction
     completedBytes:(signed long long)completedBytes
        totalBytes:(signed long long)totalBytes
            status:(NSString *)status
{
    _stage = (signed long long)stage;
    if (fraction >= 0.0) {
        _fraction = MAX(0.0, MIN(1.0, fraction));
    }
    if (completedBytes > 0) _completedBytes = completedBytes;
    if (totalBytes > 0) _totalBytes = totalBytes;
    if (status.length > 0) _status = [status copy];
}

+ (NSString *)stageTitle:(CAUpdateStage)stage
{
    switch (stage) {
        case CAUpdateStageIdle:     return @"等待";
        case CAUpdateStageDownload: return @"下载";
        case CAUpdateStageVerify:   return @"校验";
        case CAUpdateStageExtract:  return @"解包";
        case CAUpdateStageSign:     return @"签名";
        case CAUpdateStageInstall:  return @"安装";
        case CAUpdateStageFinished: return @"完成";
    }
    return @"等待";
}

- (NSString *)stageTitle
{
    return [CAUpdateProgress stageTitle:(CAUpdateStage)_stage];
}

- (NSString *)byteCountText
{
    if (_totalBytes <= 0) {
        return _completedBytes > 0
            ? [NSByteCountFormatter stringFromByteCount:_completedBytes countStyle:NSByteCountFormatterCountStyleFile]
            : @"—";
    }
    NSString *completed = [NSByteCountFormatter stringFromByteCount:_completedBytes countStyle:NSByteCountFormatterCountStyleFile];
    NSString *total = [NSByteCountFormatter stringFromByteCount:_totalBytes countStyle:NSByteCountFormatterCountStyleFile];
    return [NSString stringWithFormat:@"%@ / %@", completed, total];
}

@end
