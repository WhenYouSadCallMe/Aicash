//
//  CAArchiveExtractor.m
//  对齐原包：tar.gz 与 deb 解包、路径逃逸防护（safeRelativePath:）、
//           支持 tar 条目类型：regular file / directory / symbolic link / hard link / GNU long name / PAX
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CAArchiveExtractor.h"
#import "CALogger.h"
#import <zlib.h>
#import <sys/stat.h>

static const size_t kTarBlock = 512;

@implementation CAArchiveExtractor

#pragma mark - 路径防护

+ (NSString *)safeRelativePath:(NSString *)relative inRoot:(NSString *)root error:(NSError **)error
{
    return [CARuntimePaths safeRelativePath:relative inRoot:root error:error];
}

#pragma mark - tar.gz

+ (BOOL)extractTarGzip:(NSString *)archivePath
           toDirectory:(NSString *)destination
  expectedExpandedSize:(unsigned long long)expectedExpandedSize
              progress:(CAArchiveProgressHandler)progress
                 error:(NSError **)error
{
    NSData *tarData = [self gunzipDataAtPath:archivePath error:error];
    if (!tarData) return NO;
    if (expectedExpandedSize > 0 && tarData.length > expectedExpandedSize * 2) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Archive" code:413
                                            userInfo:@{ NSLocalizedDescriptionKey: @"expanded size exceeds expectation" }];
        return NO;
    }
    return [self extractTarData:tarData toDirectory:destination progress:progress error:error];
}

+ (BOOL)extractRuntimeFromDeb:(NSString *)debPath toDirectory:(NSString *)destination progress:(CAArchiveProgressHandler)progress error:(NSError **)error
{
    NSData *arData = [NSData dataWithContentsOfFile:debPath options:NSDataReadingMappedIfSafe error:error];
    if (!arData) return NO;
    const char *magic = "!<arch>\n";
    if (arData.length < 8 || memcmp(arData.bytes, magic, 8) != 0) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Archive" code:400
                                            userInfo:@{ NSLocalizedDescriptionKey: @"not an ar/deb container" }];
        return NO;
    }
    NSUInteger cursor = 8;
    NSData *payload = nil;
    NSString *memberName = nil;
    while (cursor + 60 <= arData.length) {
        const uint8_t *header = (const uint8_t *)arData.bytes + cursor;
        char name[17] = {0};
        memcpy(name, header, 16);
        NSString *member = [[NSString stringWithUTF8String:name] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *sizeString = [[[NSString alloc] initWithBytes:header + 48 length:10 encoding:NSUTF8StringEncoding]
                                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSUInteger size = (NSUInteger)sizeString.longLongValue;
        NSUInteger dataStart = cursor + 60;
        if (dataStart + size > arData.length) break;
        if ([member hasPrefix:@"data.tar"]) {
            payload = [arData subdataWithRange:NSMakeRange(dataStart, size)];
            memberName = member;
            break;
        }
        cursor = dataStart + size + (size % 2);
    }
    if (!payload) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Archive" code:404
                                            userInfo:@{ NSLocalizedDescriptionKey: @"deb has no data.tar member" }];
        return NO;
    }

    // data.tar.gz → zlib 直接解；data.tar.xz / data.tar.zst → 交给外部解码器（Helpers 内置或系统路径）
    if ([memberName containsString:@".xz"] || [memberName containsString:@".zst"]) {
        BOOL isZstd = [memberName containsString:@".zst"];
        NSData *decoded = [self decodeWithExternalTool:payload
                                              isZstd:isZstd
                                            progress:progress
                                                 error:error];
        if (!decoded) {
            CALog(CALogLevelError, @"RUNTIME", @"deb payload %@ 需要 %@ 解码器：未找到可用工具",
                  memberName, isZstd ? @"zstd" : @"xz");
            return NO;
        }
        payload = decoded;
    }
    return [self extractTarData:payload toDirectory:destination progress:progress error:error];
}

#pragma mark - 外部解码（xz / zstd）

