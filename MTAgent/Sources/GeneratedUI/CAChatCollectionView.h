//
//  CAChatCollectionView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CABottomFollowTarget;

@interface CAChatCollectionView : UIView
    - (void)adjustedContentInsetDidChange;
    - (void)advanceBottomFollow:(id)arg1;
    - (CADisplayLink *)bottomFollowLink;
    - (CABottomFollowTarget *)bottomFollowTarget;
    - (double)bottomFollowY;
    - (bool)bottomPinSuspended;
    - (void)cancelBottomFollow;
    - (bool)correctingBottom;
    - (void)didMoveToWindow;
    - (bool)keepsBottomPinned;
    - (UIEdgeInsets)lastAdjustedInsets;
    - (CGSize)lastContentSize;
    - (double)lastFollowFrameAt;
    - (CGSize)lastViewportSize;
    - (void)layoutSubviews;
    - (id)messageSectionWithAssistantHeader:(id)arg1;
    - (bool)pendingBottomPosition;
    - (void)requestBottomPosition;
    - (void)setBottomFollowLink:(id)arg1;
    - (void)setBottomFollowTarget:(id)arg1;
    - (void)setBottomFollowY:(id)arg1;
    - (void)setBottomPinSuspended:(id)arg1;
    - (void)setCorrectingBottom:(id)arg1;
    - (void)setKeepsBottomPinned:(id)arg1;
    - (void)setLastAdjustedInsets:(id)arg1;
    - (void)setLastContentSize:(id)arg1;
    - (void)setLastFollowFrameAt:(id)arg1;
    - (void)setLastViewportSize:(id)arg1;
    - (void)setPendingBottomPosition:(id)arg1;
    - (void)setSmoothStreamingFollow:(id)arg1;
    - (bool)smoothStreamingFollow;

@end

NS_ASSUME_NONNULL_END
