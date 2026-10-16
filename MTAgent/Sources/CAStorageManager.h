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

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)bytesBelow:(id)arg1;
    - (id)bytesBelow:(id)arg1 excluding:(id)arg2;
    - (id)cacheRoots;
    - (id)cleanDirectory:(id)arg1 preservingNames:(id)arg2 bytes:(id)arg3 count:(id)arg4 error:(id)arg5;
    - (id)cleanExpiredCaches;
    - (id)initWithSupport:(id)arg1 temporary:(id)arg2 caches:(id)arg3 cliLogs:(id)arg4;
    - (id)ownedBaseRootForDeletionPath:(id)arg1;
    - (id)protectedPathsComplete:(id)arg1 conversationBytes:(id)arg2 livePaths:(id)arg3;
    - (id)regularFilesBelow:(id)arg1 complete:(id)arg2;
    - (id)removePath:(id)arg1 bytes:(id)arg2 count:(id)arg3 error:(id)arg4;
    - (id)resetLocalStatePreservingCredentials;
    - (id)snapshotWithProgress:(id)arg1;
    - (id)validateDeletionPath:(id)arg1 forTraversal:(id)arg2 error:(id)arg3;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

NS_ASSUME_NONNULL_END
