//
//  CAAgentRuntimeProcess — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAAgentRuntimeProcess;
@class NSFileHandle;
@class OS_dispatch_queue;
@class OS_dispatch_source;

@interface CAAgentRuntimeProcess : NSObject
    - (bool)drainHandle:(id)arg1 handler:(id)arg2;
    - (id)errorSource;
    - (instancetype)initWithPID:(int)pid inputHandle:(NSFileHandle *)inputHandle outputHandle:(NSFileHandle *)outputHandle errorHandle:(NSFileHandle *)errorHandle usedPersona:(BOOL)usedPersona outputHandler:(nullable id)outputHandler errorHandler:(nullable id)errorHandler terminationHandler:(nullable id)terminationHandler;
    - (id)ioQueue;
    - (bool)isRunning;
    - (bool)launchedWithRootPersona;
    - (id)lifetimeRetainer;
    - (id)outputSource;
    - (int)processIdentifier;
    - (void)setErrorSource:(id)arg1;
    - (void)setIoQueue:(id)arg1;
    - (void)setLaunchedWithRootPersona:(id)arg1;
    - (void)setLifetimeRetainer:(nullable id)arg1;
    - (void)setOutputSource:(id)arg1;
    - (void)setProcessIdentifier:(id)arg1;
    - (void)setRunning:(id)arg1;
    - (void)setStandardError:(id)arg1;
    - (void)setStandardInput:(id)arg1;
    - (void)setStandardOutput:(id)arg1;
    - (void)setTerminationHandler:(id)arg1;
    - (void)setTerminationStatus:(id)arg1;
    - (id)standardError;
    - (id)standardInput;
    - (id)standardOutput;
    - (void)terminate;
    - (id)terminationHandler;
    - (int)terminationStatus;

@end

NS_ASSUME_NONNULL_END
