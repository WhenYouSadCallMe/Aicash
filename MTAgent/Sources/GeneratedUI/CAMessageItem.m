//
//  CAMessageItem — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//
//  聊天主流程实装：本类作为会话页的消息模型（文本 / 思考卡片 / 工具卡片 / 提示），
//  由 CAChatViewController 创建，交给 CAMessageCell / CAThinkingCell / CAToolCardCell 渲染。
//  注意：头文件里 setter 的形参统一是 id（自动生成占位），因此标量字段一律走
//  「ivar + 与头文件逐字一致的访问器」，外部写入用装箱（[item setStreaming:@YES]）。
//

#import "CAMessageItem.h"
#import "CAToolItem.h"

@interface CAMessageItem () {
    long long _role;
    bool _streaming;
    long long _activityKind;
    bool _activityRunning;
    double _activityDuration;
    bool _activityExpanded;
    unsigned long long _activityDetailBytes;
    bool _activityDetailPersistencePending;
    bool _activityModelRequested;
    bool _queued;
}

@property (nonatomic, copy) NSString *messageId;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, copy) NSString *tokenUsage;
@property (nonatomic, strong) CAToolItem *toolItem;
@property (nonatomic, strong) NSArray *displayAttachments;
@property (nonatomic, strong) NSArray *generatedArtifacts;
@property (nonatomic, strong) id parsedBlocksCache;
@property (nonatomic, strong) NSArray *queuedAttachments;
@property (nonatomic, copy) NSString *queuedComposerText;
@property (nonatomic, copy) NSString *queuedPromptText;
@property (nonatomic, copy) NSString *activityTitle;
@property (nonatomic, copy) NSString *activityDetail;
@property (nonatomic, strong) NSDate *activityStartedAt;
@property (nonatomic, copy) NSString *activityDetailFile;
@property (nonatomic, strong) id activityDetailRenderCache;
@property (nonatomic, copy) NSString *activityModelName;
@property (nonatomic, copy) NSString *activityReasoningEffort;
@end

@implementation CAMessageItem

- (instancetype)init
{
    if ((self = [super init])) {
        _messageId = [[NSUUID UUID] UUIDString].lowercaseString;
        _text = @"";
        _timestamp = [NSDate date];
        _activityStartedAt = [NSDate date];
        _displayAttachments = @[];
        _generatedArtifacts = @[];
        _queuedAttachments = @[];
        _role = CAMessageRoleAssistant;
    }
    return self;
}

#pragma mark - 标量访问器（与头文件签名逐字一致：setter 形参为 id）

- (signed long long)role { return _role; }

- (void)setRole:(id)arg1
{
    _role = [arg1 respondsToSelector:@selector(longLongValue)] ? [arg1 longLongValue] : CAMessageRoleAssistant;
}

- (bool)streaming { return _streaming; }

- (void)setStreaming:(id)arg1
{
    _streaming = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

- (signed long long)activityKind { return _activityKind; }

- (void)setActivityKind:(id)arg1
{
    _activityKind = [arg1 respondsToSelector:@selector(longLongValue)] ? [arg1 longLongValue] : CAMessageActivityKindNone;
}

- (bool)activityRunning { return _activityRunning; }

- (void)setActivityRunning:(id)arg1
{
    _activityRunning = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

- (double)activityDuration { return _activityDuration; }

- (void)setActivityDuration:(id)arg1
{
    _activityDuration = [arg1 respondsToSelector:@selector(doubleValue)] ? [arg1 doubleValue] : 0;
}

- (bool)activityExpanded { return _activityExpanded; }

- (void)setActivityExpanded:(id)arg1
{
    _activityExpanded = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

- (unsigned long long)activityDetailBytes { return _activityDetailBytes; }

- (void)setActivityDetailBytes:(id)arg1
{
    _activityDetailBytes = [arg1 respondsToSelector:@selector(unsignedLongLongValue)] ? [arg1 unsignedLongLongValue] : 0;
}

- (bool)activityDetailPersistencePending { return _activityDetailPersistencePending; }

- (void)setActivityDetailPersistencePending:(id)arg1
{
    _activityDetailPersistencePending = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

- (bool)activityModelRequested { return _activityModelRequested; }

- (void)setActivityModelRequested:(id)arg1
{
    _activityModelRequested = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

- (bool)queued { return _queued; }

- (void)setQueued:(id)arg1
{
    _queued = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

#pragma mark - 工厂（原包同名选择器：实例方法形式）

- (id)userMessageWithText:(id)arg1
{
    CAMessageItem *item = [CAMessageItem new];
    item.role = @(CAMessageRoleUser);
    item.text = [arg1 isKindOfClass:NSString.class] ? arg1 : (arg1 ? [arg1 description] : @"");
    item.timestamp = [NSDate date];
    return item;
}

- (id)assistantMessageWithText:(id)arg1
{
    CAMessageItem *item = [CAMessageItem new];
    item.role = @(CAMessageRoleAssistant);
    item.text = [arg1 isKindOfClass:NSString.class] ? arg1 : (arg1 ? [arg1 description] : @"");
    item.timestamp = [NSDate date];
    return item;
}

- (id)activityMessageWithKind:(id)arg1 title:(id)arg2 detail:(id)arg3 running:(id)arg4
{
    CAMessageItem *item = [CAMessageItem new];
    item.role = @(CAMessageRoleAssistant);
    long long kind = [arg1 respondsToSelector:@selector(longLongValue)] ? [arg1 longLongValue] : CAMessageActivityKindThinking;
    item.activityKind = @(kind);
    item.activityTitle = [arg2 isKindOfClass:NSString.class] ? arg2 : @"";
    item.activityDetail = [arg3 isKindOfClass:NSString.class] ? arg3 : @"";
    item.activityRunning = @([arg4 respondsToSelector:@selector(boolValue)] ? [arg4 boolValue] : NO);
    item.activityStartedAt = [NSDate date];
    return item;
}

- (id)toolMessageWithItem:(id)arg1
{
    CAMessageItem *item = [CAMessageItem new];
    item.role = @(CAMessageRoleAssistant);
    item.activityKind = @(CAMessageActivityKindTool);
    item.activityTitle = @"工具调用";
    if ([arg1 isKindOfClass:CAToolItem.class]) {
        CAToolItem *tool = arg1;
        item.toolItem = tool;
        item.activityDetail = tool.command ?: @"";
    }
    item.activityRunning = @YES;
    item.activityStartedAt = [NSDate date];
    return item;
}

#pragma mark - 聊天主流程便捷写入（新选择器；标量字段装箱写入的语义封装）

- (void)setStreamingFlag:(BOOL)streaming
{
    [self setStreaming:@(streaming)];
}

- (void)setActivityOfKind:(CAMessageActivityKind)kind
                    title:(nullable NSString *)title
                   detail:(nullable NSString *)detail
                  running:(BOOL)running
{
    [self setActivityKind:@((long long)kind)];
    self.activityTitle = title ?: @"";
    self.activityDetail = detail ?: @"";
    [self setActivityRunning:@(running)];
}

- (void)toggleActivityExpanded
{
    [self setActivityExpanded:@(!_activityExpanded)];
}

- (void)appendText:(nullable NSString *)delta
{
    NSString *chunk = delta ?: @"";
    if (chunk.length == 0) return;
    self.text = [(self.text ?: @"") stringByAppendingString:chunk];
}

- (BOOL)isNoticeMessage
{
    return _activityKind == CAMessageActivityKindNotice;
}

@end
