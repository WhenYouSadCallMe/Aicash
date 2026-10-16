//
//  CAUpdateViewController — 运行时更新/修复进度页（下载 → 校验 → 解包 → 签名 → 安装）
//  选择器原型取自 SPEC/method_types.json（参数类型按原包原型校正）；本实现补全分阶段安装行为
//  依赖：CARuntimeCatalog / CARuntimePaths / CAUpdateManager / CAArchiveExtractor /
//        CAManagedRuntimeDownload（→ CAUpdateDownload）/ CALogger
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "CAUpdateProgress.h"

NS_ASSUME_NONNULL_BEGIN

@class CAUpdateViewController;
@class UIActivityIndicatorView;
@class UIProgressView;

@class CARuntimeCatalogEntry;
@class NSArray;
@class NSString;
@class UIButton;
@class UILabel;
@class UIView;

/// 结束回调（成功/失败 + 文案）
typedef void (^CAUpdateFinishHandler)(BOOL success, NSString *_Nullable message);

@interface CAUpdateViewController : UIViewController
    - (signed long long)activeStage;
    - (void)applyTheme;
    - (UIView *)card;
    - (UIButton *)closeButton;
    - (void)closeSheet;
    - (id)completionHandler;
    - (UILabel *)countLabel;
    - (UILabel *)detailLabel;
    - (void)finishUpdate:(bool)arg1 message:(NSString *)arg2;
    - (bool)finished;
    - (id)initWithPythonVersion:(NSString *)arg1;
    - (id)initWithReverseToolsVersion:(NSString *)arg1;
    - (id)initWithTheosVersion:(NSString *)arg1;
    - (id)initWithVersion:(NSString *)arg1;
    - (id)labelWithSize:(double)arg1 weight:(double)arg2;
    - (id)progressBar;
    - (void)pythonEnvironmentChanged;
    - (bool)pythonRuntime;
    - (void)renderProgress:(id)arg1;
    - (UIButton *)retryButton;
    - (void)reverseToolsEnvironmentChanged;
    - (bool)reverseToolsRuntime;
    - (void)setActiveStage:(signed long long)arg1;
    - (void)setCard:(UIView *)arg1;
    - (void)setCloseButton:(UIButton *)arg1;
    - (void)setCompletionHandler:(id)arg1;
    - (void)setCountLabel:(UILabel *)arg1;
    - (void)setDetailLabel:(UILabel *)arg1;
    - (void)setFinished:(bool)arg1;
    - (void)setProgressBar:(UIProgressView *)arg1;
    - (void)setPythonRuntime:(bool)arg1;
    - (void)setRetryButton:(UIButton *)arg1;
    - (void)setReverseToolsRuntime:(bool)arg1;
    - (void)setSpinner:(UIActivityIndicatorView *)arg1;
    - (void)setStageIcons:(id)arg1;
    - (void)setStageLabels:(id)arg1;
    - (void)setStatusLabel:(UILabel *)arg1;
    - (void)setSuccess:(bool)arg1;
    - (void)setTheosRuntime:(bool)arg1;
    - (void)setTitleLabel:(UILabel *)arg1;
    - (void)setVersion:(NSString *)arg1;
    - (id)spinner;
    - (NSArray *)stageIcons;
    - (NSArray *)stageLabels;
    - (void)startUpdate;
    - (UILabel *)statusLabel;
    - (bool)success;
    - (void)theosEnvironmentChanged;
    - (bool)theosRuntime;
    - (UILabel *)titleLabel;
    - (void)updateStageIcons;
    - (NSString *)version;
    - (void)viewDidLoad;

#pragma mark - 外壳补全（使用面）

/// 目标运行时 ID（codex / python / theos / reverse-tools）
- (NSString *)runtimeID;

- (instancetype)initWithRuntimeID:(NSString *)runtimeID version:(nullable NSString *)version;

/// 结束回调（与 completionHandler 等价，块签名明确）
@property (nonatomic, copy, nullable) CAUpdateFinishHandler finishHandler;

/// 重试（失败后再次执行完整分阶段安装）
- (void)restartUpdate;

/// 同步分阶段安装（下载 → 校验 → 解包 → 签名 → 安装）；供设置页/诊断页复用
+ (BOOL)installRuntimeEntry:(CARuntimeCatalogEntry *)entry
                   progress:(nullable void (^)(CAUpdateProgress *progress))progress
                      error:(NSError **)error;

/// 已安装运行时版本（读 <runtimeRoot>/manifest.json；未安装返回 nil）
+ (nullable NSString *)installedVersionForRuntimeID:(NSString *)runtimeID;

/// 是否已安装（有安装记录，或运行时目录内已有解包内容）
+ (BOOL)isRuntimeInstalled:(NSString *)runtimeID;

@end

NS_ASSUME_NONNULL_END
