//
//  CATextEditorViewController.m — 文本文件编辑器（真实界面实现）
//
//  initWithTitle:path:template:editable:
//    · 后台读文件（NSString stringWithContentsOfFile:encoding:NSUTF8StringEncoding error:）
//    · 文件不存在 / 存在但为空且 prefillTemplateWhenEmpty → 预填 templateText
//    · 顶部 infoBar：路径（等宽小字）+ 状态（行数 / 字节数 / 未保存的修改）
//    · 保存：先写临时文件再 replaceItemAtURL:（失败退回原子写），成功后回调 onSaved
//
//  头文件的选择器参数类型统一是占位 id；实现逐字沿用该签名，函数体第一行局部强转后使用。
//

#import "CATextEditorViewController.h"
#import "CALogger.h"

#pragma mark - 文件内工具（静态函数：不为面板新增选择器）

/// id 占位参数 → BOOL（头文件里真实语义多为 bool）
static BOOL CATextEditorBool(id value)
{
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [(NSNumber *)value boolValue];
    }
    return value != nil;
}

/// 统一关闭入口：已 push 则 pop，模态则 dismiss
static void CATextEditorDismiss(UIViewController *controller)
{
    if (!controller) return;
    UINavigationController *navigation = controller.navigationController;
    if (navigation && navigation.viewControllers.count > 1) {
        [navigation popViewControllerAnimated:YES];
    } else if (controller.presentingViewController) {
        [controller dismissViewControllerAnimated:YES completion:nil];
    }
}

/// 轻提示（挂到仍在屏幕上的容器上，1.6s 后自动消失）
static void CATextEditorToast(UIView *hostView, NSString *message)
{
    if (!hostView || message.length == 0) return;

    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    container.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];
    container.layer.cornerRadius = 12.0;
    container.layer.masksToBounds = YES;
    [hostView addSubview:container];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = message;
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    [container addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [container.centerXAnchor constraintEqualToAnchor:hostView.centerXAnchor],
        [container.centerYAnchor constraintEqualToAnchor:hostView.centerYAnchor],
        [container.widthAnchor constraintLessThanOrEqualToAnchor:hostView.widthAnchor constant:-56.0],

        [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:8.0],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-8.0],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:14.0],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-14.0],
    ]];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [container removeFromSuperview];
    });
}

static void CATextEditorPresentAlert(UIViewController *controller, NSString *title, NSString *message)
{
    if (!controller) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}

/// 字节数文案
static NSString *CATextEditorSizeText(unsigned long long bytes)
{
    if (bytes < 1024ULL) {
        return [NSString stringWithFormat:@"%llu 字节", bytes];
    }
    if (bytes < 1024ULL * 1024ULL) {
        return [NSString stringWithFormat:@"%.1f KB", (double)bytes / 1024.0];
    }
    return [NSString stringWithFormat:@"%.1f MB", (double)bytes / (1024.0 * 1024.0)];
}

/// 原子写：先写临时文件，再 replaceItemAtURL: 替换；不支持替换时退回 writeToFile:atomically:
static BOOL CATextEditorWriteAtomically(NSString *path, NSString *text, NSError **error)
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *directory = [path stringByDeletingLastPathComponent];
    if (directory.length > 0) {
        [manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    }

    NSString *tmpPath = [directory stringByAppendingPathComponent:
                         [NSString stringWithFormat:@".%@.%@.tmp", path.lastPathComponent, [[NSUUID UUID] UUIDString]]];
    if (![text writeToFile:tmpPath atomically:YES encoding:NSUTF8StringEncoding error:error]) {
        return NO;
    }

    if ([manager fileExistsAtPath:path]) {
        NSURL *resultURL = nil;
        NSError *replaceError = nil;
        BOOL replaced = [manager replaceItemAtURL:[NSURL fileURLWithPath:path]
                                   withItemAtURL:[NSURL fileURLWithPath:tmpPath]
                                  backupItemName:nil
                                         options:0
                                resultingItemURL:&resultURL
                                           error:&replaceError];
        if (replaced) return YES;
        [manager removeItemAtPath:tmpPath error:NULL];
        CALog(CALogLevelWarn, @"GENERAL", @"replaceItemAtURL failed code=%ld, fallback to atomic write",
              (long)replaceError.code);
        return [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error];
    }

    NSError *moveError = nil;
    if ([manager moveItemAtPath:tmpPath toPath:path error:&moveError]) return YES;
    [manager removeItemAtPath:tmpPath error:NULL];
    if (error) *error = moveError;
    return NO;
}

