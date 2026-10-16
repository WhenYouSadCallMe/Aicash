//
//  CAStorageManager.h
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAStorageManager : NSObject

+ (instancetype)sharedManager;

- (BOOL)prepareDirectoriesWithError:(NSError **)error;
- (void)purgeCachesWithCompletion:(nullable void (^)(NSError *_Nullable error))completion;
- (void)cleanupLegacyExternalResidue;
- (void)cleanupLegacyExternalResidueAtPath:(NSString *)path;
- (unsigned long long)directorySizeAtPath:(NSString *)path;
- (void)clearRuntimeDownloadCaches;

// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)
    @property (nonatomic, strong, nullable) NSString * caches;
    @property (nonatomic, strong, nullable) NSString * cliLogs;
    @property (nonatomic, copy, nullable) id isBuildCacheInUse;
    @property (nonatomic, copy, nullable) id isBusy;
    @property (nonatomic, strong, nullable) NSString * legacyHelpers;
    @property (nonatomic, copy, nullable) id liveProtectedPaths;
    @property (nonatomic, strong, nullable) NSString * temporary;
// ==PARITY-PROPERTIES-END==

#pragma mark - P2 补齐（原包方法对齐）

// 初始化（原包 initWithSupport:temporary:caches:cliLogs:）
- (instancetype)initWithSupport:(nullable NSString *)support
                      temporary:(nullable NSString *)temporary
                         caches:(nullable NSString *)caches
                       cliLogs:(nullable NSString *)cliLogs;

// 属性（原包 proplist）
@property (nonatomic, copy, readonly) NSString *support;

// 体积 / 文件统计
- (unsigned long long)bytesBelow:(NSString *)path;
- (unsigned long long)bytesBelow:(NSString *)path excluding:(nullable NSString *)excluding;
- (NSUInteger)regularFilesBelow:(NSString *)path complete:(NSError *_Nullable * _Nullable)error;

// 清理
- (nullable NSDictionary *)cleanDirectory:(NSString *)directory
                          preservingNames:(nullable NSArray<NSString *> *)preservingNames
                                    bytes:(nullable unsigned long long *)bytes
                                    count:(nullable NSUInteger *)count
                                    error:(NSError **)error;
- (BOOL)cleanExpiredCaches;
- (nullable NSArray<NSString *> *)cacheRoots;
- (BOOL)resetLocalStatePreservingCredentials;

// 删除安全校验（路径必须在本管理器管辖的根目录内）
- (nullable NSString *)ownedBaseRootForDeletionPath:(nullable NSString *)path;
- (BOOL)validateDeletionPath:(nullable NSString *)path forTraversal:(BOOL)traversal error:(NSError **)error;
- (BOOL)removePath:(NSString *)path bytes:(nullable unsigned long long *)bytes count:(nullable NSUInteger *)count error:(NSError **)error;

// 快照
- (nullable NSDictionary *)snapshotWithProgress:(nullable void (^)(double fraction, NSString *_Nullable stage))progress;
- (nullable NSDictionary *)protectedPathsComplete:(BOOL)complete conversationBytes:(unsigned long long)conversationBytes livePaths:(nullable NSArray<NSString *> *)livePaths;
@end

NS_ASSUME_NONNULL_END
