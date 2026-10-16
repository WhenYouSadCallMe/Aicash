//
//  CAGitSummaryCell — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAGitSummaryCell : UITableViewCell
    - (void)applyModel:(id)arg1;
    - (CAGitPill *)branchPill;
    - (void)branchTapped;
    - (void)fetchTapped;
    - (CAGitSummaryCell *)initWithStyle:(id)arg1 reuseIdentifier:(id)arg2;
    - (id)onBranch;
    - (id)onFetch;
    - (id)onPull;
    - (id)onPush;
    - (id)onRemote;
    - (void)prepareForReuse;
    - (void)pullTapped;
    - (void)pushTapped;
    - (CAGitPill *)remotePill;
    - (void)remoteTapped;
    - (void)setOnBranch:(id)arg1;
    - (void)setOnFetch:(id)arg1;
    - (void)setOnPull:(id)arg1;
    - (void)setOnPush:(id)arg1;
    - (void)setOnRemote:(id)arg1;

@end

NS_ASSUME_NONNULL_END
