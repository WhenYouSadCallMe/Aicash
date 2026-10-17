#import "CAContextUsageViewController.h"
#import "CAContextGaugeView.h"
#import "CACodexEngine.h"

@interface CAContextUsageViewController ()
@property(nonatomic,strong) UILabel *cacheHintValue, *cacheTokensValue, *cacheValueLabel;
@property(nonatomic,strong) CAContextGaugeView *cacheGauge;
@property(nonatomic,strong) NSMutableArray *cardViews;
@property(nonatomic,strong) UILabel *contextHintValue, *contextTokensValue, *contextValueLabel, *modelLabelValue;
@property(nonatomic,strong) CAContextGaugeView *contextGauge;
@property(nonatomic,weak) CACodexEngine *engineValue;
@end

@implementation CAContextUsageViewController

- (instancetype)initWithEngine:(CACodexEngine *)engine { if ((self=[super init])) _engineValue=engine; return self; }
- (UILabel *)cacheHint{return _cacheHintValue;} - (id)cacheProgress{return _cacheGauge;} - (UILabel *)cacheTokens{return _cacheTokensValue;} - (UILabel *)cacheValue{return _cacheValueLabel;}
- (NSMutableArray *)cards{return _cardViews;} - (void)closeSheet{[self dismissViewControllerAnimated:YES completion:nil];}
- (UILabel *)contextHint{return _contextHintValue;} - (id)contextProgress{return _contextGauge;} - (UILabel *)contextTokens{return _contextTokensValue;} - (UILabel *)contextValue{return _contextValueLabel;}
- (id)engine{return _engineValue ?: [CACodexEngine sharedEngine];} - (UILabel *)modelLabel{return _modelLabelValue;}
- (void)setEngine:(id)v{_engineValue=[v isKindOfClass:CACodexEngine.class]?v:nil;if(self.isViewLoaded)[self refreshUsage];}
- (void)setCards:(id)v{_cardViews=[v isKindOfClass:NSMutableArray.class]?v:[NSMutableArray array];}
- (void)setCacheHint:(id)v{_cacheHintValue=[v isKindOfClass:UILabel.class]?v:nil;} - (void)setCacheProgress:(id)v{_cacheGauge=[v isKindOfClass:CAContextGaugeView.class]?v:nil;}
- (void)setCacheTokens:(id)v{_cacheTokensValue=[v isKindOfClass:UILabel.class]?v:nil;} - (void)setCacheValue:(id)v{_cacheValueLabel=[v isKindOfClass:UILabel.class]?v:nil;}
- (void)setContextHint:(id)v{_contextHintValue=[v isKindOfClass:UILabel.class]?v:nil;} - (void)setContextProgress:(id)v{_contextGauge=[v isKindOfClass:CAContextGaugeView.class]?v:nil;}
- (void)setContextTokens:(id)v{_contextTokensValue=[v isKindOfClass:UILabel.class]?v:nil;} - (void)setContextValue:(id)v{_contextValueLabel=[v isKindOfClass:UILabel.class]?v:nil;} - (void)setModelLabel:(id)v{_modelLabelValue=[v isKindOfClass:UILabel.class]?v:nil;}

- (NSString *)tokenString:(id)v{unsigned long long n=[v respondsToSelector:@selector(unsignedLongLongValue)]?[v unsignedLongLongValue]:0;return n?[NSString stringWithFormat:@"%llu tokens",n]:@"0 tokens";}
- (id)labelWithSize:(id)size weight:(id)weight secondary:(id)secondary
{
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    CGFloat pointSize = [size respondsToSelector:@selector(doubleValue)] ? [size doubleValue] : 14.0;
    CGFloat fontWeight = [weight respondsToSelector:@selector(doubleValue)] ? [weight doubleValue] : UIFontWeightRegular;
    label.font = [UIFont systemFontOfSize:pointSize weight:fontWeight];
    label.textColor = [secondary boolValue] ? UIColor.secondaryLabelColor : UIColor.labelColor;
    label.numberOfLines = 0;
    return label;
}
- (id)metricCardWithTitle:(id)title value:(id)value tokens:(id)tokens hint:(id)hint progress:(id)progress
{
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 12.0;
    UILabel *titleLabel = [self labelWithSize:@16 weight:@(UIFontWeightSemibold) secondary:@NO];
    titleLabel.text = [title isKindOfClass:NSString.class] ? title : @"用量";
    UILabel *valueLabel = [self labelWithSize:@26 weight:@(UIFontWeightBold) secondary:@NO];
    valueLabel.text = [value isKindOfClass:NSString.class] ? value : @"—";
    UILabel *tokensLabel = [self labelWithSize:@13 weight:@(UIFontWeightRegular) secondary:@YES];
    tokensLabel.text = [tokens isKindOfClass:NSString.class] ? tokens : @"";
    UILabel *hintLabel = [self labelWithSize:@12 weight:@(UIFontWeightRegular) secondary:@YES];
    hintLabel.text = [hint isKindOfClass:NSString.class] ? hint : @"";
    UIProgressView *bar = [UIProgressView new]; bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.progress = [progress respondsToSelector:@selector(floatValue)] ? MAX(0, MIN(1, [progress floatValue])) : 0;
    [card addSubview:titleLabel]; [card addSubview:valueLabel]; [card addSubview:tokensLabel]; [card addSubview:hintLabel]; [card addSubview:bar];
    [NSLayoutConstraint activateConstraints:@[[titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:14],[titleLabel.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],[titleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],[valueLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6],[valueLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],[tokensLabel.topAnchor constraintEqualToAnchor:valueLabel.bottomAnchor constant:3],[tokensLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],[hintLabel.topAnchor constraintEqualToAnchor:tokensLabel.bottomAnchor constant:3],[hintLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],[hintLabel.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],[bar.topAnchor constraintEqualToAnchor:hintLabel.bottomAnchor constant:9],[bar.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],[bar.trailingAnchor constraintEqualToAnchor:titleLabel.trailingAnchor],[bar.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14],[card.heightAnchor constraintGreaterThanOrEqualToConstant:140]]];
    return card;
}
- (id)progressView { return self.contextGauge; }

