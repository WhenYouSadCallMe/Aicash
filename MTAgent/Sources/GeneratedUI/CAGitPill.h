//
//  CAGitPill.h — Git 仓库卡片里的分支/远程胶囊按钮（原包 3 个 ivar: _chevronView/_iconView/_label）
//
//  选择器原型取自 SPEC/method_types.json（逐字保留）：
//    -initWithFrame:  -configureWithTitle:symbol:emphasized:showsChevron:
//    -setEnabled:  -setHighlighted:
//  原包该类拥有 initWithFrame: / setEnabled: / setHighlighted:，是 UIControl（按钮）派生：
//  基类由生成时的 NSObject 修正为 UIControl，导出的选择器集合完全不变。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAGitPill;

@interface CAGitPill : UIControl
    - (void)configureWithTitle:(id)arg1 symbol:(id)arg2 emphasized:(id)arg3 showsChevron:(id)arg4;
    - (id)initWithFrame:(id)arg1;
    - (void)setEnabled:(id)arg1;
    - (void)setHighlighted:(id)arg1;
@end

NS_ASSUME_NONNULL_END
