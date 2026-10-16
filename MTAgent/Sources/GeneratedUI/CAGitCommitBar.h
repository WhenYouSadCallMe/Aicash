//
//  CAGitCommitBar.h — 提交栏（分段「全部更改 / 仅已暂存」 + 提交信息输入 + 提交按钮）
//
//  选择器原型取自 SPEC/method_types.json（逐字保留）：原包 13 个 ivar
//  （_commitButton/_hintLabel/_lastTextWidth/_on*/_placeholder/_scopeControl/_textHeight/_textView/_topLine）。
//  原包该类拥有 initWithFrame: / layoutSubviews / applyTheme，是 UIView 派生：
//  基类由生成时的 NSObject 修正为 UIView，导出的选择器集合完全不变。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAGitCommitBar;

@class NSString;

@interface CAGitCommitBar : UIView
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

#pragma mark - 使用面（复刻补全）

/// 当前分段：NO = 全部更改，YES = 仅已暂存
- (BOOL)scopeIsStagedOnly;

@end

NS_ASSUME_NONNULL_END
