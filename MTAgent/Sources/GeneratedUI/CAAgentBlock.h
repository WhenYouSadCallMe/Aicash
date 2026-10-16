//
//  CAAgentBlock — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAMessageItem;

@interface CAAgentBlock : NSObject
    - (NSString *)blockId;
    - (NSArray *)groupedMessages;
    - (CAMessageItem *)message;
    - (void)setBlockId:(id)arg1;
    - (void)setGroupedMessages:(id)arg1;
    - (void)setMessage:(id)arg1;
    - (void)setType:(id)arg1;
    - (signed long long)type;

@end

NS_ASSUME_NONNULL_END
