//
//  CAExtensionListViewController — Skills / 插件 / MCP / 提示词 / 记忆 列表面板
//
//  真实数据来源：CAComposerCatalog.sharedCatalog.items（扫描 ~/.codex/skills、~/.codex/prompts、
//  ~/.codex/plugins、config.toml 的 [mcp_servers.*] 以及 <workspace>/.codex/skills 等目录得到条目）。
//  开关写回：skill 走 -setSkill:enabled:completion:（落盘技能状态文件），mcp 走 -setMCPServer:enabled:completion:
//  （改写 config.toml 的 enabled），其余 kind 只维护本地状态。
//  删除：skill / prompt / 本地插件直接删文件或目录，mcp 走 -removeMCPServer:completion:。
//

#import "CAExtensionListViewController.h"
#import "CAComposerCatalog.h"
#import "CARuntimePaths.h"
#import "CACommon.h"
#import "CATextDetailViewController.h"
#import "CATextEditorViewController.h"

static NSString * const kCAExtensionListCellIdentifier = @"CAExtensionListCell";

/// 统一使用 UITableViewCellStyleSubtitle（标题 + 副标题），写法与 CASettingsViewController 的 CASettingsValueCell 一致。
@interface CAExtensionListValueCell : UITableViewCell
@end

@implementation CAExtensionListValueCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    return [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
}

@end

@interface CAExtensionListViewController () <UITableViewDataSource, UITableViewDelegate>
{
    CAComposerCatalogKind _kind;      // -kind / -setKind: 的真实存储
    NSArray *_sections;               // @[ @{ @"title": …, @"items": @[CAComposerCatalogItem, …] } ]
    UITableView *_tableView;
    UILabel *_emptyLabel;
    UIRefreshControl *_refreshControl;
    BOOL _refreshing;
    BOOL _observerInstalled;
}

#pragma mark - 私有辅助（工具方法，不属于原包选择器）

- (CAComposerCatalogItem *)itemAtIndexPath:(NSIndexPath *)indexPath;
- (NSString *)sectionTitleAtIndex:(NSInteger)section;
- (NSString *)kindDisplayName;
- (BOOL)isValidEntryName:(NSString *)name;
- (NSString *)removalTargetPathForItem:(CAComposerCatalogItem *)item;
- (void)handleClose;
- (void)handleSwitchChanged:(UISwitch *)sender;
- (void)catalogDidChangeNotification:(NSNotification *)notification;
- (void)endRefreshing;
- (void)updateEmptyState;
- (void)showMessage:(NSString *)message title:(NSString *)title;

@end

@implementation CAExtensionListViewController

#pragma mark - 开关

- (void)applyMCPServer:(id)arg1 enabled:(id)arg2 toggle:(id)arg3
{
    // 逐字沿用头文件占位签名：函数体首行强转后再用
    CAComposerCatalogItem *item = [arg1 isKindOfClass:CAComposerCatalogItem.class] ? (CAComposerCatalogItem *)arg1 : nil;
    BOOL enabled = [arg2 respondsToSelector:@selector(boolValue)] ? [arg2 boolValue] : NO;
    UISwitch *toggle = [arg3 isKindOfClass:UISwitch.class] ? (UISwitch *)arg3 : nil;
    if (!item) {
        if (toggle) toggle.on = !enabled;
        return;
    }

    // 先落本地状态，界面立即一致；随后由目录通知重建分组
    item.enabled = enabled;
    __weak typeof(self) weakSelf = self;
    [[CAComposerCatalog sharedCatalog] setMCPServer:item enabled:enabled completion:^(BOOL ok, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (!ok) {
                item.enabled = !enabled;
                if (toggle) toggle.on = !enabled;
                CALog(CALogLevelWarn, @"CHAT-PLUGIN", @"MCP toggle failed name=%@ error=%@",
                      item.name ?: item.identifier, error.localizedDescription ?: @"未知错误");
                [strongSelf showMessage:[NSString stringWithFormat:@"config.toml 写入失败：%@",
                                         error.localizedDescription ?: @"未知错误"]
                                  title:@"MCP 服务"];
            }
            [strongSelf catalogDidChange];
        });
    }];
}

