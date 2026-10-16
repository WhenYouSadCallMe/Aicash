//
//  CAGitGroupHeaderView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAGitGroupHeaderView;

@interface CAGitGroupHeaderView : UIView
    - (void)actionTapped;
    - (void)configureWithTitle:(id)arg1 count:(id)arg2 symbol:(id)arg3 tint:(id)arg4 expanded:(id)arg5 actionTitle:(id)arg6 actionEnabled:(id)arg7;
    - (CAGitGroupHeaderView *)initWithReuseIdentifier:(id)arg1;
    - (id)onAction;
    - (id)onToggle;
    - (void)prepareForReuse;
    - (void)setOnAction:(id)arg1;
    - (void)setOnToggle:(id)arg1;
    - (void)toggleTapped;

@end

NS_ASSUME_NONNULL_END
