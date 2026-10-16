//
//  CAAgentStatusViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray;
@class UITableView;
@class UIViewController;

@interface CAAgentStatusViewController : UIViewController
    - (void)close;
    - (UIViewController *)detailController;
    - (bool)mainRunning;
    - (signed long long)numberOfSectionsInTableView:(id)arg1;
    - (void)setDetailController:(id)arg1;
    - (void)setMainRunning:(id)arg1;
    - (void)setSnapshots:(id)arg1;
    - (void)setTableView:(id)arg1;
    - (NSArray *)snapshots;
    - (UITableView *)tableView;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2;
    - (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2;
    - (void)updateSnapshots:(id)arg1 mainRunning:(id)arg2;
    - (void)viewDidLoad;

@end

NS_ASSUME_NONNULL_END
