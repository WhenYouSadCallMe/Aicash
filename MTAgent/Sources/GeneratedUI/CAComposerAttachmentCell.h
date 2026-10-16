//
//  CAComposerAttachmentCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAComposerAttachmentCell;

@interface CAComposerAttachmentCell : UITableViewCell
    - (void)configure:(id)arg1;
    - (CAComposerAttachmentCell *)initWithFrame:(id)arg1;
    - (UILabel *)nameLabel;
    - (id)onRemove;
    - (void)prepareForReuse;
    - (UIButton *)removeButton;
    - (void)removeTapped;
    - (NSString *)representedPath;
    - (void)setNameLabel:(id)arg1;
    - (void)setOnRemove:(id)arg1;
    - (void)setRemoveButton:(id)arg1;
    - (void)setRepresentedPath:(id)arg1;
    - (void)setThumbView:(id)arg1;
    - (UIImageView *)thumbView;

@end

NS_ASSUME_NONNULL_END
