//
//  CAToolItem — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//
//  聊天主流程实装：一条工具调用的状态（命令 / 状态 / 输出 / 退出码），
//  由 CAChatViewController 在解析 codex 事件时写入，交给 CAToolCardCell 渲染。
//  标量字段走「ivar + 与头文件逐字一致的访问器」，外部写入用装箱或 chat* 便捷方法。
//

#import "CAToolItem.h"

@interface CAToolItem () {
    long long _status;
    long long _exitCode;
    unsigned long long _outputBytes;
    bool _outputPersistencePending;
    bool _isExpanded;
}

@property (nonatomic, copy) NSString *itemId;
@property (nonatomic, copy) NSString *command;
@property (nonatomic, copy) NSString *output;
@property (nonatomic, copy) NSString *outputFile;
@end

@implementation CAToolItem

- (instancetype)init
{
    if ((self = [super init])) {
        _itemId = [[NSUUID UUID] UUIDString].lowercaseString;
        _command = @"";
        _output = @"";
        _status = CAToolStatusRunning;
        _exitCode = 0;
    }
    return self;
}

#pragma mark - 标量访问器（setter 形参与头文件一致：id）

- (signed long long)status { return _status; }

- (void)setStatus:(id)arg1
{
    _status = [arg1 respondsToSelector:@selector(longLongValue)] ? [arg1 longLongValue] : CAToolStatusRunning;
}

- (signed long long)exitCode { return _exitCode; }

- (void)setExitCode:(id)arg1
{
    _exitCode = [arg1 respondsToSelector:@selector(longLongValue)] ? [arg1 longLongValue] : 0;
}

- (unsigned long long)outputBytes { return _outputBytes; }

- (void)setOutputBytes:(id)arg1
{
    _outputBytes = [arg1 respondsToSelector:@selector(unsignedLongLongValue)] ? [arg1 unsignedLongLongValue] : 0;
}

- (bool)outputPersistencePending { return _outputPersistencePending; }

- (void)setOutputPersistencePending:(id)arg1
{
    _outputPersistencePending = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

- (bool)isExpanded { return _isExpanded; }

- (void)setIsExpanded:(id)arg1
{
    _isExpanded = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

#pragma mark - 对象字段（写回时同步字节数）

- (void)setOutput:(id)arg1
{
    NSString *text = [arg1 isKindOfClass:NSString.class] ? arg1 : (arg1 ? [arg1 description] : @"");
    _output = [text copy];
    _outputBytes = (unsigned long long)text.length;
}

- (void)setCommand:(id)arg1
{
    NSString *text = [arg1 isKindOfClass:NSString.class] ? arg1 : (arg1 ? [arg1 description] : @"");
    _command = [text copy];
}

- (void)setItemId:(id)arg1
{
    if ([arg1 isKindOfClass:NSString.class] && [arg1 length] > 0) _itemId = [arg1 copy];
}

- (void)setOutputFile:(id)arg1
{
    _outputFile = [arg1 isKindOfClass:NSString.class] ? [arg1 copy] : nil;
}

#pragma mark - 聊天主流程便捷写入

- (void)chatSetStatus:(CAToolStatus)status exitCode:(NSInteger)exitCode
{
    _status = (long long)status;
    _exitCode = (long long)exitCode;
}

- (void)chatAppendOutput:(NSString *)chunk
{
    if (chunk.length == 0) return;
    NSString *current = _output ?: @"";
    _output = [current stringByAppendingString:chunk];
    _outputBytes = (unsigned long long)_output.length;
}

- (BOOL)isRunningTool
{
    return _status == CAToolStatusRunning;
}

@end