- (void)applySkill:(id)arg1 enabled:(id)arg2 toggle:(id)arg3
{
    CAComposerCatalogItem *item = [arg1 isKindOfClass:CAComposerCatalogItem.class] ? (CAComposerCatalogItem *)arg1 : nil;
    BOOL enabled = [arg2 respondsToSelector:@selector(boolValue)] ? [arg2 boolValue] : NO;
    UISwitch *toggle = [arg3 isKindOfClass:UISwitch.class] ? (UISwitch *)arg3 : nil;
    if (!item) {
        if (toggle) toggle.on = !enabled;
        return;
    }

    item.enabled = enabled;
    __weak typeof(self) weakSelf = self;
    [[CAComposerCatalog sharedCatalog] setSkill:item enabled:enabled completion:^(BOOL ok, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (!ok) {
                item.enabled = !enabled;
                if (toggle) toggle.on = !enabled;
                CALog(CALogLevelWarn, @"CHAT-PLUGIN", @"skill toggle failed name=%@ error=%@",
                      item.name ?: item.identifier, error.localizedDescription ?: @"未知错误");
                [strongSelf showMessage:[NSString stringWithFormat:@"技能状态写入失败：%@",
                                         error.localizedDescription ?: @"未知错误"]
                                  title:item.displayTitle ?: @"Skill"];
            }
            [strongSelf catalogDidChange];
        });
    }];
}

#pragma mark - 目录变化

- (void)catalogDidChange
{
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self catalogDidChange];
        });
        return;
    }
    [self rebuildSections];
}

- (void)catalogDidChangeNotification:(NSNotification *)notification
{
    [self catalogDidChange];
}

#pragma mark - 路径

- (id)codexHome
{
    return [CARuntimePaths codexHome];
}

- (id)workspace
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *workspace = [defaults stringForKey:CADefaultsActiveWorkspace];
    if (workspace.length) return workspace;
    return [CARuntimePaths documentsCodexDirectory];
}

- (id)locallyManagedSkillRoots
{
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    NSString *home = [self codexHome];
    NSString *workspace = [self workspace];
    if (home.length) {
        [roots addObject:[home stringByAppendingPathComponent:@"skills"]];
        [roots addObject:[[home stringByAppendingPathComponent:@"skills"] stringByAppendingPathComponent:@".system"]];
        [roots addObject:[home stringByAppendingPathComponent:@"plugins"]];
    }
    if (workspace.length) {
        [roots addObject:[workspace stringByAppendingPathComponent:@".codex/skills"]];
        [roots addObject:[workspace stringByAppendingPathComponent:@".agents/skills"]];
        [roots addObject:[workspace stringByAppendingPathComponent:@".codex/plugins"]];
        [roots addObject:[workspace stringByAppendingPathComponent:@".agents/plugins"]];
    }
    NSString *managed = NSProcessInfo.processInfo.environment[CAEnvManagedSkillsPath];
    if (managed.length) [roots addObject:managed];
    return roots;
}

- (id)locallyManagedSkillRootForItem:(id)arg1
{
    // arg1 既可能是 CAComposerCatalogItem（取 path），也可能是路径字符串
    NSString *path = nil;
    if ([arg1 isKindOfClass:CAComposerCatalogItem.class]) {
        path = ((CAComposerCatalogItem *)arg1).path;
    } else if ([arg1 isKindOfClass:NSString.class]) {
        path = (NSString *)arg1;
    }
    if (!path.length) return nil;

    NSString *standardized = path.stringByStandardizingPath;
    for (NSString *root in [self locallyManagedSkillRoots]) {
        NSString *normalizedRoot = root.stringByStandardizingPath;
        if (!normalizedRoot.length) continue;
        // 必须严格位于 root 之下（root 自身不允许作为删除目标）
        if ([standardized hasPrefix:[normalizedRoot stringByAppendingString:@"/"]]) return normalizedRoot;
    }
    return nil;
}

- (bool)isLocallyManagedSkill:(id)arg1
{
    return [self locallyManagedSkillRootForItem:arg1] != nil;
}

- (bool)isLocallyManagedMCP:(id)arg1
{
    NSString *name = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : nil;
    if (!name.length) return NO;
    // 内部桥（codexapp / mtagent / native-tools…）由 App 自身管理，不在界面上删除
    return ![CAComposerCatalog isInternalMCPName:name];
}

