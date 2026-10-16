//
//  CAAgentProgressRingView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAAgentProgressRingView : UIView
    - (CAAgentProgressRingView *)initWithFrame:(id)arg1;
    - (void)layoutSubviews;
    - (CAShapeLayer *)progressLayer;
    - (void)setProgressLayer:(id)arg1;
    - (void)setStatus:(id)arg1;
    - (void)setTrackLayer:(id)arg1;
    - (NSString *)status;
    - (CAShapeLayer *)trackLayer;

@end

NS_ASSUME_NONNULL_END
