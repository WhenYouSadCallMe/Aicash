//
//  CALogViewerViewController.h — 日志查看（等级 / 分类 / 搜索过滤，复制 / 分享 / 导出 / 清空）
//
//  原包符号对齐：-reloadLogForce:、-handleCopyVisibleLogs、-handleShareLogFile、
//  -handleExportLogFile、-confirmClearLog、-levelFilterChanged、-selectCategory:、_refreshTimer
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CALogViewerViewController : UIViewController

/// 全部日志条目（元素为私有实现类 CALogViewerEntry）
@property (nonatomic, strong, nullable) NSArray *allEntries;

/// 过滤后条目
@property (nonatomic, strong, nullable) NSArray *visibleEntries;

/// 可选分类（CALogger knownCategories + 行内解析结果）
@property (nonatomic, strong, nullable) NSArray<NSString *> *categories;

/// 当前分类过滤（nil 表示全部）
@property (nonatomic, copy, nullable) NSString *categoryFilter;

/// 搜索关键字
@property (nonatomic, copy, nullable) NSString *searchQuery;

/// 解析到的总条目数（未过滤）
@property (nonatomic, assign) NSUInteger totalEntryCount;

/// 自动刷新定时器（原包 ivar: _refreshTimer）
@property (nonatomic, strong, nullable) NSTimer *refreshTimer;

/// 是否已成功读取过一轮
@property (nonatomic, assign) BOOL hasLoadedOnce;

/// 用户是否正在滚动（滚动中暂停自动刷新）
@property (nonatomic, assign) BOOL userIsScrolling;

#pragma mark - 读取 / 过滤

- (void)reloadLogForce:(BOOL)force;

#pragma mark - 输出

- (void)handleCopyVisibleLogs;
- (void)handleShareLogFile;
- (void)handleExportLogFile;
- (void)confirmClearLog;


// ==PARITY-PROPERTIES-BEGIN== (auto-generated from original __objc_proplist)
    @property (nonatomic, strong, nullable) UIButton * categoryButton;
    @property (nonatomic, strong, nullable) UILabel * emptyLabel;
    @property (nonatomic, strong, nullable) NSString * fileSignature;
    @property (nonatomic, strong, nullable) UIButton * jumpBottomButton;
    @property (nonatomic, strong, nullable) UISegmentedControl * levelControl;
    @property (nonatomic, strong, nullable) UIBarButtonItem * logCopyItem;
    @property (nonatomic, strong, nullable) UIBarButtonItem * moreItem;
    @property (nonatomic, strong, nullable) NSArray * pendingEntries;
    @property (nonatomic, assign) BOOL preparingShare;
    @property (nonatomic, assign) BOOL reading;
    @property (nonatomic, strong, nullable) UISearchController * searchController;
// ==PARITY-PROPERTIES-END==

// ==PARITY-SELECTOR-PLACEHOLDER-BEGIN==
    - (id)applyPendingEntriesIfNeeded;
    - (id)clearLog;
    - (id)filterBar;
    - (id)prepareLogSnapshot:(id)arg1;
    - (id)setFilterBar:(id)arg1;
    - (id)updateLevelTitles;
// ==PARITY-SELECTOR-PLACEHOLDER-END==
@end

NS_ASSUME_NONNULL_END
