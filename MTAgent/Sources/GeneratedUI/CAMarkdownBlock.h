//
//  CAMarkdownBlock — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAMarkdownBlock : NSObject
    - (NSString *)content;
    - (bool)continuationFromPreviousText;
    - (NSString *)language;
    - (NSString *)mediaAltText;
    - (NSString *)mediaTarget;
    - (void)setContent:(id)arg1;
    - (void)setContinuationFromPreviousText:(id)arg1;
    - (void)setLanguage:(id)arg1;
    - (void)setMediaAltText:(id)arg1;
    - (void)setMediaTarget:(id)arg1;
    - (void)setTableAlignments:(id)arg1;
    - (void)setTableRows:(id)arg1;
    - (void)setType:(id)arg1;
    - (NSArray *)tableAlignments;
    - (NSArray *)tableRows;
    - (signed long long)type;

@end

NS_ASSUME_NONNULL_END
