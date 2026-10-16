//
//  CALogEntryCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CALogEntryCell;

@interface CALogEntryCell : UITableViewCell
    - (void)configureWithEntry:(id)arg1;
    - (CALogEntryCell *)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2;
    - (UIView *)levelBar;
    - (UILabel *)messageLabel;
    - (UILabel *)metaLabel;
    - (void)setLevelBar:(id)arg1;
    - (void)setMessageLabel:(id)arg1;
    - (void)setMetaLabel:(id)arg1;

@end

NS_ASSUME_NONNULL_END
