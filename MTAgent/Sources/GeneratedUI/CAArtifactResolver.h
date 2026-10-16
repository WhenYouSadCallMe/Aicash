//
//  CAArtifactResolver — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAArtifactResolver : NSObject
    - (id)descriptorsForPaths:(id)arg1 text:(id)arg2 workspace:(id)arg3 conversation:(id)arg4 message:(id)arg5;
    - (id)generatedRoot;
    - (id)kindForPath:(id)arg1;
    - (id)safeDirectoryForConversation:(id)arg1;
    - (id)storeImageData:(id)arg1 conversation:(id)arg2;
    - (id)validatedFilePath:(id)arg1 workspace:(id)arg2;
    - (id)validatedPath:(id)arg1 workspace:(id)arg2;

@end

NS_ASSUME_NONNULL_END
