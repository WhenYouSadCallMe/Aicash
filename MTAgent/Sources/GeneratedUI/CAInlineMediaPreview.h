//
//  CAInlineMediaPreview — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AVPlayerLayer;
@class CAInlineMediaPreview;

@interface CAInlineMediaPreview : NSObject
    - (UILabel *)captionLabel;
    - (CAInlineMediaPreview *)initWithPath:(id)arg1 video:(id)arg2;
    - (void)layoutSubviews;
    - (NSString *)path;
    - (UIButton *)playButton;
    - (AVPlayer *)player;
    - (AVPlayerLayer *)playerLayer;
    - (void)setCaptionLabel:(id)arg1;
    - (void)setPath:(id)arg1;
    - (void)setPlayButton:(id)arg1;
    - (void)setPlayer:(id)arg1;
    - (void)setPlayerLayer:(id)arg1;
    - (void)setVideo:(id)arg1;
    - (void)togglePlayback;
    - (bool)video;

@end

NS_ASSUME_NONNULL_END
