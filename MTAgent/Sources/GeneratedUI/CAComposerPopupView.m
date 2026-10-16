//
//  CAComposerPopupView — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//
//  聊天主流程实装：输入框 “/” 面板（分组列表 + 键盘上下移动高亮 + 回车选中 + 关闭）。
//  数据由 CAChatViewController 从 CAComposerCatalog 组装成 CAComposerPopupSection 数组后注入。
//

#import "CAComposerPopupView.h"
#import "CAComposerPopupSection.h"
#import "CAComposerPopupItem.h"
#import "CAComposerPopupCell.h"

static CGFloat const kCAComposerPopupHeaderHeight = 34.0;
static CGFloat const kCAComposerPopupRowHeight    = 50.0;
static CGFloat const kCAComposerPopupMaxHeight    = 320.0;

@interface CAComposerPopupView () <UITableViewDataSource, UITableViewDelegate> {
    NSArray *_sections;
}

@property (nonatomic, strong) UIVisualEffectView *backgroundEffect;
@property (nonatomic, strong) UIView *clipView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIView *headerSeparator;
@property (nonatomic, strong) UILabel *headerTitleLabel;
@property (nonatomic, strong) UILabel *headerHintLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSIndexPath *highlightedIndexPath;
@property (nonatomic, copy) NSString *headerTitle;
@property (nonatomic, copy) NSString *headerHint;
@property (nonatomic, strong) id onSelectItem;
@property (nonatomic, strong) id onClose;
@end

@implementation CAComposerPopupView

#pragma mark - 生命周期

- (id)initWithFrame:(id)arg1
{
    if ((self = [super initWithFrame:CGRectZero])) {
        [self setupPopup];
    }
    return self;
}

- (void)setupPopup
{
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = UIColor.clearColor;
    self.layer.cornerRadius = 14.0;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    self.layer.borderColor = UIColor.separatorColor.CGColor;

    UIBlurEffect *effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    _backgroundEffect = [[UIVisualEffectView alloc] initWithEffect:effect];
    _backgroundEffect.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_backgroundEffect];

    _clipView = [[UIView alloc] init];
    _clipView.translatesAutoresizingMaskIntoConstraints = NO;
    _clipView.backgroundColor = UIColor.clearColor;
    [self addSubview:_clipView];

    _headerView = [[UIView alloc] init];
    _headerView.translatesAutoresizingMaskIntoConstraints = NO;
    [_clipView addSubview:_headerView];

    _headerTitleLabel = [[UILabel alloc] init];
    _headerTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _headerTitleLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightSemibold];
    _headerTitleLabel.textColor = UIColor.secondaryLabelColor;
    _headerTitleLabel.text = @"命令与技能";
    [_headerView addSubview:_headerTitleLabel];

    _headerHintLabel = [[UILabel alloc] init];
    _headerHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _headerHintLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightRegular];
    _headerHintLabel.textColor = UIColor.tertiaryLabelColor;
    [_headerView addSubview:_headerHintLabel];

    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_closeButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    _closeButton.tintColor = UIColor.tertiaryLabelColor;
    [_closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_headerView addSubview:_closeButton];

    _headerSeparator = [[UIView alloc] init];
    _headerSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    _headerSeparator.backgroundColor = UIColor.separatorColor;
    [_clipView addSubview:_headerSeparator];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.backgroundColor = UIColor.clearColor;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.rowHeight = kCAComposerPopupRowHeight;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:CAComposerPopupCell.class forCellReuseIdentifier:@"CAComposerPopupCell"];
    [_clipView addSubview:_tableView];

    [NSLayoutConstraint activateConstraints:@[
        [_backgroundEffect.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_backgroundEffect.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_backgroundEffect.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_backgroundEffect.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [_clipView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_clipView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_clipView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_clipView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],

        [_headerView.topAnchor constraintEqualToAnchor:_clipView.topAnchor],
        [_headerView.leadingAnchor constraintEqualToAnchor:_clipView.leadingAnchor],
        [_headerView.trailingAnchor constraintEqualToAnchor:_clipView.trailingAnchor],
        [_headerView.heightAnchor constraintEqualToConstant:kCAComposerPopupHeaderHeight],

        [_headerTitleLabel.leadingAnchor constraintEqualToAnchor:_headerView.leadingAnchor constant:12.0],
        [_headerTitleLabel.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],

        [_closeButton.trailingAnchor constraintEqualToAnchor:_headerView.trailingAnchor constant:-8.0],
        [_closeButton.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],
        [_closeButton.widthAnchor constraintEqualToConstant:26.0],
        [_closeButton.heightAnchor constraintEqualToConstant:26.0],

        [_headerHintLabel.trailingAnchor constraintEqualToAnchor:_closeButton.leadingAnchor constant:-6.0],
        [_headerHintLabel.centerYAnchor constraintEqualToAnchor:_headerView.centerYAnchor],

        [_headerSeparator.topAnchor constraintEqualToAnchor:_headerView.bottomAnchor],
        [_headerSeparator.leadingAnchor constraintEqualToAnchor:_clipView.leadingAnchor],
        [_headerSeparator.trailingAnchor constraintEqualToAnchor:_clipView.trailingAnchor],
        [_headerSeparator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],

        [_tableView.topAnchor constraintEqualToAnchor:_headerSeparator.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:_clipView.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:_clipView.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:_clipView.bottomAnchor],
    ]];

    [self applyTheme];
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    self.layer.cornerRadius = 14.0;
}

