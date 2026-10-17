//
//  CAReasoningEffortViewController.h
//  「模型与思考强度」面板（原版：点底部强度 chip 打开的等高列表面板）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAReasoningEffortViewController : UITableViewController

/// 可选强度 level 列表（小写 codex 值，如 auto/none/low/medium/high/xhigh/max）
@property (nonatomic, copy) NSArray<NSString *> *levels;
/// 当前选中的 level
@property (nonatomic, copy, nullable) NSString *selectedLevel;
/// 选中回调（level 为 codex 原始值）
@property (nonatomic, copy, nullable) void (^onLevelSelected)(NSString *level);

@end

NS_ASSUME_NONNULL_END
