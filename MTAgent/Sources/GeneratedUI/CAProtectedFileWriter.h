//
//  CAProtectedFileWriter — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAProtectedFileWriter : NSObject
    - (id)queue;
    - (void)removeFileAtPath:(id)arg1 completion:(id)arg2;
    - (bool)runRootHelperArguments:(id)arg1 error:(id)arg2;
    - (void)writeText:(id)arg1 toPath:(id)arg2 backup:(id)arg3 completion:(id)arg4;
    - (bool)writeTextNow:(id)arg1 toPath:(id)arg2 error:(id)arg3;

@end

NS_ASSUME_NONNULL_END
