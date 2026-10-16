//
//  CAGitSnapshot — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAGitSnapshot : NSObject
    - (unsigned __int64)ahead;
    - (unsigned __int64)behind;
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
    - (unsigned __int64)stagedCount;
    - (bool)trackingCountsKnown;
    - (NSString *)trackingRef;
    - (NSString *)trackingRemote;
    - (unsigned __int64)unstagedCount;
    - (NSString *)upstream;
    - (NSString *)userEmail;
    - (NSString *)userName;

@end

NS_ASSUME_NONNULL_END
