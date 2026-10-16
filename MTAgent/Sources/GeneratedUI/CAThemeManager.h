//
//  CAThemeManager — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class UIWindow;

@interface CAThemeManager : NSObject
    - (id)accentColor;
    - (void)applyToWindow:(id)arg1;
    - (id)backgroundColor;
    - (id)chatBackgroundColor;
    - (id)controlBorderColor;
    - (id)controlFillColor;
    - (signed long long)mode;
    - (id)neutralLight:(id)arg1 dark:(id)arg2;
    - (id)primaryTextColor;
    - (id)raisedSurfaceColor;
    - (id)secondaryTextColor;
    - (id)sendButtonColor;
    - (id)sendSymbolColor;
    - (id)separatorColor;
    - (void)setMode:(id)arg1;
    - (void)setWindow:(id)arg1;
    - (id)sharedManager;
    - (id)surfaceColor;
    - (id)userMessageColor;
    - (UIWindow *)window;

@end

NS_ASSUME_NONNULL_END
