//
//  MTShareExtension.m — 分享扩展（原包：CAMTShareViewController / CAMTShareInbox / CAMTShareGroup /
//                        MTShareActiveConversation）
//  行为：把图片/文件/视频写入 app group 的 Inbox，并把「当前会话 + 附件清单」写入共享 defaults，
//        由主 app 启动时读取（原包符号：CAMTShareGroup、CAMTShareInbox、MTShareActiveConversation）。
//

#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const CAMTShareGroupIdentifier      = @"group.wiki.qaq.codexapp";
static NSString *const CAMTShareInboxDirectoryName   = @"CodexAttachments/Inbox";
static NSString *const CAMTShareActiveConversationKey = @"MTShareActiveConversation";
static NSString *const CAMTSharePendingItemsKey      = @"MTSharePendingItems";

#pragma mark - CAMTShareGroup

@interface CAMTShareGroup : NSObject
+ (nullable NSURL *)containerURL;
+ (NSString *)inboxPath;
+ (NSUserDefaults *)sharedDefaults;
@end

@implementation CAMTShareGroup

+ (NSURL *)containerURL
{
    return [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:CAMTShareGroupIdentifier];
}

+ (NSString *)inboxPath
{
    NSURL *container = [self containerURL];
    NSString *base = container.path ?: NSTemporaryDirectory();
    return [base stringByAppendingPathComponent:CAMTShareInboxDirectoryName];
}

+ (NSUserDefaults *)sharedDefaults
{
    return [[NSUserDefaults alloc] initWithSuiteName:CAMTShareGroupIdentifier] ?: NSUserDefaults.standardUserDefaults;
}

@end

#pragma mark - CAMTShareInbox

@interface CAMTShareInbox : NSObject
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;
- (void)addItemWithSuggestedName:(NSString *)name filenameExtension:(NSString *)extension;
- (NSArray<NSDictionary *> *)persist:(NSError **)error;
@end

@implementation CAMTShareInbox

- (instancetype)init
{
    if ((self = [super init])) _items = [NSMutableArray array];
    return self;
}

- (void)addItemWithSuggestedName:(NSString *)name filenameExtension:(NSString *)extension
{
    NSMutableDictionary *item = [NSMutableDictionary dictionary];
    item[@"suggestedName"] = name ?: @"attachment";
    item[@"extension"] = extension ?: @"";
    item[@"createdAt"] = @([[NSDate date] timeIntervalSince1970]);
    [_items addObject:item];
}

- (NSArray<NSDictionary *> *)persist:(NSError **)error
{
    NSString *inbox = [CAMTShareGroup inboxPath];
    [[NSFileManager defaultManager] createDirectoryAtPath:inbox withIntermediateDirectories:YES
                                              attributes:@{ NSFilePosixPermissions: @(0755) } error:error];
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.items options:NSJSONWritingPrettyPrinted error:error];
    NSString *manifest = [inbox stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"%@.json", NSUUID.UUID.UUIDString]];
    [data writeToFile:manifest options:NSDataWritingAtomic error:error];
    [[CAMTShareGroup sharedDefaults] setObject:manifest forKey:CAMTSharePendingItemsKey];
    [[CAMTShareGroup sharedDefaults] synchronize];
    return self.items;
}

@end

#pragma mark - CAMTShareViewController

@interface CAMTShareViewController : UIViewController
@property (nonatomic, strong) CAMTShareInbox *inbox;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *sendButton;
- (void)loadInputItems;
- (void)handleSend:(id)sender;
- (void)handleCancel:(id)sender;
- (void)finishWithSuccess:(BOOL)success;
@end

@implementation CAMTShareViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.inbox = [CAMTShareInbox new];

    self.titleLabel = [UILabel new];
    self.titleLabel.text = @"MT 智能体";
    self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.titleLabel];

    self.sendButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.sendButton setTitle:@"发送到 MT 智能体" forState:UIControlStateNormal];
    [self.sendButton addTarget:self action:@selector(handleSend:) forControlEvents:UIControlEventTouchUpInside];
    self.sendButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.sendButton];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:@"取消" forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(handleCancel:) forControlEvents:UIControlEventTouchUpInside];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:cancel];

    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.sendButton.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.sendButton.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [cancel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [cancel.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
    ]];
    [self loadInputItems];
}

- (void)loadInputItems
{
    for (NSExtensionItem *item in self.extensionContext.inputItems) {
        for (NSItemProvider *provider in item.attachments ?: @[]) {
            NSString *identifier = provider.registeredTypeIdentifiers.firstObject;
            NSString *extension = identifier ? [UTType typeWithIdentifier:identifier].preferredFilenameExtension : @"";
            NSString *name = provider.suggestedName ?: @"attachment";
            [self.inbox addItemWithSuggestedName:name filenameExtension:extension];
            if ([provider hasItemConformingToTypeIdentifier:UTTypeImage.identifier] ||
                [provider hasItemConformingToTypeIdentifier:UTTypeFileURL.identifier] ||
                [provider hasItemConformingToTypeIdentifier:UTTypeMovie.identifier]) {
                [provider loadFileRepresentationForTypeIdentifier:identifier completionHandler:^(NSURL *url, NSError *error) {
                    if (!url) return;
                    NSString *inbox = [CAMTShareGroup inboxPath];
                    [[NSFileManager defaultManager] createDirectoryAtPath:inbox withIntermediateDirectories:YES
                                                              attributes:@{ NSFilePosixPermissions: @(0755) } error:NULL];
                    NSString *target = [inbox stringByAppendingPathComponent:url.lastPathComponent];
                    [[NSFileManager defaultManager] removeItemAtPath:target error:NULL];
                    [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:target] error:NULL];
                }];
            }
        }
    }
}

- (void)handleSend:(id)sender
{
    [self.inbox persist:NULL];
    [[CAMTShareGroup sharedDefaults] setObject:@([[NSDate date] timeIntervalSince1970]) forKey:CAMTShareActiveConversationKey];
    [self finishWithSuccess:YES];
}

- (void)handleCancel:(id)sender { [self finishWithSuccess:NO]; }

- (void)finishWithSuccess:(BOOL)success
{
    NSError *error = success ? nil : [NSError errorWithDomain:@"wiki.qaq.codexapp.share" code:1 userInfo:nil];
    [self.extensionContext completeRequestReturningItems:@[] completionHandler:nil];
    (void)error;
}

@end