- (id)editableFilePathForItem:(id)arg1
{
    if (![arg1 isKindOfClass:CAComposerCatalogItem.class]) return nil;
    CAComposerCatalogItem *item = (CAComposerCatalogItem *)arg1;
    NSString *path = item.path;
    if (!path.length) return nil;

    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory]) return nil;
    if (!isDirectory) return path;

    for (NSString *candidate in @[ @"SKILL.md", @"skill.md", @"plugin.json", @"README.md" ]) {
        NSString *child = [path stringByAppendingPathComponent:candidate];
        if ([NSFileManager.defaultManager fileExistsAtPath:child]) return child;
    }
    return nil;
}

#pragma mark - 删除

- (void)confirmRemoveMCP:(id)arg1
{
    CAComposerCatalogItem *item = [arg1 isKindOfClass:CAComposerCatalogItem.class] ? (CAComposerCatalogItem *)arg1 : nil;
    if (!item) return;

    BOOL local = [self isLocallyManagedMCP:item.name];
    NSString *message = local
        ? [NSString stringWithFormat:@"将从 config.toml 移除 [mcp_servers.%@]。", item.name ?: item.identifier]
        : [NSString stringWithFormat:@"%@ 是 App 内部桥服务，不允许从这里删除。", item.name ?: item.identifier];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"删除 MCP 服务 %@ ?", item.name ?: item.identifier]
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:local ? @"删除" : @"知道了"
                                             style:local ? UIAlertActionStyleDestructive : UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf || !local) return;
        [[CAComposerCatalog sharedCatalog] removeMCPServer:item completion:^(BOOL ok, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) innerSelf = weakSelf;
                if (!innerSelf) return;
                if (!ok) {
                    [innerSelf showMessage:[NSString stringWithFormat:@"删除失败：%@",
                                            error.localizedDescription ?: @"未知错误"]
                                     title:@"MCP 服务"];
                } else {
                    [innerSelf rebuildSections];
                }
            });
        }];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmRemovePrompt:(id)arg1
{
    CAComposerCatalogItem *item = [arg1 isKindOfClass:CAComposerCatalogItem.class] ? (CAComposerCatalogItem *)arg1 : nil;
    if (!item) return;

    NSString *path = [self editableFilePathForItem:item] ?: item.path;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"删除提示词 %@ ?", item.displayTitle]
                                                                  message:path.length
                                                                      ? [NSString stringWithFormat:@"将删除文件：%@", path]
                                                                      : @"将删除该提示词。"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSError *error = nil;
        if (path.length && ![NSFileManager.defaultManager removeItemAtPath:path error:&error]) {
            [strongSelf showMessage:[NSString stringWithFormat:@"删除失败：%@", error.localizedDescription ?: @"未知错误"]
                             title:@"提示词"];
            return;
        }
        CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"prompt removed name=%@ path=%@", item.name ?: item.identifier, path ?: @"(unknown)");
        [strongSelf refreshForce:@YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmRemoveSkill:(id)arg1
{
    CAComposerCatalogItem *item = [arg1 isKindOfClass:CAComposerCatalogItem.class] ? (CAComposerCatalogItem *)arg1 : nil;
    if (!item) return;

    NSString *path = [self removalTargetPathForItem:item];
    BOOL managed = [self isLocallyManagedSkill:path] || [self isLocallyManagedSkill:item.path];
    NSString *message = managed
        ? [NSString stringWithFormat:@"将删除目录：%@", path ?: item.path ?: @"(未知)"]
        : [NSString stringWithFormat:@"%@ 不在本地 Skill 目录下，删除前请确认来源：%@",
           item.displayTitle, path ?: item.path ?: @"(未知)"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"删除 %@ ?", item.displayTitle]
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSError *error = nil;
        if (path.length && ![NSFileManager.defaultManager removeItemAtPath:path error:&error]) {
            [strongSelf showMessage:[NSString stringWithFormat:@"删除失败：%@", error.localizedDescription ?: @"未知错误"]
                             title:item.displayTitle ?: @"Skill"];
            return;
        }
        CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"skill removed name=%@ path=%@ managed=%d",
              item.name ?: item.identifier, path ?: @"(unknown)", managed ? 1 : 0);
        [strongSelf refreshForce:@YES];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 新建

- (void)createPromptNamed:(id)arg1
{
    NSString *name = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : nil;
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![self isValidEntryName:name]) {
        [self showMessage:@"名字不能为空，也不能包含 / 或 \\。" title:@"新建提示词"];
        return;
    }

    NSString *directory = [[self codexHome] stringByAppendingPathComponent:@"prompts"];
    NSString *path = [directory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"md"]];
    NSString *template = [NSString stringWithFormat:
        @"# %@\n\n"
        @"- 用途：一句话说明这条提示词解决什么问题。\n"
        @"- 输入：需要用户提供的参数（如 {{file}}）。\n"
        @"- 要求：\n"
        @"  1. 用简体中文回复。\n"
        @"  2. 先给结论，再给依据。\n", name];

    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        [self showMessage:[NSString stringWithFormat:@"目录创建失败：%@", error.localizedDescription ?: @"未知错误"]
                    title:@"新建提示词"];
        return;
    }
    if (![template writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [self showMessage:[NSString stringWithFormat:@"文件写入失败：%@", error.localizedDescription ?: @"未知错误"]
                    title:@"新建提示词"];
        return;
    }

    CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"prompt created name=%@ path=%@", name, path);
    [self refreshForce:@YES];
    [self showMessage:[NSString stringWithFormat:@"已创建提示词：%@\n%@", name, path] title:@"新建提示词"];
}

