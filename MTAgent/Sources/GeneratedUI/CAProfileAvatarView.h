//
//  CAProfileAvatarView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAProfileAvatarView;
@class NSURLSessionDataTask;

@interface CAProfileAvatarView : UIView
    - (NSString *)identity;
    - (id)imageCache;
    - (NSURLSessionDataTask *)imageTask;
    - (NSString *)imageURL;
    - (UIImageView *)imageView;
    - (CAProfileAvatarView *)initWithFrame:(id)arg1;
    - (UILabel *)initialLabel;
    - (void)layoutSubviews;
    - (NSString *)requestID;
    - (void)setIdentity:(id)arg1;
    - (void)setImageTask:(id)arg1;
    - (void)setImageURL:(id)arg1;
    - (void)setImageView:(id)arg1;
    - (void)setInitialLabel:(id)arg1;
    - (void)setRequestID:(id)arg1;
    - (void)showProfileName:(id)arg1 email:(id)arg2 identity:(id)arg3 imageURL:(id)arg4;
    - (void)showSymbol:(id)arg1;

@end

NS_ASSUME_NONNULL_END
