#import "CAAgentRuntimeManager.h"
#import "CAAgentRuntimeProcess.h"
#import "CAProcess.h"

@interface CAAgentRuntimeProcess (ManagerPrivate)
- (void)setProcess:(CAProcess *)process;
@end

@interface CAAgentRuntimeManager ()
@property(nonatomic,strong) NSMutableArray<CAAgentRuntimeProcess *> *processes;
@property(nonatomic,assign) BOOL lastRoot;
@property(nonatomic,strong) dispatch_queue_t stateQueue;
@end

@implementation CAAgentRuntimeManager

+ (instancetype)sharedManager
{
    static CAAgentRuntimeManager *manager; static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ manager=[CAAgentRuntimeManager new]; });
    return manager;
}

- (instancetype)init
{
    if ((self=[super init])) { _processes=[NSMutableArray array]; _stateQueue=dispatch_queue_create("com.codexapp.runtime.manager", DISPATCH_QUEUE_SERIAL); }
    return self;
}

- (id)sharedManager { return [CAAgentRuntimeManager sharedManager]; }
- (bool)personaAPIsAvailable { return NO; }
- (bool)lastLaunchUsedRootPersona { return _lastRoot; }
- (unsigned long long)activeProcessCount { __block NSUInteger count; dispatch_sync(_stateQueue,^{count=self.processes.count;}); return count; }
- (unsigned long long)activeRootProcessCount { __block NSUInteger count=0; dispatch_sync(_stateQueue,^{for(CAAgentRuntimeProcess *p in self.processes) if(p.launchedWithRootPersona) count++;}); return count; }
- (id)diagnosticSnapshot { return @{ @"activeProcessCount": @([self activeProcessCount]), @"activeRootProcessCount": @([self activeRootProcessCount]), @"personaAPIsAvailable": @([self personaAPIsAvailable]), @"lastLaunchUsedRootPersona": @(_lastRoot) }; }

- (CAAgentRuntimeProcess *)launchCodexExecutable:(id)executable arguments:(NSArray *)arguments currentDirectory:(id)directory environment:(NSDictionary *)environment outputHandler:(id)outputHandler errorHandler:(id)errorHandler terminationHandler:(id)terminationHandler error:(NSError **)errorArg
{
    NSString *path = [executable isKindOfClass:NSURL.class] ? [executable path] : ([executable isKindOfClass:NSString.class] ? executable : nil);
    if (!path.length) { NSError *error=[NSError errorWithDomain:@"CodexApp.Runtime" code:400 userInfo:@{NSLocalizedDescriptionKey:@"missing executable"}]; if(errorArg) *errorArg=error; return nil; }
    CAProcess *task=[CAProcess new]; task.executableURL=[NSURL fileURLWithPath:path]; task.arguments=[arguments isKindOfClass:NSArray.class]?arguments:@[]; task.environment=[environment isKindOfClass:NSDictionary.class]?environment:nil; if([directory isKindOfClass:NSString.class]&&[directory length]) task.currentDirectoryURL=[NSURL fileURLWithPath:directory];
    NSPipe *input=[NSPipe pipe], *output=[NSPipe pipe], *errorPipe=[NSPipe pipe]; task.standardInput=input;task.standardOutput=output;task.standardError=errorPipe;
    BOOL usedRoot=NO; _lastRoot=usedRoot;
    CAAgentRuntimeProcess *wrapper=[[CAAgentRuntimeProcess alloc] initWithPID:0 inputHandle:input.fileHandleForWriting outputHandle:output.fileHandleForReading errorHandle:errorPipe.fileHandleForReading usedPersona:usedRoot outputHandler:outputHandler errorHandler:errorHandler terminationHandler:terminationHandler];
    NSError *launchError=nil; if(![task launchAndReturnError:&launchError]){if(errorArg)*errorArg=launchError;return nil;}
    [wrapper setProcess:task]; [wrapper setProcessIdentifier:@(task.processIdentifier)]; [wrapper setRunning:@YES];
    __weak typeof(self) weakSelf=self; __weak CAAgentRuntimeProcess *weakWrapper=wrapper;
    task.terminationHandler=^(CAProcess *finished){ CAAgentRuntimeProcess *strongWrapper=weakWrapper; if(!strongWrapper)return; [strongWrapper setTerminationStatus:@(finished.terminationStatus)];[strongWrapper setRunning:@NO]; void(^done)(CAAgentRuntimeProcess *)=strongWrapper.terminationHandler; if(done)done(strongWrapper); [strongWrapper setLifetimeRetainer:nil]; [weakSelf processDidTerminate:strongWrapper status:@(finished.terminationStatus)]; };
    dispatch_sync(_stateQueue,^{[self.processes addObject:wrapper];}); return wrapper;
}

- (void)processDidTerminate:(id)process status:(id)status { dispatch_async(_stateQueue,^{[self.processes removeObject:process];}); }

@end
