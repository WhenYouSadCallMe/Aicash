//
//  CAPlanDecisionViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAPlanDecisionViewController;

@interface CAPlanDecisionViewController : UIViewController
    - (NSMutableDictionary *)choiceRows;
    - (id)completion;
    - (NSMutableDictionary *)customRows;
    - (void)deferQuestions;
    - (void)finishAllowingUnknown:(id)arg1;
    - (NSMutableDictionary *)freeformEditors;
    - (CAPlanDecisionViewController *)initWithQuestions:(id)arg1 completion:(id)arg2;
    - (id)label:(id)arg1 font:(id)arg2 color:(id)arg3;
    - (NSMutableDictionary *)privateEditors;
    - (NSArray *)questions;
    - (void)refreshSelectionState;
    - (UILabel *)remainingLabel;
    - (bool)resolved;
    - (void)secretFieldChanged:(id)arg1;
    - (void)selectChoice:(id)arg1;
    - (NSMutableDictionary *)selections;
    - (void)setChoiceRows:(id)arg1;
    - (void)setCompletion:(id)arg1;
    - (void)setCustomRows:(id)arg1;
    - (void)setFreeformEditors:(id)arg1;
    - (void)setPrivateEditors:(id)arg1;
    - (void)setQuestions:(id)arg1;
    - (void)setRemainingLabel:(id)arg1;
    - (void)setResolved:(id)arg1;
    - (void)setSelections:(id)arg1;
    - (void)setSubmitButton:(id)arg1;
    - (UIButton *)submitButton;
    - (void)submitDecisions;
    - (id)textAnswerForIndex:(id)arg1;
    - (void)textViewDidChange:(id)arg1;
    - (void)viewDidAppear:(id)arg1;
    - (void)viewDidLoad;

@end

NS_ASSUME_NONNULL_END
