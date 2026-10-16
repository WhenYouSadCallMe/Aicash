//
//  CAComposerTextView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class UIDropInteraction;

@interface CAComposerTextView : UIView
    - (bool)becomeFirstResponder;
    - (bool)composerDropInstalled;
    - (id)composerDropInteraction;
    - (void)didMoveToWindow;
    - (bool)dropInteraction:(id)arg1 canHandleSession:(id)arg2;
    - (void)dropInteraction:(id)arg1 performDrop:(id)arg2;
    - (id)dropInteraction:(id)arg1 sessionDidUpdate:(id)arg2;
    - (UIView *)emptyAccessoryView;
    - (void)handleHardwareDown:(id)arg1;
    - (void)handleHardwareEscape:(id)arg1;
    - (void)handleHardwareReturn:(id)arg1;
    - (void)handleHardwareShiftReturn:(id)arg1;
    - (void)handleHardwareUp:(id)arg1;
    - (id)inputAccessoryView;
    - (void)insertText:(id)arg1;
    - (void)installComposerDropInteraction;
    - (bool)interceptsNavigationKeys;
    - (bool)isLongComposerPaste:(id)arg1;
    - (id)keyCommands;
    - (void)loadFileProvider:(id)arg1 typeIdentifier:(id)arg2;
    - (void)moveCaretVertically:(id)arg1;
    - (id)onHardwareArrow;
    - (id)onHardwareEscape;
    - (id)onHardwareReturn;
    - (id)onPasteFile;
    - (id)onPasteImage;
    - (id)onPasteLongText;
    - (void)paste:(id)arg1;
    - (NSDictionary *)plainTextTypingAttributes;
    - (id)preferredFileTypeForProvider:(id)arg1;
    - (void)replaceRange:(id)arg1 withText:(id)arg2;
    - (void)restorePlainTextTypingAttributes;
    - (void)setComposerDropInstalled:(id)arg1;
    - (void)setComposerDropInteraction:(id)arg1;
    - (void)setEmptyAccessoryView:(id)arg1;
    - (void)setInterceptsNavigationKeys:(id)arg1;
    - (void)setMarkedText:(id)arg1 selectedRange:(id)arg2;
    - (void)setOnHardwareArrow:(id)arg1;
    - (void)setOnHardwareEscape:(id)arg1;
    - (void)setOnHardwareReturn:(id)arg1;
    - (void)setOnPasteFile:(id)arg1;
    - (void)setOnPasteImage:(id)arg1;
    - (void)setOnPasteLongText:(id)arg1;
    - (void)setPlainTextTypingAttributes:(id)arg1;
    - (void)setSelectedRange:(id)arg1;
    - (void)setSelectedTextRange:(id)arg1;
    - (bool)shouldCreateTextAttachmentForPaste:(id)arg1;
    - (id)temporaryCopyOfURL:(id)arg1 suggestedName:(id)arg2;

@end

NS_ASSUME_NONNULL_END
