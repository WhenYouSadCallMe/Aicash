//
//  CAExtensionListViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAExtensionListViewController;

@interface CAExtensionListViewController : UIViewController
    - (void)applyMCPServer:(id)arg1 enabled:(id)arg2 toggle:(id)arg3;
    - (void)applySkill:(id)arg1 enabled:(id)arg2 toggle:(id)arg3;
    - (void)catalogDidChange;
    - (id)codexHome;
    - (void)confirmRemoveMCP:(id)arg1;
    - (void)confirmRemovePrompt:(id)arg1;
    - (void)confirmRemoveSkill:(id)arg1;
    - (void)createPromptNamed:(id)arg1;
    - (void)createSkillNamed:(id)arg1;
    - (id)editableFilePathForItem:(id)arg1;
    - (UILabel *)emptyLabel;
    - (id)emptyText;
    - (void)handleAddPrompt;
    - (void)handleAddSkill;
    - (bool)includesItem:(id)arg1;
    - (CAExtensionListViewController *)initWithKind:(id)arg1;
    - (bool)isLocallyManagedMCP:(id)arg1;
    - (bool)isLocallyManagedSkill:(id)arg1;
    - (signed long long)kind;
    - (id)locallyManagedSkillRootForItem:(id)arg1;
    - (id)locallyManagedSkillRoots;
    - (signed long long)numberOfSectionsInTableView:(id)arg1;
    - (void)openItem:(id)arg1;
    - (void)pullToRefresh;
    - (void)rebuildSections;
    - (void)refreshForce:(id)arg1;
    - (NSArray *)sections;
    - (void)setEmptyLabel:(id)arg1;
    - (void)setKind:(id)arg1;
    - (void)setSections:(id)arg1;
    - (void)setTableView:(id)arg1;
    - (id)symbolName;
    - (UITableView *)tableView;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2;
    - (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2;
    - (id)tableView:(id)arg1 trailingSwipeActionsConfigurationForRowAtIndexPath:(id)arg2;
    - (void)themeDidChange;
    - (void)viewDidLoad;
    - (void)viewWillAppear:(id)arg1;
    - (id)workspace;

@end

NS_ASSUME_NONNULL_END
