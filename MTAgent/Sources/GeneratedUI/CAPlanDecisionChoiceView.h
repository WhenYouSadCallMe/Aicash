//
//  CAPlanDecisionChoiceView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAPlanDecisionChoiceView;

@interface CAPlanDecisionChoiceView : UIView
    - (UILabel *)choiceDescription;
    - (UILabel *)choiceTitle;
    - (NSString *)choiceValue;
    - (id)initWithTitle:(id)arg1 detail:(id)arg2;
    - (unsigned long long)questionIndex;
    - (UIImageView *)selectionIcon;
    - (void)setChoiceDescription:(id)arg1;
    - (void)setChoiceTitle:(id)arg1;
    - (void)setChoiceValue:(id)arg1;
    - (void)setQuestionIndex:(id)arg1;
    - (void)setSelectionIcon:(id)arg1;
    - (void)traitCollectionDidChange:(id)arg1;
    - (void)updateChosen:(id)arg1;

@end

NS_ASSUME_NONNULL_END
