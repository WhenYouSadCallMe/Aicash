//
//  CASwitchButton — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CASwitchButton;

@class UIColor;
@class UIView;

@interface CASwitchButton : NSObject
    - (void)commonInit;
    - (void)handleTap;
    - (id)initWithCoder:(id)arg1;
    - (id)initWithFrame:(id)arg1;
    - (bool)isOn;
    - (CGRect)knobFrameForOn:(id)arg1;
    - (UIView *)knobView;
    - (void)layoutSubviews;
    - (UIColor *)onTintColor;
    - (bool)pointInside:(id)arg1 withEvent:(id)arg2;
    - (void)setKnobView:(id)arg1;
    - (void)setOn:(id)arg1;
    - (void)setOn:(id)arg1 animated:(id)arg2;
    - (void)setOnTintColor:(id)arg1;
    - (void)setSelected:(id)arg1;
    - (id)switchWithOn:(id)arg1;
    - (id)trackColorForOn:(id)arg1;
    - (void)updateAppearanceAnimated:(id)arg1;

@end

NS_ASSUME_NONNULL_END
