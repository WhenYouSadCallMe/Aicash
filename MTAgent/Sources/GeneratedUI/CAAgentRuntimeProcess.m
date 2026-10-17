#import "CAAgentRuntimeProcess.h"
#import "CAProcess.h"
#import <signal.h>

@interface CAAgentRuntimeProcess ()
@property(nonatomic,strong) NSFileHandle *standardInputValue;
@property(nonatomic,strong) NSFileHandle *standardOutputValue;
@property(nonatomic,strong) NSFileHandle *standardErrorValue;
@property(nonatomic,strong) dispatch_queue_t ioQueueValue;
@property(nonatomic,strong) dispatch_source_t outputSourceValue;
@property(nonatomic,strong) dispatch_source_t errorSourceValue;
@property(nonatomic,strong) id lifetimeRetainerValue;
@property(nonatomic,copy) void (^terminationHandlerValue)(CAAgentRuntimeProcess *process);
@property(nonatomic,assign) pid_t processIdentifierValue;
@property(nonatomic,assign) int terminationStatusValue;
@property(nonatomic,assign) BOOL runningValue;
@property(nonatomic,assign) BOOL launchedWithRootPersonaValue;
@property(nonatomic,strong) CAProcess *process;
@end

@implementation CAAgentRuntimeProcess

- (id)ioQueue{return _ioQueueValue;} - (void)setIoQueue:(id)v{_ioQueueValue=v;}
- (id)outputSource{return _outputSourceValue;} - (void)setOutputSource:(id)v{_outputSourceValue=v;}
- (id)errorSource{return _errorSourceValue;} - (void)setErrorSource:(id)v{_errorSourceValue=v;}
- (id)lifetimeRetainer{return _lifetimeRetainerValue;} - (void)setLifetimeRetainer:(id)v{_lifetimeRetainerValue=v;}
- (id)standardInput{return _standardInputValue;} - (void)setStandardInput:(id)v{_standardInputValue=v;}
- (id)standardOutput{return _standardOutputValue;} - (void)setStandardOutput:(id)v{_standardOutputValue=v;}
- (id)standardError{return _standardErrorValue;} - (void)setStandardError:(id)v{_standardErrorValue=v;}
- (id)terminationHandler{return _terminationHandlerValue;} - (void)setTerminationHandler:(id)v{_terminationHandlerValue=[v copy];}
- (int)processIdentifier{return (int)_processIdentifierValue;} - (void)setProcessIdentifier:(id)v{_processIdentifierValue=[v intValue];}
- (int)terminationStatus{return _terminationStatusValue;} - (void)setTerminationStatus:(id)v{_terminationStatusValue=[v intValue];}
- (bool)isRunning{return _runningValue;} - (void)setRunning:(id)v{_runningValue=[v boolValue];}
- (bool)launchedWithRootPersona{return _launchedWithRootPersonaValue;} - (void)setLaunchedWithRootPersona:(id)v{_launchedWithRootPersonaValue=[v boolValue];}

- (instancetype)initWithPID:(int)pid inputHandle:(NSFileHandle *)input outputHandle:(NSFileHandle *)output errorHandle:(NSFileHandle *)error usedPersona:(BOOL)persona outputHandler:(id)outHandler errorHandler:(id)errHandler terminationHandler:(id)termination
{
    if ((self=[super init])) {
        _processIdentifierValue=pid; _standardInputValue=input; _standardOutputValue=output; _standardErrorValue=error; _launchedWithRootPersonaValue=persona; _runningValue=_processIdentifierValue>0; _ioQueueValue=dispatch_queue_create("com.codexapp.runtime.io", DISPATCH_QUEUE_SERIAL);
        [self drainHandle:output handler:outHandler]; [self drainHandle:error handler:errHandler];
        self.terminationHandlerValue=[termination copy];
        self.lifetimeRetainerValue=self;
    }
    return self;
}

- (bool)drainHandle:(id)handle handler:(id)handler
{
    if (![handle isKindOfClass:NSFileHandle.class] || !handler) return NO;
    NSFileHandle *file=handle; void (^callback)(NSData *)=[handler copy];
    file.readabilityHandler=^(NSFileHandle *h){NSData *data=h.availableData;if(!data.length){h.readabilityHandler=nil;return;}dispatch_async(self.ioQueueValue,^{callback(data);});}; return YES;
}

- (void)terminate
{
    if (_process) [_process terminate]; else if (_processIdentifierValue>0 && _runningValue) kill(_processIdentifierValue,SIGTERM);
    _standardOutputValue.readabilityHandler=nil;
    _standardErrorValue.readabilityHandler=nil;
    _runningValue=NO; _outputSourceValue=nil; _errorSourceValue=nil; _lifetimeRetainerValue=nil;
}

@end
