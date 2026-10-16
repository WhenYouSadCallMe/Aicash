//
//  MTGeneratedArtifactCard.m
//

#import "MTGeneratedArtifactCard.h"

@implementation MTGeneratedArtifactCard
{
    UILabel *_nameLabel;
    UILabel *_sizeLabel;
    UIButton *_openButton;
    UILabel *_kindLabel;
}

+ (CGFloat)preferredHeight { return 52.0; }

- (instancetype)initWithArtifactPath:(NSString *)path
{
    if ((self = [super initWithFrame:CGRectMake(0, 0, 320, [MTGeneratedArtifactCard preferredHeight])])) {
        self.backgroundColor = [UIColor secondarySystemBackgroundColor];
        self.layer.cornerRadius = 10.0;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _kindLabel = [UILabel new];
        _kindLabel.font = [UIFont systemFontOfSize:16.0];
        _kindLabel.text = @"📄";
        _kindLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_kindLabel];

        _nameLabel = [UILabel new];
        _nameLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        _nameLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_nameLabel];

        _sizeLabel = [UILabel new];
        _sizeLabel.font = [UIFont systemFontOfSize:12.0];
        _sizeLabel.textColor = [UIColor secondaryLabelColor];
        _sizeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_sizeLabel];

        _openButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_openButton setTitle:@"打开" forState:UIControlStateNormal];
        _openButton.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightSemibold];
        _openButton.translatesAutoresizingMaskIntoConstraints = NO;
        [_openButton addTarget:self action:@selector(openTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_openButton];

        [NSLayoutConstraint activateConstraints:@[
            [_kindLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12.0],
            [_kindLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_nameLabel.leadingAnchor constraintEqualToAnchor:_kindLabel.trailingAnchor constant:8.0],
            [_nameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_sizeLabel.leadingAnchor constant:-8.0],
            [_nameLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_sizeLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_openButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12.0],
            [_openButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_sizeLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_openButton.leadingAnchor constant:-8.0],
        ]];

        self.artifactPath = [path copy];
        [self reload];
    }
    return self;
}

- (void)setArtifactPath:(NSString *)artifactPath
{
    _artifactPath = [artifactPath copy];
    _artifactName = _artifactPath.lastPathComponent ?: @"(未命名)";
    [self reload];
}

- (NSString *)sizeText
{
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:self.artifactPath error:NULL];
    unsigned long long bytes = [attributes[NSFileSize] unsignedLongLongValue];
    if (!bytes) return @"—";
    if (bytes < 1024) return [NSString stringWithFormat:@"%llu B", bytes];
    if (bytes < 1024 * 1024) return [NSString stringWithFormat:@"%.1f KB", bytes / 1024.0];
    return [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)];
}

- (void)reload
{
    _nameLabel.text = self.artifactName ?: @"(未命名)";
    _sizeLabel.text = [self sizeText];
    BOOL exists = self.artifactPath.length > 0 &&
                  [NSFileManager.defaultManager fileExistsAtPath:self.artifactPath];
    _openButton.enabled = exists;
    _openButton.alpha = exists ? 1.0 : 0.4;
}

- (void)openTapped
{
    if (self.openHandler) self.openHandler(self);
}

@end
