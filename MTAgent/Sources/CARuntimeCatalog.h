//
//  CARuntimeCatalog.h — 运行时清单（runtime-manifest.json）模型与拉取
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CARuntimeCatalogEntry : NSObject

@property (nonatomic, copy, nullable) NSString *runtimeID;
@property (nonatomic, copy, nullable) NSString *displayName;
@property (nonatomic, copy, nullable) NSString *summary;
@property (nonatomic, copy, nullable) NSString *handler;
@property (nonatomic, copy, nullable) NSString *group;
@property (nonatomic, copy, nullable) NSString *version;
@property (nonatomic, assign) NSInteger revision;
@property (nonatomic, copy, nullable) NSString *archiveURL;
@property (nonatomic, copy, nullable) NSString *archiveSHA256;
@property (nonatomic, assign) unsigned long long downloadSize;
@property (nonatomic, assign) unsigned long long expandedSize;
@property (nonatomic, assign) NSInteger order;
@property (nonatomic, assign) BOOL optional;
@property (nonatomic, copy, nullable) NSDictionary *install;
@property (nonatomic, copy, nullable) NSDictionary *raw;

+ (nullable instancetype)entryWithDictionary:(NSDictionary *)dictionary error:(NSError **)error;

@end

@interface CARuntimeCatalog : NSObject

@property (nonatomic, copy, readonly) NSString *manifestURLString;
@property (nonatomic, copy, readonly) NSString *cachePath;
@property (nonatomic, strong, readonly) NSArray<CARuntimeCatalogEntry *> *entries;
@property (nonatomic, strong, readonly) NSArray<NSString *> *newlyAvailableRuntimeIDs;
@property (nonatomic, strong, readonly) NSArray<NSString *> *changedRuntimeIDs;
@property (nonatomic, copy, nullable) NSString *lastError;
@property (nonatomic, assign) BOOL refreshing;

+ (instancetype)sharedCatalog;

- (void)startAutoRefresh;
- (void)refreshIfStale;
- (void)refreshNowWithCompletion:(nullable void (^)(BOOL ok, NSError *_Nullable error))completion;
- (nullable CARuntimeCatalogEntry *)entryForID:(NSString *)runtimeID;
- (BOOL)isSafeHTTPSURL:(NSURL *)url;
- (nullable NSArray<CARuntimeCatalogEntry *> *)entriesFromData:(NSData *)data error:(NSError **)error;
- (void)applyEntries:(NSArray<CARuntimeCatalogEntry *> *)entries markChanges:(BOOL)markChanges;
- (BOOL)loadCachedManifest;
- (NSString *)fallbackDisplayName:(NSString *)runtimeID;
- (NSString *)fallbackHandler:(NSString *)runtimeID;


// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)
    @property (nonatomic, strong, nullable) NSDate * lastRefreshDate;
// ==PARITY-PROPERTIES-END==

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)markCurrentChangesSeen;
    - (id)toolEntries;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

extern NSNotificationName const CARuntimeCatalogDidChangeNotification;

NS_ASSUME_NONNULL_END
