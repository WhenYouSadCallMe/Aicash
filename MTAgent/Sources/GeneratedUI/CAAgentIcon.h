//
//  CAAgentIcon — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAAgentIcon : NSObject
    - (id)accentColorForActivity:(id)arg1;
    - (id)accentColorForToolItem:(id)arg1;
    - (id)availableSymbol:(id)arg1 fallback:(id)arg2;
    - (bool)command:(id)arg1 containsPhrase:(id)arg2;
    - (id)commandTokens:(id)arg1;
    - (id)symbolNameForActivity:(id)arg1;
    - (id)symbolNameForCommand:(id)arg1;
    - (id)symbolNameForToolItem:(id)arg1;
    - (bool)text:(id)arg1 containsAny:(id)arg2;
    - (bool)tokens:(id)arg1 containsAny:(id)arg2;

@end

NS_ASSUME_NONNULL_END
