//
//  CAActivityCardCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAActivityCardCell : UITableViewCell
    - (UIButton *)actionCopyButton;
    - (CAAgentCapsuleView *)capsuleView;
    - (UIButton *)collapseButton;
    - (void)configure:(id)arg1;
    - (CAMessageItem *)configuredMessage;
    - (UIView *)detailContainer;
    - (NSLayoutConstraint *)detailContainerHeight;
    - (NSLayoutConstraint *)detailContentsBottom;
    - (UILabel *)detailLabel;
    - (NSLayoutConstraint *)detailTopSpacing;
    - (void)didMoveToWindow;
    - (UILabel *)durationLabel;
    - (id)durationTextForMessage:(id)arg1;
    - (NSTimer *)durationTimer;
    - (UILabel *)effortBadge;
    - (CGRect)expandedBodyRectForCollapseSnapshot;
    - (UIButton *)fullDetailButton;
    - (NSLayoutConstraint *)fullDetailHeight;
    - (NSLayoutConstraint *)fullDetailTop;
    - (void)handleCopyDetail;
    - (void)handleStop;
    - (bool)hasRenderedState;
    - (UIImageView *)iconView;
    - (CAActivityCardCell *)initWithFrame:(id)arg1;
    - (bool)lastRunningState;
    - (NSString *)lastStateTitle;
    - (void)loadCompleteDetail:(id)arg1;
    - (void)logVisibleState:(id)arg1;
    - (unsigned __int64)measuredRevision;
    - (CGSize)measuredSize;
    - (NSLayoutConstraint *)metadataHeight;
    - (UIStackView *)metadataStack;
    - (NSLayoutConstraint *)metadataTop;
    - (UILabel *)modelBadge;
    - (id)onDetailLayoutChange;
    - (id)onShowFullDetail;
    - (id)onStop;
    - (id)onToggle;
    - (id)preferredLayoutAttributesFittingAttributes:(id)arg1;
    - (void)prepareForReuse;
    - (void)prewarmDetailForMessage:(id)arg1 completion:(id)arg2;
    - (void)refreshDuration;
    - (unsigned __int64)renderRevision;
    - (NSDictionary *)renderSignature;
    - (NSAttributedString *)renderedDetail;
    - (id)renderedDetailForText:(id)arg1 kind:(id)arg2 baseColor:(id)arg3;
    - (NSString *)renderedDetailSource;
    - (NSString *)representedMessageID;
    - (void)setActionCopyButton:(id)arg1;
    - (void)setCapsuleView:(id)arg1;
    - (void)setCollapseButton:(id)arg1;
    - (void)setConfiguredMessage:(id)arg1;
    - (void)setDetailContainer:(id)arg1;
    - (void)setDetailContainerHeight:(id)arg1;
    - (void)setDetailContentsBottom:(id)arg1;
    - (void)setDetailLabel:(id)arg1;
    - (void)setDetailTopSpacing:(id)arg1;
    - (void)setDurationLabel:(id)arg1;
    - (void)setDurationTimer:(id)arg1;
    - (void)setEffortBadge:(id)arg1;
    - (void)setFullDetailButton:(id)arg1;
    - (void)setFullDetailHeight:(id)arg1;
    - (void)setFullDetailTop:(id)arg1;
    - (void)setHasRenderedState:(id)arg1;
    - (void)setIconView:(id)arg1;
    - (void)setLastRunningState:(id)arg1;
    - (void)setLastStateTitle:(id)arg1;
    - (void)setMeasuredRevision:(id)arg1;
    - (void)setMeasuredSize:(id)arg1;
    - (void)setMetadataHeight:(id)arg1;
    - (void)setMetadataStack:(id)arg1;
    - (void)setMetadataTop:(id)arg1;
    - (void)setModelBadge:(id)arg1;
    - (void)setOnDetailLayoutChange:(id)arg1;
    - (void)setOnShowFullDetail:(id)arg1;
    - (void)setOnStop:(id)arg1;
    - (void)setOnToggle:(id)arg1;
    - (void)setRenderRevision:(id)arg1;
    - (void)setRenderSignature:(id)arg1;
    - (void)setRenderedDetail:(id)arg1;
    - (void)setRenderedDetailSource:(id)arg1;
    - (void)setStopButton:(id)arg1;
    - (void)setTitleLabel:(id)arg1;
    - (void)showFullDetail;
    - (UIButton *)stopButton;
    - (void)synchronizeStateTimer;
    - (void)tapped;
    - (UILabel *)titleLabel;

@end

NS_ASSUME_NONNULL_END
