//
//  CABackgroundKeepAlive.m — 后台保活实现
//
//  行为对齐原包观测：
//    · AVAudioSession CategoryPlayback + 静音 WAV 循环播放（volume=0，numberOfLoops=-1）
//    · beginBackgroundTaskWithExpirationHandler: 续期（generation 防重入 endBackgroundTask）
//    · dispatch source 脉冲：定期校验音频 + 续期后台任务
//    · AV 中断 / 媒体服务重置 / 路由变化 → 重建静音音频
//  日志分类：KEEPALIVE（原包分类表 contracts.json categories 中确有该分类）
//

#import "CACommon.h"
#import "CABackgroundKeepAlive.h"
#import "CALogger.h"

#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

const NSTimeInterval CABackgroundKeepAlivePulseInterval = 25.0;

/// 每 N 个脉冲强制校验一次静音音频是否仍在播放（原包 -verifySilentAudio 的触发点）
static const NSUInteger kCABackgroundKeepAliveVerifyEveryPulses = 4;

/// 静音 WAV 参数（8kHz / 16bit / 单声道 / 1 秒）
static const uint32_t kCASilentWAVSampleRate = 8000;
static const uint16_t kCASilentWAVChannels   = 1;
static const uint16_t kCASilentWAVBits       = 16;

#pragma mark - WAV 组装（小端序）

static void CABackgroundKeepAliveAppendTag(NSMutableData *data, const char *tag)
{
    [data appendBytes:tag length:4];
}

static void CABackgroundKeepAliveAppendUInt32(NSMutableData *data, uint32_t value)
{
    uint8_t bytes[4] = {
        (uint8_t)(value & 0xFFu),
        (uint8_t)((value >> 8) & 0xFFu),
        (uint8_t)((value >> 16) & 0xFFu),
        (uint8_t)((value >> 24) & 0xFFu)
    };
    [data appendBytes:bytes length:sizeof(bytes)];
}

static void CABackgroundKeepAliveAppendUInt16(NSMutableData *data, uint16_t value)
{
    uint8_t bytes[2] = { (uint8_t)(value & 0xFFu), (uint8_t)((value >> 8) & 0xFFu) };
    [data appendBytes:bytes length:sizeof(bytes)];
}

@interface CABackgroundKeepAlive ()

@property (nonatomic, assign, readwrite) BOOL started;
@property (nonatomic, assign, readwrite) NSUInteger pulseCount;
@property (nonatomic, assign, readwrite) BOOL observersInstalled;
@property (nonatomic, assign, readwrite) NSUInteger backgroundTask;
@property (nonatomic, assign, readwrite) NSUInteger backgroundTaskGeneration;
@property (nonatomic, strong, readwrite, nullable) AVAudioPlayer *silentPlayer;
@property (nonatomic, strong, readwrite, nullable) NSObject<OS_dispatch_source> *pulseTimer;

- (BOOL)keepAliveDisabledByPreference;

@end

@implementation CABackgroundKeepAlive

+ (instancetype)sharedKeepAlive
{
    static CABackgroundKeepAlive *keepAlive; static dispatch_once_t once;
    dispatch_once(&once, ^{ keepAlive = [CABackgroundKeepAlive new]; });
    return keepAlive;
}

+ (instancetype)sharedInstance
{
    return [self sharedKeepAlive];
}

- (instancetype)init
{
    if ((self = [super init])) {
        _started = NO;
        _pulseCount = 0;
        _backgroundTask = UIBackgroundTaskInvalid;
        _backgroundTaskGeneration = 0;
        _observersInstalled = NO;
        [self installAudioObserversIfNeeded];
        CALog(CALogLevelInfo, @"KEEPALIVE", @"background keep-alive ready");
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_pulseTimer) {
        dispatch_source_cancel(_pulseTimer);
        _pulseTimer = nil;
    }
    if (_backgroundTask != UIBackgroundTaskInvalid) {
        NSUInteger identifier = _backgroundTask;
        _backgroundTask = UIBackgroundTaskInvalid;
        [[UIApplication sharedApplication] endBackgroundTask:identifier];
    }
}

#pragma mark - 前后台

- (BOOL)keepAliveDisabledByPreference
{
    // 原包 defaults 键 CodexKeepAlive：仅当用户显式关闭时跳过保活
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:CADefaultsKeepAlive] == nil) return NO;
    return ![defaults boolForKey:CADefaultsKeepAlive];
}

- (void)start
{
    if (self.started) return;
    if ([self keepAliveDisabledByPreference]) {
        CALog(CALogLevelDebug, @"KEEPALIVE", @"background keep-alive disabled by %@", CADefaultsKeepAlive);
        return;
    }
    self.started = YES;
    [self configureAudioSession];
    [self ensureSilentPlayer];
    [self startSilentAudio];
    [self renewBackgroundTask];
    [self startPulseTimer];
}

