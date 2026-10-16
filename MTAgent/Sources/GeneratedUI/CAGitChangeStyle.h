//
//  CAGitChangeStyle — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAGitChangeStyle;

@interface CAGitChangeStyle : NSObject
    - (UIColor *)color;
    - (CAGitChangeStyle *)initWithLabel:(id)arg1 symbol:(id)arg2 color:(id)arg3;
    - (NSString *)label;
    - (id)styleForChange:(id)arg1 side:(id)arg2;
    - (NSString *)symbol;

@end

NS_ASSUME_NONNULL_END