- (void)traitCollectionDidChange:(id)arg1
{
    [super traitCollectionDidChange:[arg1 isKindOfClass:UITraitCollection.class] ? arg1 : nil];
    [self applyTheme];
}

- (void)applyTheme
{
    self.backgroundColor = UIColor.clearColor;
    self.layer.borderColor = UIColor.separatorColor.CGColor;
    self.headerTitleLabel.text = self.headerTitle.length > 0 ? self.headerTitle : @"命令与技能";
    self.headerHintLabel.text = self.headerHint ?: @"↑↓ 选择 · ⏎ 插入";
    self.tableView.backgroundColor = UIColor.clearColor;
}

#pragma mark - 数据

- (NSArray *)sections { return _sections ?: @[]; }

- (void)setSections:(id)arg1
{
    [self setSections:arg1 preserveHighlight:@NO];
}

- (void)setSections:(id)arg1 preserveHighlight:(id)arg2
{
    BOOL preserve = [arg2 respondsToSelector:@selector(boolValue)] ? [arg2 boolValue] : NO;
    id highlightedItem = [self itemAtIndexPath:self.highlightedIndexPath];
    NSString *previousHighlightIdentifier = preserve && [highlightedItem isKindOfClass:CAComposerPopupItem.class]
        ? ((CAComposerPopupItem *)highlightedItem).identifier : nil;
    _sections = [arg1 isKindOfClass:NSArray.class] ? [arg1 copy] : @[];
    [self.tableView reloadData];

    self.highlightedIndexPath = nil;
    if (previousHighlightIdentifier.length > 0) {
        self.highlightedIndexPath = [self indexPathForIdentifier:previousHighlightIdentifier];
    }
    if (!self.highlightedIndexPath) {
        self.highlightedIndexPath = [self firstSelectableIndexPathFrom:@[@0, @0] forward:@YES];
    }
    [self refreshHighlight];
}

- (id)itemAtIndexPath:(id)arg1
{
    NSIndexPath *indexPath = [arg1 isKindOfClass:NSIndexPath.class] ? arg1 : nil;
    if (!indexPath) return nil;
    NSArray *sections = self.sections;
    if ((NSUInteger)indexPath.section >= sections.count) return nil;
    id section = sections[(NSUInteger)indexPath.section];
    NSArray *items = [section isKindOfClass:CAComposerPopupSection.class] ? ((CAComposerPopupSection *)section).items : @[];
    if ((NSUInteger)indexPath.row >= items.count) return nil;
    return items[(NSUInteger)indexPath.row];
}

- (id)indexPathForIdentifier:(id)arg1
{
    NSString *identifier = [arg1 isKindOfClass:NSString.class] ? arg1 : nil;
    if (identifier.length == 0) return nil;
    NSArray *sections = self.sections;
    for (NSUInteger section = 0; section < sections.count; section++) {
        id rawSection = sections[section];
        NSArray *items = [rawSection isKindOfClass:CAComposerPopupSection.class] ? ((CAComposerPopupSection *)rawSection).items : @[];
        for (NSUInteger row = 0; row < items.count; row++) {
            id item = items[row];
            if ([item isKindOfClass:CAComposerPopupItem.class] &&
                [((CAComposerPopupItem *)item).identifier isEqualToString:identifier]) {
                return [NSIndexPath indexPathForRow:(NSInteger)row inSection:(NSInteger)section];
            }
        }
    }
    return nil;
}

