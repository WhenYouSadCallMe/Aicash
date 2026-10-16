//
//  CAGitChipLabel.h — Git 状态胶囊标签（原包 1 个 ivar: _contentInsets）
//
//  选择器原型取自 SPEC/method_types.json（逐字保留）：
//    -configureWithText:color:  -contentInsets  -setContentInsets:
//    -drawTextInRect:  -intrinsicContentSize  -initWithFrame:
//  原包该类拥有 drawTextInRect: / intrinsicContentSize，是 UILabel 派生：
//  基类由生成时的 NSObject 修正为 UILabel，导出的选择器集合完全不变。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAGitChipLabel;

@interface CAGitChipLabel : UILabel
    - (void)configureWithText:(id)arg1 color:(id)arg2;
    - (UIEdgeInsets)contentInsets;
    - (void)drawTextInRect:(id)arg1;
    - (id)initWithFrame:(id)arg1;
    - (CGSize)intrinsicContentSize;
    - (void)setContentInsets:(id)arg1;
@end

NS_ASSUME_NONNULL_END
