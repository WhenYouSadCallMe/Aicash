//
//  CAGitSnapshot.h — 仓库快照（分支 / 上游 / 远程 / 变更列表）
//
//  选择器原型取自 SPEC/method_types.json（逐字保留）：原包 20 个 ivar、42 个访问器。
//  本实现补齐快照的构造与解析：由 CAGitRepository 调 `git status --porcelain=v2 --branch -z`
//  解析出 branches / remotes / changes，供 CAGitChangesViewController 直接渲染。
//
//  变更字典（CAGitSnapshot.changes 的元素）键名统一如下，跨文件共用：
//    path / originalPath / subtitle / symbol / tint / label
//    staged / untracked / conflicted / added / deleted / renamed / modified
//    indexStatus / worktreeStatus（git porcelain 的 XY 两个字符）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray;
@class NSDictionary;
@class NSString;

/// 变更字典键（跨 CAGitSnapshot / CAGitRepository / CAGitChangeStyle / CAGitChangeCell 共用）
extern NSString *const kCAGitChangePathKey;           // NSString，相对仓库根
extern NSString *const kCAGitChangeOriginalPathKey;   // NSString，重命名前的路径（可空）
extern NSString *const kCAGitChangeSubtitleKey;       // NSString，列表副标题（相对路径展示）
extern NSString *const kCAGitChangeSymbolKey;         // NSString，SF Symbol 名
extern NSString *const kCAGitChangeTintKey;           // UIColor
extern NSString *const kCAGitChangeLabelKey;          // NSString，「未跟踪 / 已修改 / 已暂存」…
extern NSString *const kCAGitChangeStagedKey;         // NSNumber(BOOL)
extern NSString *const kCAGitChangeUntrackedKey;      // NSNumber(BOOL)
extern NSString *const kCAGitChangeConflictedKey;     // NSNumber(BOOL)
extern NSString *const kCAGitChangeAddedKey;          // NSNumber(BOOL)
extern NSString *const kCAGitChangeDeletedKey;        // NSNumber(BOOL)
extern NSString *const kCAGitChangeRenamedKey;        // NSNumber(BOOL)
extern NSString *const kCAGitChangeModifiedKey;       // NSNumber(BOOL)
extern NSString *const kCAGitChangeIndexStatusKey;    // NSNumber(char) 暂存区状态字符
extern NSString *const kCAGitChangeWorktreeStatusKey; // NSNumber(char) 工作区状态字符

@interface CAGitSnapshot : NSObject
    - (unsigned long long)ahead;
    - (unsigned long long)behind;
    - (NSString *)branch;
    - (NSString *)branchSummary;
    - (NSArray *)changes;
    - (NSString *)error;
    - (bool)hasConflicts;
    - (bool)hasHead;
    - (NSDictionary *)remoteURLs;
    - (NSArray *)remotes;
    - (bool)repository;
    - (NSString *)repositoryRoot;
    - (void)setAhead:(id)arg1;
    - (void)setBehind:(id)arg1;
    - (void)setBranch:(id)arg1;
    - (void)setBranchSummary:(id)arg1;
    - (void)setChanges:(id)arg1;
    - (void)setError:(id)arg1;
    - (void)setHasConflicts:(id)arg1;
    - (void)setHasHead:(id)arg1;
    - (void)setRemoteURLs:(id)arg1;
    - (void)setRemotes:(id)arg1;
    - (void)setRepository:(id)arg1;
    - (void)setRepositoryRoot:(id)arg1;
    - (void)setStagedCount:(id)arg1;
    - (void)setTrackingCountsKnown:(id)arg1;
    - (void)setTrackingRef:(id)arg1;
    - (void)setTrackingRemote:(id)arg1;
    - (void)setUnstagedCount:(id)arg1;
    - (void)setUpstream:(id)arg1;
    - (void)setUserEmail:(id)arg1;
    - (void)setUserName:(id)arg1;
    - (unsigned long long)stagedCount;
    - (bool)trackingCountsKnown;
    - (NSString *)trackingRef;
    - (NSString *)trackingRemote;
    - (unsigned long long)unstagedCount;
    - (NSString *)upstream;
    - (NSString *)userEmail;
    - (NSString *)userName;

#pragma mark - 使用面（复刻补全）

/// 解析 `git status --porcelain=v2 --branch -z` 的输出，返回快照（解析失败时 error 非空）
+ (instancetype)snapshotFromStatusOutput:(nullable NSString *)output;

/// 空仓库/非仓库的快照（error 说明原因）
+ (instancetype)emptySnapshotWithError:(nullable NSString *)error;

/// 当前工作区的演示快照（无 git 可执行文件时退化为演示数据，界面仍可完整浏览）
+ (instancetype)demoSnapshotWithWorkspaceName:(nullable NSString *)name;

/// 变更按 staged / unstaged 分组（复刻补全：VC 的分区数据源）
- (NSArray *)changesStaged:(BOOL)staged;

/// 把重命名/删除等状态翻译成中文标签（未跟踪 / 已修改 / 已暂存 / 冲突 / 重命名 / 已删除）
+ (NSString *)labelForStatus:(char)status untracked:(BOOL)untracked staged:(BOOL)staged;

/// 状态字符对应的 SF Symbol 与颜色（对齐截图：新增=绿色加号方块、修改=橙色笔、删除=红色减号）
+ (NSString *)symbolForStatus:(char)status untracked:(BOOL)untracked;
+ (UIColor *)tintForStatus:(char)status untracked:(BOOL)untracked;
@end

NS_ASSUME_NONNULL_END
