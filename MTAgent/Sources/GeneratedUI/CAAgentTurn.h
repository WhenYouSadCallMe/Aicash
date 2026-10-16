//
//  CAAgentTurn — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAAgentTurn : NSObject
    - (signed long long)blockTypeForMessage:(id)arg1;
    - (NSMutableArray *)blocks;
    - (bool)isQueued;
    - (signed long long)role;
    - (void)setBlocks:(id)arg1;
    - (void)setQueued:(id)arg1;
    - (void)setRole:(id)arg1;
    - (void)setTurnId:(id)arg1;
    - (bool)shouldDisplayMessage:(id)arg1;
    - (NSString *)turnId;
    - (signed long long)turnRoleForMessage:(id)arg1;
    - (id)turnsFromMessages:(id)arg1;

@end

NS_ASSUME_NONNULL_END
