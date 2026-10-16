//
//  CAPlanReviewViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAPlanReviewViewController : UIViewController
    - (id)action:(id)arg1 fill:(id)arg2 selector:(id)arg3;
    - (void)approvePlan;
    - (void)close;
    - (void)editPlan;
    - (CAPlanReviewViewController *)initWithPlan:(id)arg1 onEdit:(id)arg2 onApprove:(id)arg3;
    - (id)onApprove;
    - (id)onEdit;
    - (NSString *)plan;
    - (UITextView *)planText;
    - (id)readablePlan;
    - (void)setOnApprove:(id)arg1;
    - (void)setOnEdit:(id)arg1;
    - (void)setPlan:(id)arg1;
    - (void)setPlanText:(id)arg1;
    - (void)viewDidLoad;

@end

NS_ASSUME_NONNULL_END