- (id)selectableIndexPaths
{
    NSMutableArray<NSIndexPath *> *paths = [NSMutableArray array];
    NSArray *sections = self.sections;
    for (NSUInteger section = 0; section < sections.count; section++) {
        id rawSection = sections[section];
        NSArray *items = [rawSection isKindOfClass:CAComposerPopupSection.class] ? ((CAComposerPopupSection *)rawSection).items : @[];
        for (NSUInteger row = 0; row < items.count; row++) {
            id item = items[row];
            if ([item isKindOfClass:CAComposerPopupItem.class] && ((CAComposerPopupItem *)item).enabled) {
                [paths addObject:[NSIndexPath indexPathForRow:(NSInteger)row inSection:(NSInteger)section]];
            }
        }
    }
    return paths;
}

- (bool)hasSelectableItems
{
    NSArray *paths = [self selectableIndexPaths];
    return paths.count > 0;
}

- (id)firstSelectableIndexPathFrom:(id)arg1 forward:(id)arg2
{
    BOOL forward = [arg2 respondsToSelector:@selector(boolValue)] ? [arg2 boolValue] : YES;
    NSArray<NSIndexPath *> *paths = [self selectableIndexPaths];
    if (paths.count == 0) return nil;

    NSIndexPath *anchor = nil;
    if ([arg1 isKindOfClass:NSIndexPath.class]) {
        anchor = arg1;
    } else if ([arg1 isKindOfClass:NSArray.class] && [(NSArray *)arg1 count] >= 2) {
        NSArray *components = (NSArray *)arg1;
        anchor = [NSIndexPath indexPathForRow:[components[1] integerValue]
                                   inSection:[components[0] integerValue]];
    }
    if (!anchor) return forward ? paths.firstObject : paths.lastObject;

    NSIndexPath *best = nil;
    for (NSIndexPath *path in paths) {
        NSComparisonResult order = [path compare:anchor];
        if (forward) {
            if (order == NSOrderedDescending) { best = path; break; }
        } else if (order == NSOrderedAscending) {
            best = path;
        }
    }
    if (best) return best;
    return forward ? paths.firstObject : paths.lastObject;
}

#pragma mark - 键盘交互

- (bool)moveHighlightBy:(id)arg1
{
    NSInteger delta = [arg1 respondsToSelector:@selector(integerValue)] ? [arg1 integerValue] : 0;
    NSArray<NSIndexPath *> *paths = [self selectableIndexPaths];
    if (paths.count == 0) return NO;
    NSIndexPath *current = self.highlightedIndexPath;
    NSUInteger index = 0;
    if (current && [paths containsObject:current]) index = [paths indexOfObject:current];
    else index = delta > 0 ? 0 : paths.count - 1;

    NSInteger next = (NSInteger)index + (delta >= 0 ? MAX(delta, 1) : delta);
    while (next < 0) next += (NSInteger)paths.count;
    NSUInteger wrapped = (NSUInteger)(next % (NSInteger)paths.count);
    self.highlightedIndexPath = paths[wrapped];
    [self refreshHighlight];
    return YES;
}

- (bool)selectHighlightedItem
{
    NSIndexPath *path = self.highlightedIndexPath;
    if (!path) path = [self firstSelectableIndexPathFrom:@[@0, @0] forward:@YES];
    if (!path) return NO;
    CAComposerPopupItem *item = [self itemAtIndexPath:path];
    if (!item || !item.enabled) return NO;
    [self notifySelection:item];
    return YES;
}

- (void)notifySelection:(CAComposerPopupItem *)item
{
    id handler = self.onSelectItem;
    if (!handler) return;
    void (^block)(CAComposerPopupItem *) = handler;
    block(item);
}

- (void)closeTapped
{
    id handler = self.onClose;
    if (!handler) return;
    void (^block)(void) = handler;
    block();
}

