//
//  CAAgentStatusDetailViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAAgentStatusDetailViewController;

@interface CAAgentStatusDetailViewController : UIViewController
    - (id)initWithSnapshot:(id)arg1;
    - (signed long long)numberOfSectionsInTableView:(id)arg1;
    - (void)refreshTitle;
    - (id)sections;
    - (void)setSnapshot:(id)arg1;
    - (NSDictionary *)snapshot;
    - (id)statusText:(id)arg1;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2;
    - (void)updateSnapshot:(id)arg1;
    - (void)viewDidLoad;

@end

NS_ASSUME_NONNULL_END
