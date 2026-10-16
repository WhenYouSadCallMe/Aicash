//
//  CAFileToolMain.m — ca-filetool 多调用工具集（原包 Helpers/ca-filetool）
//  原包符号：CAFileToolMain / CAFileToolShouldHandleArguments / CATheosHelperAssembleDeb /
//           CATheosHelperSpawnArray / CATheosHelperTreeBytes / CATheosHelperVerifyDebArchive /
//           CATheosHelperWriteArMember / CATarWriteHeader / CATarAddPath / CAFindParseAnd/Or/Not /
//           CASortKeyFromSpec / CAStandaloneWriteAll / CAHumanReadableBytes …
//  调用名（全部由包内符号链接决定）：cat ls grep sed find tar cp mv rm mkdir touch stat uname
//           which xxd od wc head tail sort uniq nl du basename dirname readlink realpath chmod ln tee
//           theos-helper
//

#import "CACommon.h"
#import "CARuntimePaths.h"
#import "CAArchiveExtractor.h"
#import <sys/stat.h>
#import <sys/utsname.h>
#import <dirent.h>
#import <zlib.h>
#import "CAProcess.h"

#pragma mark - 小工具

static void CAWriteAll(NSFileHandle *handle, NSData *data) { [handle writeData:data]; }

static NSString *CABaseName(NSString *path)
{
    NSString *stripped = [path stringByStandardizingPath];
    if ([stripped isEqualToString:@"/"]) return @"/";
    return stripped.lastPathComponent;
}

static NSString *CADirName(NSString *path)
{
    NSString *dir = [path stringByDeletingLastPathComponent];
    return dir.length ? dir : @"/";
}

static NSString *CAHumanReadableBytes(unsigned long long bytes)
{
    NSArray *units = @[ @"B", @"K", @"M", @"G", @"T" ];
    double value = (double)bytes;
    NSUInteger index = 0;
    while (value >= 1024.0 && index + 1 < units.count) { value /= 1024.0; index += 1; }
    return index == 0 ? [NSString stringWithFormat:@"%lluB", bytes] : [NSString stringWithFormat:@"%.1f%@", value, units[index]];
}

static int CAUnsupported(NSString *tool, NSString *argument)
{
    fprintf(stderr, "%s: unsupported argument: %s\n", tool.UTF8String, argument.UTF8String);
    return 2;
}

static NSArray<NSString *> *CAJoinedArguments(int argc, char **argv, int startIndex)
{
    NSMutableArray<NSString *> *arguments = [NSMutableArray array];
    for (int i = startIndex; i < argc; i++) [arguments addObject:[NSString stringWithUTF8String:argv[i]]];
    return arguments;
}

#pragma mark - 工具实现

static int CAToolCat(int argc, char **argv)
{
    NSFileHandle *out = NSFileHandle.fileHandleWithStandardOutput;
    for (int i = 1; i < argc; i++) {
        NSString *path = [NSString stringWithUTF8String:argv[i]];
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) { fprintf(stderr, "cat: %s: No such file or directory\n", path.UTF8String); return 1; }
        CAWriteAll(out, data);
    }
    return 0;
}

static int CAToolTee(int argc, char **argv)
{
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    BOOL append = NO;
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-a"]) { append = YES; continue; }
        [files addObject:argument];
    }
    NSFileHandle *in = NSFileHandle.fileHandleWithStandardInput;
    NSData *data = [in readDataToEndOfFile];
    CAWriteAll(NSFileHandle.fileHandleWithStandardOutput, data);
    for (NSString *path in files) {
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:@{ NSFilePosixPermissions: @(0644) }];
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (append) [handle seekToEndOfFile];
        CAWriteAll(handle, data);
        [handle closeFile];
    }
    return 0;
}

static int CAToolLs(int argc, char **argv)
{
    BOOL longFormat = NO, showAll = NO, human = NO, recursive = NO, directoryOnly = NO;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-l"]) longFormat = YES;
        else if ([argument isEqualToString:@"-a"] || [argument isEqualToString:@"--all"]) showAll = YES;
        else if ([argument isEqualToString:@"-h"] || [argument isEqualToString:@"--human-readable"]) human = YES;
        else if ([argument isEqualToString:@"-R"] || [argument isEqualToString:@"--recursive"]) recursive = YES;
        else if (argument.length && [argument characterAtIndex:0] == '-') { /* 忽略其余开关 */ }
        else [paths addObject:argument];
    }
    if (!paths.count) [paths addObject:@"."];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *path in paths) {
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:path isDirectory:&isDirectory]) { fprintf(stderr, "ls: %s: No such file or directory\n", path.UTF8String); return 1; }
        NSArray<NSString *> *names = isDirectory ? [fm contentsOfDirectoryAtPath:path error:NULL] : @[ path ];
        if (!isDirectory && directoryOnly) continue;
        names = [names sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *name in names) {
            if (!showAll && [name hasPrefix:@"."]) continue;
            NSString *full = isDirectory ? [path stringByAppendingPathComponent:name] : name;
            if (longFormat) {
                NSDictionary *attributes = [fm attributesOfItemAtPath:full error:NULL];
                unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
                printf("%s %8llu %s %s\n", [attributes[NSFilePosixPermissions] stringValue].UTF8String,
                       size, human ? CAHumanReadableBytes(size).UTF8String : "",
                       (isDirectory ? name : full).UTF8String);
            } else {
                printf("%s\n", (isDirectory ? name : full).UTF8String);
            }
        }
    }
    return 0;
}

static int CAToolMkdir(int argc, char **argv)
{
    BOOL parents = NO, verbose = NO;
    mode_t mode = 0755;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-p"]) parents = YES;
        else if ([argument isEqualToString:@"-v"]) verbose = YES;
        else if ([argument isEqualToString:@"-m"] && i + 1 < argc) mode = (mode_t)strtol(argv[++i], NULL, 8);
        else [paths addObject:argument];
    }
    for (NSString *path in paths) {
        NSError *error = nil;
        BOOL ok = [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:parents
                                                           attributes:@{ NSFilePosixPermissions: @(mode) } error:&error];
        if (!ok && !parents) { fprintf(stderr, "mkdir: %s: %s\n", path.UTF8String, error.localizedDescription.UTF8String); return 1; }
        if (ok && verbose) printf("mkdir: created directory '%s'\n", path.UTF8String);
    }
    return 0;
}