- (void)createSkillNamed:(id)arg1
{
    NSString *name = [arg1 isKindOfClass:NSString.class] ? (NSString *)arg1 : nil;
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (![self isValidEntryName:name]) {
        [self showMessage:@"名字不能为空，也不能包含 / 或 \\。" title:@"新建 Skill"];
        return;
    }

    NSString *root = [[self codexHome] stringByAppendingPathComponent:@"skills"];
    NSString *directory = [root stringByAppendingPathComponent:name];
    NSString *manifestPath = [directory stringByAppendingPathComponent:@"SKILL.md"];
    NSString *template = [NSString stringWithFormat:
        @"# %@\n\n"
        @"- 用途：说明这个 Skill 解决什么问题。\n"
        @"- 触发条件：当用户提到 … 时使用本 Skill。\n"
        @"- 步骤：\n"
        @"  1. 先确认工作区与目标文件。\n"
        @"  2. 按固定流程执行并输出结果。\n", name];

    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) {
        [self showMessage:[NSString stringWithFormat:@"目录创建失败：%@", error.localizedDescription ?: @"未知错误"]
                    title:@"新建 Skill"];
        return;
    }
    if (![template writeToFile:manifestPath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [self showMessage:[NSString stringWithFormat:@"SKILL.md 写入失败：%@", error.localizedDescription ?: @"未知错误"]
                    title:@"新建 Skill"];
        return;
    }

    CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"skill created name=%@ path=%@", name, manifestPath);
    [self refreshForce:@YES];
    [self showMessage:[NSString stringWithFormat:@"已创建 Skill：%@\n%@", name, manifestPath] title:@"新建 Skill"];
}

#pragma mark - 空态

- (UILabel *)emptyLabel
{
    return _emptyLabel;
}

- (id)emptyText
{
    switch (_kind) {
        case CAComposerCatalogKindSkill:
            return @"还没有安装任何 Skill。点右上角 + 新建。";
        case CAComposerCatalogKindPlugin:
            return @"还没有可用的插件。把插件目录放到 ~/.codex/plugins 下即可出现在这里。";
        case CAComposerCatalogKindMCP:
            return @"还没有配置 MCP 服务。config.toml 里的 [mcp_servers.*] 会显示在这里。";
        case CAComposerCatalogKindPrompt:
            return @"还没有提示词。点右上角 + 新建。";
        case CAComposerCatalogKindMemory:
            return @"还没有记忆条目。";
        default:
            return @"这里还没有内容。";
    }
}

