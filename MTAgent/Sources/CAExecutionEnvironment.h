//
//  CAExecutionEnvironment.h — 运行环境探测（越狱/TrollStore/根模式/launcher）与派生策略
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CARootMode) { CARootModeUnknown = 0, CARootModeRootless, CARootModeRootful, CARootModeRootHide, CARootModeRoothide };

@interface CAExecutionEnvironmentProfile : NSObject <NSCopying>
@property (nonatomic, copy)   NSString *environmentKind;      // standalone / jailbroken / trollstore ...
@property (nonatomic, assign) BOOL hasJailbreakEvidence;
@property (nonatomic, assign) BOOL hasTrollStore;
@property (nonatomic, assign) BOOL prefersNativeTheosPackaging;
@property (nonatomic, assign) CARootMode rootMode;
@property (nonatomic, copy)   NSString *rootModeString;
@property (nonatomic, copy)   NSString *familyName;
@property (nonatomic, copy)   NSString *brandName;
@property (nonatomic, copy)   NSString *launcherDisplayName;
@property (nonatomic, copy)   NSString *launcherBundleId;
@property (nonatomic, copy)   NSString *launcherAppPath;
@property (nonatomic, copy)   NSString *trollStoreFlavor;
@property (nonatomic, copy)   NSString *evidenceSummary;
@end

@interface CAExecutionEnvironment : NSObject

@property (nonatomic, strong) CAExecutionEnvironmentProfile *profile;
@property (nonatomic, copy) NSString *shellExecutable;
@property (nonatomic, copy) NSString *shellSpawnMode;      // forkless-posix_spawn / native-fork
@property (nonatomic, copy) NSString *runtimeEnvironmentKind;
@property (nonatomic, assign) BOOL runtimeHasJailbreakEvidence;
@property (nonatomic, assign) BOOL runtimeHasTrollStore;
@property (nonatomic, copy) NSString *runtimeJailbreakBrand;
@property (nonatomic, copy) NSString *runtimeJailbreakFamily;
@property (nonatomic, copy) NSString *runtimeJailbreakLauncher;
@property (nonatomic, copy) NSString *runtimeJailbreakLauncherBundle;
@property (nonatomic, copy) NSString *runtimeEnvironmentEvidence;
@property (nonatomic, assign) CARootMode runtimeRootMode;
@property (nonatomic, copy) NSString *runtimeTrollStoreFlavor;

+ (instancetype)sharedEnvironment;

- (void)refresh;
- (NSDictionary<NSString *, NSString *> *)environmentVariablesForRuntime;
- (NSString *)shellBootstrapProbeOutput;      // 原包探查脚本（EUID/SHELL_OK/DOCS_READ/DOCS_WRITE）
- (NSDictionary<NSString *, NSNumber *> *)resolvedWorkspaceKeys;

// 证据扫描
- (NSArray<NSString *> *)scanApplicationEvidence;
- (BOOL)hasRootHideRuntimeFilesystemEvidence;
- (BOOL)hasRootHideIdentityFilesystemEvidence;
- (BOOL)hasRootHidePrebootEvidence;
- (NSString *)detectTrollStoreFlavorWithApplicationEvidence:(NSArray<NSString *> *)evidence;
- (NSString *)resolvedBrandWithApplicationEvidence:(NSArray<NSString *> *)evidence legacyName:(NSString *)legacy;

@end

NS_ASSUME_NONNULL_END
