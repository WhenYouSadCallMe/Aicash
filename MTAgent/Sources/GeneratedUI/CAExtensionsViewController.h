//
//  CAExtensionsViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAExtensionsViewController : UIViewController
    - (void)catalogDidChange;
    - (id)codexHome;
    - (void)ensureGlobalInstructionSeeded;
    - (id)extensionRows;
    - (id)globalInstructionPath;
    - (id)globalInstructionTemplate;
    - (id)globalOutputInstructionBlock;
    - (id)globalSubagentInstructionBlock;
    - (NSDictionary *)instructionStatus;
    - (id)legacyGlobalInstructionTemplate;
    - (void)loadInstructionStatus;
    - (signed __int64)numberOfSectionsInTableView:(id)arg1;
    - (void)openInstructionAtPath:(id)arg1 title:(id)arg2 note:(id)arg3 template:(id)arg4;
    - (void)pullToRefresh;
    - (void)refreshForce:(id)arg1;
    - (bool)seedingGlobalInstruction;
    - (void)setInstructionStatus:(id)arg1;
    - (void)setSeedingGlobalInstruction:(id)arg1;
    - (void)setStatusGeneration:(id)arg1;
    - (void)setTableView:(id)arg1;
    - (unsigned __int64)statusGeneration;
    - (UITableView *)tableView;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2;
    - (signed __int64)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2;
    - (void)themeDidChange;
    - (void)viewDidLoad;
    - (void)viewWillAppear:(id)arg1;
    - (id)workspace;

@end

NS_ASSUME_NONNULL_END
