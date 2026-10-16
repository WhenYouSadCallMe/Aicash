//
//  CADiagnosticsRingView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAShapeLayer;

@class UILabel;

@interface CADiagnosticsRingView : UIView
    - (CGSize)intrinsicContentSize;
    - (UILabel *)label;
    - (void)layoutSubviews;
    - (id)progressLayer;
    - (void)setLabel:(id)arg1;
    - (void)setPending:(id)arg1 state:(id)arg2;
    - (void)setProgressLayer:(id)arg1;
    - (void)setTrackLayer:(id)arg1;
    - (id)trackLayer;

@end

NS_ASSUME_NONNULL_END
