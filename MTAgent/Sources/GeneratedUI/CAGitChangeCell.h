//
//  CAGitChangeCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAGitChangeCell : UITableViewCell
    - (void)configureWithChange:(id)arg1 side:(id)arg2 stats:(id)arg3 enabled:(id)arg4;
    - (CAGitChangeCell *)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2;
    - (id)onToggle;
    - (void)prepareForReuse;
    - (void)setOnToggle:(id)arg1;
    - (void)toggleTapped;

@end

NS_ASSUME_NONNULL_END