- (void)handleAddPrompt
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新建提示词"
                                                                  message:@"文件会写入 ~/.codex/prompts/<名字>.md"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"例如：review-diff";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf createPromptNamed:alert.textFields.firstObject.text];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleAddSkill
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新建 Skill"
                                                                  message:@"目录会写入 ~/.codex/skills/<名字>/SKILL.md"
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"例如：commit-helper";
        textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf createSkillNamed:alert.textFields.firstObject.text];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 过滤

- (bool)includesItem:(id)arg1
{
    if (![arg1 isKindOfClass:CAComposerCatalogItem.class]) return NO;
    CAComposerCatalogItem *item = (CAComposerCatalogItem *)arg1;
    return item.kind == _kind;
}

- (id)initWithKind:(id)arg1
{
    self = [super init];
    if (self) {
        [self setKind:arg1];
        _sections = @[];
        self.title = [self kindDisplayName];
    }
    return self;
}

#pragma mark - 打开条目

- (void)openItem:(id)arg1
{
    if (![arg1 isKindOfClass:CAComposerCatalogItem.class]) return;
    CAComposerCatalogItem *item = (CAComposerCatalogItem *)arg1;
    NSString *editablePath = [self editableFilePathForItem:item];

    __weak typeof(self) weakSelf = self;
    if (editablePath.length) {
        // 有可编辑文件（SKILL.md / plugin.json / *.md）→ 文本编辑器
        CATextEditorViewController *editor = [[CATextEditorViewController alloc] initWithTitle:item.displayTitle
                                                                                         path:editablePath
                                                                                     template:@""
                                                                                     editable:@YES];
        [editor setOnSaved:^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            [strongSelf refreshForce:@YES];
        }];
        UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:editor];
        [self presentViewController:navigation animated:YES completion:nil];
        return;
    }

    // 目录类 / 纯配置类条目 → 只读详情
    NSString *text = [NSString stringWithFormat:
        @"%@\n\n标识：%@\n类型：%@\n作用域：%@\n启用：%@\n路径：%@\n\n%@",
        item.displayTitle,
        item.identifier ?: @"(无)",
        [CAComposerCatalogItem kindNameForKind:item.kind],
        item.scope.length ? item.scope : @"(未标注)",
        item.enabled ? @"已启用" : @"未启用",
        item.path.length ? item.path : @"(无)",
        item.summary.length ? item.summary : (item.detail ?: @"(无说明)")];
    CATextDetailViewController *detail = [[CATextDetailViewController alloc] initWithTitle:item.displayTitle text:text];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:detail];
    [self presentViewController:navigation animated:YES completion:nil];
}

#pragma mark - 刷新

- (void)pullToRefresh
{
    if (_refreshing) return;
    _refreshing = YES;
    // 下拉刷新不强制打断在途请求
    [self refreshForce:@NO];
}

- (void)refreshForce:(id)arg1
{
    // arg1 为原包占位形参（id）：@YES 表示强制刷新（打断在途请求），@NO / 其它值走普通刷新
    BOOL force = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : YES;
    __weak typeof(self) weakSelf = self;
    [[CAComposerCatalog sharedCatalog] refreshForWorkspace:[self workspace] force:force completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            if (error) {
                CALog(CALogLevelWarn, @"CHAT-PLUGIN", @"extension list refresh failed kind=%@ error=%@",
                      [CAComposerCatalogItem kindNameForKind:strongSelf->_kind], error.localizedDescription ?: @"未知错误");
            }
            [strongSelf endRefreshing];
            // 刷新完成统一回主线程走 catalogDidChange（内部 rebuildSections）
            [strongSelf catalogDidChange];
        });
    }];
}

- (void)rebuildSections
{
    NSMutableArray<CAComposerCatalogItem *> *enabled = [NSMutableArray array];
    NSMutableArray<CAComposerCatalogItem *> *disabled = [NSMutableArray array];
    for (id raw in [CAComposerCatalog sharedCatalog].items) {
        if (![self includesItem:raw]) continue;
        CAComposerCatalogItem *item = (CAComposerCatalogItem *)raw;
        if (item.enabled) [enabled addObject:item];
        else [disabled addObject:item];
    }

    NSMutableArray<NSDictionary *> *sections = [NSMutableArray array];
    if (enabled.count) [sections addObject:@{ @"title": @"已启用", @"items": enabled }];
    if (disabled.count) [sections addObject:@{ @"title": @"未启用", @"items": disabled }];

    [self setSections:sections];
    [_tableView reloadData];
    [self updateEmptyState];
}

