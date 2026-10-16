//
//  CAGitSummaryModel.m — 仓库卡片视图模型
//
//  原包 17 个 ivar / 35 个访问器，本实现补齐「从快照派生卡片状态」的语义：
//    title        仓库名（工作区最后一段路径，Documents 这类）
//    detail       卡片副标题：无提交 / 无上游 / 领先落后
//    hint         底部提示文案（与截图逐字一致）
//    branchTitle  分支胶囊文案（master / main）
//    remoteTitle  远程胶囊文案（添加远程 / origin）
//    *Enabled     三个网络按钮的可用性（无远程时置灰 —— 与截图一致）
//

#import "CAGitSummaryModel.h"
#import "CAGitSnapshot.h"

@interface CAGitSummaryModel ()
{
    NSString *_title;
    NSString *_detail;
    NSString *_hint;
    NSString *_remoteTitle;
    NSString *_remoteURL;
    NSString *_branchTitle;
    unsigned long long _ahead;
    unsigned long long _behind;
    BOOL _remoteConfigured;
    BOOL _remoteEnabled;
    BOOL _branchEnabled;
    BOOL _fetchEnabled;
    BOOL _pullEnabled;
    BOOL _pushEnabled;
    BOOL _pushProminent;
    BOOL _busy;
    BOOL _detailIsActivity;
}
@end

@implementation CAGitSummaryModel

#pragma mark - 构造

/// 由快照派生卡片状态（复刻补全的构造入口）
+ (instancetype)modelWithSnapshot:(CAGitSnapshot *)snapshot workspaceName:(NSString *)name busy:(BOOL)busy activity:(NSString *)activity
{
    CAGitSummaryModel *model = [[CAGitSummaryModel alloc] init];
    NSString *fallbackName = name.length > 0 ? name : @"工作区";
    model.title = fallbackName;
    model.branchTitle = snapshot.branch.length > 0 ? snapshot.branch : @"—";

    // 注意：这些 setter 在生成头文件里的形参是 id 占位，标量必须装箱
    BOOL hasRemote = snapshot.remotes.count > 0;
    model.remoteConfigured = @(hasRemote);
    model.remoteEnabled = @YES;
    model.branchEnabled = @(snapshot.repository);
    model.ahead = @(snapshot.ahead);
    model.behind = @(snapshot.behind);

    if (hasRemote) {
        NSString *remoteName = snapshot.remotes.firstObject;
        model.remoteTitle = remoteName;
        model.remoteURL = snapshot.remoteURLs[remoteName];
        model.fetchEnabled = @YES;
        model.pullEnabled = @YES;
        model.pushEnabled = @(snapshot.hasHead);
        model.pushProminent = @(snapshot.ahead > 0);
    } else {
        model.remoteTitle = @"添加远程";
        // remoteURL 留空即可（setRemoteURL: 在生成头文件里是非空形参，避免显式赋 nil）
        model.fetchEnabled = @NO;
        model.pullEnabled = @NO;
        model.pushEnabled = @NO;
        model.pushProminent = @NO;
    }

    model.busy = @(busy);
    model.detailIsActivity = @(activity.length > 0);
    model.detail = activity.length > 0 ? activity : [self detailForSnapshot:snapshot];
    model.hint = hasRemote ? [self hintForSnapshot:snapshot] : @"还没有远程仓库。点击“添加远程”填写 HTTPS 地址后，即可推送提交。";
    return model;
}

+ (NSString *)detailForSnapshot:(CAGitSnapshot *)snapshot
{
    if (!snapshot.repository) {
        return snapshot.error.length > 0 ? snapshot.error : @"不是 Git 仓库";
    }
    if (!snapshot.hasHead) {
        return @"未设置上游 · 尚无提交";
    }
    if (snapshot.remotes.count == 0 || snapshot.upstream.length == 0) {
        return @"未设置上游";
    }
    if (snapshot.ahead > 0 || snapshot.behind > 0) {
        return snapshot.branchSummary;
    }
    return [NSString stringWithFormat:@"与 %@ 一致", snapshot.trackingRef ?: snapshot.upstream];
}

+ (NSString *)hintForSnapshot:(CAGitSnapshot *)snapshot
{
    if (snapshot.hasConflicts) {
        return @"存在未解决的冲突，先处理冲突再提交。";
    }
    if (snapshot.ahead > 0) {
        return [NSString stringWithFormat:@"本地领先 %llu 个提交，可以推送到远程。", snapshot.ahead];
    }
    if (snapshot.behind > 0) {
        return [NSString stringWithFormat:@"远程领先 %llu 个提交，建议先拉取。", snapshot.behind];
    }
    return @"工作区与远程一致，随时可以提交新的更改。";
}

#pragma mark - 访问器

- (unsigned long long)ahead { return _ahead; }
- (void)setAhead:(id)arg1 { _ahead = [(NSNumber *)arg1 respondsToSelector:@selector(unsignedLongLongValue)] ? [(NSNumber *)arg1 unsignedLongLongValue] : 0; }

- (unsigned long long)behind { return _behind; }
- (void)setBehind:(id)arg1 { _behind = [(NSNumber *)arg1 respondsToSelector:@selector(unsignedLongLongValue)] ? [(NSNumber *)arg1 unsignedLongLongValue] : 0; }

- (bool)branchEnabled { return _branchEnabled; }
- (void)setBranchEnabled:(id)arg1 { _branchEnabled = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO; }

- (NSString *)branchTitle { return _branchTitle ?: @"—"; }
- (void)setBranchTitle:(id)arg1 { _branchTitle = [(NSString *)arg1 copy]; }

- (bool)busy { return _busy; }
- (void)setBusy:(id)arg1 { _busy = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO; }

- (NSString *)detail { return _detail ?: @""; }
- (void)setDetail:(id)arg1 { _detail = [(NSString *)arg1 copy]; }

- (bool)detailIsActivity { return _detailIsActivity; }
- (void)setDetailIsActivity:(id)arg1 { _detailIsActivity = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO; }

- (bool)fetchEnabled { return _fetchEnabled; }
- (void)setFetchEnabled:(id)arg1 { _fetchEnabled = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO; }

- (NSString *)hint { return _hint ?: @""; }
- (void)setHint:(id)arg1 { _hint = [(NSString *)arg1 copy]; }

- (bool)pullEnabled { return _pullEnabled; }
- (void)setPullEnabled:(id)arg1 { _pullEnabled = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO; }

- (bool)pushEnabled { return _pushEnabled; }
- (void)setPushEnabled:(id)arg1 { _pushEnabled = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO; }

- (bool)pushProminent { return _pushProminent; }
- (void)setPushProminent:(id)arg1 { _pushProminent = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO; }

- (bool)remoteConfigured { return _remoteConfigured; }
- (void)setRemoteConfigured:(id)arg1 { _remoteConfigured = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO; }

- (bool)remoteEnabled { return _remoteEnabled; }
- (void)setRemoteEnabled:(id)arg1 { _remoteEnabled = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO; }

- (NSString *)remoteTitle { return _remoteTitle ?: @"添加远程"; }
- (void)setRemoteTitle:(id)arg1 { _remoteTitle = [(NSString *)arg1 copy]; }

- (NSString *)remoteURL { return _remoteURL; }
- (void)setRemoteURL:(id)arg1 { _remoteURL = [(NSString *)arg1 copy]; }

- (NSString *)title { return _title ?: @"工作区"; }
- (void)setTitle:(id)arg1 { _title = [(NSString *)arg1 copy]; }

@end
