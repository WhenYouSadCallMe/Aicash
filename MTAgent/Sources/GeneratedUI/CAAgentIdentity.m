//
//  CAAgentIdentity — Agent 身份显示名的读写（本机 defaults + 变更通知）
//
//  原包观测：
//    · defaults 键 CAAgentDisplayName（空值回退默认名「MT」）
//    · 身份变更通知 CAAgentIdentityDidChangeNotification
//    · 原包为类方法 +displayName / +saveDisplayName:；头文件生成成了实例方法形态，
//      这里保持头文件的实例方法不动，额外补上同名类方法（追加，不改任何既有签名）。
//

#import "CAAgentIdentity.h"
#import "CACommon.h"

/// 显示名默认值（与设置页「Agent 身份  MT」右侧详情一致）
static NSString *const CAAgentIdentityDefaultDisplayName = @"MT";

/// 显示名 defaults 键（原包字面量，勿改）
static NSString *const CAAgentIdentityDisplayNameKey = @"CAAgentDisplayName";

/// 身份变更通知名（原包字面量，勿改）
static NSString *const CAAgentIdentityDidChangeNotificationName = @"CAAgentIdentityDidChangeNotification";

/// 显示名长度约束：去首尾空白后 1..24
static const NSUInteger CAAgentIdentityMinNameLength = 1;
static const NSUInteger CAAgentIdentityMaxNameLength = 24;

/// 归一化草稿：只接受字符串（或字符串等价物），去掉首尾空白与换行
static NSString *CAAgentIdentityNormalizedDisplayName(id value)
{
    NSString *raw = nil;
    if ([value isKindOfClass:NSString.class]) {
        raw = (NSString *)value;
    } else if ([value isKindOfClass:NSAttributedString.class]) {
        raw = [(NSAttributedString *)value string];
    } else if (value) {
        raw = [value description];
    }
    if (![raw isKindOfClass:NSString.class]) return @"";
    return [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
}

@implementation CAAgentIdentity

#pragma mark - 类方法（原包形态，追加）

+ (id)displayName
{
    NSString *stored = [NSUserDefaults.standardUserDefaults stringForKey:CAAgentIdentityDisplayNameKey];
    NSString *normalized = CAAgentIdentityNormalizedDisplayName(stored);
    if (normalized.length >= CAAgentIdentityMinNameLength) return normalized;
    return CAAgentIdentityDefaultDisplayName;
}

+ (bool)saveDisplayName:(id)arg1
{
    NSString *name = CAAgentIdentityNormalizedDisplayName(arg1);
    if (name.length < CAAgentIdentityMinNameLength || name.length > CAAgentIdentityMaxNameLength) {
        CALog(CALogLevelWarn, @"GENERAL", @"agent identity rejected length=%lu", (unsigned long)name.length);
        return NO;
    }

    [NSUserDefaults.standardUserDefaults setObject:name forKey:CAAgentIdentityDisplayNameKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:CAAgentIdentityDidChangeNotificationName
                                                        object:nil
                                                      userInfo:@{ CAAgentIdentityDisplayNameKey: name }];
    CALog(CALogLevelInfo, @"GENERAL", @"agent identity saved name=%@", name);
    return YES;
}

#pragma mark - 实例方法（头文件声明的形态，转发到类方法）

- (id)displayName
{
    return [CAAgentIdentity displayName];
}

- (bool)saveDisplayName:(id)arg1
{
    return [CAAgentIdentity saveDisplayName:arg1];
}

@end
