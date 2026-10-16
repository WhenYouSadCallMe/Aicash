//
//  CABackgroundKeepAlive.h — 后台保活（静音音频 + 后台任务续期 + 脉冲）
//
//  原包符号对齐（SPEC/assets/objc_api_map.json → "CABackgroundKeepAlive"）：
//    +sharedInstance / -start / -stop / -renewBackgroundTask / -endBackgroundTask
//    -startPulseTimer / -stopPulseTimer / -pulse / -configureAudioSession / -ensureSilentPlayer
//    -startSilentAudio / -stopSilentAudio / -silentWAVData / -verifySilentAudio
//    -installAudioObserversIfNeeded / -audioSessionInterrupted: / -audioServicesWereReset: / -audioRouteChanged:
//    -applicationDidEnterBackground / -applicationWillEnterForeground / -dealloc
//  原包 ivar：_backgroundTask _backgroundTaskGeneration _observersInstalled _pulseCount _pulseTimer _silentPlayer _started
//  原包日志文案（SPEC/assets/strings_full.txt @0x583dbe…@0x584019，分类 KEEPALIVE）：
//    background keep-alive ready / entered background; enabling keep-alive /
//    entering foreground; releasing background keep-alive / audio session category failed: %@ /
//    silent audio player init failed: %@ / audio session activation failed: %@ / silent audio play=%d active=%d /
//    audio session deactivate: %@ / silent audio inactive; recovering / audio interruption ended; recovering /
//    media services reset; rebuilding silent audio / audio route changed; recovering player /
//    CodexKeepAlive / background task expired generation=%lu / background task renewed id=%llu remaining=%.1f /
//    pulse=%lu audio=%d bgTask=%llu remaining=%.1f
//

#import <Foundation/Foundation.h>

@class AVAudioPlayer;

NS_ASSUME_NONNULL_BEGIN

/// 脉冲间隔（原包：音轨持续循环 + 周期性 renewBackgroundTask；此处 25s，早于后台任务过期）
extern const NSTimeInterval CABackgroundKeepAlivePulseInterval;

@interface CABackgroundKeepAlive : NSObject

@property (nonatomic, assign, readonly) BOOL started;                          // _started
@property (nonatomic, assign, readonly) NSUInteger pulseCount;                 // _pulseCount
@property (nonatomic, assign, readonly) BOOL observersInstalled;               // _observersInstalled
@property (nonatomic, assign, readonly) NSUInteger backgroundTask;             // _backgroundTask（UIBackgroundTaskIdentifier）
@property (nonatomic, assign, readonly) NSUInteger backgroundTaskGeneration;   // _backgroundTaskGeneration
@property (nonatomic, strong, readonly, nullable) AVAudioPlayer *silentPlayer; // _silentPlayer
@property (nonatomic, strong, readonly, nullable) NSObject<OS_dispatch_source> *pulseTimer; // _pulseTimer

+ (instancetype)sharedKeepAlive;
+ (instancetype)sharedInstance;   // 原包名，等价入口

#pragma mark - 生命周期

- (void)start;
- (void)stop;

#pragma mark - 后台任务

- (void)renewBackgroundTask;
- (void)endBackgroundTask;

#pragma mark - 脉冲

- (void)startPulseTimer;
- (void)stopPulseTimer;
- (void)pulse;

#pragma mark - 静音音频

- (void)configureAudioSession;
- (void)ensureSilentPlayer;
- (void)startSilentAudio;
- (void)stopSilentAudio;
- (void)verifySilentAudio;
- (NSData *)silentWAVData;

#pragma mark - 观察者 / 通知入口

- (void)installAudioObserversIfNeeded;
- (void)applicationDidEnterBackground;
- (void)applicationWillEnterForeground;
- (void)audioSessionInterrupted:(NSNotification *)notification;
- (void)audioServicesWereReset:(NSNotification *)notification;
- (void)audioRouteChanged:(NSNotification *)notification;

@end

NS_ASSUME_NONNULL_END
