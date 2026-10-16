//
//  CAGitChangesViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAGitChangesViewController : UIViewController
    - (void)anchorAlert:(id)arg1 toView:(id)arg2;
    - (void)applyPrefix:(id)arg1;
    - (void)beginOperation:(id)arg1;
    - (UIView *)bottomFiller;
    - (void)buildCommitBar;
    - (void)buildLayout;
    - (void)buildNavigationItems;
    - (void)buildTable;
    - (bool)canMutate;
    - (id)changeAtIndexPath:(id)arg1;
    - (void)changeBranch:(id)arg1 create:(id)arg2;
    - (id)changesForKind:(id)arg1;
    - (void)close;
    - (NSMutableSet *)collapsedKinds;
    - (void)commit;
    - (CAGitCommitBar *)commitBar;
    - (void)configureIdentityThenCommit;
    - (void)configureRemote;
    - (NSArray *)conflictChanges;
    - (void)createBranch;
    - (NSDictionary *)diffStats;
    - (void)discardAll;
    - (void)discardFile:(id)arg1;
    - (CAGitEmptyStateView *)emptyView;
    - (void)expandSheet;
    - (void)fetch;
    - (void)finishFileOperation:(id)arg1 status:(id)arg2;
    - (void)finishOperation:(id)arg1 output:(id)arg2 status:(id)arg3;
    - (CAGitRepository *)git;
    - (void)handleEmptyAction;
    - (CAGitChangesViewController *)initWithWorkspacePath:(id)arg1;
    - (void)initializeRepository;
    - (signed __int64)kindForSection:(id)arg1;
    - (bool)loading;
    - (UIBarButtonItem *)moreItem;
    - (id)moreMenu;
    - (bool)mutating;
    - (NSString *)networkAction;
    - (NSString *)networkBranch;
    - (signed __int64)numberOfSectionsInTableView:(id)arg1;
    - (id)onRepositoryChanged;
    - (void)openDiff:(id)arg1 staged:(id)arg2;
    - (NSString *)operationStatus;
    - (void)performNetworkAction:(id)arg1;
    - (void)presentationControllerDidDismiss:(id)arg1;
    - (bool)presentationControllerShouldDismiss:(id)arg1;
    - (void)pull;
    - (void)push;
    - (NSString *)pushToken;
    - (NSString *)pushUsername;
    - (void)rebuildModel;
    - (void)refresh;
    - (UIRefreshControl *)refreshControl;
    - (unsigned __int64)refreshGeneration;
    - (UIBarButtonItem *)refreshItem;
    - (id)remoteSummaryText;
    - (void)requestRemoteCredentials;
    - (NSArray *)sectionKinds;
    - (void)selectBranch;
    - (void)selectRemote;
    - (NSString *)selectedRemote;
    - (void)setBottomFiller:(id)arg1;
    - (void)setCollapsedKinds:(id)arg1;
    - (void)setCommitBar:(id)arg1;
    - (void)setConflictChanges:(id)arg1;
    - (void)setDiffStats:(id)arg1;
    - (void)setEmptyView:(id)arg1;
    - (void)setGit:(id)arg1;
    - (void)setLoading:(id)arg1;
    - (void)setMoreItem:(id)arg1;
    - (void)setMutating:(id)arg1;
    - (void)setNetworkAction:(id)arg1;
    - (void)setNetworkBranch:(id)arg1;
    - (void)setOnRepositoryChanged:(id)arg1;
    - (void)setOperationStatus:(id)arg1;
    - (void)setPushToken:(id)arg1;
    - (void)setPushUsername:(id)arg1;
    - (void)setRefreshControl:(id)arg1;
    - (void)setRefreshGeneration:(id)arg1;
    - (void)setRefreshItem:(id)arg1;
    - (void)setSectionKinds:(id)arg1;
    - (void)setSelectedRemote:(id)arg1;
    - (void)setSnapshot:(id)arg1;
    - (void)setStageAll:(id)arg1;
    - (void)setStagedChanges:(id)arg1;
    - (void)setTableToBar:(id)arg1;
    - (void)setTableToGuide:(id)arg1;
    - (void)setTableView:(id)arg1;
    - (void)setUnstagedChanges:(id)arg1;
    - (void)setWorkspacePath:(id)arg1;
    - (void)showMessage:(id)arg1 detail:(id)arg2;
    - (void)showSuccess:(id)arg1 detail:(id)arg2;
    - (signed __int64)sideForKind:(id)arg1;
    - (CAGitSnapshot *)snapshot;
    - (bool)stageAll;
    - (void)stageEverything;
    - (void)stageFile:(id)arg1 unstage:(id)arg2;
    - (NSArray *)stagedChanges;
    - (id)statsForChange:(id)arg1 kind:(id)arg2;
    - (id)summaryCell;
    - (id)summaryModel;
    - (id)syncHint;
    - (NSLayoutConstraint *)tableToBar;
    - (NSLayoutConstraint *)tableToGuide;
    - (UITableView *)tableView;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (id)tableView:(id)arg1 contextMenuConfigurationForRowAtIndexPath:(id)arg2 point:(id)arg3;
    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2;
    - (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2;
    - (double)tableView:(id)arg1 heightForHeaderInSection:(id)arg2;
    - (id)tableView:(id)arg1 leadingSwipeActionsConfigurationForRowAtIndexPath:(id)arg2;
    - (signed __int64)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2;
    - (id)tableView:(id)arg1 trailingSwipeActionsConfigurationForRowAtIndexPath:(id)arg2;
    - (id)tableView:(id)arg1 viewForHeaderInSection:(id)arg2;
    - (void)tableView:(id)arg1 willDisplayFooterView:(id)arg2 forSection:(id)arg3;
    - (void)themeDidChange;
    - (void)toggleKind:(id)arg1;
    - (void)traitCollectionDidChange:(id)arg1;
    - (NSArray *)unstagedChanges;
    - (void)updateCommitBar;
    - (void)updateControls;
    - (void)updateEmptyState;
    - (void)viewDidAppear:(id)arg1;
    - (void)viewDidLoad;
    - (NSString *)workspacePath;

@end

NS_ASSUME_NONNULL_END
