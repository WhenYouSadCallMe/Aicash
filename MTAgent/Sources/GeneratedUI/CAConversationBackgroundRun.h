//
//  CAConversationBackgroundRun — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CACodexEngine;
@class CAConversationBackgroundRun;
@class CAConversationRecord;
@class CAMessageItem;
@class NSMutableOrderedSet;

@interface CAConversationBackgroundRun : NSObject
    - (id)assistantForID:(id)arg1;
    - (void)cleanupAttachments;
    - (void)codexEngineDidCompleteTurnWithUsage:(id)arg1;
    - (void)codexEngineDidFailWithError:(id)arg1;
    - (void)codexEngineDidGenerateFileAtPath:(id)arg1;
    - (void)codexEngineDidGenerateImageData:(id)arg1;
    - (void)codexEngineDidReceiveActivityCard:(id)arg1;
    - (void)codexEngineDidReceiveAgentMessage:(id)arg1 messageId:(id)arg2;
    - (void)codexEngineDidReceiveAgentMessageDelta:(id)arg1 messageId:(id)arg2;
    - (void)codexEngineDidReceiveProposedPlan:(id)arg1;
    - (void)codexEngineDidReceiveThreadId:(id)arg1;
    - (void)codexEngineDidStartToolItem:(id)arg1;
    - (void)codexEngineDidStartTurn;
    - (void)codexEngineDidUpdateActivityCard:(id)arg1;
    - (void)codexEngineDidUpdateActivityStatus:(id)arg1;
    - (void)codexEngineDidUpdateToolItem:(id)arg1;
    - (id)didFinish;
    - (id)engine;
    - (void)finish;
    - (bool)finished;
    - (id)generatedArtifactMessage;
    - (id)generatedArtifactPaths;
    - (NSArray *)inFlightAttachments;
    - (id)initWithEngine:(id)arg1 record:(id)arg2 inFlightAttachments:(id)arg3 generatedArtifactPaths:(id)arg4 generatedArtifactMessage:(id)arg5;
    - (id)record;
    - (unsigned long long)saveGeneration;
    - (void)saveNow;
    - (void)scheduleSave;
    - (void)setDidFinish:(id)arg1;
    - (void)setEngine:(id)arg1;
    - (void)setFinished:(id)arg1;
    - (void)setGeneratedArtifactMessage:(id)arg1;
    - (void)setGeneratedArtifactPaths:(id)arg1;
    - (void)setInFlightAttachments:(id)arg1;
    - (void)setRecord:(id)arg1;
    - (void)setSaveGeneration:(id)arg1;
    - (void)setStreamTargets:(id)arg1;
    - (NSMutableDictionary *)streamTargets;
    - (void)upsertActivity:(id)arg1;

@end

NS_ASSUME_NONNULL_END
