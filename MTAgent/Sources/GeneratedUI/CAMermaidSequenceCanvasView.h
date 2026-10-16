//
//  CAMermaidSequenceCanvasView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray;

@interface CAMermaidSequenceCanvasView : UIView
    - (NSArray *)activationSegments;
    - (CGSize)configureWithParticipants:(id)arg1 items:(id)arg2;
    - (void)drawArrowAt:(id)arg1 from:(id)arg2 cross:(id)arg3 color:(id)arg4;
    - (void)drawRect:(id)arg1;
    - (NSArray *)items;
    - (NSArray *)participants;
    - (void)setActivationSegments:(id)arg1;
    - (void)setItems:(id)arg1;
    - (void)setParticipants:(id)arg1;
    - (void)traitCollectionDidChange:(id)arg1;

@end

NS_ASSUME_NONNULL_END