+ (nullable NSData *)decodeWithExternalTool:(NSData *)payload
                                     isZstd:(BOOL)isZstd
                                   progress:(CAArchiveProgressHandler)progress
                                      error:(NSError **)error
{
    NSString *suffix = isZstd ? @"zst" : @"xz";
    NSString *tmpDir = CARuntimePaths.tmpDirectory;
    [CARuntimePaths ensureDirectory:tmpDir mode:0700 error:NULL];
    NSString *input = [tmpDir stringByAppendingPathComponent:[NSString stringWithFormat:@"deb-payload-%@.%@", NSUUID.UUID.UUIDString, suffix]];
    NSString *output = [input stringByAppendingPathExtension:@"tar"];
    if (![payload writeToFile:input options:NSDataWritingAtomic error:error]) return nil;

    NSArray<NSString *> *candidates = isZstd
        ? @[ [[CARuntimePaths helpersDirectory] stringByAppendingPathComponent:@"zstd"],
             @"/var/jb/usr/bin/zstd", @"/var/jb/bin/zstd", @"/usr/local/bin/zstd", @"/usr/bin/zstd" ]
        : @[ [[CARuntimePaths helpersDirectory] stringByAppendingPathComponent:@"xz"],
             @"/var/jb/usr/bin/xz", @"/var/jb/bin/xz", @"/usr/local/bin/xz", @"/usr/bin/xz" ];

    NSString *tool = nil;
    for (NSString *candidate in candidates) {
        if ([NSFileManager.defaultManager isExecutableFileAtPath:candidate]) { tool = candidate; break; }
    }
    if (!tool) {
        [NSFileManager.defaultManager removeItemAtPath:input error:NULL];
        return nil;
    }
    if (progress) progress(0.3, [NSString stringWithFormat:@"decoding %@ via %@", suffix, tool.lastPathComponent]);

    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:tool];
    task.arguments = @[ @"-dc", input ];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSPipe pipe];
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        [NSFileManager.defaultManager removeItemAtPath:input error:NULL];
        if (error) *error = launchError;
        return nil;
    }
    NSData *decoded = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    [NSFileManager.defaultManager removeItemAtPath:input error:NULL];
    if (task.terminationStatus != 0 || !decoded.length) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Archive" code:task.terminationStatus
                                            userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ 解码失败 status=%d", suffix, task.terminationStatus] }];
        return nil;
    }
    [decoded writeToFile:output options:NSDataWritingAtomic error:NULL];
    [NSFileManager.defaultManager removeItemAtPath:output error:NULL];
    return decoded;
}

+ (NSData *)gunzipDataAtPath:(NSString *)path error:(NSError **)error
{
    gzFile file = gzopen(path.fileSystemRepresentation, "rb");
    if (!file) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Archive" code:404 userInfo:@{ NSLocalizedDescriptionKey: @"cannot open archive" }];
        return nil;
    }
    NSMutableData *output = [NSMutableData data];
    uint8_t buffer[64 * 1024];
    int read = 0;
    while ((read = gzread(file, buffer, sizeof(buffer))) > 0) {
        [output appendBytes:buffer length:(NSUInteger)read];
    }
    int status = 0;
    gzerror(file, &status);
    gzclose(file);
    if (output.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Archive" code:500 userInfo:@{ NSLocalizedDescriptionKey: @"gunzip produced no data" }];
        return nil;
    }
    return output;
}

#pragma mark - tar 解析

