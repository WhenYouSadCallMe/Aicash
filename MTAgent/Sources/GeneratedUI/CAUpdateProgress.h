//
//  CAUpdateProgress — 运行时更新进度模型（stage / fraction / bytes / status）
//  选择器与返回值取自 SPEC/method_types.json（参数类型按原包原型校正）
//  行为：CAUpdateDownload 写字节进度，CAUpdateViewController 渲染分阶段状态
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString;

/// 分阶段安装进度（与原包 stage 数值同序：下载 → 校验 → 解包 → 签名 → 安装）
typedef NS_ENUM(NSInteger, CAUpdateStage) {
    CAUpdateStageIdle     = 0,
    CAUpdateStageDownload = 1,
    CAUpdateStageVerify   = 2,
    CAUpdateStageExtract  = 3,
    CAUpdateStageSign     = 4,
    CAUpdateStageInstall  = 5,
    CAUpdateStageFinished = 6,
};

@interface CAUpdateProgress : NSObject
    - (signed long long)completedBytes;
    - (double)fraction;
    - (void)setCompletedBytes:(signed long long)arg1;
    - (void)setFraction:(double)arg1;
    - (void)setStage:(signed long long)arg1;
    - (void)setStatus:(NSString *)arg1;
    - (void)setTotalBytes:(signed long long)arg1;
    - (signed long long)stage;
    - (NSString *)status;
    - (signed long long)totalBytes;

/// 便捷构造
+ (instancetype)progressWithStage:(CAUpdateStage)stage
                         fraction:(double)fraction
                           status:(nullable NSString *)status;

/// 应用一次分阶段/字节更新（fraction < 0 时保持原值）
- (void)applyStage:(CAUpdateStage)stage
          fraction:(double)fraction
     completedBytes:(signed long long)completedBytes
        totalBytes:(signed long long)totalBytes
            status:(nullable NSString *)status;

/// 阶段中文名（等待 / 下载 / 校验 / 解包 / 签名 / 安装 / 完成）
+ (NSString *)stageTitle:(CAUpdateStage)stage;
- (NSString *)stageTitle;

/// 人类可读字节数（如 12.3 MB；totalBytes 为 0 时返回 @"—"）
- (NSString *)byteCountText;

@end

NS_ASSUME_NONNULL_END
