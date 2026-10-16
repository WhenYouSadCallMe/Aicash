//
//  CAGitChangeStyle.m — 单个变更行的视觉样式（标签 / 图标 / 颜色）
//
//  原包同类方法为类方法 +styleForChange:side:，此处同时保留头文件里的
//  同名实例方法（选择器逐字不变），供两种调用方式使用。
//

#import "CAGitChangeStyle.h"
#import "CAGitSnapshot.h"

@interface CAGitChangeStyle ()
{
    NSString *_label;
    NSString *_symbol;
    UIColor *_color;
}
@end

@implementation CAGitChangeStyle

- (id)initWithLabel:(id)arg1 symbol:(id)arg2 color:(id)arg3
{
    if ((self = [super init])) {
        _label = [(NSString *)arg1 copy];
        _symbol = [(NSString *)arg2 copy];
        _color = (UIColor *)arg3 ?: UIColor.systemGrayColor;
    }
    return self;
}

- (NSString *)label { return _label ?: @""; }
- (NSString *)symbol { return _symbol ?: @"pencil"; }
- (UIColor *)color { return _color ?: UIColor.systemGrayColor; }

- (id)styleForChange:(id)arg1 side:(id)arg2
{
    return [CAGitChangeStyle styleForChange:arg1 side:arg2];
}

/// side：0 = 未暂存（工作区），1 = 已暂存（索引）
+ (id)styleForChange:(id)arg1 side:(id)arg2
{
    NSDictionary *change = [arg1 isKindOfClass:NSDictionary.class] ? (NSDictionary *)arg1 : nil;
    if (change == nil) {
        return [[CAGitChangeStyle alloc] initWithLabel:@"已修改" symbol:@"pencil" color:UIColor.systemOrangeColor];
    }

    BOOL staged = [(NSNumber *)arg2 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg2 boolValue] : NO;
    NSString *label = change[kCAGitChangeLabelKey];
    if (staged && ![label containsString:@"暂存"]) {
        label = @"已暂存";
    }
    UIColor *color = change[kCAGitChangeTintKey];
    if (staged) {
        color = UIColor.systemBlueColor;
    }
    NSString *symbol = change[kCAGitChangeSymbolKey];
    return [[CAGitChangeStyle alloc] initWithLabel:label ?: @"已修改"
                                            symbol:symbol ?: @"pencil"
                                             color:color ?: UIColor.systemOrangeColor];
}

@end
