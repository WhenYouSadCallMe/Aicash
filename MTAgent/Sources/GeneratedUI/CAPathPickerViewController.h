//
//  CAPathPickerViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAPathPickerViewController;

@interface CAPathPickerViewController : UIViewController
    - (void)cancel;
    - (void)createFolder;
    - (id)createItem;
    - (NSString *)currentPath;
    - (NSArray *)entries;
    - (id)initWithPath:(id)arg1;
    - (id)onDirectorySelected;
    - (UIView *)pathBar;
    - (UILabel *)pathLabel;
    - (NSString *)readGeneration;
    - (void)reloadDirectory;
    - (void)selectCurrentDirectory;
    - (id)selectItem;
    - (void)setCreateItem:(id)arg1;
    - (void)setCurrentPath:(id)arg1;
    - (void)setEntries:(id)arg1;
    - (void)setOnDirectorySelected:(id)arg1;
    - (void)setPathBar:(id)arg1;
    - (void)setPathLabel:(id)arg1;
    - (void)setReadGeneration:(id)arg1;
    - (void)setSelectItem:(id)arg1;
    - (void)setTableView:(id)arg1;
    - (void)showError:(id)arg1;
    - (UITableView *)tableView;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2;
    - (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2;
    - (void)themeDidChange;
    - (void)viewDidLoad;

@end

NS_ASSUME_NONNULL_END
