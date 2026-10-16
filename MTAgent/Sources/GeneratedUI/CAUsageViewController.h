//
//  CAUsageViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CACodexEngine;
@class CAConversationRecord;
@class UIActivityIndicatorView;

@interface CAUsageViewController : UIViewController
    - (void)addEquivalentUsageCostCard;
    - (void)addWindowCard:(id)arg1 fallback:(id)arg2;
    - (void)applyTheme;
    - (void)applyThemeToView:(id)arg1;
    - (void)buildLayout;
    - (id)buttonWithSymbol:(id)arg1 label:(id)arg2 action:(id)arg3;
    - (UIButton *)closeButton;
    - (void)closePage;
    - (CACodexEngine *)engine;
    - (id)friendlyWindowName:(id)arg1 fallback:(id)arg2;
    - (UIView *)header;
    - (id)labelWithSize:(id)arg1 weight:(id)arg2 secondary:(id)arg3;
    - (UILabel *)planLabel;
    - (unsigned long long)quotaRefreshGeneration;
    - (CAConversationRecord *)record;
    - (UIButton *)refreshButton;
    - (void)refreshQuota;
    - (bool)refreshing;
    - (void)reloadSnapshot;
    - (id)resetTextForWindow:(id)arg1;
    - (void)setCloseButton:(id)arg1;
    - (void)setEngine:(id)arg1;
    - (void)setHeader:(id)arg1;
    - (void)setPlanLabel:(id)arg1;
    - (void)setQuotaRefreshGeneration:(id)arg1;
    - (void)setRecord:(id)arg1;
    - (void)setRefreshButton:(id)arg1;
    - (void)setRefreshing:(id)arg1;
    - (void)setSpinner:(id)arg1;
    - (void)setStackView:(id)arg1;
    - (void)setStatusLabel:(id)arg1;
    - (void)setTitleLabel:(id)arg1;
    - (UIActivityIndicatorView *)spinner;
    - (UIStackView *)stackView;
    - (UILabel *)statusLabel;
    - (void)themeDidChange;
    - (UILabel *)titleLabel;
    - (id)usageTokenString:(id)arg1;
    - (void)viewDidLoad;

@end

NS_ASSUME_NONNULL_END
