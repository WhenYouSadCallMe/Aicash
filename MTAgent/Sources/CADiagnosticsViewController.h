//
//  CADiagnosticsViewController.h — 诊断页（网络 / 远端开关 / 运行时 / 环境 / shell 探针 / MCP 桥 / 登录态）
//
//  原包符号对齐：-run、-diagnosticSnapshot、-handleCopyReport、-handleShareReport、
//  checkCount / problemCount / startedAt / finishedAt / probing / installStatus /
//  activeInstallRuntimeID / installCompletedCount / installTotalCount / rerunItem / shareItem / reportCopyItem
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CADiagnosticsViewController : UIViewController

/// 分区（元素为私有实现类 CADiagnosticsSection）
@property (nonatomic, strong, nullable) NSArray *sections;

/// 最近一次探测快照
@property (nonatomic, strong, nullable) NSDictionary *result;

@property (nonatomic, assign) NSInteger checkCount;
@property (nonatomic, assign) NSInteger problemCount;
@property (nonatomic, strong, nullable) NSDate *startedAt;
@property (nonatomic, strong, nullable) NSDate *finishedAt;
@property (nonatomic, assign) BOOL probing;

/// 运行时安装状态文案（原包 ivar: _installStatus）
@property (nonatomic, copy, nullable) NSString *installStatus;
@property (nonatomic, copy, nullable) NSString *activeInstallRuntimeID;
@property (nonatomic, assign) NSInteger installCompletedCount;
@property (nonatomic, assign) NSInteger installTotalCount;

/// 导航项：重新检查 / 分享报告 / 复制报告
@property (nonatomic, strong, nullable) UIBarButtonItem *rerunItem;
@property (nonatomic, strong, nullable) UIBarButtonItem *shareItem;
@property (nonatomic, strong, nullable) UIBarButtonItem *reportCopyItem;

#pragma mark - 探测

/// 重新跑一遍全部检查
- (void)run;

/// 生成诊断快照（可后台调用）
- (NSDictionary *)diagnosticSnapshot;

#pragma mark - 报告

- (void)handleCopyReport;
- (void)handleShareReport;


// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)
    @property (nonatomic, assign) int elapsedTimer;
    @property (nonatomic, assign) BOOL installingRuntime;
    @property (nonatomic, assign) unsigned long long runGeneration;
// ==PARITY-PROPERTIES-END==

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)finishRuntimeInstallBatchWithFailures:(id)arg1;
    - (id)hasRuntimeActivity;
    - (id)installRequiredRuntimes;
    - (id)installRuntimeID:(id)arg1 completion:(id)arg2;
    - (id)installRuntimeIDs:(id)arg1 index:(id)arg2 failures:(id)arg3;
    - (id)installSingleRuntimeID:(id)arg1;
    - (id)kickAutomaticRuntimeRecovery;
    - (id)liveRuntimeActivityForID:(id)arg1;
    - (id)requiredRuntimeIDsNeedingInstall;
    - (id)requiredRuntimeInstallDetail;
    - (id)runtimeCheckForID:(id)arg1;
    - (id)runtimeItemFromCheck:(id)arg1;
    - (id)runtimeStateDidChange:(id)arg1;
    - (id)setRuntimeInstallStatus:(id)arg1 runtimeID:(id)arg2;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

NS_ASSUME_NONNULL_END
