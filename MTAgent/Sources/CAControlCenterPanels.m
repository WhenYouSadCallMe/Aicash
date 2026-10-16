//
//  CAControlCenterPanels.m — 复刻补全面板的构造函数与入口注册
//
//  设计：
//    · 每个面板一个工厂方法，内部准备好默认数据源（工作区 / 真实文件 / 演示数据），
//      调用方（会话页 / 设置页各行的面板）拿到的都是「拿来即用」的控制器；
//    · CAControlCenterViewController 是面板中心列表本身（本文件私有类，**不从设置页暴露**），
//      分组照原包的信息架构：仓库与变更 / 模型 / 扩展与指令 / 计划与审批 / 存储与设置 / 文本与外壳。
//

#import "CAControlCenterPanels.h"

#import "CAGitChangesViewController.h"
#import "CAModelPickerViewController.h"
#import "CAModelPricingViewController.h"
#import "CAAgentProfileViewController.h"
#import "CAAgentStatusDetailViewController.h"
#import "CAArtifactPreviewViewController.h"
#import "CAExtensionListViewController.h"
#import "CAExtensionsViewController.h"
#import "CAPathPickerViewController.h"
#import "CAPlanDecisionViewController.h"
#import "CAPlanReviewViewController.h"
#import "CAProjectInstructionsViewController.h"
#import "CAStorageViewController.h"
#import "CASubagentSettingsViewController.h"
#import "CATextDetailViewController.h"
#import "CATextEditorViewController.h"
#import "CARootViewController.h"
#import "CAComposerCatalog.h"
#import "CARuntimePaths.h"
#import "CACommon.h"

#pragma mark - 面板中心列表

/// 一行入口：标题 + 副标题 + 图标 + 构造函数
@interface CAPanelCenterRow : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) UIViewController * (^maker)(void);
+ (instancetype)rowWithTitle:(NSString *)title subtitle:(NSString *)subtitle symbol:(NSString *)symbol maker:(UIViewController * (^)(void))maker;
@end

@implementation CAPanelCenterRow

+ (instancetype)rowWithTitle:(NSString *)title subtitle:(NSString *)subtitle symbol:(NSString *)symbol maker:(UIViewController * (^)(void))maker
{
    CAPanelCenterRow *row = [[CAPanelCenterRow alloc] init];
    row.title = title;
    row.subtitle = subtitle;
    row.symbol = symbol;
    row.maker = maker;
    return row;
}

@end

#pragma mark - 面板中心控制器

@interface CAControlCenterViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy, nullable) NSString *workspacePath;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSArray *> *sections;
@end

@implementation CAControlCenterViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"面板中心";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark.circle.fill"]
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(ca_close)];
    close.tintColor = UIColor.tertiaryLabelColor;
    self.navigationItem.leftBarButtonItem = close;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 52.0;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"CAControlCenterCell"];
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    [self ca_buildSections];
}