static int CAToolRemove(int argc, char **argv)
{
    BOOL recursive = NO, force = NO;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-r"] || [argument isEqualToString:@"-R"] || [argument isEqualToString:@"--recursive"]) recursive = YES;
        else if ([argument isEqualToString:@"-f"] || [argument isEqualToString:@"--force"]) force = YES;
        else if ([argument isEqualToString:@"-rf"] || [argument isEqualToString:@"-fr"]) { recursive = YES; force = YES; }
        else [paths addObject:argument];
    }
    for (NSString *path in paths) {
        NSError *error = nil;
        BOOL isDirectory = NO;
        BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory];
        if (!exists) {
            if (!force) { fprintf(stderr, "rm: %s: No such file or directory\n", path.UTF8String); return 1; }
            continue;
        }
        if (isDirectory && !recursive) { fprintf(stderr, "rm: %s: is a directory\n", path.UTF8String); return 1; }
        if (![NSFileManager.defaultManager removeItemAtPath:path error:&error]) {
            fprintf(stderr, "rm: %s: %s\n", path.UTF8String, error.localizedDescription.UTF8String);
            return 1;
        }
        CALog(CALogLevelDebug, @"SHELL", @"protected remove path=%@ success=YES", path);
    }
    return 0;
}

static int CAToolTouch(int argc, char **argv)
{
    NSArray<NSString *> *paths = CAJoinedArguments(argc, argv, 1);
    for (NSString *path in paths) {
        NSFileManager *fm = NSFileManager.defaultManager;
        if (![fm fileExistsAtPath:path]) {
            if (![fm createFileAtPath:path contents:nil attributes:@{ NSFilePosixPermissions: @(0644) }]) return 1;
        } else {
            [fm setAttributes:@{ NSFileModificationDate: [NSDate date] } ofItemAtPath:path error:NULL];
        }
    }
    return 0;
}

static int CATreeCopy(NSString *source, NSString *destination, BOOL move)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *error = nil;
    BOOL isDirectory = NO;
    [fm fileExistsAtPath:source isDirectory:&isDirectory];
    NSString *target = destination;
    if (isDirectory) {
        NSString *base = source.lastPathComponent;
        target = [destination stringByAppendingPathComponent:base];
        if (![fm fileExistsAtPath:target]) {
            if (![fm createDirectoryAtPath:target withIntermediateDirectories:YES attributes:@{ NSFilePosixPermissions: @(0755) } error:&error]) return 1;
        }
        for (NSString *name in [fm contentsOfDirectoryAtPath:source error:NULL]) {
            if (CATreeCopy([source stringByAppendingPathComponent:name], target, move) != 0) return 1;
        }
        if (move) [fm removeItemAtPath:source error:NULL];
        return 0;
    }
    if ([fm fileExistsAtPath:target isDirectory:&isDirectory] && isDirectory) {
        target = [target stringByAppendingPathComponent:source.lastPathComponent];
    }
    [fm removeItemAtPath:target error:NULL];
    NSData *data = [NSData dataWithContentsOfFile:source options:NSDataReadingMappedIfSafe error:&error];
    if (!data) data = [NSData dataWithContentsOfFile:source];
    unsigned long command = move ? 0 : 0;
    if (move) {
        if ([fm moveItemAtPath:source toPath:target error:&error]) { (void)command; return 0; }
    }
    if (data && [data writeToFile:target options:NSDataWritingAtomic error:&error]) {
        NSDictionary *attributes = [fm attributesOfItemAtPath:source error:NULL];
        if (attributes[NSFilePosixPermissions]) chmod(target.fileSystemRepresentation, (mode_t)[attributes[NSFilePosixPermissions] unsignedLongValue]);
        return 0;
    }
    fprintf(stderr, "copyfile: %s -> %s: %s\n", source.UTF8String, target.UTF8String, error.localizedDescription.UTF8String);
    return 1;
}

static int CAToolCopyOrMove(int argc, char **argv, BOOL move)
{
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if (argument.length && [argument characterAtIndex:0] == '-') continue;
        [paths addObject:argument];
    }
    if (paths.count < 2) return CAUnsupported(move ? @"mv" : @"cp", @"missing operand");
    NSString *destination = paths.lastObject;
    for (NSUInteger i = 0; i + 1 < paths.count; i++) {
        if (CATreeCopy(paths[i], destination, move) != 0) return 1;
    }
    return 0;
}

static int CAToolChmod(int argc, char **argv)
{
    if (argc < 3) return CAUnsupported(@"chmod", @"missing operand");
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    mode_t mode = 0;
    BOOL recursive = NO;
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-R"]) { recursive = YES; continue; }
        if (mode == 0) { mode = (mode_t)strtol(argument.UTF8String, NULL, 8); continue; }
        [paths addObject:argument];
    }
    for (NSString *path in paths) {
        chmod(path.fileSystemRepresentation, mode);
        if (recursive) {
            for (NSString *relative in [NSFileManager.defaultManager enumeratorAtPath:path]) {
                chmod([path stringByAppendingPathComponent:relative].fileSystemRepresentation, mode);
            }
        }
    }
    return 0;
}

static int CAToolLink(int argc, char **argv)
{
    if (argc < 3) return CAUnsupported(@"ln", @"missing operand");
    BOOL symbolic = NO;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-s"]) { symbolic = YES; continue; }
        if ([argument isEqualToString:@"-f"]) continue;
        [paths addObject:argument];
    }
    if (paths.count < 2) return CAUnsupported(@"ln", @"missing operand");
    NSError *error = nil;
    [NSFileManager.defaultManager removeItemAtPath:paths[1] error:NULL];
    if (symbolic) return [NSFileManager.defaultManager createSymbolicLinkAtPath:paths[1] withDestinationPath:paths[0] error:&error] ? 0 : 1;
    return [NSFileManager.defaultManager linkItemAtPath:paths[0] toPath:paths[1] error:&error] ? 0 : 1;
}

static int CAToolStat(int argc, char **argv)
{
    NSArray<NSString *> *paths = CAJoinedArguments(argc, argv, 1);
    for (NSString *path in paths) {
        struct stat st;
        if (stat(path.fileSystemRepresentation, &st) != 0) { fprintf(stderr, "stat: %s: No such file or directory\n", path.UTF8String); return 1; }
        printf("%o %lld %lld %s\n", st.st_mode & 07777, (long long)st.st_size, (long long)st.st_mtime, path.UTF8String);
    }
    return 0;
}

static int CAToolUname(int argc, char **argv)
{
    struct utsname info;
    uname(&info);
    BOOL unsupported = NO;
    NSString *unexpected = nil;
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-a"]) { printf("%s %s %s %s %s\n", info.sysname, info.nodename, info.release, info.version, info.machine); return 0; }
        if ([argument isEqualToString:@"-s"] || [argument isEqualToString:@"-o"]) { printf("%s\n", info.sysname); continue; }
        if ([argument isEqualToString:@"-n"]) { printf("%s\n", info.nodename); continue; }
        if ([argument isEqualToString:@"-r"]) { printf("%s\n", info.release); continue; }
        if ([argument isEqualToString:@"-v"]) { printf("%s\n", info.version); continue; }
        if ([argument isEqualToString:@"-m"]) { printf("%s\n", info.machine); continue; }
        if ([argument hasPrefix:@"-"] && ![argument isEqualToString:@"-s"]) { unsupported = YES; unexpected = argument; }
    }
    if (unsupported) { fprintf(stderr, "uname: unsupported argument: %s\n", unexpected.UTF8String); return 2; }
    if (argc == 1) printf("%s\n", info.sysname);
    return 0;
}

