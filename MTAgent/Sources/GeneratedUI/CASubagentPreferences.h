//
//  CASubagentPreferences — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CASubagentPreferences;

@class NSUserDefaults;

@interface CASubagentPreferences : NSObject
    - (id)argumentsForConfiguration:(id)arg1;
    - (NSUserDefaults *)defaults;
    - (id)effortOverrideForThirdParty:(id)arg1;
    - (id)explicitOverridesForThirdParty:(id)arg1;
    - (id)initWithDefaults:(id)arg1;
    - (id)key:(id)arg1 thirdParty:(id)arg2;
    - (id)modelOverrideForThirdParty:(id)arg1;
    - (id)resolvedWithMainModel:(id)arg1 effort:(id)arg2 thirdParty:(id)arg3;
    - (void)setDefaults:(id)arg1;
    - (void)setEffortOverride:(id)arg1 thirdParty:(id)arg2;
    - (void)setModelOverride:(id)arg1 thirdParty:(id)arg2;
    - (void)setValue:(id)arg1 kind:(id)arg2 thirdParty:(id)arg3;
    - (id)sharedPreferences;
    - (id)threadConfigOverridesForConfiguration:(id)arg1;

@end

NS_ASSUME_NONNULL_END