- (void)stop
{
    if (!self.started) return;
    self.started = NO;
    [self stopPulseTimer];
    [self stopSilentAudio];
    [self endBackgroundTask];
}

- (void)applicationDidEnterBackground
{
    CALog(CALogLevelInfo, @"KEEPALIVE", @"entered background; enabling keep-alive");
    [self start];
}

- (void)applicationWillEnterForeground
{
    CALog(CALogLevelInfo, @"KEEPALIVE", @"entering foreground; releasing background keep-alive");
    [self stop];
}

#pragma mark - 后台任务

- (void)renewBackgroundTask
{
    __weak typeof(self) weakSelf = self;
    NSUInteger generation = self.backgroundTaskGeneration + 1;
    self.backgroundTaskGeneration = generation;

    NSUInteger identifier = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"CodexKeepAlive"
                                                                        expirationHandler:^{
        CABackgroundKeepAlive *strongSelf = weakSelf;
        if (!strongSelf) return;
        if (strongSelf.backgroundTaskGeneration != generation) return;   // 已被后续续期取代
        CALog(CALogLevelWarn, @"KEEPALIVE", @"background task expired generation=%lu", (unsigned long)generation);
        [strongSelf endBackgroundTask];
    }];

    self.backgroundTask = identifier;
    if (identifier != UIBackgroundTaskInvalid) {
        CALog(CALogLevelDebug, @"KEEPALIVE", @"background task renewed id=%llu remaining=%.1f",
              (unsigned long long)identifier, [[UIApplication sharedApplication] backgroundTimeRemaining]);
    }
}

- (void)endBackgroundTask
{
    if (self.backgroundTask == UIBackgroundTaskInvalid) return;
    NSUInteger identifier = self.backgroundTask;
    self.backgroundTask = UIBackgroundTaskInvalid;
    self.backgroundTaskGeneration += 1;   // 让挂起的过期回调失效
    [[UIApplication sharedApplication] endBackgroundTask:identifier];
}

#pragma mark - 脉冲

- (void)startPulseTimer
{
    if (self.pulseTimer) return;
    NSObject<OS_dispatch_source> *timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    if (!timer) return;
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(CABackgroundKeepAlivePulseInterval * NSEC_PER_SEC)),
                              (uint64_t)(CABackgroundKeepAlivePulseInterval * NSEC_PER_SEC),
                              (uint64_t)(2 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(timer, ^{
        [weakSelf pulse];
    });
    self.pulseTimer = timer;
    dispatch_resume(timer);
}

- (void)stopPulseTimer
{
    if (!self.pulseTimer) return;
    dispatch_source_cancel(self.pulseTimer);
    self.pulseTimer = nil;
}

- (void)pulse
{
    if (!self.started) return;
    self.pulseCount += 1;

    if (self.pulseCount % kCABackgroundKeepAliveVerifyEveryPulses == 0) {
        [self verifySilentAudio];
    }
    [self renewBackgroundTask];

    CALog(CALogLevelDebug, @"KEEPALIVE", @"pulse=%lu audio=%d bgTask=%llu remaining=%.1f",
          (unsigned long)self.pulseCount,
          (int)(self.silentPlayer.isPlaying ? 1 : 0),
          (unsigned long long)self.backgroundTask,
          [[UIApplication sharedApplication] backgroundTimeRemaining]);
}

#pragma mark - 静音音频

- (void)configureAudioSession
{
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    BOOL ok = [session setCategory:AVAudioSessionCategoryPlayback
                       withOptions:AVAudioSessionCategoryOptionMixWithOthers
                             error:&error];
    if (!ok) {
        CALog(CALogLevelWarn, @"KEEPALIVE", @"audio session category failed: %@", error.localizedDescription ?: @"unknown");
    }
}

