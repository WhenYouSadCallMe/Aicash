//
//  CAMessageItem — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAToolItem;

@class NSArray;
@class NSDate;
@class NSString;

// ==CHAT-KIT-BEGIN== 聊天主流程共享定义（会话页 / 消息 Cell / 模型共用）
typedef NS_ENUM(NSInteger, CAMessageRole) {
    CAMessageRoleUser      = 0,
    CAMessageRoleAssistant = 1,
    CAMessageRoleSystem    = 2,
};

/// 消息卡片种类：普通文本 / 思考卡片 / 工具卡片 / 系统提示（错误、运行时引导）
typedef NS_ENUM(NSInteger, CAMessageActivityKind) {
    CAMessageActivityKindNone     = 0,
    CAMessageActivityKindText     = 0,
    CAMessageActivityKindThinking = 1,
    CAMessageActivityKindTool     = 2,
    CAMessageActivityKindNotice   = 3,
};
// ==CHAT-KIT-END==

@interface CAMessageItem : NSObject
    - (NSString *)activityDetail;
    - (unsigned long long)activityDetailBytes;
    - (NSString *)activityDetailFile;
    - (bool)activityDetailPersistencePending;
    - (id)activityDetailRenderCache;
    - (double)activityDuration;
    - (bool)activityExpanded;
    - (signed long long)activityKind;
    - (id)activityMessageWithKind:(id)arg1 title:(id)arg2 detail:(id)arg3 running:(id)arg4;
    - (NSString *)activityModelName;
    - (bool)activityModelRequested;
    - (NSString *)activityReasoningEffort;
    - (bool)activityRunning;
    - (NSDate *)activityStartedAt;
    - (NSString *)activityTitle;
    - (id)assistantMessageWithText:(id)arg1;
    - (NSArray *)displayAttachments;
    - (NSArray *)generatedArtifacts;
    - (NSString *)messageId;
    - (id)parsedBlocksCache;
    - (bool)queued;
    - (NSArray *)queuedAttachments;
    - (NSString *)queuedComposerText;
    - (NSString *)queuedPromptText;
    - (signed long long)role;
    - (void)setActivityDetail:(id)arg1;
    - (void)setActivityDetailBytes:(id)arg1;
    - (void)setActivityDetailFile:(id)arg1;
    - (void)setActivityDetailPersistencePending:(id)arg1;
    - (void)setActivityDetailRenderCache:(id)arg1;
    - (void)setActivityDuration:(id)arg1;
    - (void)setActivityExpanded:(id)arg1;
    - (void)setActivityKind:(id)arg1;
    - (void)setActivityModelName:(id)arg1;
    - (void)setActivityModelRequested:(id)arg1;
    - (void)setActivityReasoningEffort:(id)arg1;
    - (void)setActivityRunning:(id)arg1;
    - (void)setActivityStartedAt:(id)arg1;
    - (void)setActivityTitle:(id)arg1;
    - (void)setDisplayAttachments:(id)arg1;
    - (void)setGeneratedArtifacts:(id)arg1;
    - (void)setMessageId:(id)arg1;
    - (void)setParsedBlocksCache:(id)arg1;
    - (void)setQueued:(id)arg1;
    - (void)setQueuedAttachments:(id)arg1;
    - (void)setQueuedComposerText:(id)arg1;
    - (void)setQueuedPromptText:(id)arg1;
    - (void)setRole:(id)arg1;
    - (void)setStreaming:(id)arg1;
    - (void)setText:(id)arg1;
    - (void)setTimestamp:(id)arg1;
    - (void)setTokenUsage:(id)arg1;
    - (void)setToolItem:(id)arg1;
    - (bool)streaming;
    - (NSString *)text;
    - (NSDate *)timestamp;
    - (NSString *)tokenUsage;
    - (id)toolItem;
    - (id)toolMessageWithItem:(id)arg1;
    - (id)userMessageWithText:(id)arg1;

// ==CHAT-KIT-API-BEGIN== 聊天主流程便捷写入（不动上面 parity 选择器的占位签名）
/// 标量字段装箱写入的语义封装
- (void)setStreamingFlag:(BOOL)streaming;
- (void)setActivityOfKind:(CAMessageActivityKind)kind
                    title:(nullable NSString *)title
                   detail:(nullable NSString *)detail
                  running:(BOOL)running;
- (void)toggleActivityExpanded;
- (void)appendText:(nullable NSString *)delta;
- (BOOL)isNoticeMessage;
// ==CHAT-KIT-API-END==

@end

NS_ASSUME_NONNULL_END
