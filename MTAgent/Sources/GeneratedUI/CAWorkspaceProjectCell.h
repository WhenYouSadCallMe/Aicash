//
//  CAWorkspaceProjectCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAWorkspaceProjectCell : UITableViewCell
    - (CAWorkspaceBadgeView *)badge;
    - (UIImageView *)checkView;
    - (void)configureWithName:(id)arg1 path:(id)arg2 meta:(id)arg3 metaWarning:(id)arg4 symbol:(id)arg5 tint:(id)arg6 active:(id)arg7;
    - (CAWorkspaceProjectCell *)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2;
    - (UILabel *)metaLabel;
    - (UILabel *)nameLabel;
    - (UILabel *)pathLabel;
    - (void)setBadge:(id)arg1;
    - (void)setCheckView:(id)arg1;
    - (void)setMetaLabel:(id)arg1;
    - (void)setNameLabel:(id)arg1;
    - (void)setPathLabel:(id)arg1;

@end

NS_ASSUME_NONNULL_END
