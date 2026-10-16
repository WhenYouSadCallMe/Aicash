//
//  CAComposerPopupView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAComposerPopupView : UIView
    - (void)applyTheme;
    - (UIVisualEffectView *)backgroundEffect;
    - (UIView *)clipView;
    - (UIButton *)closeButton;
    - (void)closeTapped;
    - (id)firstSelectableIndexPathFrom:(id)arg1 forward:(id)arg2;
    - (bool)hasSelectableItems;
    - (NSString *)headerHint;
    - (UILabel *)headerHintLabel;
    - (UIView *)headerSeparator;
    - (NSString *)headerTitle;
    - (UILabel *)headerTitleLabel;
    - (UIView *)headerView;
    - (NSIndexPath *)highlightedIndexPath;
    - (id)indexPathForIdentifier:(id)arg1;
    - (CAComposerPopupView *)initWithFrame:(id)arg1;
    - (id)itemAtIndexPath:(id)arg1;
    - (void)layoutSubviews;
    - (bool)moveHighlightBy:(id)arg1;
    - (signed long long)numberOfSectionsInTableView:(id)arg1;
    - (id)onClose;
    - (id)onSelectItem;
    - (double)preferredHeight;
    - (double)rowHeight;
    - (NSArray *)sections;
    - (bool)selectHighlightedItem;
    - (id)selectableIndexPaths;
    - (void)setBackgroundEffect:(id)arg1;
    - (void)setClipView:(id)arg1;
    - (void)setCloseButton:(id)arg1;
    - (void)setHeaderHint:(id)arg1;
    - (void)setHeaderHintLabel:(id)arg1;
    - (void)setHeaderSeparator:(id)arg1;
    - (void)setHeaderTitle:(id)arg1;
    - (void)setHeaderTitleLabel:(id)arg1;
    - (void)setHeaderView:(id)arg1;
    - (void)setHighlightedIndexPath:(id)arg1;
    - (void)setOnClose:(id)arg1;
    - (void)setOnSelectItem:(id)arg1;
    - (void)setSections:(id)arg1;
    - (void)setSections:(id)arg1 preserveHighlight:(id)arg2;
    - (void)setTableView:(id)arg1;
    - (UITableView *)tableView;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2;
    - (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2;
    - (double)tableView:(id)arg1 heightForHeaderInSection:(id)arg2;
    - (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (bool)tableView:(id)arg1 shouldHighlightRowAtIndexPath:(id)arg2;
    - (id)tableView:(id)arg1 viewForFooterInSection:(id)arg2;
    - (id)tableView:(id)arg1 viewForHeaderInSection:(id)arg2;
    - (void)traitCollectionDidChange:(id)arg1;

@end

NS_ASSUME_NONNULL_END
