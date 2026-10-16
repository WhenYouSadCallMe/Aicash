//
//  CAAccountProfile — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAAccountProfile : NSObject
    - (NSString *)accountType;
    - (bool)authenticated;
    - (NSString *)displayName;
    - (NSString *)email;
    - (NSString *)imageURL;
    - (NSString *)planType;
    - (bool)readSucceeded;
    - (void)setAccountType:(id)arg1;
    - (void)setAuthenticated:(id)arg1;
    - (void)setDisplayName:(id)arg1;
    - (void)setEmail:(id)arg1;
    - (void)setImageURL:(id)arg1;
    - (void)setPlanType:(id)arg1;
    - (void)setReadSucceeded:(id)arg1;
    - (void)setUserId:(id)arg1;
    - (NSString *)userId;

@end

NS_ASSUME_NONNULL_END
