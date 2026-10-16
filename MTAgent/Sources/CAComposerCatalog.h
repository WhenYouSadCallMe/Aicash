//
//  CAComposerCatalog.h — 输入框（composer）目录：技能 / 插件 / MCP / 提示 / 记忆
//
//  原包符号对齐（SPEC/assets/objc_api_map.json → "CAComposerCatalog" / "CAComposerCatalogItem"）：
//    +sharedCatalog / -refreshForWorkspace:force:completion: / -restorePersistentCacheForWorkspace: /
//    -persistCacheForWorkspace: / -invalidate / -setSkill:enabled:completion: / -setMCPServer:enabled:completion: /
//    -removeMCPServer:completion: / -forgetMCPServerNamed: / -refreshLocalSkillsForWorkspace:completion: /
//    -refreshMCPForWorkspace:completion: / +scanSkillsWithHome:workspace: / +scanLocalPluginsWithHome:workspace: /
//    +scanConfiguredMCPWithHome: / +scanPromptsWithHome: / +scanMemoryWithHome:workspace: / +scanFilesWithHome:workspace: /
//    +sortedSkills: / +isInternalMCPName: / +logPluginMarketplaceResult:source:
//  条目 ivar（原包）：_body _detail _enabled _identifier _installed _kind _name _path _scope _summary _title
//  原包通知：CAComposerCatalogDidChangeNotification
//  原包文案（strings_full.txt 0x58df54…0x58f0a7 段）= 本文件内所有 CALog 模板
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 目录变更通知（原包名：CAComposerCatalogDidChangeNotification）
extern NSNotificationName const CAComposerCatalogDidChangeNotification;

typedef NS_ENUM(NSInteger, CAComposerCatalogKind) {
    CAComposerCatalogKindUnknown = 0,
    CAComposerCatalogKindSkill,
    CAComposerCatalogKindPlugin,
    CAComposerCatalogKindMCP,
    CAComposerCatalogKindPrompt,
    CAComposerCatalogKindMemory,
};

#pragma mark - 条目

@interface CAComposerCatalogItem : NSObject

@property (nonatomic, assign) CAComposerCatalogKind kind;         // _kind
@property (nonatomic, copy)   NSString *identifier;               // _identifier（skill:… / plugin:… / plugin-local:… / mcp:… / prompt:… / prompts:… / memory:…）
@property (nonatomic, copy)   NSString *name;                     // _name
@property (nonatomic, copy)   NSString *title;                    // _title
@property (nonatomic, copy)   NSString *summary;                  // _summary
@property (nonatomic, copy)   NSString *scope;                    // _scope（user / project / workspace / system / local / internal）
@property (nonatomic, copy)   NSString *path;                     // _path
@property (nonatomic, copy)   NSString *body;                     // _body
@property (nonatomic, copy)   NSString *detail;                   // _detail
@property (nonatomic, assign) BOOL enabled;                       // _enabled
@property (nonatomic, assign) BOOL installed;                     // _installed

+ (instancetype)itemWithKind:(CAComposerCatalogKind)kind identifier:(NSString *)identifier;

+ (NSString *)kindNameForKind:(CAComposerCatalogKind)kind;        // skill / plugin / mcp / prompt / memory
+ (CAComposerCatalogKind)kindForName:(NSString *)name;
- (NSString *)kindName;
- (NSString *)displayTitle;                                       // title ?: name ?: identifier

- (NSDictionary *)dictionaryRepresentation;
+ (nullable instancetype)itemWithDictionary:(NSDictionary *)dictionary;

@end

#pragma mark - 目录

@interface CAComposerCatalog : NSObject

@property (nonatomic, copy, readonly) NSArray<CAComposerCatalogItem *> *items;
@property (nonatomic, copy, readonly, nullable) NSString *workspacePath;
@property (nonatomic, assign, readonly) BOOL loading;
@property (nonatomic, strong, readonly, nullable) NSDate *loadedAt;
@property (nonatomic, copy, readonly, nullable) NSString *lastError;
@property (nonatomic, copy, readonly, nullable) NSString *lastMCPError;
@property (nonatomic, copy, readonly, nullable) NSString *lastPluginError;

+ (instancetype)sharedCatalog;

#pragma mark 刷新 / 缓存

- (void)refreshForWorkspace:(nullable NSString *)workspace
                      force:(BOOL)force
                 completion:(nullable void (^)(NSError *_Nullable error))completion;

- (void)refreshLocalSkillsForWorkspace:(nullable NSString *)workspace
                            completion:(nullable void (^)(NSError *_Nullable error))completion;

