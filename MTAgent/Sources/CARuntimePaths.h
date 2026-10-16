//
//  CARuntimePaths.h
//

#import <Foundation/Foundation.h>
#import <sys/stat.h>

NS_ASSUME_NONNULL_BEGIN

@interface CARuntimePaths : NSObject

+ (NSString *)documentsDirectory;
+ (NSString *)documentsCodexDirectory;
+ (NSString *)documentsCodexLogDirectory;
+ (NSString *)documentsHelpersDirectory;
+ (NSString *)documentsCodexMTDirectory;

+ (NSString *)supportDirectory;
+ (NSString *)cachesDirectory;
+ (NSString *)preferencesPlistPath;

+ (NSString *)deviceGroupIDPath;
+ (NSString *)legacyExternalDeviceGroupIDPath;
+ (NSString *)legacyExternalDiagnosticsDirectory;
+ (NSString *)legacyCodexHelpersDirectory;

+ (NSString *)codexHome;
+ (NSString *)authJSONPath;
+ (NSString *)configTOMLPath;
+ (NSString *)thirdPartyCatalogPath;
+ (NSString *)sessionsDirectory;
+ (NSString *)archivedSessionsDirectory;
+ (NSString *)conversationsDirectory;
+ (NSString *)artifactsDirectory;
+ (NSString *)composerCatalogCacheDirectory;
+ (NSString *)logsDirectory;
+ (NSString *)legacyLogsDirectory;
+ (NSString *)runtimeDownloadsDirectory;
+ (NSString *)reverseToolsDirectory;
+ (NSString *)logsCacheDirectory;
+ (NSString *)diagnosticsDirectory;
+ (NSString *)runtimeProbeDirectory;
+ (NSString *)tmpDirectory;
+ (NSString *)globalTmpDirectory;

+ (NSString *)helpersDirectory;
+ (NSString *)bashRealPath;
+ (NSString *)bashPath;
+ (NSString *)shPath;
+ (NSString *)bashCodexPath;
+ (NSString *)fileToolPath;
+ (NSString *)codexSignPath;
+ (NSString *)theosHelperPath;
+ (NSString *)bundledCACertPath;
+ (NSString *)helperSearchPath;
+ (NSString *)jailbreakRootPath;

+ (NSString *)runtimeRootForID:(NSString *)runtimeID;
+ (NSString *)installedManifestPathForRuntimeID:(NSString *)runtimeID;
+ (NSString *)archiveCachePathForEntry:(NSString *)runtimeID sha256:(nullable NSString *)sha;

+ (nullable NSString *)safeRelativePath:(NSString *)relative inRoot:(NSString *)root error:(NSError **)error;
+ (BOOL)ensureDirectory:(NSString *)path mode:(mode_t)mode error:(NSError **)error;
+ (BOOL)writeFileAtomically:(NSString *)path contents:(NSData *)data mode:(mode_t)mode error:(NSError **)error;


// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)appBundleRoot;
    - (id)applicationSupportRoot;
    - (id)bundleCodeModeHostExecutable;
    - (id)bundleCodexExecutable;
    - (id)bundleHelpersDirectory;
    - (id)bundlePythonRuntimeRoot;
    - (id)bundleReverseToolsRuntimeRoot;
    - (id)bundleTheosRuntimeRoot;
    - (id)codexHomeDirectory;
    - (id)executableNamed:(id)arg1 environment:(id)arg2;
    - (id)remoteStateDirectory;
    - (id)runtimeConfigurationDirectory;
// ==PARITY-SELECTOR-PLACEHOLDER-END==

// P2 补齐（原包方法对齐）
+ (NSString *)thirdPartyModelCatalogPath;
+ (NSArray<NSString *> *)helperSearchPathComponents;
@end

NS_ASSUME_NONNULL_END
