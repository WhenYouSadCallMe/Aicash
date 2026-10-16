//
//  CAToolItem — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString;

// ==CHAT-KIT-BEGIN== 聊天主流程共享定义：工具调用状态（原包 _status 取值）
typedef NS_ENUM(NSInteger, CAToolStatus) {
    CAToolStatusRunning   = 0,
    CAToolStatusSucceeded = 1,
    CAToolStatusFailed    = 2,
};
// ==CHAT-KIT-END==

@interface CAToolItem : NSObject
    - (NSString *)command;
    - (signed long long)exitCode;
    - (bool)isExpanded;
    - (NSString *)itemId;
    - (NSString *)output;
    - (unsigned long long)outputBytes;
    - (NSString *)outputFile;
    - (bool)outputPersistencePending;
    - (void)setCommand:(id)arg1;
    - (void)setExitCode:(id)arg1;
    - (void)setIsExpanded:(id)arg1;
    - (void)setItemId:(id)arg1;
    - (void)setOutput:(id)arg1;
    - (void)setOutputBytes:(id)arg1;
    - (void)setOutputFile:(id)arg1;
    - (void)setOutputPersistencePending:(id)arg1;
    - (void)setStatus:(id)arg1;
    - (signed long long)status;

// ==CHAT-KIT-API-BEGIN== 聊天主流程便捷写入（不动上面 parity 选择器的占位签名）
- (void)chatSetStatus:(CAToolStatus)status exitCode:(NSInteger)exitCode;
- (void)chatAppendOutput:(nullable NSString *)chunk;
- (BOOL)isRunningTool;
// ==CHAT-KIT-API-END==

@end

NS_ASSUME_NONNULL_END
