//
//  CARemoteOperations.h — 远端策略/心跳（Supabase 契约）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CARemoteOperations : NSObject

@property (nonatomic, copy, nullable) NSString *anonymousID;
@property (nonatomic, copy, nullable) NSString *deviceGroupID;
@property (nonatomic, assign) BOOL remoteLoggingEnabled;
@property (nonatomic, assign) NSInteger heartbeatFailureLimit;
@property (nonatomic, assign) NSInteger consecutiveHeartbeatFailures;
@property (nonatomic, assign) BOOL heartbeatHealthy;
@property (nonatomic, copy, nullable) NSDate *lastHeartbeatSuccess;
@property (nonatomic, assign) BOOL policyKnown;
@property (nonatomic, copy, nullable) NSDictionary *policy;

+ (instancetype)sharedOperations;

- (NSURLRequest *)requestForPath:(NSString *)path method:(NSString *)method;
- (NSURLSession *)ephemeralSession;
- (NSString *)deviceModel;
- (NSString *)appVersion;

- (void)start;
- (void)performRefresh;
- (void)publishStateIfNeeded;
- (BOOL)heartbeatFreshAtTime:(NSDate *)now;
- (void)fetchPolicyWithCompletion:(nullable void (^)(NSDictionary *_Nullable policy, NSError *_Nullable error))completion;
- (void)applyPolicy:(NSDictionary *)policy;
- (void)sendHeartbeatWithCompletion:(nullable void (^)(BOOL ok, NSError *_Nullable error))completion;


// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)
    @property (nonatomic, strong, nullable) NSObject<OS_dispatch_queue> * queue;
    @property (nonatomic, assign) BOOL requestInFlight;
    @property (nonatomic, assign) BOOL started;
    @property (nonatomic, assign) BOOL theosRuntimeAllowed;
// ==PARITY-PROPERTIES-END==

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)remoteTheosEnabled;
    - (id)setRemoteTheosEnabled:(id)arg1;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

extern NSNotificationName const CARemoteOperationsDidChangeNotification;

NS_ASSUME_NONNULL_END
