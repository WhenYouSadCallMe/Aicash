//
//  CAAgentRuntimeManager — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAAgentRuntimeProcess;

@interface CAAgentRuntimeManager : NSObject
    - (unsigned long long)activeProcessCount;
    - (unsigned long long)activeRootProcessCount;
    - (id)diagnosticSnapshot;
    - (bool)lastLaunchUsedRootPersona;
    - (nullable CAAgentRuntimeProcess *)launchCodexExecutable:(id)executable arguments:(nullable NSArray *)arguments currentDirectory:(nullable id)currentDirectory environment:(nullable NSDictionary *)environment outputHandler:(nullable id)outputHandler errorHandler:(nullable id)errorHandler terminationHandler:(nullable id)terminationHandler error:(NSError **)error;
    - (bool)personaAPIsAvailable;
    - (void)processDidTerminate:(id)arg1 status:(id)arg2;
    - (id)sharedManager;

@end

NS_ASSUME_NONNULL_END
