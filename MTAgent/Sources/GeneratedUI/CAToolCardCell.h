//
//  CAToolCardCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAToolCardCell : UITableViewCell
    - (UIButton *)actionCopyButton;
    - (CAAgentCapsuleView *)capsuleView;
    - (UIButton *)collapseButton;
    - (UILabel *)commandLabel;
    - (id)compactCommand:(id)arg1;
    - (void)configureWithToolItem:(id)arg1;
    - (CAToolItem *)configuredTool;
    - (CGRect)expandedBodyRectForCollapseSnapshot;
    - (UIButton *)fullOutputButton;
    - (NSLayoutConstraint *)fullOutputHeight;
    - (NSLayoutConstraint *)fullOutputTop;
    - (void)handleCopyOutput;
    - (void)handleShowFullOutput;
    - (void)handleStop;
    - (void)handleTap;
    - (bool)hasRenderedState;
    - (UIImageView *)iconView;
    - (CAToolCardCell *)initWithFrame:(id)arg1;
    - (NSString *)lastItemID;
    - (signed __int64)lastStatus;
    - (void)loadCompleteOutput:(id)arg1;
    - (id)onShowFullOutput;
    - (id)onStop;
    - (id)onToggleExpand;
    - (UIView *)outputContainer;
    - (NSLayoutConstraint *)outputContentsBottom;
    - (NSLayoutConstraint *)outputHeightConstraint;
    - (UILabel *)outputLabel;
    - (NSLayoutConstraint *)outputTopSpacing;
    - (id)preferredLayoutAttributesFittingAttributes:(id)arg1;
    - (void)prepareForReuse;
    - (NSString *)rawOutput;
    - (NSAttributedString *)renderedOutput;
    - (NSString *)renderedOutputSource;
    - (void)setActionCopyButton:(id)arg1;
    - (void)setCapsuleView:(id)arg1;
    - (void)setCollapseButton:(id)arg1;
    - (void)setCommandLabel:(id)arg1;
    - (void)setConfiguredTool:(id)arg1;
    - (void)setFullOutputButton:(id)arg1;
    - (void)setFullOutputHeight:(id)arg1;
    - (void)setFullOutputTop:(id)arg1;
    - (void)setHasRenderedState:(id)arg1;
    - (void)setIconView:(id)arg1;
    - (void)setLastItemID:(id)arg1;
    - (void)setLastStatus:(id)arg1;
    - (void)setOnShowFullOutput:(id)arg1;
    - (void)setOnStop:(id)arg1;
    - (void)setOnToggleExpand:(id)arg1;
    - (void)setOutputContainer:(id)arg1;
    - (void)setOutputContentsBottom:(id)arg1;
    - (void)setOutputHeightConstraint:(id)arg1;
    - (void)setOutputLabel:(id)arg1;
    - (void)setOutputTopSpacing:(id)arg1;
    - (void)setRawOutput:(id)arg1;
    - (void)setRenderedOutput:(id)arg1;
    - (void)setRenderedOutputSource:(id)arg1;
    - (void)setStatusLabel:(id)arg1;
    - (void)setStopButton:(id)arg1;
    - (UILabel *)statusLabel;
    - (UIButton *)stopButton;

@end

NS_ASSUME_NONNULL_END
