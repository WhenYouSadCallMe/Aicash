//
//  CAMermaidCanvasView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray;
@class NSString;

@interface CAMermaidCanvasView : UIView
    - (CGSize)configureWithNodes:(id)arg1 edges:(id)arg2 direction:(id)arg3;
    - (NSString *)direction;
    - (void)drawRect:(id)arg1;
    - (NSArray *)edges;
    - (NSArray *)nodes;
    - (void)setDirection:(id)arg1;
    - (void)setEdges:(id)arg1;
    - (void)setNodes:(id)arg1;
    - (void)traitCollectionDidChange:(id)arg1;

@end

NS_ASSUME_NONNULL_END
