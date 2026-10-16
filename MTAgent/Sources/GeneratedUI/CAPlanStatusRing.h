//
//  CAPlanStatusRing — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAPlanStatusRing;
@class CAShapeLayer;

@class NSString;
@class UIImageView;

@interface CAPlanStatusRing : NSObject
    - (id)arcLayer;
    - (UIImageView *)checkView;
    - (void)didMoveToWindow;
    - (id)initWithFrame:(id)arg1;
    - (void)layoutSubviews;
    - (void)setArcLayer:(id)arg1;
    - (void)setCheckView:(id)arg1;
    - (void)setState:(id)arg1;
    - (void)setTrackLayer:(id)arg1;
    - (NSString *)state;
    - (void)syncAnimation;
    - (id)trackLayer;
    - (void)traitCollectionDidChange:(id)arg1;
    - (void)updateForState:(id)arg1;

@end

NS_ASSUME_NONNULL_END
