//
//  CAProcess.h — iOS 可用的进程派生封装（NSTask 在 iOS SDK 不可用）
//  设计目标：与 NSTask 的使用面保持同名同形，便于把调用点从 NSTask 直接替换为 CAProcess：
//    executableURL / arguments / environment / currentDirectoryURL /
//    standardInput / standardOutput / standardError（接受 NSPipe）/ terminationHandler /
//    launchAndReturnError: / waitUntilExit / terminate / processIdentifier / terminationStatus / isRunning
//  实现：posix_spawn + dup2 + 后台 waitpid（原包同款路径：forkless-posix_spawn）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAProcess : NSObject

@property (nonatomic, copy, nullable) NSURL *executableURL;
@property (nonatomic, copy, nullable) NSArray<NSString *> *arguments;
@property (nonatomic, copy, nullable) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, copy, nullable) NSURL *currentDirectoryURL;

@property (nonatomic, strong, nullable) id standardInput;    // NSPipe
@property (nonatomic, strong, nullable) id standardOutput;   // NSPipe
@property (nonatomic, strong, nullable) id standardError;    // NSPipe

@property (nonatomic, copy, nullable) void (^terminationHandler)(CAProcess *task);

@property (nonatomic, readonly) pid_t processIdentifier;
@property (nonatomic, readonly) int terminationStatus;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) BOOL isLaunched;

- (BOOL)launchAndReturnError:(NSError **)error;
- (void)waitUntilExit;
- (void)terminate;
- (void)interrupt;
- (int)waitUntilExitWithTimeout:(NSTimeInterval)timeout;

@end

NS_ASSUME_NONNULL_END
