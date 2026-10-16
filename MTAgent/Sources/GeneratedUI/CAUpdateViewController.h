//
//  CAUpdateViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAUpdateViewController : UIViewController
    - (signed long long)activeStage;
    - (void)applyTheme;
    - (UIView *)card;
    - (UIButton *)closeButton;
    - (void)closeSheet;
    - (id)completionHandler;
    - (UILabel *)countLabel;
    - (UILabel *)detailLabel;
    - (void)finishUpdate:(id)arg1 message:(id)arg2;
    - (bool)finished;
    - (CAUpdateViewController *)initWithPythonVersion:(id)arg1;
    - (CAUpdateViewController *)initWithReverseToolsVersion:(id)arg1;
    - (CAUpdateViewController *)initWithTheosVersion:(id)arg1;
    - (CAUpdateViewController *)initWithVersion:(id)arg1;
    - (id)labelWithSize:(id)arg1 weight:(id)arg2;
    - (UIProgressView *)progressBar;
    - (void)pythonEnvironmentChanged;
    - (bool)pythonRuntime;
    - (void)renderProgress:(id)arg1;
    - (UIButton *)retryButton;
    - (void)reverseToolsEnvironmentChanged;
    - (bool)reverseToolsRuntime;
    - (void)setActiveStage:(id)arg1;
    - (void)setCard:(id)arg1;
    - (void)setCloseButton:(id)arg1;
    - (void)setCompletionHandler:(id)arg1;
    - (void)setCountLabel:(id)arg1;
    - (void)setDetailLabel:(id)arg1;
    - (void)setFinished:(id)arg1;
    - (void)setProgressBar:(id)arg1;
    - (void)setPythonRuntime:(id)arg1;
    - (void)setRetryButton:(id)arg1;
    - (void)setReverseToolsRuntime:(id)arg1;
    - (void)setSpinner:(id)arg1;
    - (void)setStageIcons:(id)arg1;
    - (void)setStageLabels:(id)arg1;
    - (void)setStatusLabel:(id)arg1;
    - (void)setSuccess:(id)arg1;
    - (void)setTheosRuntime:(id)arg1;
    - (void)setTitleLabel:(id)arg1;
    - (void)setVersion:(id)arg1;
    - (UIActivityIndicatorView *)spinner;
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

@end

NS_ASSUME_NONNULL_END