static int CAToolWhich(int argc, char **argv)
{
    NSString *path = NSProcessInfo.processInfo.environment[@"PATH"] ?: CARuntimePaths.helperSearchPath;
    int status = 0;
    for (int i = 1; i < argc; i++) {
        NSString *name = [NSString stringWithUTF8String:argv[i]];
        if ([name isEqualToString:@"-v"] || [name isEqualToString:@"-V"] || [name isEqualToString:@"-a"]) continue;
        NSString *found = nil;
        if ([name containsString:@"/"]) {
            if ([NSFileManager.defaultManager isExecutableFileAtPath:name]) found = name;
        } else {
            for (NSString *dir in [path componentsSeparatedByString:@":"]) {
                NSString *candidate = [dir stringByAppendingPathComponent:name];
                if ([NSFileManager.defaultManager isExecutableFileAtPath:candidate]) { found = candidate; break; }
            }
        }
        if (found) printf("%s\n", found.UTF8String);
        else { status = 1; }
    }
    return status;
}

static int CAToolBasename(int argc, char **argv)
{
    if (argc < 2) return CAUnsupported(@"basename", @"missing operand");
    printf("%s\n", CABaseName([NSString stringWithUTF8String:argv[1]]).UTF8String);
    return 0;
}

static int CAToolDirname(int argc, char **argv)
{
    if (argc < 2) return CAUnsupported(@"dirname", @"missing operand");
    printf("%s\n", CADirName([NSString stringWithUTF8String:argv[1]]).UTF8String);
    return 0;
}

static int CAToolReadlink(int argc, char **argv)
{
    if (argc < 2) return CAUnsupported(@"readlink", @"missing operand");
    BOOL canonical = NO;
    NSString *path = nil;
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-f"]) { canonical = YES; continue; }
        path = argument;
    }
    if (!path.length) return CAUnsupported(@"readlink", @"missing operand");
    char buffer[PATH_MAX];
    ssize_t length = readlink(path.fileSystemRepresentation, buffer, sizeof(buffer) - 1);
    if (length < 0) return 1;
    buffer[length] = 0;
    if (canonical) {
        char resolved[PATH_MAX];
        if (realpath(path.fileSystemRepresentation, resolved)) { printf("%s\n", resolved); return 0; }
    }
    printf("%s\n", buffer);
    return 0;
}

static int CAToolRealpath(int argc, char **argv)
{
    for (int i = 1; i < argc; i++) {
        char resolved[PATH_MAX];
        NSString *path = [NSString stringWithUTF8String:argv[i]];
        if (realpath(path.fileSystemRepresentation, resolved)) printf("%s\n", resolved);
        else { fprintf(stderr, "realpath: %s: No such file or directory\n", path.UTF8String); return 1; }
    }
    return 0;
}

static int CAToolDu(int argc, char **argv)
{
    BOOL human = NO, summary = NO;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-h"]) human = YES;
        else if ([argument isEqualToString:@"-s"]) summary = YES;
        else [paths addObject:argument];
    }
    if (!paths.count) [paths addObject:@"."];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *path in paths) {
        unsigned long long total = 0;
        BOOL isDirectory = NO;
        [fm fileExistsAtPath:path isDirectory:&isDirectory];
        if (isDirectory) {
            for (NSString *relative in [fm enumeratorAtPath:path]) {
                NSDictionary *attributes = [fm attributesOfItemAtPath:[path stringByAppendingPathComponent:relative] error:NULL];
                if ([attributes[NSFileType] isEqual:NSFileTypeRegular]) total += [attributes[NSFileSize] unsignedLongLongValue];
            }
        } else {
            total = [[fm attributesOfItemAtPath:path error:NULL][NSFileSize] unsignedLongLongValue];
        }
        if (human) printf("%s\t%s\n", CAHumanReadableBytes(total).UTF8String, path.UTF8String);
        else printf("%llu\t%s\n", total / 1024, path.UTF8String);
    }
    return 0;
}

static int CAToolWc(int argc, char **argv)
{
    BOOL countLines = NO, countWords = NO, countBytes = NO;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-l"] || [argument isEqualToString:@"--lines"]) countLines = YES;
        else if ([argument isEqualToString:@"-w"] || [argument isEqualToString:@"--words"]) countWords = YES;
        else if ([argument isEqualToString:@"-c"] || [argument isEqualToString:@"--bytes"]) countBytes = YES;
        else [paths addObject:argument];
    }
    if (!countLines && !countWords && !countBytes) { countLines = countWords = countBytes = YES; }
    NSData *input = nil;
    if (!paths.count) input = [NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile];
    NSMutableArray<NSData *> *datas = [NSMutableArray array];
    if (input) [datas addObject:input];
    else for (NSString *path in paths) { NSData *d = [NSData dataWithContentsOfFile:path]; if (d) [datas addObject:d]; }
    for (NSData *data in datas) {
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
        if (countLines) printf("%lu ", (unsigned long)[text componentsSeparatedByString:@"\n"].count - 1);
        if (countWords) printf("%lu ", (unsigned long)[[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] count]);
        if (countBytes) printf("%lu ", (unsigned long)data.length);
        printf("\n");
    }
    return 0;
}

static int CAToolHeadOrTail(int argc, char **argv, BOOL tail)
{
    NSInteger lines = 10;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-n"] && i + 1 < argc) { lines = [NSString stringWithUTF8String:argv[++i]].integerValue; continue; }
        if ([argument hasPrefix:@"-n"]) { lines = [argument substringFromIndex:2].integerValue; continue; }
        if ([argument hasPrefix:@"-"] && argument.length > 1 && isdigit((unsigned char)[argument characterAtIndex:1])) { lines = [argument substringFromIndex:1].integerValue; continue; }
        [paths addObject:argument];
    }
    NSString *text = nil;
    if (paths.count) text = [NSString stringWithContentsOfFile:paths.firstObject encoding:NSUTF8StringEncoding error:NULL];
    else text = [[NSString alloc] initWithData:[NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile] encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *all = [text ?: @"" componentsSeparatedByString:@"\n"];
    NSArray<NSString *> *selected = tail ? [all subarrayWithRange:NSMakeRange((NSUInteger)MAX(0, (NSInteger)all.count - lines), (NSUInteger)MIN((NSInteger)lines, (NSInteger)all.count))]
                                        : [all subarrayWithRange:NSMakeRange(0, (NSUInteger)MIN((NSInteger)lines, (NSInteger)all.count))];
    for (NSString *line in selected) if (line.length) printf("%s\n", line.UTF8String);
    return 0;
}