#pragma mark - 数据

- (NSArray *)sections
{
    return _sections;
}

- (id)symbolName
{
    switch (_kind) {
        case CAComposerCatalogKindSkill:  return @"sparkles";
        case CAComposerCatalogKindPlugin: return @"shippingbox";
        case CAComposerCatalogKindMCP:    return @"server.rack";
        case CAComposerCatalogKindPrompt: return @"text.badge.plus";
        case CAComposerCatalogKindMemory: return @"brain";
        default:                          return @"square.grid.2x2";
    }
}

#pragma mark - getter / setter

- (void)setEmptyLabel:(id)arg1
{
    _emptyLabel = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil;
}

- (void)setKind:(id)arg1
{
    // kind 支持三种入参：CAComposerCatalogKind 数值（NSNumber）、种类名（skill / plugin / mcp / prompt / memory）
    // 以及 nil（缺省落到 Skill）。数值 0 在枚举里是 Unknown，这里按「未指定」处理为 Skill。
    if ([arg1 isKindOfClass:NSNumber.class]) {
        NSInteger value = [(NSNumber *)arg1 integerValue];
        _kind = value > 0 ? (CAComposerCatalogKind)value : CAComposerCatalogKindSkill;
    } else if ([arg1 isKindOfClass:NSString.class]) {
        _kind = [CAComposerCatalogItem kindForName:(NSString *)arg1];
    } else if (arg1 == nil) {
        _kind = CAComposerCatalogKindSkill;
    }
}

- (void)setSections:(id)arg1
{
    _sections = [arg1 isKindOfClass:NSArray.class] ? [(NSArray *)arg1 copy] : @[];
}

- (void)setTableView:(id)arg1
{
    _tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : nil;
}

- (signed long long)kind
{
    return (signed long long)_kind;
}

- (UITableView *)tableView
{
    return _tableView;
}

#pragma mark - UITableViewDataSource

- (signed long long)numberOfSectionsInTableView:(id)arg1
{
    return (signed long long)_sections.count;
}

