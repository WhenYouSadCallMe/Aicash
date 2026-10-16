//
//  CAProjectInstructionsViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray;
@class NSDictionary;
@class UITableView;

@interface CAProjectInstructionsViewController : UIViewController
    - (id)instructionPathForWorkspace:(id)arg1;
    - (void)reloadStatuses;
    - (void)setStatusByPath:(id)arg1;
    - (void)setStatusGeneration:(id)arg1;
    - (void)setTableView:(id)arg1;
    - (void)setWorkspaces:(id)arg1;
    - (NSDictionary *)statusByPath;
    - (unsigned long long)statusGeneration;
    - (UITableView *)tableView;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2;
    - (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2;
    - (void)themeDidChange;
    - (void)viewDidLoad;
    - (void)viewWillAppear:(id)arg1;
    - (NSArray *)workspaces;

@end

NS_ASSUME_NONNULL_END
