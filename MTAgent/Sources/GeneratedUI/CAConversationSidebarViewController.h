//
//  CAConversationSidebarViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAConversationSidebarDelegate;
@class CAProfileAvatarView;
@class UIControl;

@interface CAConversationSidebarViewController : UIViewController
    - (CAProfileAvatarView *)accountAvatar;
    - (UIControl *)accountControl;
    - (UILabel *)accountEmailLabel;
    - (UIView *)accountFooter;
    - (NSLayoutConstraint *)accountHeight;
    - (id)accountHome;
    - (UILabel *)accountNameLabel;
    - (UIView *)accountPanel;
    - (UILabel *)accountStatusLabel;
    - (NSString *)activeConversationId;
    - (void)applyAccountProfile:(id)arg1;
    - (void)applyProviderIdentity;
    - (void)applyResponsiveLayout;
    - (void)buildAccountFooter;
    - (void)buildHeader;
    - (void)closeSidebar;
    - (bool)compactLayout;
    - (UIButton *)composeButton;
    - (NSLayoutConstraint *)composeHeight;
    - (void)confirmDelete:(id)arg1;
    - (void)confirmRemoveWorkspaceAtPath:(id)arg1;
    - (void)costSummaryDidChange:(id)arg1;
    - (NSDictionary *)countsByWorkspace;
    - (void)createConversation;
    - (CAConversationSidebarDelegate *)delegate;
    - (UILabel *)emptyLabel;
    - (void)expandWorkspaceAtPath:(id)arg1;
    - (NSMutableSet *)expandedWorkspacePaths;
    - (unsigned long long)filzaRequestGeneration;
    - (void)finishPermanentWorkspaceRemovalAtPath:(id)arg1;
    - (UIView *)footerSeparator;
    - (NSLayoutConstraint *)footerTop;
    - (NSLayoutConstraint *)headerHeight;
    - (UIStackView *)headerStack;
    - (id)labelWithSize:(id)arg1 weight:(id)arg2;
    - (void)moveRecord:(id)arg1;
    - (void)newConversationForWorkspacePath:(id)arg1;
    - (signed long long)numberOfSectionsInTableView:(id)arg1;
    - (void)openSettings;
    - (void)openUsage;
    - (void)openWorkspacePathInFilza:(id)arg1;
    - (void)openWorkspaces;
    - (void)persistExpandedWorkspaces;
    - (NSString *)profileHome;
    - (NSString *)profileRefreshID;
    - (UILabel *)providerHintLabel;
    - (UIImageView *)quotaChevron;
    - (UIControl *)quotaControl;
    - (UIStackView *)quotaHeading;
    - (NSString *)quotaRefreshError;
    - (unsigned long long)quotaRefreshGeneration;
    - (UILabel *)quotaStatus;
    - (UILabel *)quotaTitle;
    - (NSLayoutConstraint *)quotaTop;
    - (UIStackView *)quotaWindows;
    - (id)recordAtIndexPath:(id)arg1;
    - (NSDictionary *)recordsByWorkspace;
    - (void)refreshQuota;
    - (void)refreshQuotaSnapshot;
    - (bool)refreshingQuota;
    - (void)reloadAccountProfile;
    - (void)reloadConversations;
    - (void)reloadWorkspaceTitle;
    - (void)renameRecord:(id)arg1;
    - (void)renameWorkspaceAtPath:(id)arg1;
    - (NSSet *)runningConversationIds;
    - (NSSet *)runningWorkspacePaths;
    - (NSArray *)sectionWorkspaces;
    - (void)setAccountAvatar:(id)arg1;
    - (void)setAccountControl:(id)arg1;
    - (void)setAccountEmailLabel:(id)arg1;
    - (void)setAccountFooter:(id)arg1;
    - (void)setAccountHeight:(id)arg1;
    - (void)setAccountNameLabel:(id)arg1;
    - (void)setAccountPanel:(id)arg1;
    - (void)setAccountStatusLabel:(id)arg1;
    - (void)setActiveConversationId:(id)arg1;
    - (void)setCompactLayout:(id)arg1;
    - (void)setComposeButton:(id)arg1;
    - (void)setComposeHeight:(id)arg1;
    - (void)setCountsByWorkspace:(id)arg1;
    - (void)setDelegate:(id)arg1;
    - (void)setEmptyLabel:(id)arg1;
    - (void)setExpandedWorkspacePaths:(id)arg1;
    - (void)setFilzaRequestGeneration:(id)arg1;
    - (void)setFooterSeparator:(id)arg1;
    - (void)setFooterTop:(id)arg1;
    - (void)setHeaderHeight:(id)arg1;
    - (void)setHeaderStack:(id)arg1;
    - (void)setProfileHome:(id)arg1;
    - (void)setProfileRefreshID:(id)arg1;
    - (void)setProviderHintLabel:(id)arg1;
    - (void)setQuotaChevron:(id)arg1;
    - (void)setQuotaControl:(id)arg1;
    - (void)setQuotaHeading:(id)arg1;
    - (void)setQuotaRefreshError:(id)arg1;
    - (void)setQuotaRefreshGeneration:(id)arg1;
    - (void)setQuotaStatus:(id)arg1;
    - (void)setQuotaTitle:(id)arg1;
    - (void)setQuotaTop:(id)arg1;
    - (void)setQuotaWindows:(id)arg1;
    - (void)setRecordsByWorkspace:(id)arg1;
    - (void)setRefreshingQuota:(id)arg1;
    - (void)setRunningConversationIds:(id)arg1;
    - (void)setRunningWorkspacePaths:(id)arg1;
    - (void)setSectionWorkspaces:(id)arg1;
    - (void)setSettingsButton:(id)arg1;
    - (void)setSidebarHeader:(id)arg1;
    - (void)setTableView:(id)arg1;
    - (void)setWindowBars:(id)arg1;
    - (void)setWindowTitles:(id)arg1;
    - (void)setWindowValues:(id)arg1;
    - (void)setWorkspaceButton:(id)arg1;
    - (void)setWorkspaceHeight:(id)arg1;
    - (void)setWorkspacePath:(id)arg1;
    - (UIButton *)settingsButton;
    - (UIView *)sidebarHeader;
    - (UITableView *)tableView;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2;
    - (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2;
    - (double)tableView:(id)arg1 heightForHeaderInSection:(id)arg2;
    - (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (id)tableView:(id)arg1 trailingSwipeActionsConfigurationForRowAtIndexPath:(id)arg2;
    - (id)tableView:(id)arg1 viewForHeaderInSection:(id)arg2;
    - (void)themeDidChange;
    - (void)toggleWorkspaceHeader:(id)arg1;
    - (void)viewDidAppear:(id)arg1;
    - (void)viewDidLayoutSubviews;
    - (void)viewDidLoad;
    - (NSArray *)windowBars;
    - (id)windowTitle:(id)arg1 fallback:(id)arg2;
    - (NSArray *)windowTitles;
    - (NSArray *)windowValues;
    - (UIButton *)workspaceButton;
    - (NSLayoutConstraint *)workspaceHeight;
    - (NSString *)workspacePath;

@end

NS_ASSUME_NONNULL_END
