//
//  CAMermaidSequenceItem — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString;

@interface CAMermaidSequenceItem : NSObject
    - (bool)crossArrow;
    - (bool)dashed;
    - (double)height;
    - (NSString *)kind;
    - (NSString *)label;
    - (signed long long)matchingIndex;
    - (NSString *)notePosition;
    - (void)setCrossArrow:(id)arg1;
    - (void)setDashed:(id)arg1;
    - (void)setHeight:(id)arg1;
    - (void)setKind:(id)arg1;
    - (void)setLabel:(id)arg1;
    - (void)setMatchingIndex:(id)arg1;
    - (void)setNotePosition:(id)arg1;
    - (void)setSource:(id)arg1;
    - (void)setTarget:(id)arg1;
    - (void)setType:(id)arg1;
    - (void)setY:(id)arg1;
    - (NSString *)source;
    - (NSString *)target;
    - (signed long long)type;
    - (double)y;

@end

NS_ASSUME_NONNULL_END
