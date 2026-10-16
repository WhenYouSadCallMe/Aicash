//
//  CAContextUsageViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAContextUsageViewController : UIViewController
    - (UILabel *)cacheHint;
    - (UIProgressView *)cacheProgress;
    - (UILabel *)cacheTokens;
    - (UILabel *)cacheValue;
    - (NSMutableArray *)cards;
    - (void)closeSheet;
    - (UILabel *)contextHint;
    - (UIProgressView *)contextProgress;
    - (UILabel *)contextTokens;
    - (UILabel *)contextValue;
    - (CACodexEngine *)engine;
    - (id)labelWithSize:(id)arg1 weight:(id)arg2 secondary:(id)arg3;
    - (id)metricCardWithTitle:(id)arg1 value:(id)arg2 tokens:(id)arg3 hint:(id)arg4 progress:(id)arg5;
    - (UILabel *)modelLabel;
    - (id)progressView;
    - (void)refreshUsage;
    - (void)setCacheHint:(id)arg1;
    - (void)setCacheProgress:(id)arg1;
    - (void)setCacheTokens:(id)arg1;
    - (void)setCacheValue:(id)arg1;
    - (void)setCards:(id)arg1;
    - (void)setContextHint:(id)arg1;
    - (void)setContextProgress:(id)arg1;
    - (void)setContextTokens:(id)arg1;
    - (void)setContextValue:(id)arg1;
    - (void)setEngine:(id)arg1;
    - (void)setModelLabel:(id)arg1;
    - (id)tokenString:(id)arg1;
    - (void)traitCollectionDidChange:(id)arg1;
    - (void)viewDidLoad;

@end

NS_ASSUME_NONNULL_END
