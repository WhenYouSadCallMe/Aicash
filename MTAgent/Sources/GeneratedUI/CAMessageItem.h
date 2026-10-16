//
//  CAMessageItem — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAMessageItem : NSObject
    - (NSString *)activityDetail;
    - (unsigned __int64)activityDetailBytes;
    - (NSString *)activityDetailFile;
    - (bool)activityDetailPersistencePending;
    - (id)activityDetailRenderCache;
    - (double)activityDuration;
    - (bool)activityExpanded;
    - (signed __int64)activityKind;
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
    - (signed __int64)role;
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
    - (CAToolItem *)toolItem;
    - (id)toolMessageWithItem:(id)arg1;
    - (id)userMessageWithText:(id)arg1;

@end

NS_ASSUME_NONNULL_END