- (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2
{
    NSInteger section = [arg2 respondsToSelector:@selector(integerValue)] ? [arg2 integerValue] : 0;
    if (section < 0 || (NSUInteger)section >= _sections.count) return 0;
    NSArray *items = _sections[(NSUInteger)section][@"items"];
    return (signed long long)items.count;
}

- (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : _tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    if (!tableView || !indexPath) return nil;

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCAExtensionListCellIdentifier forIndexPath:indexPath];
    CAComposerCatalogItem *item = [self itemAtIndexPath:indexPath];
    if (!item) return cell;

    cell.textLabel.text = item.displayTitle;
    cell.detailTextLabel.text = item.summary.length ? item.summary : item.identifier;
    cell.detailTextLabel.numberOfLines = 2;
    cell.imageView.image = [UIImage systemImageNamed:self.symbolName];
    cell.imageView.tintColor = item.enabled ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    UISwitch *toggle = [[UISwitch alloc] init];
    toggle.on = item.enabled;
    toggle.tag = indexPath.section * 1000 + indexPath.row;
    [toggle addTarget:self action:@selector(handleSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2
{
    UITableView *tableView = [arg1 isKindOfClass:UITableView.class] ? (UITableView *)arg1 : _tableView;
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    if (tableView && indexPath) [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self openItem:[self itemAtIndexPath:indexPath]];
}

- (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2
{
    NSInteger section = [arg2 respondsToSelector:@selector(integerValue)] ? [arg2 integerValue] : 0;
    if (section != (NSInteger)_sections.count - 1) return nil;

    NSString *home = [self codexHome];
    switch (_kind) {
        case CAComposerCatalogKindSkill:
            return [NSString stringWithFormat:@"本地 Skill 目录：%@/skills（工作区侧：%@/.codex/skills）。左滑可删除。",
                    home, [self workspace]];
        case CAComposerCatalogKindMCP:
            return [NSString stringWithFormat:@"开关会改写 config.toml 里的 [mcp_servers.<名字>].enabled（%@）。",
                    [CARuntimePaths configTOMLPath]];
        case CAComposerCatalogKindPrompt:
            return [NSString stringWithFormat:@"提示词目录：%@/prompts。左滑可删除。", home];
        case CAComposerCatalogKindPlugin:
            return [NSString stringWithFormat:@"插件目录：%@/plugins。左滑可删除本地插件。", home];
        case CAComposerCatalogKindMemory:
            return @"记忆条目由会话自动生成，仅在此查看。";
        default:
            return nil;
    }
}

- (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2
{
    NSInteger section = [arg2 respondsToSelector:@selector(integerValue)] ? [arg2 integerValue] : 0;
    return [self sectionTitleAtIndex:section];
}

- (id)tableView:(id)arg1 trailingSwipeActionsConfigurationForRowAtIndexPath:(id)arg2
{
    NSIndexPath *indexPath = [arg2 isKindOfClass:NSIndexPath.class] ? (NSIndexPath *)arg2 : nil;
    CAComposerCatalogItem *item = [self itemAtIndexPath:indexPath];
    if (!item) return nil;

    BOOL canRemove = NO;
    switch (item.kind) {
        case CAComposerCatalogKindSkill:
        case CAComposerCatalogKindPrompt:
            canRemove = YES;
            break;
        case CAComposerCatalogKindMCP:
            canRemove = [self isLocallyManagedMCP:item.name];
            break;
        case CAComposerCatalogKindPlugin:
            // 本地插件（~/.codex/plugins/<名字>）允许删除；server 侧插件不可删
            canRemove = [self isLocallyManagedSkill:item.path];
            break;
        default:
            canRemove = NO;
            break;
    }
    if (!canRemove) return nil;

    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                         title:@"删除"
                                                                       handler:^(UIContextualAction *action, UIView *sourceView, void (^completionHandler)(BOOL)) {
        if (item.kind == CAComposerCatalogKindMCP) {
            [self confirmRemoveMCP:item];
        } else if (item.kind == CAComposerCatalogKindPrompt) {
            [self confirmRemovePrompt:item];
        } else {
            [self confirmRemoveSkill:item];
        }
        if (completionHandler) completionHandler(YES);
    }];
    remove.image = [UIImage systemImageNamed:@"trash"];

    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[ remove ]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}

#pragma mark - 主题

- (void)themeDidChange
{
    // 系统语义色：浅色 / 深色自动跟随，无需硬编码
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _tableView.separatorColor = UIColor.separatorColor;
    _emptyLabel.textColor = UIColor.secondaryLabelColor;
    [_tableView reloadData];
}

#pragma mark - 生命周期

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = [self kindDisplayName];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.rowHeight = UITableViewAutomaticDimension;
    _tableView.estimatedRowHeight = 64.0;
    [_tableView registerClass:CAExtensionListValueCell.class forCellReuseIdentifier:kCAExtensionListCellIdentifier];
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    _refreshControl = [[UIRefreshControl alloc] init];
    _refreshControl.tintColor = UIColor.secondaryLabelColor;
    [_refreshControl addTarget:self action:@selector(pullToRefresh) forControlEvents:UIControlEventValueChanged];
    _tableView.refreshControl = _refreshControl;

    // 关闭 / 新建
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(handleClose)];
    if (_kind == CAComposerCatalogKindSkill) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                              target:self
                                                                                              action:@selector(handleAddSkill)];
    } else if (_kind == CAComposerCatalogKindPrompt) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                              target:self
                                                                                              action:@selector(handleAddPrompt)];
    }

    // 空态文案（-emptyText 按 kind 给出中文说明）
    _emptyLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _emptyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    _emptyLabel.hidden = YES;
    [self.view addSubview:_emptyLabel];
    [NSLayoutConstraint activateConstraints:@[
        [_emptyLabel.leadingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.leadingAnchor],
        [_emptyLabel.trailingAnchor constraintEqualToAnchor:self.view.layoutMarginsGuide.trailingAnchor],
        [_emptyLabel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
    ]];
    [self setEmptyLabel:_emptyLabel];

    if (!_observerInstalled) {
        _observerInstalled = YES;
        // 原包通知名即 CAComposerCatalog.h 里导出的 CAComposerCatalogDidChangeNotification
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(catalogDidChangeNotification:)
                                                     name:CAComposerCatalogDidChangeNotification
                                                   object:nil];
    }

    [self themeDidChange];
    [self rebuildSections];
    [self refreshForce:@YES];
}

