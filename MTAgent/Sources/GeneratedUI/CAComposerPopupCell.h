//
//  CAComposerPopupCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAComposerPopupCell;

@interface CAComposerPopupCell : UITableViewCell
    - (UILabel *)badgeLabel;
    - (void)configureWithItem:(id)arg1;
    - (UIView *)highlightView;
    - (UIView *)iconTile;
    - (UIImageView *)iconView;
    - (id)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2;
    - (bool)keyboardHighlighted;
    - (void)setBadgeLabel:(id)arg1;
    - (void)setHighlightView:(id)arg1;
    - (void)setHighlighted:(id)arg1 animated:(id)arg2;
    - (void)setIconTile:(id)arg1;
    - (void)setIconView:(id)arg1;
    - (void)setKeyboardHighlighted:(id)arg1;
    - (void)setSubtitleLabel:(id)arg1;
    - (void)setTitleLabel:(id)arg1;
    - (UILabel *)subtitleLabel;
    - (UILabel *)titleLabel;

@end

NS_ASSUME_NONNULL_END
