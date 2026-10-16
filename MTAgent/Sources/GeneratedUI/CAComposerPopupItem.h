//
//  CAComposerPopupItem — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString;
@class UIColor;

@interface CAComposerPopupItem : NSObject
    - (NSString *)badge;
    - (bool)enabled;
    - (NSString *)identifier;
    - (id)itemWithIdentifier:(id)arg1 title:(id)arg2 subtitle:(id)arg3 symbol:(id)arg4;
    - (id)payload;
    - (id)placeholderWithTitle:(id)arg1 subtitle:(id)arg2 symbol:(id)arg3;
    - (void)setBadge:(id)arg1;
    - (void)setEnabled:(id)arg1;
    - (void)setIdentifier:(id)arg1;
    - (void)setPayload:(id)arg1;
    - (void)setSubtitle:(id)arg1;
    - (void)setSymbol:(id)arg1;
    - (void)setTint:(id)arg1;
    - (void)setTitle:(id)arg1;
    - (NSString *)subtitle;
    - (NSString *)symbol;
    - (UIColor *)tint;
    - (NSString *)title;

@end

NS_ASSUME_NONNULL_END
