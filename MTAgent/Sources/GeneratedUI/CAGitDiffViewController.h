//
//  CAGitDiffViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAGitChipLabel;
@class CAGitDiffResult;
@class CAGitRepository;
@class UISegmentedControl;

@class NSDictionary;
@class UIImageView;
@class UILabel;
@class UITextView;
@class UIView;

@interface CAGitDiffViewController : UIViewController
    - (NSDictionary *)change;
    - (void)copyDiff;
    - (UILabel *)countsLabel;
    - (id)diff;
    - (unsigned long long)generation;
    - (id)git;
    - (void)loadDiff;
    - (UILabel *)noticeLabel;
    - (bool)prefersStaged;
    - (id)scopeControl;
    - (void)setChange:(id)arg1;
    - (void)setCountsLabel:(id)arg1;
    - (void)setDiff:(id)arg1;
    - (void)setGeneration:(id)arg1;
    - (void)setGit:(id)arg1;
    - (void)setNoticeLabel:(id)arg1;
    - (void)setPrefersStaged:(id)arg1;
    - (void)setScopeControl:(id)arg1;
    - (void)setStats:(id)arg1;
    - (void)setStatusChip:(id)arg1;
    - (void)setSymbolView:(id)arg1;
    - (void)setTextView:(id)arg1;
    - (void)setTile:(id)arg1;
    - (void)shareDiff;
    - (NSDictionary *)stats;
    - (id)statusChip;
    - (UIImageView *)symbolView;
    - (UITextView *)textView;
    - (UIView *)tile;
    - (void)updateHeaderForStaged:(id)arg1;
    - (void)viewDidLoad;

@end

NS_ASSUME_NONNULL_END
