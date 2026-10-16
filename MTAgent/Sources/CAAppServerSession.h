//
//  CAAppServerSession.h — codex app-server（--stdio）JSON-RPC 会话
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class CAAppServerSession;


// ==PARITY-FORWARD-DECLS-BEGIN==
@class CAAgentRuntimeProcess;
// ==PARITY-FORWARD-DECLS-END==

@protocol CAAppServerSessionDelegate <NSObject>
@optional
- (void)appServerSession:(CAAppServerSession *)session didInvalidateWithReason:(NSString *)reason;
- (void)appServerSession:(CAAppServerSession *)session didRequestUserInput:(NSDictionary *)request;
- (void)appServerSession:(CAAppServerSession *)session didReportUsage:(NSDictionary *)usage;
- (void)appServerSession:(CAAppServerSession *)session didEmitNotification:(NSString *)method params:(NSDictionary *)params;
@end

@interface CAAppServerSession : NSObject

@property (nonatomic, weak, nullable) id<CAAppServerSessionDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *executable;
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, copy, readonly) NSString *workingDirectory;
@property (nonatomic, assign, readonly) BOOL isRunning;
@property (nonatomic, assign, readonly) int processIdentifier;
@property (nonatomic, copy, nullable) NSString *signature;

/// 原包同名属性：app-server 向客户端发带 id 请求时的处理器。
/// 签名：void (^)(NSString *method, NSDictionary *params, NSNumber *requestID)
/// 设置后，带 id 且无 result/error 的入站消息交给 handler，不再走 didEmitNotification（避免重复弹卡）；
/// 未设置时维持旧行为（按通知分发）。
@property (nonatomic, copy, nullable) void (^serverRequestHandler)(NSString *method, NSDictionary *params, NSNumber *requestID);

- (instancetype)initWithExecutable:(NSString *)executable
                         arguments:(NSArray<NSString *> *)arguments
                       environment:(NSDictionary<NSString *, NSString *> *)environment
                 workingDirectory:(NSString *)workingDirectory;

- (void)startWithCompletion:(nullable void (^)(BOOL ok, NSError *_Nullable error))completion;
- (void)stop;
- (BOOL)retireIfIdle;

- (void)callMethod:(NSString *)method
        parameters:(nullable NSDictionary *)parameters
        completion:(nullable void (^)(id _Nullable result, NSError *_Nullable error))completion;

/// 应答 app-server 发来的带 id 请求（如 item/tool/requestUserInput）：回 {"jsonrpc":"2.0","id":rid,"result":...}
/// result 传 nil 时回空对象 {}（codex 协议正常路径语义）。
- (void)sendResult:(nullable id)result forRequestID:(nullable id)requestID;

- (NSDictionary *)diagnosticSnapshot;


// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)
    @property (nonatomic, strong, nullable) NSString * currentDirectory;
    @property (nonatomic, strong, nullable) NSFileHandle * inputHandle;
    @property (nonatomic, strong, nullable) NSString * lastError;
    @property (nonatomic, strong, nullable) NSMutableData * lineBuffer;
    @property (nonatomic, copy, nullable) id notificationHandler;
    @property (nonatomic, strong, nullable) NSMutableDictionary * pendingRequests;
    @property (nonatomic, strong, nullable) CAAgentRuntimeProcess * process;
    @property (nonatomic, strong, nullable) NSObject<OS_dispatch_queue> * queue;
    @property (nonatomic, assign) BOOL reportedLateSubagentCleanup;
    @property (nonatomic, assign) BOOL restartAfterStop;
    @property (nonatomic, strong, nullable) NSMutableArray * startWaiters;
    @property (nonatomic, copy, nullable) id stopLifetimeRetainer;
    @property (nonatomic, assign) BOOL stopRequested;
    @property (nonatomic, strong, nullable) NSMutableArray * stopWaiters;
// ==PARITY-PROPERTIES-END==

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)finishStartWaiters:(id)arg1 error:(id)arg2;
    - (id)finishStopWaiters;
    - (id)handleMessage:(id)arg1;
    - (id)processData:(id)arg1;
    - (id)rootPersona;
    - (id)sendNotificationMethod:(id)arg1 params:(id)arg2;
    - (id)sendRequestMethod:(id)arg1 params:(id)arg2 timeout:(id)arg3 completion:(id)arg4;
    - (id)setUnexpectedTerminationHandler:(id)arg1;
    - (id)stopWithCompletion:(id)arg1;
    - (id)unexpectedTerminationHandler;
    - (id)writeJSON:(id)arg1;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

NS_ASSUME_NONNULL_END
