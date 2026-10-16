//
//  CAToolItem — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString;

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

@end

NS_ASSUME_NONNULL_END