#pragma mark - 面板

@interface CATextEditorViewController () <UITextViewDelegate>
{
    BOOL _editable;
    BOOL _fileExists;
    UIView *_infoBar;
    BOOL _loaded;
    NSString *_note;
    id _onSaved;                // void(^)(void)
    NSString *_originalText;
    NSString *_path;
    UILabel *_pathLabel;
    BOOL _prefillTemplateWhenEmpty;
    UIBarButtonItem *_saveItem;
    BOOL _saving;
    UIActivityIndicatorView *_spinner;
    UILabel *_statusLabel;
    NSString *_templateText;
    UITextView *_textView;

    NSString *_displayTitle;
    UIButton *_copyButton;
    BOOL _finishing;            // 主动关闭中：不再提示未保存
}

@end

@implementation CATextEditorViewController

#pragma mark - 访问器（头文件里声明的选择器）

- (id)displayPath
{
    NSString *path = self.path;
    if (path.length == 0) return @"（未指定路径）";
    NSString *home = NSHomeDirectory();
    if (home.length > 0 && [path hasPrefix:home]) {
        return [@"~" stringByAppendingString:[path substringFromIndex:home.length]];
    }
    return path;
}

- (bool)editable
{
    return _editable ? YES : NO;
}

- (bool)fileExists
{
    return _fileExists ? YES : NO;
}

- (void)finish
{
    _finishing = YES;
    CATextEditorDismiss(self);
}

- (void)handleCancel
{
    if (![self isDirty]) {
        [self finish];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"放弃修改？"
                                                                   message:@"这个文件还有未保存的改动，关闭后改动会丢失。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"继续编辑" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"放弃修改"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf finish];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)handleCopy
{
    NSString *text = _textView.text ?: @"";
    if (text.length == 0) {
        CATextEditorToast(self.view, @"没有可复制的内容");
        return;
    }
    [UIPasteboard generalPasteboard].string = text;
    CATextEditorToast(self.view, [NSString stringWithFormat:@"已复制 %lu 字", (unsigned long)text.length]);
}

- (void)handleSave
{
    if (_saving || !_editable) return;

    NSString *path = self.path;
    if (path.length == 0) {
        CATextEditorToast(self.view, @"没有可写入的路径");
        return;
    }
    NSString *text = _textView.text ?: @"";

    _saving = YES;
    _spinner.hidden = NO;
    [_spinner startAnimating];
    _saveItem.enabled = NO;
    [self updateStatus];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        BOOL ok = CATextEditorWriteAtomically(path, text, &error);

        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;

            strongSelf->_saving = NO;
            [strongSelf->_spinner stopAnimating];
            strongSelf->_spinner.hidden = YES;

            if (ok) {
                strongSelf->_fileExists = YES;
                strongSelf->_originalText = [text copy];
                [strongSelf updateStatus];
                strongSelf->_saveItem.enabled = [strongSelf isDirty];
                CATextEditorToast(strongSelf.view, @"已保存");
                CALog(CALogLevelInfo, @"GENERAL", @"text file saved path=%@ bytes=%lu",
                      path, (unsigned long)[text dataUsingEncoding:NSUTF8StringEncoding].length);
                id saved = strongSelf->_onSaved;
                if (saved) {
                    void (^onSaved)(void) = (void (^)(void))saved;
                    onSaved();
                }
            } else {
                [strongSelf updateStatus];
                strongSelf->_saveItem.enabled = [strongSelf isDirty];
                CATextEditorPresentAlert(strongSelf, @"保存失败",
                                         error.localizedDescription ?: @"无法写入这个文件。");
                CALog(CALogLevelError, @"GENERAL", @"text file save failed path=%@ code=%ld",
                      path, (long)error.code);
            }
        });
    });
}

- (UIView *)infoBar
{
    return _infoBar;
}

