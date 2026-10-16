//
//  CAInlineZoomImagePreview — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAInlineZoomImagePreview : NSObject
    - (void)centerZoomContent;
    - (bool)fitted;
    - (UIImageView *)imageView;
    - (void)layoutSubviews;
    - (void)scrollViewDidZoom:(id)arg1;
    - (void)setFitted:(id)arg1;
    - (void)setImageView:(id)arg1;
    - (void)setPreviewImage:(id)arg1;
    - (void)updatePanAvailability;
    - (id)viewForZoomingInScrollView:(id)arg1;

@end

NS_ASSUME_NONNULL_END
