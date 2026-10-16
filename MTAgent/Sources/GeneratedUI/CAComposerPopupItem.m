//
//  CAComposerPopupItem — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//
//  聊天主流程实装：输入框 “/” 面板的单条目数据模型（标题 / 副标题 / 图标 / 徽标 / 负载）。
//  payload 里放对应的 CAComposerCatalogItem，选中后由 CAChatViewController 决定插入什么文本。
//

#import "CAComposerPopupItem.h"

@interface CAComposerPopupItem () {
    bool _enabled;
}

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) NSString *badge;
@property (nonatomic, strong) UIColor *tint;
@property (nonatomic, strong) id payload;
@end

@implementation CAComposerPopupItem

- (instancetype)init
{
    if ((self = [super init])) {
        _identifier = [[NSUUID UUID] UUIDString].lowercaseString;
        _title = @"";
        _subtitle = @"";
        _symbol = @"";
        _badge = @"";
        _enabled = true;
    }
    return self;
}

- (bool)enabled { return _enabled; }

- (void)setEnabled:(id)arg1
{
    _enabled = [arg1 respondsToSelector:@selector(boolValue)] ? [arg1 boolValue] : NO;
}

#pragma mark - 工厂（原包同名选择器：实例方法形式）

- (id)itemWithIdentifier:(id)arg1 title:(id)arg2 subtitle:(id)arg3 symbol:(id)arg4
{
    CAComposerPopupItem *item = [[CAComposerPopupItem alloc] init];
    if ([arg1 isKindOfClass:NSString.class] && [arg1 length] > 0) item.identifier = arg1;
    item.title = [arg2 isKindOfClass:NSString.class] ? arg2 : @"";
    item.subtitle = [arg3 isKindOfClass:NSString.class] ? arg3 : @"";
    item.symbol = [arg4 isKindOfClass:NSString.class] ? arg4 : @"";
    return item;
}

- (id)placeholderWithTitle:(id)arg1 subtitle:(id)arg2 symbol:(id)arg3
{
    CAComposerPopupItem *item = [[CAComposerPopupItem alloc] init];
    item.identifier = @"placeholder";
    item.title = [arg1 isKindOfClass:NSString.class] ? arg1 : @"";
    item.subtitle = [arg2 isKindOfClass:NSString.class] ? arg2 : @"";
    item.symbol = [arg3 isKindOfClass:NSString.class] ? arg3 : @"";
    item.enabled = @NO;
    return item;
}

@end