- (void)ca_buildSections
{
    NSString *workspace = self.workspacePath;
    __weak typeof(self) weakSelf = self;

    NSArray<CAPanelCenterRow *> *repository = @[
        [CAPanelCenterRow rowWithTitle:@"Git 变更" subtitle:@"暂存 / 提交 / 分支 / 远程" symbol:@"arrow.triangle.branch" maker:^UIViewController *{
            __strong typeof(weakSelf) self = weakSelf;
            return [CAControlCenterPanels gitChangesViewControllerForWorkspace:self.workspacePath];
        }],
        [CAPanelCenterRow rowWithTitle:@"项目指令" subtitle:@"每个工作区的 AGENTS.md" symbol:@"doc.text" maker:^UIViewController *{
            return [CAControlCenterPanels projectInstructionsViewController];
        }],
        [CAPanelCenterRow rowWithTitle:@"目录选择器" subtitle:@"在应用内浏览并选择文件夹" symbol:@"folder" maker:^UIViewController *{
            return [CAControlCenterPanels pathPickerViewControllerFrom:nil onSelect:nil];
        }],
        [CAPanelCenterRow rowWithTitle:@"产物预览" subtitle:@"图片 / 文本 / 音频视频 / QuickLook" symbol:@"doc.richtext" maker:^UIViewController *{
            return [CAControlCenterPanels artifactPreviewViewControllerForPath:nil];
        }],
    ];

    NSArray<CAPanelCenterRow *> *models = @[
        [CAPanelCenterRow rowWithTitle:@"模型选择" subtitle:@"官方与第三方模型列表" symbol:@"cpu" maker:^UIViewController *{
            return [CAControlCenterPanels modelPickerViewControllerWithSelection:nil];
        }],
        [CAPanelCenterRow rowWithTitle:@"模型价格" subtitle:@"输入/输出单价与汇率" symbol:@"dollarsign.circle" maker:^UIViewController *{
            return [CAControlCenterPanels modelPricingViewController];
        }],
        [CAPanelCenterRow rowWithTitle:@"子代理设置" subtitle:@"模型与思考强度" symbol:@"person.2" maker:^UIViewController *{
            return [CAControlCenterPanels subagentSettingsViewController];
        }],
    ];

    NSArray<CAPanelCenterRow *> *extensions = @[
        [CAPanelCenterRow rowWithTitle:@"Skills 与扩展" subtitle:@"指令、Skills、提示词与插件" symbol:@"puzzlepiece.extension" maker:^UIViewController *{
            return [CAControlCenterPanels extensionsViewController];
        }],
        [CAPanelCenterRow rowWithTitle:@"Skills 列表" subtitle:@"安装、启用与新建 Skill" symbol:@"sparkles" maker:^UIViewController *{
            return [CAControlCenterPanels extensionListViewControllerWithKind:@"skill"];
        }],
        [CAPanelCenterRow rowWithTitle:@"MCP 服务" subtitle:@"本地与远端 MCP 开关" symbol:@"server.rack" maker:^UIViewController *{
            return [CAControlCenterPanels extensionListViewControllerWithKind:@"mcp"];
        }],
        [CAPanelCenterRow rowWithTitle:@"提示词" subtitle:@"prompts 目录下的片段" symbol:@"text.badge.plus" maker:^UIViewController *{
            return [CAControlCenterPanels extensionListViewControllerWithKind:@"prompt"];
        }],
    ];

    NSArray<CAPanelCenterRow *> *plan = @[
        [CAPanelCenterRow rowWithTitle:@"计划审阅" subtitle:@"批准并执行 / 编辑计划" symbol:@"list.bullet.clipboard" maker:^UIViewController *{
            return [CAControlCenterPanels planReviewDemoViewController];
        }],
        [CAPanelCenterRow rowWithTitle:@"审批对话框" subtitle:@"允许 / 拒绝 / 允许并记住" symbol:@"checkmark.shield" maker:^UIViewController *{
            return [CAControlCenterPanels planDecisionDemoViewController];
        }],
        [CAPanelCenterRow rowWithTitle:@"Agent 身份" subtitle:@"显示名与身份说明" symbol:@"sparkles" maker:^UIViewController *{
            return [CAControlCenterPanels agentProfileViewController];
        }],
        [CAPanelCenterRow rowWithTitle:@"Agent 状态" subtitle:@"运行状态、模型、上下文占用" symbol:@"waveform.path.ecg" maker:^UIViewController *{
            return [CAControlCenterPanels agentStatusDetailViewController];
        }],
    ];

    NSArray<CAPanelCenterRow *> *storage = @[
        [CAPanelCenterRow rowWithTitle:@"存储管理" subtitle:@"安全清理缓存与运行时下载" symbol:@"externaldrive" maker:^UIViewController *{
            return [CAControlCenterPanels storageViewController];
        }],
        [CAPanelCenterRow rowWithTitle:@"设置" subtitle:@"账号、Provider、运行时与诊断" symbol:@"gearshape" maker:^UIViewController *{
            Class settingsClass = NSClassFromString(@"CASettingsViewController");
            return settingsClass ? (UIViewController *)[[settingsClass alloc] init] : nil;
        }],
        [CAPanelCenterRow rowWithTitle:@"应用外壳" subtitle:@"会话 / 设置 / 诊断 三入口容器" symbol:@"rectangle.3.group" maker:^UIViewController *{
            return [CAControlCenterPanels rootShellViewController];
        }],
        [CAPanelCenterRow rowWithTitle:@"文本编辑器" subtitle:@"打开工作区里的 AGENTS.md" symbol:@"square.and.pencil" maker:^UIViewController *{
            NSString *workspace = self.workspacePath ?: [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsActiveWorkspace] ?: CARuntimePaths.documentsCodexDirectory;
            return [CAControlCenterPanels textEditorViewControllerForPath:[workspace stringByAppendingPathComponent:@"AGENTS.md"] title:@"项目指令"];
        }],
    ];

    self.sections = @[
        @[ @"仓库与变更", repository ],
        @[ @"模型", models ],
        @[ @"扩展与指令", extensions ],
        @[ @"计划与 Agent", plan ],
        @[ @"存储与外壳", storage ],
    ];
    [self.tableView reloadData];
}

