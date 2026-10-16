//
//  CAGitRepository — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAGitRepository;

@interface CAGitRepository : NSObject
    - (void)commitMessage:(id)arg1 stageAll:(id)arg2 completion:(id)arg3;
    - (void)configureRemote:(id)arg1 URL:(id)arg2 completion:(id)arg3;
    - (NSMutableArray *)countWaiters;
    - (void)deleteNewChange:(id)arg1 completion:(id)arg2;
    - (void)discardChange:(id)arg1 completion:(id)arg2;
    - (void)discardTrackedChanges:(id)arg1;
    - (void)ensureRoot:(id)arg1;
    - (void)fetchFromRemote:(id)arg1 username:(id)arg2 token:(id)arg3 completion:(id)arg4;
    - (id)gitEnvironment;
    - (id)gitExecutableForEnvironment:(id)arg1;
    - (CAGitRepository *)initWithWorkspacePath:(id)arg1;
    - (id)matchingChange:(id)arg1 snapshot:(id)arg2;
    - (double)operationTimeout;
    - (void)pullFromRemote:(id)arg1 branch:(id)arg2 username:(id)arg3 token:(id)arg4 completion:(id)arg5;
    - (void)pushToRemote:(id)arg1 branch:(id)arg2 remoteRef:(id)arg3 username:(id)arg4 token:(id)arg5 completion:(id)arg6;
    - (void)readChangeCount:(id)arg1;
    - (void)readDiffForChange:(id)arg1 staged:(id)arg2 completion:(id)arg3;
    - (void)readDiffStats:(id)arg1;
    - (void)readLocalBranches:(id)arg1;
    - (void)readSnapshot:(id)arg1;
    - (void)remoteEnvironment:(id)arg1 push:(id)arg2 username:(id)arg3 token:(id)arg4 completion:(id)arg5;
    - (NSString *)repositoryRoot;
    - (NSMutableArray *)rootWaiters;
    - (void)runArguments:(id)arg1 completion:(id)arg2;
    - (void)runArguments:(id)arg1 environment:(id)arg2 completion:(id)arg3;
    - (void)runArguments:(id)arg1 environment:(id)arg2 outputFile:(id)arg3 completion:(id)arg4;
    - (void)setCountWaiters:(id)arg1;
    - (void)setRepositoryRoot:(id)arg1;
    - (void)setRootWaiters:(id)arg1;
    - (void)setSnapshotWaiters:(id)arg1;
    - (void)setUserName:(id)arg1 email:(id)arg2 completion:(id)arg3;
    - (void)setWorkspacePath:(id)arg1;
    - (NSMutableArray *)snapshotWaiters;
    - (void)stageChange:(id)arg1 completion:(id)arg2;
    - (id)statusArguments;
    - (void)switchToBranch:(id)arg1 create:(id)arg2 completion:(id)arg3;
    - (void)unstageChange:(id)arg1 completion:(id)arg2;
    - (NSString *)workspacePath;

@end

NS_ASSUME_NONNULL_END
