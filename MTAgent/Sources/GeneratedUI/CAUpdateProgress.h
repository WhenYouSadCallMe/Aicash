//
//  CAUpdateProgress — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAUpdateProgress : NSObject
    - (signed __int64)completedBytes;
    - (double)fraction;
    - (void)setCompletedBytes:(id)arg1;
    - (void)setFraction:(id)arg1;
    - (void)setStage:(id)arg1;
    - (void)setStatus:(id)arg1;
    - (void)setTotalBytes:(id)arg1;
    - (signed __int64)stage;
    - (NSString *)status;
    - (signed __int64)totalBytes;

@end

NS_ASSUME_NONNULL_END