- (NSData *)silentWAVData
{
    static NSData *data; static dispatch_once_t once;
    dispatch_once(&once, ^{
        const uint32_t sampleRate   = kCASilentWAVSampleRate;
        const uint16_t channels     = kCASilentWAVChannels;
        const uint16_t bitsPerSample = kCASilentWAVBits;
        const uint16_t blockAlign   = (uint16_t)(channels * bitsPerSample / 8);
        const uint32_t byteRate     = sampleRate * blockAlign;
        const uint32_t frameCount   = sampleRate;                       // 1 秒
        const uint32_t payloadBytes = frameCount * blockAlign;

        NSMutableData *wav = [NSMutableData dataWithCapacity:44 + payloadBytes];
        CABackgroundKeepAliveAppendTag(wav, "RIFF");
        CABackgroundKeepAliveAppendUInt32(wav, 36 + payloadBytes);
        CABackgroundKeepAliveAppendTag(wav, "WAVE");
        CABackgroundKeepAliveAppendTag(wav, "fmt ");
        CABackgroundKeepAliveAppendUInt32(wav, 16);
        CABackgroundKeepAliveAppendUInt16(wav, 1);                      // PCM
        CABackgroundKeepAliveAppendUInt16(wav, channels);
        CABackgroundKeepAliveAppendUInt32(wav, sampleRate);
        CABackgroundKeepAliveAppendUInt32(wav, byteRate);
        CABackgroundKeepAliveAppendUInt16(wav, blockAlign);
        CABackgroundKeepAliveAppendUInt16(wav, bitsPerSample);
        CABackgroundKeepAliveAppendTag(wav, "data");
        CABackgroundKeepAliveAppendUInt32(wav, payloadBytes);
        [wav increaseLengthBy:payloadBytes];                            // 全 0 = 静音
        data = [wav copy];
    });
    return data ?: [NSData data];
}

- (void)ensureSilentPlayer
{
    if (self.silentPlayer) return;
    NSError *error = nil;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithData:[self silentWAVData] error:&error];
    if (!player) {
        CALog(CALogLevelWarn, @"KEEPALIVE", @"silent audio player init failed: %@", error.localizedDescription ?: @"unknown");
        return;
    }
    player.numberOfLoops = -1;   // 循环
    player.volume = 0.0;         // 静音
    [player prepareToPlay];
    self.silentPlayer = player;
}

- (void)startSilentAudio
{
    NSError *error = nil;
    BOOL active = [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (!active) {
        CALog(CALogLevelWarn, @"KEEPALIVE", @"audio session activation failed: %@", error.localizedDescription ?: @"unknown");
    }
    [self ensureSilentPlayer];
    BOOL playing = [self.silentPlayer play];
    CALog(CALogLevelDebug, @"KEEPALIVE", @"silent audio play=%d active=%d", (int)(playing ? 1 : 0), (int)(active ? 1 : 0));
    if (!playing) {
        CALog(CALogLevelWarn, @"KEEPALIVE", @"silent audio inactive; recovering");
        [self verifySilentAudio];
    }
}

- (void)stopSilentAudio
{
    [self.silentPlayer stop];
    self.silentPlayer = nil;
    NSError *error = nil;
    if (![[AVAudioSession sharedInstance] setActive:NO
                                        withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                              error:&error]) {
        CALog(CALogLevelDebug, @"KEEPALIVE", @"audio session deactivate: %@", error.localizedDescription ?: @"unknown");
    }
}

- (void)verifySilentAudio
{
    if (!self.started && !self.silentPlayer) return;
    if (self.silentPlayer.isPlaying) return;
    CALog(CALogLevelWarn, @"KEEPALIVE", @"silent audio inactive; recovering");
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    [self ensureSilentPlayer];
    [self.silentPlayer play];
}

#pragma mark - 观察者

- (void)installAudioObserversIfNeeded
{
    if (self.observersInstalled) return;
    self.observersInstalled = YES;

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(audioSessionInterrupted:)
                   name:AVAudioSessionInterruptionNotification object:nil];
    [center addObserver:self selector:@selector(audioServicesWereReset:)
                   name:AVAudioSessionMediaServicesWereResetNotification object:nil];
    [center addObserver:self selector:@selector(audioRouteChanged:)
                   name:AVAudioSessionRouteChangeNotification object:nil];
    [center addObserver:self selector:@selector(applicationDidEnterBackground)
                   name:UIApplicationDidEnterBackgroundNotification object:nil];
    [center addObserver:self selector:@selector(applicationWillEnterForeground)
                   name:UIApplicationWillEnterForegroundNotification object:nil];
}

- (void)audioSessionInterrupted:(NSNotification *)notification
{
    NSNumber *type = notification.userInfo[AVAudioSessionInterruptionTypeKey];
    if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan) {
        CALog(CALogLevelDebug, @"KEEPALIVE", @"audio interruption began");
        return;
    }
    CALog(CALogLevelInfo, @"KEEPALIVE", @"audio interruption ended; recovering");
    [self startSilentAudio];
}

- (void)audioServicesWereReset:(NSNotification *)notification
{
    CALog(CALogLevelWarn, @"KEEPALIVE", @"media services reset; rebuilding silent audio");
    self.silentPlayer = nil;
    [self configureAudioSession];
    [self startSilentAudio];
}

- (void)audioRouteChanged:(NSNotification *)notification
{
    CALog(CALogLevelDebug, @"KEEPALIVE", @"audio route changed; recovering player");
    [self verifySilentAudio];
}

@end