static int CAToolGrep(int argc, char **argv)
{
    BOOL ignoreCase = NO, showLineNumber = NO, countOnly = NO, filesWithMatches = NO, invert = NO, fixed = NO;
    NSMutableArray<NSString *> *operands = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-i"] || [argument isEqualToString:@"--ignore-case"]) ignoreCase = YES;
        else if ([argument isEqualToString:@"-n"] || [argument isEqualToString:@"--line-number"]) showLineNumber = YES;
        else if ([argument isEqualToString:@"-c"] || [argument isEqualToString:@"--count"]) countOnly = YES;
        else if ([argument isEqualToString:@"-l"] || [argument isEqualToString:@"--files-with-matches"]) filesWithMatches = YES;
        else if ([argument isEqualToString:@"-v"] || [argument isEqualToString:@"--invert-match"]) invert = YES;
        else if ([argument isEqualToString:@"-F"] || [argument isEqualToString:@"--fixed-strings"]) fixed = YES;
        else if ([argument isEqualToString:@"-r"] || [argument isEqualToString:@"-R"] || [argument isEqualToString:@"--recursive"]) continue;
        else if (argument.length && [argument characterAtIndex:0] == '-') continue;
        else [operands addObject:argument];
    }
    if (!operands.count) return CAUnsupported(@"grep", @"missing pattern");
    NSString *pattern = operands.firstObject;
    NSArray<NSString *> *paths = operands.count > 1 ? [operands subarrayWithRange:NSMakeRange(1, operands.count - 1)] : @[];
    NSRegularExpression *regex = fixed ? nil : [NSRegularExpression regularExpressionWithPattern:pattern options:ignoreCase ? NSRegularExpressionCaseInsensitive : 0 error:NULL];

    NSMutableArray<NSString *> *sources = [NSMutableArray array];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *path in paths) {
        BOOL isDirectory = NO;
        [fm fileExistsAtPath:path isDirectory:&isDirectory];
        if (isDirectory) {
            for (NSString *relative in [fm enumeratorAtPath:path]) {
                NSString *full = [path stringByAppendingPathComponent:relative];
                NSDictionary *attributes = [fm attributesOfItemAtPath:full error:NULL];
                if ([attributes[NSFileType] isEqual:NSFileTypeRegular]) [sources addObject:full];
            }
        } else [sources addObject:path];
    }
    if (!sources.count) sources = @[ @"/dev/stdin" ];

    int status = 1;
    for (NSString *source in sources) {
        NSString *text = [source isEqualToString:@"/dev/stdin"]
            ? [[NSString alloc] initWithData:[NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile] encoding:NSUTF8StringEncoding]
            : [NSString stringWithContentsOfFile:source encoding:NSUTF8StringEncoding error:NULL];
        if (!text) continue;
        NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
        NSUInteger matches = 0;
        for (NSUInteger index = 0; index < lines.count; index++) {
            NSString *line = lines[index];
            BOOL hit = NO;
            if (regex) hit = [regex firstMatchInString:line options:0 range:NSMakeRange(0, line.length)] != nil;
            else hit = ignoreCase ? ([line rangeOfString:pattern options:NSCaseInsensitiveSearch].location != NSNotFound)
                                  : ([line rangeOfString:pattern].location != NSNotFound);
            if (invert) hit = !hit;
            if (!hit) continue;
            matches += 1;
            status = 0;
            if (countOnly || filesWithMatches) continue;
            if (showLineNumber) printf("%lu:%s\n", (unsigned long)(index + 1), line.UTF8String);
            else printf("%s\n", line.UTF8String);
        }
        if (countOnly) printf("%lu\n", (unsigned long)matches);
        if (filesWithMatches && matches) printf("%s\n", source.UTF8String);
    }
    return status;
}

static int CAToolSed(int argc, char **argv)
{
    NSMutableArray<NSString *> *scripts = [NSMutableArray array];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-e"] && i + 1 < argc) { [scripts addObject:[NSString stringWithUTF8String:argv[++i]]]; continue; }
        if ([argument isEqualToString:@"-E"] || [argument isEqualToString:@"-r"]) continue;
        if ([argument isEqualToString:@"-i"]) { [paths addObject:@"-i"]; continue; }
        if (!scripts.count && ([argument containsString:@"s/"] || [argument containsString:@"s|"])) { [scripts addObject:argument]; continue; }
        if (!scripts.count && argument.length && [argument characterAtIndex:0] == '-') continue;
        if (!scripts.count) { [scripts addObject:argument]; continue; }
        [paths addObject:argument];
    }
    if (!scripts.count) return CAUnsupported(@"sed", @"no script");
    BOOL inPlace = [paths containsObject:@"-i"];
    [paths removeObject:@"-i"];

    NSString *script = scripts.firstObject;
    NSString *text = paths.count ? [NSString stringWithContentsOfFile:paths.firstObject encoding:NSUTF8StringEncoding error:NULL]
                                 : [[NSString alloc] initWithData:[NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile] encoding:NSUTF8StringEncoding];
    text = text ?: @"";

    NSString *output = text;
    if ([script hasPrefix:@"s"]) {
        unichar delimiter = [script characterAtIndex:1];
        NSArray<NSString *> *parts = [script componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:[NSString stringWithFormat:@"%C", delimiter]]];
        if (parts.count >= 4) {
            NSString *pattern = parts[1];
            NSString *replacement = parts[2];
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
            NSMutableString *mut = [output mutableCopy];
            [regex replaceMatchesInString:mut options:0 range:NSMakeRange(0, mut.length) withTemplate:replacement];
            output = mut;
        }
    } else if ([script hasPrefix:@"d"]) {
        output = @"";
    }

    if (inPlace && paths.count) {
        [output writeToFile:paths.firstObject atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    } else {
        printf("%s", output.UTF8String);
    }
    return 0;
}

