//
//  CAWorkspaceActionsCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAWorkspaceActionsCell;

@class UIButton;

@interface CAWorkspaceActionsCell : UITableViewCell
    - (void)applyTheme;
    - (UIButton *)browseButton;
    - (void)browseTapped;
    - (UIButton *)createButton;
    - (void)createTapped;
    - (id)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2;
    - (id)onBrowse;
    - (id)onCreate;
    - (void)setBrowseButton:(id)arg1;
    - (void)setCreateButton:(id)arg1;
    - (void)setOnBrowse:(id)arg1;
    - (void)setOnCreate:(id)arg1;
    - (id)tileWithTitle:(id)arg1 subtitle:(id)arg2 symbol:(id)arg3;

@end

NS_ASSUME_NONNULL_END
