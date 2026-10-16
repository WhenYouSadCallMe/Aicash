//
//  CAConversationCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAConversationCell : UITableViewCell
    - (UIView *)activeBar;
    - (void)configureWithRecord:(id)arg1 active:(id)arg2 running:(id)arg3;
    - (UIImageView *)conversationIcon;
    - (CAConversationCell *)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2;
    - (void)setActiveBar:(id)arg1;
    - (void)setConversationIcon:(id)arg1;
    - (void)setSubtitleLabel:(id)arg1;
    - (void)setSurfaceView:(id)arg1;
    - (void)setTitleLabel:(id)arg1;
    - (UILabel *)subtitleLabel;
    - (UIView *)surfaceView;
    - (UILabel *)titleLabel;

@end

NS_ASSUME_NONNULL_END
