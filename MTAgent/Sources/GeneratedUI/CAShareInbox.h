//
//  CAShareInbox — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAShareInbox : NSObject
    - (void)clearPublishedConversation;
    - (void)discardImportedBatches:(id)arg1;
    - (void)discardTemporaryAttachments:(id)arg1;
    - (void)loadAttachmentsForConversationId:(id)arg1 completion:(id)arg2;
    - (void)loadAttachmentsForConversationId:(id)arg1 workspacePath:(id)arg2 completion:(id)arg3;
    - (void)loadAttachmentsForConversationId:(id)arg1 workspacePath:(id)arg2 selectionToken:(id)arg3 completion:(id)arg4;
    - (void)publishConversationId:(id)arg1;
    - (void)publishConversationId:(id)arg1 workspacePath:(id)arg2;
    - (void)publishConversationId:(id)arg1 workspacePath:(id)arg2 selectionToken:(id)arg3;

@end

NS_ASSUME_NONNULL_END
