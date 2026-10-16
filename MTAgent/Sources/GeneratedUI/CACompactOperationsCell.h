//
//  CACompactOperationsCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CACompactOperationsCell;

@interface CACompactOperationsCell : UITableViewCell
    - (void)applyRunningAnimationToRow:(id)arg1 message:(id)arg2;
    - (UIImageView *)chevronView;
    - (NSLayoutConstraint *)collapsedBottom;
    - (void)configureWithMessages:(id)arg1 expanded:(id)arg2;
    - (UIView *)container;
    - (id)detailForMessage:(id)arg1;
    - (void)didMoveToWindow;
    - (id)durationText;
    - (NSTimer *)durationTimer;
    - (void)durationTimerFired:(id)arg1;
    - (bool)expanded;
    - (NSLayoutConstraint *)expandedBottom;
    - (id)firstLine:(id)arg1;
    - (double)groupDuration;
    - (bool)hasRunningOperations;
    - (UIButton *)headerButton;
    - (UIImageView *)headerIcon;
    - (id)imageForMessage:(id)arg1;
    - (id)initWithFrame:(id)arg1;
    - (bool)isFailed:(id)arg1;
    - (bool)isRunning:(id)arg1;
    - (double)maximumRowsViewportHeight;
    - (NSArray *)messages;
    - (id)onOpenMessage;
    - (id)onStop;
    - (id)onToggle;
    - (void)openRow:(id)arg1;
    - (id)preferredLayoutAttributesFittingAttributes:(id)arg1;
    - (void)prepareForReuse;
    - (void)rebuildRows;
    - (void)refreshDurationTitle;
    - (double)rowsContentHeight;
    - (NSLayoutConstraint *)rowsScrollHeightConstraint;
    - (UIScrollView *)rowsScrollView;
    - (UIStackView *)rowsStack;
    - (void)setChevronView:(id)arg1;
    - (void)setCollapsedBottom:(id)arg1;
    - (void)setContainer:(id)arg1;
    - (void)setDurationTimer:(id)arg1;
    - (void)setExpanded:(id)arg1;
    - (void)setExpandedBottom:(id)arg1;
    - (void)setHasRunningOperations:(id)arg1;
    - (void)setHeaderButton:(id)arg1;
    - (void)setHeaderIcon:(id)arg1;
    - (void)setMessages:(id)arg1;
    - (void)setOnOpenMessage:(id)arg1;
    - (void)setOnStop:(id)arg1;
    - (void)setOnToggle:(id)arg1;
    - (void)setRowsScrollHeightConstraint:(id)arg1;
    - (void)setRowsScrollView:(id)arg1;
    - (void)setRowsStack:(id)arg1;
    - (void)setStopButton:(id)arg1;
    - (void)setSummaryLabel:(id)arg1;
    - (void)setTitleLabel:(id)arg1;
    - (void)stop;
    - (UIButton *)stopButton;
    - (UILabel *)summaryLabel;
    - (void)synchronizeDurationTimer;
    - (id)tintForMessage:(id)arg1;
    - (id)titleForMessage:(id)arg1;
    - (UILabel *)titleLabel;
    - (void)toggle;
    - (void)updateRowsScrollViewportPreviousOffset:(id)arg1 stickToBottom:(id)arg2;

@end

NS_ASSUME_NONNULL_END
