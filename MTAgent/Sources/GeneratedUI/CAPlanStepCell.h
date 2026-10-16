//
//  CAPlanStepCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAPlanStatusRing;
@class CAPlanStepCell;

@class UILabel;

@interface CAPlanStepCell : UITableViewCell
    - (void)configureWithStep:(id)arg1;
    - (void)configureWithStep:(id)arg1 executionActive:(id)arg2;
    - (id)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2;
    - (void)prepareForReuse;
    - (id)ring;
    - (void)setRing:(id)arg1;
    - (void)setStepTitle:(id)arg1;
    - (UILabel *)stepTitle;

@end

NS_ASSUME_NONNULL_END
