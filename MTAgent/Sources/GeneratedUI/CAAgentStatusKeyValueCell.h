//
//  CAAgentStatusKeyValueCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAAgentStatusKeyValueCell;

@interface CAAgentStatusKeyValueCell : UITableViewCell
    - (void)configureTitle:(id)arg1 value:(id)arg2 error:(id)arg3;
    - (CAAgentStatusKeyValueCell *)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2;
    - (UILabel *)keyLabel;
    - (void)setKeyLabel:(id)arg1;
    - (void)setValueLabel:(id)arg1;
    - (UILabel *)valueLabel;

@end

NS_ASSUME_NONNULL_END
