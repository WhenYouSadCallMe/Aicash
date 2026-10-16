//
//  MTSubagentModelBadge — 子代理模型徽章（小胶囊 label，原包零细节符号）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTSubagentModelBadge : UIView

/// 徽章文本（模型 slug / 显示名）
@property (nonatomic, copy, nullable) NSString *modelSlug;

/// 徽章配色风格：default（灰）/ active（蓝）/ remote（紫）
@property (nonatomic, copy) NSString *style;

/// 依据文本的自适应宽度
+ (CGSize)sizeForSlug:(NSString *)slug;

- (instancetype)initWithSlug:(nullable NSString *)slug;

/// 点击回调（如跳转模型选择）
@property (nonatomic, copy, nullable) void (^tapHandler)(MTSubagentModelBadge *badge);

@end

NS_ASSUME_NONNULL_END
