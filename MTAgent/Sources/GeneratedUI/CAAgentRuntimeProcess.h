//
//  CAAgentRuntimeProcess — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAAgentRuntimeProcess : NSObject
    - (bool)drainHandle:(id)arg1 handler:(id)arg2;
    - (OS_dispatch_source *)errorSource;
    - (CAAgentRuntimeProcess *)initWithPID:(id)arg1 inputHandle:(id)arg2 outputHandle:(id)arg3 errorHandle:(id)arg4 usedPersona:(id)arg5 outputHandler:(id)arg6 errorHandler:(id)arg7 terminationHandler:(id)arg8;
    - (OS_dispatch_queue *)ioQueue;
    - (bool)isRunning;
    - (bool)launchedWithRootPersona;
    - (id)lifetimeRetainer;
    - (OS_dispatch_source *)outputSource;
    - (int)processIdentifier;
    - (void)setErrorSource:(id)arg1;
    - (void)setIoQueue:(id)arg1;
    - (void)setLaunchedWithRootPersona:(id)arg1;
    - (void)setLifetimeRetainer:(id)arg1;
    - (void)setOutputSource:(id)arg1;
    - (void)setProcessIdentifier:(id)arg1;
    - (void)setRunning:(id)arg1;
    - (void)setStandardError:(id)arg1;
    - (void)setStandardInput:(id)arg1;
    - (void)setStandardOutput:(id)arg1;
    - (void)setTerminationHandler:(id)arg1;
    - (void)setTerminationStatus:(id)arg1;
    - (NSFileHandle *)standardError;
    - (NSFileHandle *)standardInput;
    - (NSFileHandle *)standardOutput;
    - (void)terminate;
    - (id)terminationHandler;
    - (int)terminationStatus;

@end

NS_ASSUME_NONNULL_END