- (void)viewDidLoad{
 [super viewDidLoad]; self.title=@"上下文用量"; self.view.backgroundColor=UIColor.systemBackgroundColor; _cardViews=[NSMutableArray array];
 self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeSheet)];
 UIScrollView *scroll=[UIScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:scroll]; UIStackView *stack=[[UIStackView alloc]init];stack.translatesAutoresizingMaskIntoConstraints=NO;stack.axis=UILayoutConstraintAxisVertical;stack.spacing=10;[scroll addSubview:stack];
 _modelLabelValue=[UILabel new];_modelLabelValue.textAlignment=NSTextAlignmentCenter;_modelLabelValue.textColor=UIColor.secondaryLabelColor;[stack addArrangedSubview:_modelLabelValue];
 _contextGauge=[[CAContextGaugeView alloc]initWithFrame:CGRectZero];[stack addArrangedSubview:_contextGauge];[_contextGauge.heightAnchor constraintEqualToConstant:126].active=YES;
 _contextValueLabel=[UILabel new];_contextValueLabel.textAlignment=NSTextAlignmentCenter;_contextValueLabel.font=[UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];[stack addArrangedSubview:_contextValueLabel];
 _contextTokensValue=[UILabel new];_contextTokensValue.textAlignment=NSTextAlignmentCenter;_contextTokensValue.textColor=UIColor.secondaryLabelColor;[stack addArrangedSubview:_contextTokensValue];
 _contextHintValue=[UILabel new];_contextHintValue.textAlignment=NSTextAlignmentCenter;_contextHintValue.textColor=UIColor.secondaryLabelColor;[stack addArrangedSubview:_contextHintValue];
 _cacheGauge=[[CAContextGaugeView alloc]initWithFrame:CGRectZero];[stack addArrangedSubview:_cacheGauge];[_cacheGauge.heightAnchor constraintEqualToConstant:110].active=YES;
 _cacheValueLabel=[UILabel new];_cacheValueLabel.textAlignment=NSTextAlignmentCenter;_cacheValueLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];[stack addArrangedSubview:_cacheValueLabel];
 _cacheTokensValue=[UILabel new];_cacheTokensValue.textAlignment=NSTextAlignmentCenter;_cacheTokensValue.textColor=UIColor.secondaryLabelColor;[stack addArrangedSubview:_cacheTokensValue];
 _cacheHintValue=[UILabel new];_cacheHintValue.textAlignment=NSTextAlignmentCenter;_cacheHintValue.textColor=UIColor.secondaryLabelColor;_cacheHintValue.numberOfLines=0;[stack addArrangedSubview:_cacheHintValue];
 [NSLayoutConstraint activateConstraints:@[[scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],[scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],[stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],[stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],[stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],[stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]]];
 [self refreshUsage];
}

- (void)refreshUsage{
 CACodexEngine *e=self.engine; NSInteger p=MAX(0,MIN(100,e.contextUsagePercent)); double c=MAX(0,MIN(100,e.stableCacheHitPercent)); NSNumber *used=[e respondsToSelector:@selector(latestContextTokenCount)]?[e latestContextTokenCount]:@0; NSNumber *limit=[e respondsToSelector:@selector(contextWindowLimitTokens)]?[e contextWindowLimitTokens]:@0; NSNumber *cached=[e respondsToSelector:@selector(latestCachedInputTokens)]?[e latestCachedInputTokens]:@0;
 _modelLabelValue.text=[NSString stringWithFormat:@"模型 %@ · 窗口 %@",[e effectiveModelSlug]?:@"默认",[self tokenString:limit]]; _contextGauge.percent=@(p);_contextGauge.centerText=[NSString stringWithFormat:@"%ld%%",(long)p];_contextValueLabel.text=[NSString stringWithFormat:@"已使用 %ld%%",(long)p];_contextTokensValue.text=[NSString stringWithFormat:@"%@ / %@",[self tokenString:used],[self tokenString:limit]];_contextHintValue.text=e.contextUsageIsEstimated?@"当前值为估算值":@"来自最近一次回合用量"; NSInteger cp=(NSInteger)llround(c);_cacheGauge.percent=@(cp);_cacheGauge.centerText=[NSString stringWithFormat:@"%ld%%",(long)cp];_cacheValueLabel.text=[NSString stringWithFormat:@"缓存命中 %.0f%%",c];_cacheTokensValue.text=[NSString stringWithFormat:@"%@ 缓存输入",[self tokenString:cached]];_cacheHintValue.text=c>0?@"缓存命中越高，重复上下文成本越低":@"暂未收到缓存统计";
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous{[super traitCollectionDidChange:previous];[_contextGauge themeDidChange];[_cacheGauge themeDidChange];}
@end
