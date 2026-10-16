//
//  CATodoProgressButton — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CATodoProgressButton : NSObject
    - (signed long long)activeIndex;
    - (CAGradientLayer *)activeSegmentLayer;
    - (double)completedFraction;
    - (CAGradientLayer *)completedLayer;
    - (unsigned long long)completedSteps;
    - (CAGradientLayer *)completionSheenLayer;
    - (void)didMoveToWindow;
    - (bool)hasActiveSegment;
    - (CALayer *)headCoreLayer;
    - (CALayer *)headGlowLayer;
    - (CATodoProgressButton *)initWithFrame:(id)arg1;
    - (double)lastWidth;
    - (void)layoutSubviews;
    - (bool)pendingSync;
    - (void)playCompletionSweepIfNeeded;
    - (void)refreshProgressColors;
    - (void)removeActivityAnimations;
    - (void)setActiveIndex:(id)arg1;
    - (void)setActiveSegmentLayer:(id)arg1;
    - (void)setCompletedLayer:(id)arg1;
    - (void)setCompletedSteps:(id)arg1;
    - (void)setCompletionSheenLayer:(id)arg1;
    - (void)setHeadCoreLayer:(id)arg1;
    - (void)setHeadGlowLayer:(id)arg1;
    - (void)setLastWidth:(id)arg1;
    - (void)setPendingSync:(id)arg1;
    - (void)setTotalSteps:(id)arg1;
    - (void)setTrackLayer:(id)arg1;
    - (void)setTrailLayer:(id)arg1;
    - (void)setWasComplete:(id)arg1;
    - (void)synchronizeActivityAnimations;
    - (unsigned long long)totalSteps;
    - (CALayer *)trackLayer;
    - (CAGradientLayer *)trailLayer;
    - (void)traitCollectionDidChange:(id)arg1;
    - (void)updateCompletedSteps:(id)arg1 total:(id)arg2 activeIndex:(id)arg3 pendingSync:(id)arg4 animated:(id)arg5;
    - (bool)wasComplete;

@end

NS_ASSUME_NONNULL_END