- (void)viewWillAppear:(id)arg1
{
    BOOL animated = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : YES;
    [super viewWillAppear:animated];
    [self rebuildSections];
}

#pragma mark - 私有辅助实现

- (CAComposerCatalogItem *)itemAtIndexPath:(NSIndexPath *)indexPath
{
    if (!indexPath) return nil;
    if (indexPath.section < 0 || (NSUInteger)indexPath.section >= _sections.count) return nil;
    NSArray *items = _sections[(NSUInteger)indexPath.section][@"items"];
    if (indexPath.row < 0 || (NSUInteger)indexPath.row >= items.count) return nil;
    id item = items[(NSUInteger)indexPath.row];
    return [item isKindOfClass:CAComposerCatalogItem.class] ? (CAComposerCatalogItem *)item : nil;
}

- (NSString *)sectionTitleAtIndex:(NSInteger)section
{
    if (section < 0 || (NSUInteger)section >= _sections.count) return nil;
    return _sections[(NSUInteger)section][@"title"];
}

- (NSString *)kindDisplayName
{
    switch (_kind) {
        case CAComposerCatalogKindSkill:  return @"Skills";
        case CAComposerCatalogKindPlugin: return @"插件";
        case CAComposerCatalogKindMCP:    return @"MCP 服务";
        case CAComposerCatalogKindPrompt: return @"提示词";
        case CAComposerCatalogKindMemory: return @"记忆";
        default:                          return @"Skills 与扩展";
    }
}

- (BOOL)isValidEntryName:(NSString *)name
{
    if (!name.length) return NO;
    if ([name containsString:@"/"] || [name containsString:@"\\"]) return NO;
    if ([name hasPrefix:@"."]) return NO;
    if ([name isEqualToString:@"."] || [name isEqualToString:@".."]) return NO;
    return YES;
}

- (NSString *)removalTargetPathForItem:(CAComposerCatalogItem *)item
{
    NSString *path = [self editableFilePathForItem:item];
    if (!path.length) path = item.path;
    if (!path.length) return nil;

    BOOL isDirectory = NO;
    if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory) return path;
    NSString *parent = path.stringByDeletingLastPathComponent;
    return parent.length ? parent : path;
}

- (void)handleClose
{
    UINavigationController *navigation = self.navigationController;
    if (navigation && navigation.viewControllers.firstObject != self) {
        [navigation popViewControllerAnimated:YES];
        return;
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)handleSwitchChanged:(UISwitch *)sender
{
    NSInteger identifier = sender.tag;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:identifier % 1000 inSection:identifier / 1000];
    CAComposerCatalogItem *item = [self itemAtIndexPath:indexPath];
    if (!item) return;

    BOOL enabled = sender.isOn;
    switch (item.kind) {
        case CAComposerCatalogKindSkill:
            [self applySkill:item enabled:@(enabled) toggle:sender];
            break;
        case CAComposerCatalogKindMCP:
            [self applyMCPServer:item enabled:@(enabled) toggle:sender];
            break;
        default:
            // 其余 kind（插件 / 提示词 / 记忆）原包没有独立开关接口，只维护本地状态
            item.enabled = enabled;
            [self rebuildSections];
            break;
    }
    CALog(CALogLevelInfo, @"CHAT-PLUGIN", @"extension toggle kind=%@ name=%@ enabled=%d",
          [CAComposerCatalogItem kindNameForKind:item.kind], item.name ?: item.identifier, enabled ? 1 : 0);
}

- (void)endRefreshing
{
    _refreshing = NO;
    [_refreshControl endRefreshing];
}

- (void)updateEmptyState
{
    NSUInteger total = 0;
    for (NSDictionary *section in _sections) {
        total += [section[@"items"] count];
    }
    _emptyLabel.text = [self emptyText];
    _emptyLabel.hidden = total > 0;
}

- (void)showMessage:(NSString *)message title:(NSString *)title
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
