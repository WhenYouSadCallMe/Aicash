//
//  CAComposerPopupSection — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//
//  聊天主流程实装：输入框 “/” 面板的分组（技能 / 命令 / MCP / 记忆）。
//

#import "CAComposerPopupSection.h"
#import "CAComposerPopupItem.h"

@interface CAComposerPopupSection ()
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSArray *items;
@end

@implementation CAComposerPopupSection

- (instancetype)init
{
    if ((self = [super init])) {
        _title = @"";
        _items = @[];
    }
    return self;
}

- (void)setItems:(id)arg1
{
    _items = [arg1 isKindOfClass:NSArray.class] ? [arg1 copy] : @[];
}

- (void)setTitle:(id)arg1
{
    _title = [arg1 isKindOfClass:NSString.class] ? [arg1 copy] : @"";
}

- (id)sectionWithTitle:(id)arg1 items:(id)arg2
{
    CAComposerPopupSection *section = [[CAComposerPopupSection alloc] init];
    section.title = [arg1 isKindOfClass:NSString.class] ? arg1 : @"";
    section.items = [arg2 isKindOfClass:NSArray.class] ? arg2 : @[];
    return section;
}

@end