#pragma mark - 表格

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section < 0 || section >= (NSInteger)self.sections.count) {
        return 0;
    }
    return [(NSArray *)self.sections[section][1] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (section < 0 || section >= (NSInteger)self.sections.count) {
        return nil;
    }
    return self.sections[section][0];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return section == (NSInteger)self.sections.count - 1 ? @"这些面板在原包里分别由会话页与设置页打开，此处集中提供入口。" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CAControlCenterCell" forIndexPath:indexPath];
    CAPanelCenterRow *row = self.sections[indexPath.section][1][indexPath.row];

    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = row.title;
    content.secondaryText = row.subtitle;
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.image = [UIImage systemImageNamed:row.symbol];
    content.imageProperties.tintColor = UIColor.systemBlueColor;
    cell.contentConfiguration = content;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    CAPanelCenterRow *row = self.sections[indexPath.section][1][indexPath.row];
    UIViewController *panel = row.maker ? row.maker() : nil;
    if (panel == nil) {
        return;
    }
    [self.navigationController pushViewController:panel animated:YES];
}

- (void)ca_close
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

#pragma mark - 统一入口

@implementation CAControlCenterPanels

+ (UIViewController *)gitChangesViewControllerForWorkspace:(NSString *)workspacePath
{
    NSString *workspace = workspacePath.length > 0
        ? workspacePath
        : ([NSUserDefaults.standardUserDefaults stringForKey:CADefaultsActiveWorkspace] ?: CARuntimePaths.documentsCodexDirectory);
    return [[CAGitChangesViewController alloc] initWithWorkspacePath:workspace];
}

+ (UIViewController *)modelPickerViewControllerWithSelection:(void (^)(NSString *, BOOL))selection
{
    CAModelPickerViewController *picker = [[CAModelPickerViewController alloc] init];
    if (selection) {
        [picker setOnModelSelected:selection];
    }
    return picker;
}

+ (UIViewController *)modelPricingViewController
{
    return [[CAModelPricingViewController alloc] init];
}

+ (UIViewController *)agentProfileViewController
{
    return [[CAAgentProfileViewController alloc] init];
}

+ (UIViewController *)agentStatusDetailViewController
{
    return [[CAAgentStatusDetailViewController alloc] initWithSnapshot:nil];
}

+ (UIViewController *)artifactPreviewViewControllerForPath:(NSString *)path
{
    NSString *resolved = path;
    if (resolved.length == 0) {
        // 挑一个一定存在的本地文件：config.toml → 版本文件 → 首选项 plist
        NSArray<NSString *> *candidates = @[
            CARuntimePaths.configTOMLPath,
            [CARuntimePaths.codexHome stringByAppendingPathComponent:@"version.json"],
            CARuntimePaths.preferencesPlistPath,
        ];
        for (NSString *candidate in candidates) {
            if (candidate.length > 0 && [NSFileManager.defaultManager fileExistsAtPath:candidate]) {
                resolved = candidate;
                break;
            }
        }
    }
    if (resolved.length == 0) {
        resolved = CARuntimePaths.preferencesPlistPath;
    }
    return [[CAArtifactPreviewViewController alloc] initWithPath:resolved];
}

+ (UIViewController *)extensionListViewControllerWithKind:(NSString *)kindName
{
    CAComposerCatalogKind kind = CAComposerCatalogKindSkill;
    NSString *name = kindName.lowercaseString;
    if ([name isEqualToString:@"mcp"]) {
        kind = CAComposerCatalogKindMCP;
    } else if ([name isEqualToString:@"prompt"] || [name isEqualToString:@"prompts"]) {
        kind = CAComposerCatalogKindPrompt;
    } else if ([name isEqualToString:@"plugin"]) {
        kind = CAComposerCatalogKindPlugin;
    } else if ([name isEqualToString:@"memory"]) {
        kind = CAComposerCatalogKindMemory;
    }
    return [[CAExtensionListViewController alloc] initWithKind:@(kind)];
}

+ (UIViewController *)extensionsViewController
{
    return [[CAExtensionsViewController alloc] init];
}

+ (UIViewController *)pathPickerViewControllerFrom:(NSString *)path onSelect:(void (^)(NSString *))onSelect
{
    CAPathPickerViewController *picker = [[CAPathPickerViewController alloc] initWithPath:(path.length > 0 ? path : CARuntimePaths.documentsDirectory)];
    if (onSelect) {
        picker.onDirectorySelected = onSelect;
    }
    return picker;
}