- (id)initWithTitle:(id)arg1 path:(id)arg2 template:(id)arg3 editable:(id)arg4
{
    if ((self = [super initWithNibName:nil bundle:nil])) {
        _displayTitle = [arg1 isKindOfClass:NSString.class] ? [(NSString *)arg1 copy] : @"文本";
        _path = [arg2 isKindOfClass:NSString.class] ? [(NSString *)arg2 copy] : @"";
        _templateText = [arg3 isKindOfClass:NSString.class] ? [(NSString *)arg3 copy] : @"";
        _editable = CATextEditorBool(arg4);
        _prefillTemplateWhenEmpty = (_templateText.length > 0);
        _originalText = @"";
    }
    return self;
}

- (bool)isDirty
{
    if (!_loaded) return NO;
    NSString *current = _textView.text ?: @"";
    NSString *original = _originalText ?: @"";
    return [current isEqualToString:original] ? NO : YES;
}

- (void)loadFile
{
    NSString *path = self.path;
    if (path.length == 0) {
        _loaded = YES;
        _fileExists = NO;
        _originalText = @"";
        [self updateStatus];
        return;
    }

    NSString *templateText = _templateText ?: @"";
    BOOL prefill = _prefillTemplateWhenEmpty;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *manager = [NSFileManager defaultManager];
        BOOL exists = [manager fileExistsAtPath:path];
        NSString *contents = nil;
        if (exists) {
            NSError *error = nil;
            contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
            if (!contents) {
                // 非 UTF-8 或读取失败：退到二进制解码，保证面板不空转
                NSData *data = [NSData dataWithContentsOfFile:path];
                if (data.length > 0) {
                    contents = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                }
                CALog(CALogLevelWarn, @"GENERAL", @"text file read fallback path=%@ code=%ld",
                      path, (long)error.code);
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;

            NSString *text = contents ?: @"";
            if ((!exists || text.length == 0) && prefill && templateText.length > 0) {
                text = templateText;
            }

            strongSelf->_fileExists = exists;
            strongSelf->_originalText = exists ? (contents ?: @"") : @"";
            strongSelf->_loaded = YES;
            strongSelf->_textView.text = text;
            [strongSelf updateStatus];
            strongSelf->_saveItem.enabled = [strongSelf isDirty];
            CALog(CALogLevelInfo, @"GENERAL", @"text file loaded path=%@ exists=%d bytes=%lu",
                  path, exists ? 1 : 0,
                  (unsigned long)[text dataUsingEncoding:NSUTF8StringEncoding].length);
        });
    });
}

- (bool)loaded
{
    return _loaded ? YES : NO;
}

- (NSString *)note
{
    return _note;
}

- (id)onSaved
{
    return _onSaved;
}

- (NSString *)originalText
{
    return _originalText;
}

- (NSString *)path
{
    return _path ?: @"";
}

- (UILabel *)pathLabel
{
    return _pathLabel;
}

- (bool)prefillTemplateWhenEmpty
{
    return _prefillTemplateWhenEmpty ? YES : NO;
}

- (id)saveItem
{
    return _saveItem;
}

- (bool)saving
{
    return _saving ? YES : NO;
}

- (void)setEditable:(id)arg1
{
    _editable = CATextEditorBool(arg1);
    if (_textView) _textView.editable = _editable;
    self.navigationItem.rightBarButtonItem = _editable ? _saveItem : nil;
}

- (void)setFileExists:(id)arg1
{
    _fileExists = CATextEditorBool(arg1);
}

- (void)setInfoBar:(id)arg1
{
    _infoBar = [arg1 isKindOfClass:UIView.class] ? (UIView *)arg1 : nil;
}

- (void)setLoaded:(id)arg1
{
    _loaded = CATextEditorBool(arg1);
}

- (void)setNote:(id)arg1
{
    if ([arg1 isKindOfClass:NSString.class]) {
        _note = [(NSString *)arg1 copy];
    } else {
        _note = arg1 ? [[arg1 description] copy] : nil;
    }
    [self updateStatus];
}

- (void)setOnSaved:(id)arg1
{
    _onSaved = [arg1 copy];
}

- (void)setOriginalText:(id)arg1
{
    _originalText = [arg1 isKindOfClass:NSString.class] ? [(NSString *)arg1 copy] : @"";
}

- (void)setPath:(id)arg1
{
    _path = [arg1 isKindOfClass:NSString.class] ? [(NSString *)arg1 copy] : @"";
}