static int CAToolSort(int argc, char **argv)
{
    BOOL numeric = NO, reverse = NO, unique = NO;
    NSString *keySpec = nil;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-n"]) numeric = YES;
        else if ([argument isEqualToString:@"-r"] || [argument isEqualToString:@"--reverse"]) reverse = YES;
        else if ([argument isEqualToString:@"-u"]) unique = YES;
        else if ([argument isEqualToString:@"--sort=size"]) keySpec = @"size";
        else if ([argument isEqualToString:@"--sort=time"]) keySpec = @"time";
        else if ([argument hasPrefix:@"-k"] && argument.length > 2) keySpec = [argument substringFromIndex:2];
        else if (argument.length && [argument characterAtIndex:0] == '-') continue;
        else [paths addObject:argument];
    }
    NSString *text = paths.count ? [NSString stringWithContentsOfFile:paths.firstObject encoding:NSUTF8StringEncoding error:NULL]
                                 : [[NSString alloc] initWithData:[NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile] encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [text ?: @"" componentsSeparatedByString:@"\n"];
    NSArray<NSString *> *sorted = [lines sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSComparisonResult result;
        if (numeric) result = [@(a.integerValue) compare:@(b.integerValue)];
        else if (keySpec.length) result = [a compare:b];
        else result = [a compare:b];
        return reverse ? (result == NSOrderedAscending ? NSOrderedDescending : (result == NSOrderedDescending ? NSOrderedAscending : NSOrderedSame)) : result;
    }];
    NSMutableArray<NSString *> *seen = [NSMutableArray array];
    for (NSString *line in sorted) {
        if (!line.length) continue;
        if (unique && [seen containsObject:line]) continue;
        [seen addObject:line];
        printf("%s\n", line.UTF8String);
    }
    return 0;
}

static int CAToolUniq(int argc, char **argv)
{
    BOOL count = NO, onlyDuplicates = NO;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-c"]) count = YES;
        else if ([argument isEqualToString:@"-d"]) onlyDuplicates = YES;
        else if (argument.length && [argument characterAtIndex:0] == '-') continue;
        else [paths addObject:argument];
    }
    NSString *text = paths.count ? [NSString stringWithContentsOfFile:paths.firstObject encoding:NSUTF8StringEncoding error:NULL]
                                 : [[NSString alloc] initWithData:[NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile] encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [text ?: @"" componentsSeparatedByString:@"\n"];
    NSString *previous = nil;
    NSUInteger repeats = 0;
    for (NSString *line in lines) {
        if (previous && [line isEqualToString:previous]) { repeats += 1; continue; }
        if (previous) {
            if (!onlyDuplicates || repeats > 0) printf(count ? "%7lu %s\n" : "%s\n", count ? (unsigned long)(repeats + 1) : 0, previous.UTF8String);
        }
        previous = line;
        repeats = 0;
    }
    return 0;
}

static int CAToolNl(int argc, char **argv)
{
    BOOL numberAll = NO;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument hasPrefix:@"-b"]) { numberAll = YES; continue; }
        if ([argument hasPrefix:@"-n"] || [argument hasPrefix:@"-w"] || [argument hasPrefix:@"-s"]) continue;
        [paths addObject:argument];
    }
    NSString *text = paths.count ? [NSString stringWithContentsOfFile:paths.firstObject encoding:NSUTF8StringEncoding error:NULL]
                                 : [[NSString alloc] initWithData:[NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile] encoding:NSUTF8StringEncoding];
    NSUInteger number = 1;
    for (NSString *line in [text ?: @"" componentsSeparatedByString:@"\n"]) {
        if (!line.length) continue;
        if (numberAll || line.length) printf("%6lu\t%s\n", (unsigned long)number++, line.UTF8String);
    }
    return 0;
}

static int CAToolHexDump(int argc, char **argv, BOOL octalMode)
{
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if (argument.length && [argument characterAtIndex:0] == '-') continue;
        [paths addObject:argument];
    }
    NSData *data = paths.count ? [NSData dataWithContentsOfFile:paths.firstObject] : [NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile];
    const uint8_t *bytes = data.bytes;
    for (NSUInteger offset = 0; offset < data.length; offset += 16) {
        NSMutableString *line = [NSMutableString stringWithFormat:@"%08lx: ", (unsigned long)offset];
        for (NSUInteger i = 0; i < 16; i++) {
            if (offset + i < data.length) [line appendFormat:octalMode ? @"%03o " : @"%02x ", bytes[offset + i]];
            else [line appendString:octalMode ? @"    " : @"   "];
        }
        [line appendString:@" "];
        for (NSUInteger i = 0; i < 16 && offset + i < data.length; i++) {
            uint8_t c = bytes[offset + i];
            [line appendFormat:@"%c", (c >= 0x20 && c < 0x7f) ? c : '.'];
        }
        printf("%s\n", line.UTF8String);
    }
    return 0;
}

#pragma mark - find（-name / -type / -maxdepth）

static int CAToolFind(int argc, char **argv)
{
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    NSString *namePattern = nil;
    NSString *typeFilter = nil;
    NSInteger maxDepth = -1;
    int i = 1;
    if (argc > 1 && argv[1][0] != '-') { [roots addObject:[NSString stringWithUTF8String:argv[1]]]; i = 2; }
    if (!roots.count) [roots addObject:@"."];
    for (; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if ([argument isEqualToString:@"-name"] && i + 1 < argc) { namePattern = [NSString stringWithUTF8String:argv[++i]]; continue; }
        if ([argument isEqualToString:@"-type"] && i + 1 < argc) { typeFilter = [NSString stringWithUTF8String:argv[++i]]; continue; }
        if ([argument isEqualToString:@"-maxdepth"] && i + 1 < argc) { maxDepth = [NSString stringWithUTF8String:argv[++i]].integerValue; continue; }
        if (argument.length && [argument characterAtIndex:0] == '-') continue;
        [roots addObject:argument];
    }
    NSRegularExpression *regex = namePattern ? [NSRegularExpression regularExpressionWithPattern:
        [NSString stringWithFormat:@"^%@$", [NSRegularExpression escapedPatternForString:namePattern]]
        options:0 error:NULL] : nil;
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *root in roots) {
        BOOL isDirectory = NO;
        if (![fm fileExistsAtPath:root isDirectory:&isDirectory]) continue;
        if (!isDirectory) { printf("%s\n", root.UTF8String); continue; }
        NSUInteger rootDepth = root.pathComponents.count;
        for (NSString *relative in [fm enumeratorAtPath:root]) {
            NSString *full = [root stringByAppendingPathComponent:relative];
            NSUInteger depth = full.pathComponents.count - rootDepth;
            if (maxDepth >= 0 && (NSInteger)depth > maxDepth) continue;
            BOOL entryIsDirectory = NO;
            [fm fileExistsAtPath:full isDirectory:&entryIsDirectory];
            if (typeFilter.length) {
                if ([typeFilter isEqualToString:@"f"] && entryIsDirectory) continue;
                if ([typeFilter isEqualToString:@"d"] && !entryIsDirectory) continue;
            }
            if (regex && ![regex firstMatchInString:full.lastPathComponent options:0 range:NSMakeRange(0, full.lastPathComponent.length)]) continue;
            printf("%s\n", full.UTF8String);
        }
    }
    (void)maxDepth;
    return 0;
}

#pragma mark - tar

