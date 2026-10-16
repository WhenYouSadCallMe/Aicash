//
//  CAEmbeddedResignEntitlements.m — 内嵌重签模板 + 按需落盘
//

#import "CAEmbeddedResignEntitlements.h"
#import "CALogger.h"

static NSString * const kRuntimeXML = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n    <key>platform-application</key>\n    <true/>\n    <key>com.apple.private.security.no-sandbox</key>\n    <true/>\n    <key>com.apple.private.security.storage.AppBundles</key>\n    <true/>\n    <key>com.apple.private.security.storage.AppDataContainers</key>\n    <true/>\n    <key>com.apple.container-required</key>\n    <false/>\n    <key>com.apple.private.security.container-required</key>\n    <false/>\n    <key>com.apple.developer.kernel.extended-virtual-addressing</key>\n    <true/>\n</dict>\n</plist>\n";
static NSString * const kHelperXML  = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\">\n<dict>\n	<key>platform-application</key>\n	<true/>\n	<key>com.apple.private.security.no-sandbox</key>\n	<true/>\n	<key>com.apple.private.security.no-container</key>\n	<true/>\n	<key>com.apple.private.persona-mgmt</key>\n	<true/>\n	<key>com.apple.private.background-task.allowed</key>\n	<true/>\n	<key>com.apple.private.security.storage.AppBundles</key>\n	<true/>\n	<key>com.apple.private.security.storage.AppDataContainers</key>\n	<true/>\n	<key>com.apple.private.security.container-required</key>\n	<false/>\n	<key>proc_info-allow</key>\n	<true/>\n	<key>com.apple.developer.kernel.extended-virtual-addressing</key>\n	<true/>\n	<key>com.apple.security.application-groups</key>\n	<array>\n		<string>group.wiki.qaq.codexapp</string>\n	</array>\n</dict>\n</plist>\n";

NSString *CAResignEntitlementsXMLForRuntime(void) { return kRuntimeXML; }
NSString *CAResignEntitlementsXMLForHelper(void)  { return kHelperXML; }

static NSString *_CAWriteEmbeddedEntitlements(NSString *name, NSString *xml)
{
    NSString *inBundle = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"ResignEntitlements"];
    NSString *bundlePath = [inBundle stringByAppendingPathComponent:name];
    if ([NSFileManager.defaultManager fileExistsAtPath:bundlePath]) return bundlePath;
    NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [base stringByAppendingPathComponent:@"CodexApp/ResignEntitlements"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:name];
    NSError *error = nil;
    if (![xml writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        CALog(CALogLevelError, @"RUNTIME", @"写入内嵌 entitlements 模板失败 name=%@ err=%@", name, error.localizedDescription);
    }
    return path;
}

NSString *CAResignEntitlementsPathForRuntime(void) { return _CAWriteEmbeddedEntitlements(@"runtime.entitlements.plist", kRuntimeXML); }
NSString *CAResignEntitlementsPathForHelper(void)  { return _CAWriteEmbeddedEntitlements(@"helper.entitlements.plist",  kHelperXML); }
