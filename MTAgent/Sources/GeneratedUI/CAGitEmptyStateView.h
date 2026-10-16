//
//  CAGitEmptyStateView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAGitEmptyStateView;

@interface CAGitEmptyStateView : UIView
    - (void)actionTapped;
    - (void)applyTheme;
    - (CAGitEmptyStateView *)initWithFrame:(id)arg1;
    - (id)onAction;
    - (void)setOnAction:(id)arg1;
    - (void)showLoadingWithTitle:(id)arg1;
    - (void)showSymbol:(id)arg1 title:(id)arg2 detail:(id)arg3 actionTitle:(id)arg4;

@end

NS_ASSUME_NONNULL_END