+ (BOOL)extractTarData:(NSData *)tarData toDirectory:(NSString *)destination progress:(CAArchiveProgressHandler)progress error:(NSError **)error
{
    NSError *dirError = nil;
    if (![CARuntimePaths ensureDirectory:destination mode:0755 error:&dirError]) {
        if (error) *error = dirError;
        return NO;
    }
    const uint8_t *bytes = tarData.bytes;
    NSUInteger offset = 0;
    NSString *pendingLongName = nil;
    NSString *pendingLongLink = nil;
    unsigned long long totalFiles = 0;

    while (offset + kTarBlock <= tarData.length) {
        const uint8_t *header = bytes + offset;
        if (header[0] == 0) { offset += kTarBlock; continue; }   // 结束块

        NSString *rawName = [self stringFromTarField:header + 0 length:100];
        NSString *prefix = [self stringFromTarField:header + 345 length:155];
        NSString *member = rawName;
        if (prefix.length) member = [prefix stringByAppendingPathComponent:member];

        char type = (char)header[156];
        unsigned long long size = [self octalFromField:header + 124 length:12];
        const uint8_t *data = bytes + offset + kTarBlock;

        if (type == 'L') {   // GNU long name
            pendingLongName = [self stringFromTarData:[NSData dataWithBytes:data length:(NSUInteger)size]];
            offset += kTarBlock + [self padded:size];
            continue;
        }
        if (type == 'K') {   // GNU long link
            pendingLongLink = [self stringFromTarData:[NSData dataWithBytes:data length:(NSUInteger)size]];
            offset += kTarBlock + [self padded:size];
            continue;
        }
        if (type == 'x' || type == 'g') {   // PAX
            offset += kTarBlock + [self padded:size];
            continue;
        }
        if (pendingLongName.length) { member = pendingLongName; pendingLongName = nil; }

        NSError *escape = nil;
        NSString *target = [self safeRelativePath:member inRoot:destination error:&escape];
        if (!target) {
            CALog(CALogLevelWarn, @"RUNTIME", @"archive entry rejected path=%@ reason=%@", member, escape.localizedDescription);
            offset += kTarBlock + [self padded:size];
            continue;
        }

        NSFileManager *fm = NSFileManager.defaultManager;
        switch (type) {
            case '5': {   // directory
                [fm createDirectoryAtPath:target withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions: @(0755) } error:NULL];
                break;
            }
            case '2': {   // symbolic link
                NSString *linkTarget = pendingLongLink.length ? pendingLongLink : [self stringFromTarField:header + 157 length:100];
                pendingLongLink = nil;
                [fm removeItemAtPath:target error:NULL];
                NSError *linkError = nil;
                if (![fm createSymbolicLinkAtPath:target withDestinationPath:linkTarget error:&linkError]) {
                    CALog(CALogLevelWarn, @"RUNTIME", @"symbolic link failed path=%@ target=%@ error=%@", target, linkTarget, linkError.localizedDescription);
                }
                break;
            }
            case '1': {   // hard link
                NSString *linkTarget = [self safeRelativePath:[self stringFromTarField:header + 157 length:100] inRoot:destination error:NULL];
                [fm removeItemAtPath:target error:NULL];
                if (linkTarget) [fm linkItemAtPath:linkTarget toPath:target error:NULL];
                break;
            }
            default: {    // regular file
                NSString *parent = target.stringByDeletingLastPathComponent;
                [fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions: @(0755) } error:NULL];
                NSData *fileData = [NSData dataWithBytes:data length:(NSUInteger)size];
                NSError *writeError = nil;
                if (![fileData writeToFile:target options:NSDataWritingAtomic error:&writeError]) {
                    CALog(CALogLevelWarn, @"RUNTIME", @"extract write failed path=%@ error=%@", target, writeError.localizedDescription);
                } else {
                    unsigned long long mode = [self octalFromField:header + 100 length:8];
                    if (mode) chmod(target.fileSystemRepresentation, (mode_t)(mode & 07777));
                    totalFiles += 1;
                }
                break;
            }
        }
        offset += kTarBlock + [self padded:size];
        if (progress && (totalFiles % 32 == 0)) {
            progress((double)offset / (double)tarData.length, [NSString stringWithFormat:@"extracting %@", member.lastPathComponent]);
        }
    }
    if (progress) progress(1.0, @"extracting complete");
    CALog(CALogLevelInfo, @"RUNTIME", @"archive extracted files=%llu destination=%@", totalFiles, destination);
    return YES;
}

+ (NSUInteger)padded:(unsigned long long)size { return (NSUInteger)((size + kTarBlock - 1) / kTarBlock * kTarBlock); }

+ (NSString *)stringFromTarField:(const uint8_t *)field length:(NSUInteger)length
{
    char buffer[512] = {0};
    memcpy(buffer, field, MIN(length, sizeof(buffer) - 1));
    return [NSString stringWithUTF8String:buffer] ?: @"";
}

+ (NSString *)stringFromTarData:(NSData *)data
{
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\0\n"]] ?: @"";
}

+ (unsigned long long)octalFromField:(const uint8_t *)field length:(NSUInteger)length
{
    char buffer[32] = {0};
    memcpy(buffer, field, MIN(length, sizeof(buffer) - 1));
    return strtoull(buffer, NULL, 8);
}

@end
