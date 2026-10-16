//
//  CAModelPickerViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAModelPickerViewController : UIViewController
    - (void)closePicker;
    - (id)onModelSelected;
    - (void)setOnModelSelected:(id)arg1;
    - (void)setTableView:(id)arg1;
    - (UITableView *)tableView;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2;
    - (signed __int64)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2;
    - (void)themeDidChange;
    - (void)viewDidLoad;
    - (void)viewWillAppear:(id)arg1;

@end

NS_ASSUME_NONNULL_END
