//
//  CALogger.h
//

#import "CACommon.h"

NS_ASSUME_NONNULL_BEGIN

@interface CALogger : NSObject

@property (nonatomic, copy, nullable) NSString *logFilePath;
@property (nonatomic, strong, nullable) NSUserDefaults *preferences;
@property (nonatomic, assign) BOOL runtimeEnabled;
@property (nonatomic, assign) BOOL runtimeDebugEnabled;
@property (nonatomic, copy, nullable) NSSet<NSString *> *runtimeEnabledCategories;
@property (nonatomic, assign) BOOL remoteLoggingEnabled;

+ (instancetype)sharedLogger;
- (instancetype)initWithLogFilePath:(NSString *)path defaults:(NSUserDefaults *)defaults;
- (void)beginAppSession;

- (void)applyRemoteLoggingEnabled:(BOOL)enabled;
- (BOOL)enabled;
- (void)setEnabled:(BOOL)enabled;
- (BOOL)debugEnabled;
- (void)setDebugEnabled:(BOOL)enabled;
- (NSSet<NSString *> *)knownCategories;
- (BOOL)isCategoryEnabled:(NSString *)category;
- (void)setCategory:(NSString *)category enabled:(BOOL)enabled;
- (NSString *)normalizedCategory:(NSString *)category;
- (NSString *)redactedMessage:(NSString *)message;
- (NSString *)levelName:(CALogLevel)level;
- (NSString *)section:(CALogLevel)level category:(NSString *)category;
- (void)logLevel:(CALogLevel)level category:(NSString *)category message:(NSString *)message;
- (void)rotateIfNeeded;
- (NSString *)currentLogText;
- (void)clear;

@end

NS_ASSUME_NONNULL_END
