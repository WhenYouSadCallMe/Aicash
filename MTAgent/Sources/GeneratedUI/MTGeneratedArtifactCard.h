//
//  MTGeneratedArtifactCard — 生成产物卡片视图（文件名 + 大小 + 打开按钮）
//  原包零细节符号，按用途实现合理功能。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTGeneratedArtifactCard : UIView

@property (nonatomic, copy, nullable) NSString *artifactName;
@property (nonatomic, copy, nullable) NSString *artifactPath;
@property (nonatomic, copy, nullable) void (^openHandler)(MTGeneratedArtifactCard *card);

/// 固定高度（单行卡片）
+ (CGFloat)preferredHeight;

- (instancetype)initWithArtifactPath:(nullable NSString *)path;

/// 按文件系统状态刷新（存在→可打开；缺失→置灰）
- (void)reload;

/// 人类可读大小（如 1.2 MB；文件缺失显示 —）
- (NSString *)sizeText;

@end

NS_ASSUME_NONNULL_END
