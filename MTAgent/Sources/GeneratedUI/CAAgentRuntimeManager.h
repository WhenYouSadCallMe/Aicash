//
//  CAAgentRuntimeManager — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAAgentRuntimeManager : NSObject
    - (unsigned long long)activeProcessCount;
    - (unsigned long long)activeRootProcessCount;
    - (id)diagnosticSnapshot;
    - (bool)lastLaunchUsedRootPersona;
    - (id)launchCodexExecutable:(id)arg1 arguments:(id)arg2 currentDirectory:(id)arg3 environment:(id)arg4 outputHandler:(id)arg5 errorHandler:(id)arg6 terminationHandler:(id)arg7 error:(id)arg8;
    - (bool)personaAPIsAvailable;
    - (void)processDidTerminate:(id)arg1 status:(id)arg2;
    - (id)sharedManager;

@end

NS_ASSUME_NONNULL_END
