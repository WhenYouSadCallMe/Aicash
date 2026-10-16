//
//  CAWorkspaceBadgeView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAWorkspaceBadgeView;

@class UIImageView;
@class UILabel;

@interface CAWorkspaceBadgeView : UIView
    - (void)configureWithName:(id)arg1 symbol:(id)arg2 tint:(id)arg3 size:(id)arg4;
    - (id)initWithFrame:(id)arg1;
    - (UILabel *)monogramLabel;
    - (void)setMonogramLabel:(id)arg1;
    - (void)setSymbolView:(id)arg1;
    - (UIImageView *)symbolView;

@end

NS_ASSUME_NONNULL_END