- (void)setPathLabel:(id)arg1
{
    _pathLabel = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil;
}

- (void)setPrefillTemplateWhenEmpty:(id)arg1
{
    _prefillTemplateWhenEmpty = CATextEditorBool(arg1);
}

- (void)setSaveItem:(id)arg1
{
    _saveItem = [arg1 isKindOfClass:UIBarButtonItem.class] ? (UIBarButtonItem *)arg1 : nil;
}

- (void)setSaving:(id)arg1
{
    _saving = CATextEditorBool(arg1);
    _spinner.hidden = !_saving;
    if (_saving) {
        [_spinner startAnimating];
    } else {
        [_spinner stopAnimating];
    }
}

- (void)setSpinner:(id)arg1
{
    _spinner = [arg1 isKindOfClass:UIActivityIndicatorView.class] ? (UIActivityIndicatorView *)arg1 : nil;
}

- (void)setStatusLabel:(id)arg1
{
    _statusLabel = [arg1 isKindOfClass:UILabel.class] ? (UILabel *)arg1 : nil;
}

- (void)setTemplateText:(id)arg1
{
    _templateText = [arg1 isKindOfClass:NSString.class] ? [(NSString *)arg1 copy] : @"";
}

- (void)setTextView:(id)arg1
{
    _textView = [arg1 isKindOfClass:UITextView.class] ? (UITextView *)arg1 : nil;
}

- (id)spinner
{
    return _spinner;
}

- (UILabel *)statusLabel
{
    return _statusLabel;
}

- (NSString *)templateText
{
    return _templateText;
}

- (UITextView *)textView
{
    return _textView;
}

- (void)textViewDidChange:(id)arg1
{
    [self updateStatus];
    _saveItem.enabled = _editable && [self isDirty];
}

