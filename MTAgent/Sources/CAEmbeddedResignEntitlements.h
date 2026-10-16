//
//  CAEmbeddedResignEntitlements.h — 重签用 entitlements 模板（内嵌在二进制内）
//  原包 bundle 内没有 ResignEntitlements/ 目录（只有根目录 entitlements.plist），模板嵌在 Mach-O 里；
//  本文件等价地以字符串常量内嵌，签名前按需落盘，保证 .tipa 条目与原包一致（79 条）。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSString *CAResignEntitlementsPathForRuntime(void);
NSString *CAResignEntitlementsPathForHelper(void);
NSString *CAResignEntitlementsXMLForRuntime(void);
NSString *CAResignEntitlementsXMLForHelper(void);

NS_ASSUME_NONNULL_END
