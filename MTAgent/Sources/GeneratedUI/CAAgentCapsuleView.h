//
//  CAAgentCapsuleView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAAgentCapsuleView : UIView
    - (void)didMoveToWindow;
    - (CAAgentCapsuleView *)initWithFrame:(id)arg1;
    - (double)lastSheenWidth;
    - (void)layoutSubviews;
    - (void)refreshColors;
    - (bool)running;
    - (CAGradientLayer *)runningSheenLayer;
    - (void)setLastSheenWidth:(id)arg1;
    - (void)setRunning:(id)arg1;
    - (void)setRunning:(id)arg1 animated:(id)arg2;
    - (void)setRunningSheenLayer:(id)arg1;
    - (void)synchronizeRunningAnimation;
    - (void)traitCollectionDidChange:(id)arg1;

@end

NS_ASSUME_NONNULL_END