- (void)themeDidChange
{
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    _infoBar.backgroundColor = UIColor.tertiarySystemFillColor;
    _pathLabel.textColor = UIColor.secondaryLabelColor;
    _statusLabel.textColor = UIColor.secondaryLabelColor;
    _textView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    _textView.textColor = UIColor.labelColor;
    [_copyButton setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
}

- (void)updateStatus
{
    if (!_statusLabel) return;

    if (_saving) {
        _statusLabel.text = @"保存中…";
        return;
    }

    NSString *text = _textView.text ?: @"";
    NSUInteger lineCount = 0;
    if (text.length > 0) {
        lineCount = [[text componentsSeparatedByString:@"\n"] count];
    }
    unsigned long long bytes = (unsigned long long)
        [[text dataUsingEncoding:NSUTF8StringEncoding] length];

    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (!_loaded) {
        [parts addObject:@"读取中…"];
    } else if ([self isDirty]) {
        [parts addObject:@"未保存的修改"];
    } else {
        [parts addObject:(_fileExists ? @"已保存" : @"未创建")];
    }
    [parts addObject:[NSString stringWithFormat:@"%lu 行", (unsigned long)lineCount]];
    [parts addObject:CATextEditorSizeText(bytes)];
    if (_note.length > 0) {
        [parts addObject:_note];
    }
    _statusLabel.text = [parts componentsJoinedByString:@" · "];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.title = _displayTitle.length > 0 ? _displayTitle : @"文本";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;

    UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"xmark"]
                                                               style:UIBarButtonItemStylePlain
                                                              target:self
                                                              action:@selector(handleCancel)];
    cancel.accessibilityLabel = @"关闭";
    self.navigationItem.leftBarButtonItem = cancel;

    _saveItem = [[UIBarButtonItem alloc] initWithTitle:@"保存"
                                                 style:UIBarButtonItemStyleDone
                                                target:self
                                                action:@selector(handleSave)];
    _saveItem.enabled = NO;
    self.navigationItem.rightBarButtonItem = _editable ? _saveItem : nil;

    // 顶部信息条：路径 + 状态（浅灰圆角条）
    _infoBar = [[UIView alloc] initWithFrame:CGRectZero];
    _infoBar.translatesAutoresizingMaskIntoConstraints = NO;
    _infoBar.backgroundColor = UIColor.tertiarySystemFillColor;
    _infoBar.layer.cornerRadius = 12.0;
    _infoBar.layer.masksToBounds = YES;
    [self.view addSubview:_infoBar];

    _pathLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _pathLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _pathLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightRegular];
    _pathLabel.textColor = UIColor.secondaryLabelColor;
    _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _pathLabel.text = (NSString *)[self displayPath];
    [_infoBar addSubview:_pathLabel];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    _statusLabel.textColor = UIColor.secondaryLabelColor;
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    [_infoBar addSubview:_statusLabel];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _spinner.translatesAutoresizingMaskIntoConstraints = NO;
    _spinner.hidesWhenStopped = YES;
    _spinner.hidden = YES;
    [_infoBar addSubview:_spinner];

    _copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _copyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_copyButton setTitle:@"复制" forState:UIControlStateNormal];
    [_copyButton setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
    _copyButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
    [_copyButton addTarget:self action:@selector(handleCopy) forControlEvents:UIControlEventTouchUpInside];
    [_infoBar addSubview:_copyButton];

    // 正文：白底圆角卡片
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 16.0;
    card.layer.masksToBounds = YES;
    [self.view addSubview:card];

    _textView = [[UITextView alloc] initWithFrame:CGRectZero];
    _textView.translatesAutoresizingMaskIntoConstraints = NO;
    _textView.delegate = self;
    _textView.editable = _editable;
    _textView.selectable = YES;
    _textView.backgroundColor = UIColor.clearColor;
    _textView.font = [UIFont monospacedSystemFontOfSize:13.5 weight:UIFontWeightRegular];
    _textView.textColor = UIColor.labelColor;
    _textView.textContainerInset = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
    _textView.alwaysBounceVertical = YES;
    _textView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    _textView.autocorrectionType = UITextAutocorrectionTypeNo;
    _textView.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [card addSubview:_textView];

    [NSLayoutConstraint activateConstraints:@[
        [_infoBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [_infoBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [_infoBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],

        [_pathLabel.topAnchor constraintEqualToAnchor:_infoBar.topAnchor constant:10.0],
        [_pathLabel.leadingAnchor constraintEqualToAnchor:_infoBar.leadingAnchor constant:12.0],
        [_pathLabel.trailingAnchor constraintEqualToAnchor:_infoBar.trailingAnchor constant:-12.0],

        [_statusLabel.topAnchor constraintEqualToAnchor:_pathLabel.bottomAnchor constant:4.0],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:_infoBar.leadingAnchor constant:12.0],
        [_statusLabel.bottomAnchor constraintEqualToAnchor:_infoBar.bottomAnchor constant:-10.0],

        [_copyButton.centerYAnchor constraintEqualToAnchor:_statusLabel.centerYAnchor],
        [_copyButton.trailingAnchor constraintEqualToAnchor:_infoBar.trailingAnchor constant:-12.0],
        [_statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_copyButton.leadingAnchor constant:-8.0],

        [_spinner.centerYAnchor constraintEqualToAnchor:_statusLabel.centerYAnchor],
        [_spinner.trailingAnchor constraintEqualToAnchor:_copyButton.leadingAnchor constant:-8.0],
        [_spinner.widthAnchor constraintEqualToConstant:16.0],
        [_spinner.heightAnchor constraintEqualToConstant:16.0],

        [card.topAnchor constraintEqualToAnchor:_infoBar.bottomAnchor constant:12.0],
        [card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
        [card.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12.0],

        [_textView.topAnchor constraintEqualToAnchor:card.topAnchor],
        [_textView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [_textView.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
        [_textView.bottomAnchor constraintEqualToAnchor:card.bottomAnchor],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(themeDidChange)
                                                 name:@"CAThemeDidChangeNotification"
                                               object:nil];

    [self updateStatus];
    [self loadFile];
}

- (void)viewWillDisappear:(id)arg1
{
    [super viewWillDisappear:CATextEditorBool(arg1)];

    // 手势返回 / 被别的页面盖住时，若仍有未保存改动就给个提示（不弹窗、不阻塞）
    if (![self isDirty] || _saving || _finishing) return;
    CATextEditorToast(self.navigationController.view ?: self.view, @"有未保存的修改");
    CALog(CALogLevelWarn, @"GENERAL", @"text editor dismissed with unsaved changes path=%@", self.path);
}

@end
