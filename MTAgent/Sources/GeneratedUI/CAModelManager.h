//
//  CAModelManager — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAModelItem;

@interface CAModelManager : NSObject
    - (id)activeModel;
    - (NSString *)activeReasoningEffort;
    - (void)applyAppServerModelCatalog:(id)arg1;
    - (NSArray *)availableModels;
    - (NSMutableArray *)internalModels;
    - (void)reloadAvailableModels;
    - (void)restoreActiveSelection;
    - (bool)restoreSelectionForConversationId:(id)arg1;
    - (void)saveSelectionForConversationId:(id)arg1;
    - (void)selectModelBySlug:(id)arg1;
    - (void)selectReasoningEffort:(id)arg1;
    - (id)selectionKeyForConversationId:(id)arg1;
    - (void)setActiveModel:(id)arg1;
    - (void)setActiveReasoningEffort:(id)arg1;
    - (void)setInternalModels:(id)arg1;
    - (id)sharedManager;

@end

NS_ASSUME_NONNULL_END