+ (UIViewController *)planDecisionDemoViewController
{
    // 结构与 codex app-server 的 item/tool/requestUserInput 一致：questions[{id,header,question,options}]
    NSArray<NSDictionary *> *questions = @[
        @{
            @"id": @"approve_exec",
            @"header": @"需要确认",
            @"question": @"Agent 想在工作区里执行以下命令：rm -rf build/，是否允许？",
            @"options": @[
                @{ @"label": @"允许", @"description": @"仅本次执行" },
                @{ @"label": @"拒绝", @"description": @"跳过这一步" },
                @{ @"label": @"允许并记住", @"description": @"本会话内不再询问同类命令" },
            ],
        },
        @{
            @"id": @"api_key",
            @"header": @"凭据",
            @"question": @"请输入第三方服务的访问令牌。",
            @"secret": @YES,
        },
        @{
            @"id": @"note",
            @"header": @"补充说明",
            @"question": @"对这次改动还有什么要求？（可留空）",
            @"freeform": @YES,
        },
    ];

    return [[CAPlanDecisionViewController alloc] initWithQuestions:questions completion:^(BOOL approved, NSDictionary *answers, BOOL remember) {
        NSString *detail = [NSString stringWithFormat:@"approved=%@ remember=%@\n%@",
                            approved ? @"YES" : @"NO",
                            remember ? @"YES" : @"NO",
                            answers.description ?: @"{}"];
        NSLog(@"[CAControlCenter] plan decision: %@", detail);
    }];
}

+ (UIViewController *)planReviewDemoViewController
{
    NSString *plan =
        @"# 计划：给会话页补上 Git 角标\n"
        @"\n"
        @"1. 读 defaults CodexActiveWorkspace 确定仓库根；\n"
        @"2. 用 CAGitRepository 每 5 秒读一次变更数；\n"
        @"3. 顶栏右上角渲染红色角标（>99 显示 99+）；\n"
        @"4. 点角标打开 CAGitChangesViewController。\n"
        @"\n"
        @"```sh\n"
        @"# 验证\n"
        @"git status --porcelain | wc -l\n"
        @"```\n";
    return [[CAPlanReviewViewController alloc] initWithPlan:plan onEdit:^(NSString *editedPlan) {
        NSLog(@"[CAControlCenter] plan edited: %lu chars", (unsigned long)editedPlan.length);
    } onApprove:^(NSString *approvedPlan) {
        NSLog(@"[CAControlCenter] plan approved: %lu chars", (unsigned long)approvedPlan.length);
    }];
}

+ (UIViewController *)projectInstructionsViewController
{
    return [[CAProjectInstructionsViewController alloc] init];
}

+ (UIViewController *)storageViewController
{
    return [[CAStorageViewController alloc] init];
}

+ (UIViewController *)subagentSettingsViewController
{
    return [[CASubagentSettingsViewController alloc] init];
}

+ (UIViewController *)textDetailViewControllerWithTitle:(NSString *)title text:(NSString *)text
{
    return [[CATextDetailViewController alloc] initWithTitle:title text:text];
}

+ (UIViewController *)textEditorViewControllerForPath:(NSString *)path title:(NSString *)title
{
    NSString *resolved = path;
    if (resolved.length == 0) {
        resolved = [CARuntimePaths.documentsCodexDirectory stringByAppendingPathComponent:@"AGENTS.md"];
    }
    NSString *template = @"# 项目指令\n\n- 用简体中文回复。\n- 改动前先读现有实现，不要凭猜测改接口。\n";
    return [[CATextEditorViewController alloc] initWithTitle:(title.length > 0 ? title : @"文本编辑")
                                                        path:resolved
                                                    template:template
                                                    editable:@YES];
}

+ (UIViewController *)rootShellViewController
{
    return [CARootViewController launcherRootViewController];
}

+ (UIViewController *)panelCenterViewControllerForWorkspace:(NSString *)workspacePath
{
    CAControlCenterViewController *center = [[CAControlCenterViewController alloc] init];
    center.workspacePath = workspacePath.length > 0
        ? workspacePath
        : [NSUserDefaults.standardUserDefaults stringForKey:CADefaultsActiveWorkspace];
    return center;
}

+ (void)presentPanel:(UIViewController *)panel from:(UIViewController *)host
{
    if (panel == nil || host == nil) {
        return;
    }
    if (host.navigationController != nil) {
        [host.navigationController pushViewController:panel animated:YES];
        return;
    }
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:panel];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    [host presentViewController:navigation animated:YES completion:nil];
}

@end
