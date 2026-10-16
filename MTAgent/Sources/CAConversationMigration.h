//
//  CAConversationMigration — 会话迁移 journal 模型（原包零提及符号，IDA 字符串表确认存在）
//  工作区/存储切换时，逐条记录迁移动作（version/conversationId/source/target/phase），支持 JSON 持久化。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const CAConversationMigrationJournalDidChangeNotification;

@interface CAConversationMigration : NSObject

@property (nonatomic, assign) NSInteger version;        // journal 格式版本（当前 1）
@property (nonatomic, copy, nullable) NSString *conversationId;
@property (nonatomic, copy, nullable) NSString *source;  // 源路径 / 源存储标识
@property (nonatomic, copy, nullable) NSString *target;  // 目标路径 / 目标存储标识
@property (nonatomic, copy, nullable) NSString *phase;   // pending / copying / committed / failed

/// journal 文件路径（Application Support/CodexApp/migration-journal.json）
+ (NSString *)journalPath;

/// 读取整本 journal（缺失返回空数组）
+ (NSArray<CAConversationMigration *> *)loadJournal;

/// 追加一条迁移记录并原子落盘
+ (BOOL)appendMigration:(CAConversationMigration *)migration error:(NSError **)error;

/// 清空 journal（迁移全部完成后调用）
+ (BOOL)clearJournal:(NSError **)error;

/// 字段校验构造：conversationId/source/target 任一缺失返回 nil
+ (nullable instancetype)migrationFromDictionary:(NSDictionary *)dictionary;

- (NSDictionary *)toDictionary;
- (BOOL)isTerminalPhase;   // committed / failed

@end

NS_ASSUME_NONNULL_END
