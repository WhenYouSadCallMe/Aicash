//
//  CASubagentSettingsViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CASubagentSettingsViewController : UIViewController
    - (CACodexEngine *)contextEngine;
    - (id)effectiveContextEngine;
    - (id)effortTitle:(id)arg1;
    - (id)efforts;
    - (id)modelItem;
    - (signed __int64)numberOfSectionsInTableView:(id)arg1;
    - (void)presentOptions:(id)arg1 cell:(id)arg2;
    - (void)refresh;
    - (void)selectModel:(id)arg1;
    - (id)selectedModel;
    - (void)setContextEngine:(id)arg1;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2;
    - (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2;
    - (signed __int64)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2;
    - (bool)thirdParty;
    - (void)viewDidLoad;
    - (void)viewWillAppear:(id)arg1;

@end

NS_ASSUME_NONNULL_END
