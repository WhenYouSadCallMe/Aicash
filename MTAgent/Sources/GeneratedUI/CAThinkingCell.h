//
//  CAThinkingCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAThinkingCell : UITableViewCell
    - (bool)ambientMusingActive;
    - (bool)canContinueAmbientGeneration:(id)arg1;
    - (void)cancelAmbientMusing;
    - (UIImageView *)chevronView;
    - (UIButton *)collapseButton;
    - (NSLayoutConstraint *)collapseHeightConstraint;
    - (NSLayoutConstraint *)collapseTopConstraint;
    - (void)configureWithMessage:(id)arg1;
    - (UIView *)containerView;
    - (NSLayoutConstraint *)detailHeightConstraint;
    - (UILabel *)detailLabel;
    - (NSLayoutConstraint *)detailTopConstraint;
    - (void)didMoveToWindow;
    - (UILabel *)durationLabel;
    - (id)durationText;
    - (CGRect)expandedBodyRectForCollapseSnapshot;
    - (bool)gestureRecognizer:(id)arg1 shouldReceiveTouch:(id)arg2;
    - (void)handleTap;
    - (UIImageView *)iconView;
    - (CAThinkingCell *)initWithFrame:(id)arg1;
    - (CAMessageItem *)message;
    - (unsigned __int64)musingGeneration;
    - (NSString *)musingMessageID;
    - (NSString *)musingPhaseKey;
    - (signed __int64)musingPhraseIndex;
    - (id)musingsForCurrentMessage;
    - (signed __int64)nextMusingIndex;
    - (id)onToggle;
    - (void)pauseVisualActivityForInactivity;
    - (id)preferredLayoutAttributesFittingAttributes:(id)arg1;
    - (void)prepareForReuse;
    - (void)refreshDuration;
    - (void)setAmbientMusingActive:(id)arg1;
    - (void)setChevronView:(id)arg1;
    - (void)setCollapseButton:(id)arg1;
    - (void)setCollapseHeightConstraint:(id)arg1;
    - (void)setCollapseTopConstraint:(id)arg1;
    - (void)setContainerView:(id)arg1;
    - (void)setDetailHeightConstraint:(id)arg1;
    - (void)setDetailLabel:(id)arg1;
    - (void)setDetailTopConstraint:(id)arg1;
    - (void)setDurationLabel:(id)arg1;
    - (void)setIconView:(id)arg1;
    - (void)setMessage:(id)arg1;
    - (void)setMusingGeneration:(id)arg1;
    - (void)setMusingMessageID:(id)arg1;
    - (void)setMusingPhaseKey:(id)arg1;
    - (void)setMusingPhraseIndex:(id)arg1;
    - (void)setOnToggle:(id)arg1;
    - (void)setSpinner:(id)arg1;
    - (void)setStatusLabel:(id)arg1;
    - (void)setTimer:(id)arg1;
    - (bool)shouldUseAmbientMusingForMessage:(id)arg1;
    - (void)showMusingDotsForPhrase:(id)arg1 round:(id)arg2 dot:(id)arg3 generation:(id)arg4;
    - (void)showMusingPhraseAtIndex:(id)arg1 generation:(id)arg2;
    - (UIActivityIndicatorView *)spinner;
    - (void)startAmbientMusingForMessage:(id)arg1;
    - (UILabel *)statusLabel;
    - (void)thinkingAppDidBecomeActive:(id)arg1;
    - (void)thinkingAppWillResignActive:(id)arg1;
    - (NSTimer *)timer;
    - (void)typeMusingPhrase:(id)arg1 character:(id)arg2 generation:(id)arg3;
    - (void)updateTimer;

@end

NS_ASSUME_NONNULL_END