- (void)refreshHighlight
{
    NSArray<UITableViewCell *> *visible = self.tableView.visibleCells;
    for (UITableViewCell *cell in visible) {
        if (![cell isKindOfClass:CAComposerPopupCell.class]) continue;
        NSIndexPath *path = [self.tableView indexPathForCell:cell];
        BOOL highlighted = (path && [path isEqual:self.highlightedIndexPath]);
        [(CAComposerPopupCell *)cell setKeyboardHighlighted:@(highlighted)];
    }
    if (self.highlightedIndexPath) {
        [self.tableView selectRowAtIndexPath:self.highlightedIndexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
}

#pragma mark - 尺寸

- (double)rowHeight
{
    return kCAComposerPopupRowHeight;
}

- (double)preferredHeight
{
    NSUInteger rows = 0;
    NSUInteger sectionsWithTitles = 0;
    for (id rawSection in self.sections) {
        if (![rawSection isKindOfClass:CAComposerPopupSection.class]) continue;
        CAComposerPopupSection *section = rawSection;
        rows += section.items.count;
        if (section.title.length > 0) sectionsWithTitles++;
    }
    CGFloat height = kCAComposerPopupHeaderHeight + rows * kCAComposerPopupRowHeight + sectionsWithTitles * 22.0;
    return MIN(MAX(height, kCAComposerPopupHeaderHeight + kCAComposerPopupRowHeight), kCAComposerPopupMaxHeight);
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)self.sections.count;
}

- (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2
{
    NSInteger section = [arg2 respondsToSelector:@selector(integerValue)] ? [arg2 integerValue] : 0;
    NSArray *sections = self.sections;
    if (section < 0 || (NSUInteger)section >= sections.count) return 0;
    id rawSection = sections[(NSUInteger)section];
    NSArray *items = [rawSection isKindOfClass:CAComposerPopupSection.class] ? ((CAComposerPopupSection *)rawSection).items : @[];
    return (signed long long)items.count;
}

- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? arg1 : self.tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? arg2 : nil;
    CAComposerPopupCell *cell = (CAComposerPopupCell *)[tableView dequeueReusableCellWithIdentifier:@"CAComposerPopupCell" forIndexPath:indexPath];
    CAComposerPopupItem *item = [self itemAtIndexPath:indexPath];
    [cell configureWithItem:item];
    [cell setKeyboardHighlighted:@([indexPath isEqual:self.highlightedIndexPath])];
    return cell;
}

- (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2
{
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? arg2 : nil;
    if (!indexPath) return;
    self.highlightedIndexPath = indexPath;
    CAComposerPopupItem *item = [self itemAtIndexPath:indexPath];
    if (!item || !item.enabled) return;
    [self notifySelection:item];
}

- (bool)tableView:(id)arg1 shouldHighlightRowAtIndexPath:(id)arg2
{
    CAComposerPopupItem *item = [self itemAtIndexPath:arg2];
    return item ? item.enabled : NO;
}

- (double)tableView:(id)arg1 heightForHeaderInSection:(id)arg2
{
    NSInteger section = [arg2 respondsToSelector:@selector(integerValue)] ? [arg2 integerValue] : 0;
    NSArray *sections = self.sections;
    if (section < 0 || (NSUInteger)section >= sections.count) return 0;
    id rawSection = sections[(NSUInteger)section];
    NSString *title = [rawSection isKindOfClass:CAComposerPopupSection.class] ? ((CAComposerPopupSection *)rawSection).title : @"";
    return title.length > 0 ? 22.0 : 0.0;
}

- (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2
{
    return 0.0;
}

- (id)tableView:(id)arg1 viewForHeaderInSection:(id)arg2
{
    NSInteger section = [arg2 respondsToSelector:@selector(integerValue)] ? [arg2 integerValue] : 0;
    NSArray *sections = self.sections;
    if (section < 0 || (NSUInteger)section >= sections.count) return nil;
    id rawSection = sections[(NSUInteger)section];
    NSString *title = [rawSection isKindOfClass:CAComposerPopupSection.class] ? ((CAComposerPopupSection *)rawSection).title : @"";
    if (title.length == 0) return nil;

    UIView *header = [[UIView alloc] init];
    header.backgroundColor = UIColor.clearColor;
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = title.uppercaseString;
    label.font = [UIFont systemFontOfSize:10.5 weight:UIFontWeightSemibold];
    label.textColor = UIColor.tertiaryLabelColor;
    [header addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:14.0],
        [label.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-2.0],
    ]];
    return header;
}

- (id)tableView:(id)arg1 viewForFooterInSection:(id)arg2
{
    return nil;
}

@end
