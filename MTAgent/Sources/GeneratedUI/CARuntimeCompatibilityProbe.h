//
//  CARuntimeCompatibilityProbe — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CARuntimeCompatibilityProbe : NSObject
    - (id)formattedReport:(id)arg1;
    - (id)reportSections:(id)arg1;
    - (void)runExecutable:(id)arg1 arguments:(id)arg2 cwd:(id)arg3 environment:(id)arg4 timeout:(id)arg5 completion:(id)arg6;
    - (void)runWithCompletion:(id)arg1;
    - (id)shellValuesFromOutput:(id)arg1;

@end

NS_ASSUME_NONNULL_END