static int CATarWriteHeader(NSFileHandle *handle, NSString *name, const struct stat *st, char typeflag)
{
    uint8_t block[512];
    memset(block, 0, sizeof(block));
    NSString *storedName = name;
    if (storedName.length > 100) {
        // GNU long name 条目
        NSData *longName = [[storedName stringByAppendingString:@"\0"] dataUsingEncoding:NSUTF8StringEncoding];
        uint8_t longBlock[512];
        memset(longBlock, 0, sizeof(longBlock));
        memcpy(longBlock, "././@LongLink", 13);
        snprintf((char *)longBlock + 100, 8, "%07o", 0644);
        snprintf((char *)longBlock + 108, 8, "%07o", 0);
        snprintf((char *)longBlock + 116, 8, "%07o", 0);
        snprintf((char *)longBlock + 124, 12, "%011o", (unsigned)longName.length);
        snprintf((char *)longBlock + 136, 12, "%011o", 0);
        longBlock[156] = 'L';
        memcpy(longBlock + 257, "ustar", 5);
        memcpy(longBlock + 263, "00", 2);
        unsigned checksum = 0;
        for (int i = 0; i < 512; i++) checksum += longBlock[i];
        snprintf((char *)longBlock + 148, 8, "%06o", checksum);
        [handle writeData:[NSData dataWithBytes:longBlock length:512]];
        NSUInteger padded = (longName.length + 511) / 512 * 512;
        NSMutableData *payload = [longName mutableCopy];
        [payload setLength:padded];
        [handle writeData:payload];
        storedName = [storedName substringFromIndex:storedName.length - 100 >= 0 ? MAX(0, (NSInteger)storedName.length - 100) : 0];
    }
    memcpy(block, storedName.UTF8String, MIN(storedName.length, 100));
    snprintf((char *)block + 100, 8, "%07o", st ? (st->st_mode & 07777) : (unsigned)(typeflag == '5' ? 0755 : 0644));
    snprintf((char *)block + 108, 8, "%07o", 0);
    snprintf((char *)block + 116, 8, "%07o", 0);
    snprintf((char *)block + 124, 12, "%011o", st ? (unsigned)st->st_size : 0);
    snprintf((char *)block + 136, 12, "%011o", (unsigned)(st ? st->st_mtime : 0));
    memset(block + 148, ' ', 8);
    block[156] = (uint8_t)typeflag;
    memcpy(block + 257, "ustar", 5);
    memcpy(block + 263, "00", 2);
    unsigned checksum = 0;
    for (int i = 0; i < 512; i++) checksum += block[i];
    snprintf((char *)block + 148, 8, "%06o", checksum);
    [handle writeData:[NSData dataWithBytes:block length:512]];
    return 0;
}

static int CAToolTar(int argc, char **argv)
{
    BOOL create = NO, extract = NO, gzip = NO, verbose = NO, xz = NO;
    NSString *archivePath = nil;
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    BOOL nextIsArchive = NO;
    for (int i = 1; i < argc; i++) {
        NSString *argument = [NSString stringWithUTF8String:argv[i]];
        if (argument.length && [argument characterAtIndex:0] == '-' && ![argument isEqualToString:@"-"]) {
            for (NSUInteger c = 1; c < argument.length; c++) {
                unichar flag = [argument characterAtIndex:c];
                if (flag == 'c') create = YES;
                else if (flag == 'x') extract = YES;
                else if (flag == 'z') gzip = YES;
                else if (flag == 'J') xz = YES;
                else if (flag == 'v') verbose = YES;
                else if (flag == 'f') nextIsArchive = YES;
                else if (flag == 'C' && i + 1 < argc) { [paths addObject:[NSString stringWithFormat:@"-C:%s", argv[++i]]]; }
                else if (flag == 'p' || flag == 'h' || flag == 'P' || flag == 'm' || flag == 'S' || flag == 'O' || flag == 'k') continue;
            }
            continue;
        }
        if (nextIsArchive) { archivePath = argument; nextIsArchive = NO; continue; }
        [paths addObject:argument];
    }
    if (xz) CALog(CALogLevelWarn, @"SHELL", @"tar: xz requested; falling back to gzip member handling");

    if (create) {
        NSString *output = archivePath ?: @"-";
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ca-tar.tmp"];
        [NSFileManager.defaultManager removeItemAtPath:tempPath error:NULL];
        [NSFileManager.defaultManager createFileAtPath:tempPath contents:nil attributes:nil];
        NSFileHandle *writer = [NSFileHandle fileHandleForWritingAtPath:tempPath];
        struct stat st;
        for (NSString *path in paths) {
            if ([path hasPrefix:@"-C:"]) continue;
            NSString *relative = path.lastPathComponent;
            BOOL isDirectory = NO;
            [NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory];
            if (stat(path.fileSystemRepresentation, &st) != 0) continue;
            CATarWriteHeader(writer, isDirectory ? [relative stringByAppendingString:@"/"] : relative, &st, isDirectory ? '5' : '0');
            if (!isDirectory) {
                NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
                if (!data) data = [NSData dataWithContentsOfFile:path];
                if (data) {
                    [writer writeData:data];
                    NSUInteger padded = (data.length + 511) / 512 * 512;
                    if (padded > data.length) [writer writeData:[NSMutableData dataWithLength:padded - data.length]];
                }
            }
            if (verbose) fprintf(stderr, "%s\n", path.UTF8String);
        }
        uint8_t terminator[1024];
        memset(terminator, 0, sizeof(terminator));
        [writer writeData:[NSData dataWithBytes:terminator length:1024]];
        [writer closeFile];

        if (gzip) {
            NSString *gzPath = [tempPath stringByAppendingString:@".gz"];
            gzFile out = gzopen(gzPath.fileSystemRepresentation, "wb");
            NSData *raw = [NSData dataWithContentsOfFile:tempPath];
            if (out && raw) {
                gzwrite(out, raw.bytes, (unsigned)raw.length);
                gzclose(out);
                [NSFileManager.defaultManager removeItemAtPath:archivePath error:NULL];
                [NSFileManager.defaultManager moveItemAtPath:gzPath toPath:output error:NULL];
            }
        } else {
            [NSFileManager.defaultManager removeItemAtPath:output error:NULL];
            [NSFileManager.defaultManager moveItemAtPath:tempPath toPath:output error:NULL];
        }
        [NSFileManager.defaultManager removeItemAtPath:tempPath error:NULL];
        return 0;
    }

    if (extract) {
        NSString *destination = @".";
        NSMutableArray<NSString *> *cleanPaths = [NSMutableArray array];
        for (NSString *path in paths) {
            if ([path hasPrefix:@"-C:"]) { destination = [path substringFromIndex:3]; continue; }
            [cleanPaths addObject:path];
        }
        NSError *error = nil;
        if (gzip || [archivePath hasSuffix:@".gz"]) {
            return [CAArchiveExtractor extractTarGzip:archivePath toDirectory:destination expectedExpandedSize:0 progress:nil error:&error] ? 0 : 1;
        }
        NSData *tarData = [NSData dataWithContentsOfFile:archivePath];
        if (!tarData) { fprintf(stderr, "tar: %s: No such file or directory\n", archivePath.UTF8String); return 1; }
        return [CAArchiveExtractor extractTarData:tarData toDirectory:destination progress:nil error:&error] ? 0 : 1;
    }
    return CAUnsupported(@"tar", @"missing -c/-x");
}

