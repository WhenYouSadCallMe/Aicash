//
//  CAPlanProgressViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAPlanProgressViewController : UIViewController
    - (void)close;
    - (bool)executionActive;
    - (CAPlanProgressViewController *)initWithPlanDetail:(id)arg1 pendingSync:(id)arg2 executionActive:(id)arg3;
    - (signed __int64)numberOfSectionsInTableView:(id)arg1;
    - (id)onCloseTodo;
    - (bool)pendingSync;
    - (void)setExecutionActive:(id)arg1;
    - (void)setOnCloseTodo:(id)arg1;
    - (void)setPendingSync:(id)arg1;
    - (void)setSteps:(id)arg1;
    - (void)setSubtitle:(id)arg1;
    - (void)setTable:(id)arg1;
    - (NSArray *)steps;
    - (UILabel *)subtitle;
    - (UITableView *)table;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (signed __int64)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (void)updateSummary;
    - (void)updateWithPlanDetail:(id)arg1 pendingSync:(id)arg2 executionActive:(id)arg3;
    - (void)viewDidLoad;

@end

NS_ASSUME_NONNULL_END
