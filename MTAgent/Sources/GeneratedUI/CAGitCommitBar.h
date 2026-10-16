//
//  CAGitCommitBar — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAGitCommitBar;

@interface CAGitCommitBar : NSObject
    - (void)applyTheme;
    - (id)buildAccessoryView;
    - (void)commitTapped;
    - (void)configureWithStageAll:(id)arg1 allCount:(id)arg2 stagedCount:(id)arg3 canEdit:(id)arg4 canCommit:(id)arg5 hint:(id)arg6;
    - (void)doneTapped;
    - (void)focusMessage;
    - (id)initWithFrame:(id)arg1;
    - (void)layoutSubviews;
    - (NSString *)message;
    - (id)onBeginEditing;
    - (id)onCommit;
    - (id)onPrefix;
    - (id)onScopeChange;
    - (id)onTextChange;
    - (void)prefixTapped:(id)arg1;
    - (void)scopeChanged;
    - (void)setMessage:(id)arg1;
    - (void)setOnBeginEditing:(id)arg1;
    - (void)setOnCommit:(id)arg1;
    - (void)setOnPrefix:(id)arg1;
    - (void)setOnScopeChange:(id)arg1;
    - (void)setOnTextChange:(id)arg1;
    - (void)textChanged;
    - (void)textViewDidBeginEditing:(id)arg1;
    - (void)textViewDidChange:(id)arg1;
    - (NSString *)trimmedMessage;
    - (void)updatePlaceholder;
    - (void)updateTextHeightAnimated:(id)arg1;

@end

NS_ASSUME_NONNULL_END