#pragma mark - theos-helper 子命令

static int CATheosHelperVerifyDeb(NSString *path)
{
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length || memcmp(data.bytes, "!<arch>\n", 8) != 0) {
        fprintf(stderr, "verify-deb: not an ar archive: %s\n", path.UTF8String);
        return 1;
    }
    NSUInteger cursor = 8, members = 0;
    while (cursor + 60 <= data.length) {
        const uint8_t *header = (const uint8_t *)data.bytes + cursor;
        char name[17] = {0};
        memcpy(name, header, 16);
        NSString *member = [[NSString stringWithUTF8String:name] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSString *sizeString = [[[NSString alloc] initWithBytes:header + 48 length:10 encoding:NSUTF8StringEncoding]
                                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        NSUInteger size = (NSUInteger)sizeString.longLongValue;
        members += 1;
        printf("%-16s %8lu\n", member.UTF8String, (unsigned long)size);
        cursor += 60 + size + (size % 2);
    }
    printf("members=%lu\n", (unsigned long)members);
    return members > 0 ? 0 : 1;
}

static int CATheosHelperAssembleDeb(NSString *staging, NSString *output, NSString *version, NSString *package)
{
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:staging]) {
        fprintf(stderr, "assemble-deb: staging directory missing: %s\n", staging.UTF8String);
        return 1;
    }
    NSString *controlDir = [staging stringByAppendingPathComponent:@"DEBIAN"];
    NSString *controlPath = [controlDir stringByAppendingPathComponent:@"control"];
    NSString *control = [NSString stringWithContentsOfFile:controlPath encoding:NSUTF8StringEncoding error:NULL];
    if (!control.length) {
        control = [NSString stringWithFormat:@"Package: %@\nName: CodexApp\nVersion: %@\nArchitecture: iphoneos-arm64\nDescription: CodexApp embedded package\n",
                   package ?: @"wiki.qaq.codexapp", version ?: @"1.0.0"];
        [CARuntimePaths ensureDirectory:controlDir mode:0755 error:NULL];
        [control writeToFile:controlPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    // ar 容器：debian-binary + control.tar.gz + data.tar.gz
    NSMutableData *archive = [NSMutableData data];
    [archive appendData:[@"!<arch>\n" dataUsingEncoding:NSUTF8StringEncoding]];
    void (^appendMember)(NSString *, NSData *) = ^(NSString *name, NSData *payload) {
        NSMutableData *header = [[NSString stringWithFormat:@"%-16s%-12d%-6d%-6d%-8s%-10lu`\n",
                                  name.UTF8String, 0, 0, 0, "100644", (unsigned long)payload.length] dataUsingEncoding:NSUTF8StringEncoding];
        [archive appendData:header];
        [archive appendData:payload];
        if (payload.length % 2 == 1) [archive appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
    };
    appendMember(@"debian-binary", [@"2.0\n" dataUsingEncoding:NSUTF8StringEncoding]);

    NSString *tarTmp = [NSTemporaryDirectory() stringByAppendingPathComponent:@"codex-deb-control.tar"];
    [NSFileManager.defaultManager removeItemAtPath:tarTmp error:NULL];
    NSString *controlGz = [tarTmp stringByAppendingString:@".gz"];
    // control.tar.gz（用 tar 工具自身逻辑：这里以固定头写入 DEBIAN/control）
    NSMutableData *controlTar = [NSMutableData data];
    struct stat st;
    stat(controlPath.fileSystemRepresentation, &st);
    NSFileHandle *writer = [NSFileHandle fileHandleForWritingAtPath:tarTmp];
    if (!writer) { [fm createFileAtPath:tarTmp contents:nil attributes:nil]; writer = [NSFileHandle fileHandleForWritingAtPath:tarTmp]; }
    CATarWriteHeader(writer, @"DEBIAN/control", &st, '0');
    NSData *controlData = [NSData dataWithContentsOfFile:controlPath];
    [writer writeData:controlData];
    NSUInteger padded = (controlData.length + 511) / 512 * 512;
    if (padded > controlData.length) [writer writeData:[NSMutableData dataWithLength:padded - controlData.length]];
    uint8_t terminator[1024]; memset(terminator, 0, sizeof(terminator));
    [writer writeData:[NSData dataWithBytes:terminator length:1024]];
    [writer closeFile];
    (void)controlTar;
    gzFile out = gzopen(controlGz.fileSystemRepresentation, "wb");
    NSData *rawControlTar = [NSData dataWithContentsOfFile:tarTmp];
    if (out && rawControlTar) { gzwrite(out, rawControlTar.bytes, (unsigned)rawControlTar.length); gzclose(out); }
    appendMember(@"control.tar.gz", [NSData dataWithContentsOfFile:controlGz] ?: [NSData data]);

    NSString *dataTar = [NSTemporaryDirectory() stringByAppendingPathComponent:@"codex-deb-data.tar"];
    NSString *dataGz = [dataTar stringByAppendingString:@".gz"];
    CAProcess *tarTask = [CAProcess new];
    tarTask.executableURL = [NSURL fileURLWithPath:CARuntimePaths.fileToolPath];
    tarTask.arguments = @[ @"-czf", dataGz, @"-C", staging, @"--exclude=./DEBIAN", @"--exclude=./DEBIAN/*", @"." ];
    NSError *tarError = nil;
    if ([tarTask launchAndReturnError:&tarError]) [tarTask waitUntilExit];
    appendMember(@"data.tar.gz", [NSData dataWithContentsOfFile:dataGz] ?: [NSData data]);

    [fm removeItemAtPath:tarTmp error:NULL];
    [fm removeItemAtPath:controlGz error:NULL];
    [fm removeItemAtPath:dataTar error:NULL];
    [fm removeItemAtPath:dataGz error:NULL];

    BOOL ok = [archive writeToFile:output atomically:YES];
    CALog(ok ? CALogLevelInfo : CALogLevelError, @"THEOS", @"CodexApp: forkless deb builder completed: %@", output);
    return ok ? 0 : 1;
}

static int CATheosHelperMain(NSArray<NSString *> *arguments)
{
    NSString *operation = arguments.firstObject ?: @"";
    NSArray<NSString *> *rest = arguments.count > 1 ? [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)] : @[];

    if ([operation isEqualToString:@"upper"]) {
        printf("%s\n", rest.firstObject.uppercaseString.UTF8String);
        return 0;
    }
    if ([operation isEqualToString:@"schema-key"]) {
        NSMutableString *key = [NSMutableString string];
        for (NSInteger i = 0; i < rest.count; i++) {
            if (i > 0) [key appendString:@"_"];
            [key appendString:[rest[i] lowercaseString]];
        }
        printf("%s\n", key.UTF8String);
        return 0;
    }
    if ([operation isEqualToString:@"sort-versions"]) {
        NSArray<NSString *> *sorted = [rest sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
            return [a compare:b options:NSNumericSearch];
        }];
        for (NSString *line in sorted) printf("%s\n", line.UTF8String);
        return 0;
    }
    if ([operation isEqualToString:@"fakeroot"]) {
        // fakeroot -p <state> -r <script> / -c <command>
        NSString *rootPath = nil;
        NSMutableArray<NSString *> *command = [NSMutableArray array];
        for (NSUInteger i = 0; i < rest.count; i++) {
            if ([rest[i] isEqualToString:@"-p"] && i + 1 < rest.count) { rootPath = rest[++i]; continue; }
            if ([rest[i] isEqualToString:@"-r"] || [rest[i] isEqualToString:@"-c"]) continue;
            [command addObject:rest[i]];
        }
        if (!command.count) return CAUnsupported(@"fakeroot", @"no command");
        NSMutableDictionary *env = [NSProcessInfo.processInfo.environment mutableCopy];
        if (rootPath) env[@"FAKEROOTKEY"] = @"1";
        NSMutableArray<NSString *> *bashArguments = [NSMutableArray arrayWithObject:@"-c"];
        [bashArguments addObject:[command componentsJoinedByString:@" "]];
        CAProcess *task = [CAProcess new];
        task.executableURL = [NSURL fileURLWithPath:CARuntimePaths.bashRealPath];
        task.arguments = bashArguments;
        task.environment = env;
        NSError *error = nil;
        if (![task launchAndReturnError:&error]) {
            fprintf(stderr, "fakeroot: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
        [task waitUntilExit];
        return task.terminationStatus;
    }
    if ([operation isEqualToString:@"verify-deb"]) {
        return CATheosHelperVerifyDeb(rest.firstObject ?: @"");
    }
    if ([operation isEqualToString:@"assemble-deb"] || [operation isEqualToString:@"build-deb-forkless"]) {
        NSString *staging = nil, *output = nil, *version = nil, *package = nil;
        for (NSUInteger i = 0; i < rest.count; i++) {
            if ([rest[i] isEqualToString:@"-s"]) { staging = rest[++i]; continue; }
            if ([rest[i] isEqualToString:@"-o"]) { output = rest[++i]; continue; }
            if ([rest[i] isEqualToString:@"-v"]) { version = rest[++i]; continue; }
            if ([rest[i] isEqualToString:@"-p"]) { package = rest[++i]; continue; }
        }
        return CATheosHelperAssembleDeb(staging, output ?: @"out.deb", version, package);
    }
    fprintf(stderr, "theos-helper: unsupported operation: %s\n", operation.UTF8String);
    return 2;
}

#pragma mark - 入口

int CAFileToolMain(int argc, char **argv)
{
    @autoreleasepool {
        NSString *tool = CACurrentInvocationName();
        NSArray<NSString *> *arguments = CAJoinedArguments(argc, argv, 1);

        if ([tool isEqualToString:@"theos-helper"]) return CATheosHelperMain(arguments);
        if ([tool isEqualToString:@"cat"])     return CAToolCat(argc, argv);
        if ([tool isEqualToString:@"tee"])     return CAToolTee(argc, argv);
        if ([tool isEqualToString:@"ls"])      return CAToolLs(argc, argv);
        if ([tool isEqualToString:@"mkdir"])   return CAToolMkdir(argc, argv);
        if ([tool isEqualToString:@"rm"])      return CAToolRemove(argc, argv);
        if ([tool isEqualToString:@"touch"])   return CAToolTouch(argc, argv);
        if ([tool isEqualToString:@"cp"])      return CAToolCopyOrMove(argc, argv, NO);
        if ([tool isEqualToString:@"mv"])      return CAToolCopyOrMove(argc, argv, YES);
        if ([tool isEqualToString:@"chmod"])   return CAToolChmod(argc, argv);
        if ([tool isEqualToString:@"ln"])      return CAToolLink(argc, argv);
        if ([tool isEqualToString:@"stat"])    return CAToolStat(argc, argv);
        if ([tool isEqualToString:@"uname"])   return CAToolUname(argc, argv);
        if ([tool isEqualToString:@"which"])   return CAToolWhich(argc, argv);
        if ([tool isEqualToString:@"basename"])return CAToolBasename(argc, argv);
        if ([tool isEqualToString:@"dirname"]) return CAToolDirname(argc, argv);
        if ([tool isEqualToString:@"readlink"])return CAToolReadlink(argc, argv);
        if ([tool isEqualToString:@"realpath"])return CAToolRealpath(argc, argv);
        if ([tool isEqualToString:@"du"])      return CAToolDu(argc, argv);
        if ([tool isEqualToString:@"wc"])      return CAToolWc(argc, argv);
        if ([tool isEqualToString:@"head"])    return CAToolHeadOrTail(argc, argv, NO);
        if ([tool isEqualToString:@"tail"])    return CAToolHeadOrTail(argc, argv, YES);
        if ([tool isEqualToString:@"grep"])    return CAToolGrep(argc, argv);
        if ([tool isEqualToString:@"sed"])     return CAToolSed(argc, argv);
        if ([tool isEqualToString:@"sort"])    return CAToolSort(argc, argv);
        if ([tool isEqualToString:@"uniq"])    return CAToolUniq(argc, argv);
        if ([tool isEqualToString:@"nl"])      return CAToolNl(argc, argv);
        if ([tool isEqualToString:@"find"])    return CAToolFind(argc, argv);
        if ([tool isEqualToString:@"xxd"])     return CAToolHexDump(argc, argv, NO);
        if ([tool isEqualToString:@"od"])      return CAToolHexDump(argc, argv, YES);
        if ([tool isEqualToString:@"tar"])     return CAToolTar(argc, argv);
        if ([tool isEqualToString:@"sysctl"])  { struct utsname info; uname(&info); printf("kern.osrelease: %s\nkern.version: %s\n", info.release, info.version); return 0; }
        if ([tool isEqualToString:@"date"])    { printf("%s\n", [NSDate date].description.UTF8String); return 0; }

        // 未识别调用名：打印可用工具（原包同款工具集）
        fprintf(stderr, "ca-filetool: unsupported operation: %s\n", tool.UTF8String);
        return 2;
    }
}
