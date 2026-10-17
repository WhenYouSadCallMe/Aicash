//
//  CAReasoningEffortViewController.m
//  「模型与思考强度」面板：原版文案「思考等级：%@」「0 = 服务默认」
//

#import "CAReasoningEffortViewController.h"
#import "CAModelPricingManager.h"

static NSString * const kCAEffortCellId = @"CAEffortCell";

@interface CAReasoningEffortViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation CAReasoningEffortViewController

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = @"模型与思考强度";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 52.0;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:kCAEffortCellId];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose
                                                      target:self
                                                      action:@selector(handleClose)];
}

- (void)handleClose
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return (NSInteger)self.levels.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"思考强度";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    return @"默认跟随当前对话的主代理。修改后下一轮子代理使用新设置；0 = 服务默认。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCAEffortCellId forIndexPath:indexPath];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCAEffortCellId];

    NSString *level = (indexPath.row < (NSInteger)self.levels.count) ? self.levels[(NSUInteger)indexPath.row] : @"";
    NSString *title = [CAThirdPartyModelCatalog reasoningLevelTitle:level] ?: level;
    cell.textLabel.text = title;
    cell.textLabel.font = [UIFont systemFontOfSize:16.0];
    cell.detailTextLabel.text = [level isEqualToString:@"auto"] ? @"0 = 服务默认" : nil;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;

    BOOL selected = (self.selectedLevel.length > 0 && [level isEqualToString:self.selectedLevel]);
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.textLabel.textColor = selected ? UIColor.systemBlueColor : UIColor.labelColor;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.levels.count) return;

    NSString *level = self.levels[(NSUInteger)indexPath.row];
    self.selectedLevel = level;
    [tableView reloadData];

    if (self.onLevelSelected) self.onLevelSelected(level);
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
