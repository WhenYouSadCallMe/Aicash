//
//  CACodeBlockView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CACodeBlockView;

@interface CACodeBlockView : UIView
    - (UIButton *)actionCopyButton;
    - (UILabel *)codeLabel;
    - (NSString *)codeText;
    - (void)configureWithCode:(id)arg1 language:(id)arg2;
    - (void)handleCopy;
    - (UIView *)headerView;
    - (id)initWithFrame:(id)arg1;
    - (UILabel *)langLabel;
    - (NSString *)language;
    - (void)setActionCopyButton:(id)arg1;
    - (void)setCodeLabel:(id)arg1;
    - (void)setCodeText:(id)arg1;
    - (void)setHeaderView:(id)arg1;
    - (void)setLangLabel:(id)arg1;
    - (void)setLanguage:(id)arg1;

@end

NS_ASSUME_NONNULL_END
