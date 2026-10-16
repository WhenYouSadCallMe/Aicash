//
//  CACommandSemantic — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CACommandSemantic : NSObject
    - (id)failureTitleForKind:(id)arg1;
    - (signed __int64)kindForCommand:(id)arg1;
    - (id)returnedUnknownTitleForKind:(id)arg1 hasOutput:(id)arg2;
    - (id)runningTitleForKind:(id)arg1;
    - (id)stoppedTitleForKind:(id)arg1;
    - (id)successTitleForKind:(id)arg1;
    - (id)symbolNameForKind:(id)arg1;
    - (bool)text:(id)arg1 containsAny:(id)arg2;
    - (bool)tokens:(id)arg1 containAny:(id)arg2;
    - (id)tokensForCommand:(id)arg1;
    - (id)verbForKind:(id)arg1;

@end

NS_ASSUME_NONNULL_END
