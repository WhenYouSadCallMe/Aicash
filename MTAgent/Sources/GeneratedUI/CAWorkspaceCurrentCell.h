//
//  CAWorkspaceCurrentCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAWorkspaceCurrentCell : UITableViewCell
    - (CAWorkspaceBadgeView *)badge;
    - (UILabel *)captionLabel;
    - (void)configureWithName:(id)arg1 path:(id)arg2 meta:(id)arg3 symbol:(id)arg4 tint:(id)arg5;
    - (void)copyPathTapped;
    - (UIButton *)filzaButton;
    - (void)filzaTapped;
    - (CAWorkspaceCurrentCell *)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2;
    - (UILabel *)metaLabel;
    - (UILabel *)nameLabel;
    - (id)onCopyPath;
    - (id)onFilza;
    - (UIButton *)pathCopyButton;
    - (UILabel *)pathLabel;
    - (id)pillButtonWithTitle:(id)arg1 symbol:(id)arg2;
    - (void)setBadge:(id)arg1;
    - (void)setCaptionLabel:(id)arg1;
    - (void)setFilzaButton:(id)arg1;
    - (void)setMetaLabel:(id)arg1;
    - (void)setNameLabel:(id)arg1;
    - (void)setOnCopyPath:(id)arg1;
    - (void)setOnFilza:(id)arg1;
    - (void)setPathCopyButton:(id)arg1;
    - (void)setPathLabel:(id)arg1;

@end

NS_ASSUME_NONNULL_END
