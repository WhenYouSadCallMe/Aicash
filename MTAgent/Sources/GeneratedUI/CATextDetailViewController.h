//
//  CATextDetailViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CATextDetailViewController : UIViewController
    - (void)close;
    - (void)handleCopyText;
    - (void)handleShareText;
    - (id)initForTextSelection:(id)arg1;
    - (CATextDetailViewController *)initWithTitle:(id)arg1 text:(id)arg2;
    - (void)setShareItem:(id)arg1;
    - (void)setText:(id)arg1;
    - (void)setTextSelectionMode:(id)arg1;
    - (void)setTextView:(id)arg1;
    - (UIBarButtonItem *)shareItem;
    - (NSString *)text;
    - (bool)textSelectionMode;
    - (UITextView *)textView;
    - (void)themeDidChange;
    - (void)viewDidLoad;

@end

NS_ASSUME_NONNULL_END
