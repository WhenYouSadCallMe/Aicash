//
//  CARootViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CARootViewController : UIViewController
    - (id)childViewControllerForHomeIndicatorAutoHidden;
    - (id)childViewControllerForStatusBarHidden;
    - (id)childViewControllerForStatusBarStyle;
    - (UIViewController *)contentViewController;
    - (CARootViewController *)initWithContentViewController:(id)arg1;
    - (void)setContentViewController:(id)arg1;
    - (bool)shouldAutorotate;
    - (unsigned __int64)supportedInterfaceOrientations;
    - (void)viewDidLoad;

@end

NS_ASSUME_NONNULL_END
