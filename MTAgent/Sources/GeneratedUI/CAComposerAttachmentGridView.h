//
//  CAComposerAttachmentGridView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAComposerAttachmentGridView;

@interface CAComposerAttachmentGridView : UIView
    - (NSArray *)attachments;
    - (UICollectionView *)collectionView;
    - (id)collectionView:(id)arg1 cellForItemAtIndexPath:(id)arg2;
    - (void)collectionView:(id)arg1 didSelectItemAtIndexPath:(id)arg2;
    - (signed long long)collectionView:(id)arg1 numberOfItemsInSection:(id)arg2;
    - (id)initWithFrame:(id)arg1;
    - (NSArray *)items;
    - (id)onOpenIndex;
    - (id)onOpenPastedID;
    - (id)onRemoveIndex;
    - (id)onRemovePastedID;
    - (NSArray *)pastedTexts;
    - (double)preferredHeightForWidth:(id)arg1;
    - (void)setAttachments:(id)arg1;
    - (void)setAttachments:(id)arg1 pastedTexts:(id)arg2;
    - (void)setCollectionView:(id)arg1;
    - (void)setItems:(id)arg1;
    - (void)setOnOpenIndex:(id)arg1;
    - (void)setOnOpenPastedID:(id)arg1;
    - (void)setOnRemoveIndex:(id)arg1;
    - (void)setOnRemovePastedID:(id)arg1;
    - (void)setPastedTexts:(id)arg1;

@end

NS_ASSUME_NONNULL_END
