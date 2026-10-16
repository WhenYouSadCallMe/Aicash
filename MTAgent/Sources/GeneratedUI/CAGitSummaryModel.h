//
//  CAGitSummaryModel — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString;
@class CAGitSnapshot;

@interface CAGitSummaryModel : NSObject
    - (unsigned long long)ahead;
    - (unsigned long long)behind;
    - (bool)branchEnabled;
    - (NSString *)branchTitle;
    - (bool)busy;
    - (NSString *)detail;
    - (bool)detailIsActivity;
    - (bool)fetchEnabled;
    - (NSString *)hint;
    - (bool)pullEnabled;
    - (bool)pushEnabled;
    - (bool)pushProminent;
    - (bool)remoteConfigured;
    - (bool)remoteEnabled;
    - (NSString *)remoteTitle;
    - (NSString *)remoteURL;
    - (void)setAhead:(id)arg1;
    - (void)setBehind:(id)arg1;
    - (void)setBranchEnabled:(id)arg1;
    - (void)setBranchTitle:(id)arg1;
    - (void)setBusy:(id)arg1;
    - (void)setDetail:(id)arg1;
    - (void)setDetailIsActivity:(id)arg1;
    - (void)setFetchEnabled:(id)arg1;
    - (void)setHint:(id)arg1;
    - (void)setPullEnabled:(id)arg1;
    - (void)setPushEnabled:(id)arg1;
    - (void)setPushProminent:(id)arg1;
    - (void)setRemoteConfigured:(id)arg1;
    - (void)setRemoteEnabled:(id)arg1;
    - (void)setRemoteTitle:(id)arg1;
    - (void)setRemoteURL:(id)arg1;
    - (void)setTitle:(id)arg1;
    - (NSString *)title;

#pragma mark - 使用面（复刻补全）

/// 由快照派生仓库卡片状态；activity 非空时 detail 用来显示进行中的动作文案
+ (instancetype)modelWithSnapshot:(CAGitSnapshot *)snapshot
                    workspaceName:(nullable NSString *)name
                             busy:(BOOL)busy
                         activity:(nullable NSString *)activity;

/// 卡片副标题（无提交 / 未设置上游 / 领先落后）
+ (NSString *)detailForSnapshot:(CAGitSnapshot *)snapshot;

/// 卡片底部提示文案（有远程时）
+ (NSString *)hintForSnapshot:(CAGitSnapshot *)snapshot;

@end

NS_ASSUME_NONNULL_END
