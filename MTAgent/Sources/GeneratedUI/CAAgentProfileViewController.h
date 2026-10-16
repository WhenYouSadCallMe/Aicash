//
//  CAAgentProfileViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAAgentProfileViewController : UIViewController
    - (void)applyTheme;
    - (id)draftName;
    - (void)nameDidEdit;
    - (UITextField *)nameField;
    - (UITableViewCell *)nameFieldCell;
    - (signed long long)numberOfSectionsInTableView:(id)arg1;
    - (UILabel *)profileName;
    - (UILabel *)profileSubtitle;
    - (UIBarButtonItem *)saveItem;
    - (void)saveName;
    - (void)setNameField:(id)arg1;
    - (void)setNameFieldCell:(id)arg1;
    - (void)setProfileName:(id)arg1;
    - (void)setProfileSubtitle:(id)arg1;
    - (void)setSaveItem:(id)arg1;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2;
    - (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2;
    - (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2;
    - (bool)textFieldShouldReturn:(id)arg1;
    - (void)viewDidLoad;

@end

NS_ASSUME_NONNULL_END