- (void)refreshMCPForWorkspace:(nullable NSString *)workspace
                    completion:(nullable void (^)(NSError *_Nullable error))completion;

- (BOOL)restorePersistentCacheForWorkspace:(nullable NSString *)workspace;
- (BOOL)persistCacheForWorkspace:(nullable NSString *)workspace;
- (void)invalidate;

#pragma mark 开关 / 删除

- (void)setSkill:(CAComposerCatalogItem *)item
         enabled:(BOOL)enabled
      completion:(nullable void (^)(BOOL ok, NSError *_Nullable error))completion;

- (void)setMCPServer:(CAComposerCatalogItem *)item
             enabled:(BOOL)enabled
          completion:(nullable void (^)(BOOL ok, NSError *_Nullable error))completion;

- (void)removeMCPServer:(CAComposerCatalogItem *)item
             completion:(nullable void (^)(BOOL ok, NSError *_Nullable error))completion;

- (void)forgetMCPServerNamed:(NSString *)name;

#pragma mark 扫描（原包为类方法；同时提供同名实例方法转发）

+ (NSArray<CAComposerCatalogItem *> *)scanSkillsWithHome:(NSString *)home
                                               workspace:(nullable NSString *)workspace;
+ (NSArray<CAComposerCatalogItem *> *)scanLocalPluginsWithHome:(NSString *)home
                                                     workspace:(nullable NSString *)workspace;
+ (NSArray<CAComposerCatalogItem *> *)scanConfiguredMCPWithHome:(NSString *)home;
+ (NSArray<CAComposerCatalogItem *> *)scanPromptsWithHome:(NSString *)home;
+ (NSArray<CAComposerCatalogItem *> *)scanMemoryWithHome:(NSString *)home
                                               workspace:(nullable NSString *)workspace;
+ (NSArray<CAComposerCatalogItem *> *)scanFilesWithHome:(NSString *)home
                                              workspace:(nullable NSString *)workspace;
+ (NSArray<CAComposerCatalogItem *> *)sortedSkills:(NSArray<CAComposerCatalogItem *> *)items;

- (NSArray<CAComposerCatalogItem *> *)scanSkillsWithHome:(NSString *)home
                                               workspace:(nullable NSString *)workspace;
- (NSArray<CAComposerCatalogItem *> *)scanLocalPluginsWithHome:(NSString *)home
                                                     workspace:(nullable NSString *)workspace;
- (NSArray<CAComposerCatalogItem *> *)scanConfiguredMCPWithHome:(NSString *)home;
- (NSArray<CAComposerCatalogItem *> *)scanPromptsWithHome:(NSString *)home;
- (NSArray<CAComposerCatalogItem *> *)scanMemoryWithHome:(NSString *)home
                                               workspace:(nullable NSString *)workspace;
- (NSArray<CAComposerCatalogItem *> *)scanFilesWithHome:(NSString *)home
                                              workspace:(nullable NSString *)workspace;

#pragma mark 工具

+ (BOOL)isInternalMCPName:(NSString *)name;
+ (void)logPluginMarketplaceResult:(nullable id)result source:(NSString *)source;


// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)
    @property (nonatomic, assign) BOOL cacheLookupAttempted;
    @property (nonatomic, strong, nullable) NSArray * lastServerMCP;
    @property (nonatomic, strong, nullable) NSArray * lastServerPlugins;
    @property (nonatomic, strong, nullable) NSArray * lastServerSkills;
    @property (nonatomic, strong, nullable) NSString * lastSkillsWorkspace;
    @property (nonatomic, strong, nullable) NSArray * skillErrors;
    @property (nonatomic, assign) BOOL skillsFromServer;
// ==PARITY-PROPERTIES-END==

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)compactReferenceForItem:(id)arg1;
    - (id)composerReferenceForItem:(id)arg1;
    - (id)expandedPromptFromAttributedText:(id)arg1;
    - (id)explicitMCPEnabledForName:(id)arg1 configText:(id)arg2;
    - (id)isLocallyManagedSkillItem:(id)arg1 workspace:(id)arg2;
    - (id)mcpServersFromServerResult:(id)arg1;
    - (id)mergedAccountPlugins:(id)arg1 supplemental:(id)arg2;
    - (id)pluginsFromServerResult:(id)arg1;
    - (id)promptByDescribingMCPMentionsInText:(id)arg1 items:(id)arg2;
    - (id)skillErrorsFromServerResult:(id)arg1;
    - (id)skillsFromServerResult:(id)arg1;
    - (id)synchronizeMCPEnabledFromDisk;
    - (id)updateKnownSkills;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

NS_ASSUME_NONNULL_END
