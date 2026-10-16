//
//  CAWorkspaceViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAWorkspaceViewController : UIViewController
    - (void)activatePath:(id)arg1 name:(id)arg2;
    - (id)activeItem;
    - (void)browseDirectory:(id)arg1;
    - (void)copyPath:(id)arg1;
    - (void)createProject;
    - (unsigned __int64)filzaRequestGeneration;
    - (void)finishSelection;
    - (void)handleClose;
    - (NSArray *)items;
    - (void)loadMetadata;
    - (NSDictionary *)metaByPath;
    - (unsigned __int64)metaGeneration;
    - (id)metaTextForItem:(id)arg1 warning:(id)arg2;
    - (id)nameForItem:(id)arg1;
    - (signed __int64)numberOfSectionsInTableView:(id)arg1;
    - (id)onActiveWorkspaceChanged;
    - (void)openPathInFilza:(id)arg1;
    - (unsigned __int64)projectCount;
    - (void)reloadItems;
    - (void)removeItem:(id)arg1;
    - (void)setFilzaRequestGeneration:(id)arg1;
    - (void)setItems:(id)arg1;
    - (void)setMetaByPath:(id)arg1;
    - (void)setMetaGeneration:(id)arg1;
    - (void)setOnActiveWorkspaceChanged:(id)arg1;
    - (void)setTableView:(id)arg1;
    - (void)setWorkspaceBusyProvider:(id)arg1;
    - (void)showError:(id)arg1 title:(id)arg2;
    - (id)symbolForItem:(id)arg1;
    - (UITableView *)tableView;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (id)tableView:(id)arg1 contextMenuConfigurationForRowAtIndexPath:(id)arg2 point:(id)arg3;
    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2;
    - (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2;
    - (double)tableView:(id)arg1 heightForHeaderInSection:(id)arg2;
    - (signed __int64)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (bool)tableView:(id)arg1 shouldHighlightRowAtIndexPath:(id)arg2;
    - (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2;
    - (id)tableView:(id)arg1 trailingSwipeActionsConfigurationForRowAtIndexPath:(id)arg2;
    - (void)themeDidChange;
    - (id)tintForItem:(id)arg1;
    - (void)viewDidLoad;
    - (void)viewWillAppear:(id)arg1;
    - (id)workspaceBusyProvider;

@end

NS_ASSUME_NONNULL_END
