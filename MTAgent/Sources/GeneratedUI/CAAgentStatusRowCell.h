//
//  CAAgentStatusRowCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAAgentProgressRingView;
@class CAAgentStatusRowCell;

@interface CAAgentStatusRowCell : UITableViewCell
    - (void)configureWithSnapshot:(id)arg1 mainRunning:(id)arg2;
    - (UILabel *)detailLabelView;
    - (CAAgentStatusRowCell *)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2;
    - (void)prepareForReuse;
    - (CAAgentProgressRingView *)progressRing;
    - (void)setDetailLabelView:(id)arg1;
    - (void)setProgressRing:(id)arg1;
    - (void)setTitleLabelView:(id)arg1;
    - (id)statusText:(id)arg1;
    - (UILabel *)titleLabelView;

@end

NS_ASSUME_NONNULL_END
