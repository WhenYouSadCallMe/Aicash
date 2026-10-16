//
//  CAConversationMigration.m — 会话迁移 journal 实现
//

#import "CAConversationMigration.h"
#import "CARuntimePaths.h"
#import "CALogger.h"

NSString *const CAConversationMigrationJournalDidChangeNotification = @"CAConversationMigrationJournalDidChange";

static NSString * const CAConversationMigrationValidPhases[] = { @"pending", @"copying", @"committed", @"failed" };

@implementation CAConversationMigration

+ (NSString *)journalPath
{
    return [[CARuntimePaths supportDirectory] stringByAppendingPathComponent:@"CodexApp/migration-journal.json"];
}

+ (NSArray<CAConversationMigration *> *)loadJournal
{
    NSData *data = [NSData dataWithContentsOfFile:self.journalPath];
    if (!data.length) return @[];
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![object isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<CAConversationMigration *> *migrations = [NSMutableArray array];
    for (NSDictionary *raw in object) {
        CAConversationMigration *migration = [self migrationFromDictionary:raw];
        if (migration) [migrations addObject:migration];
    }
    return migrations;
}

+ (BOOL)writeMigrations:(NSArray<CAConversationMigration *> *)migrations error:(NSError **)error
{
    NSMutableArray<NSDictionary *> *raw = [NSMutableArray array];
    for (CAConversationMigration *migration in migrations) [raw addObject:[migration toDictionary]];
    NSData *data = [NSJSONSerialization dataWithJSONObject:raw options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;
    [[NSFileManager defaultManager] createDirectoryAtPath:self.journalPath.stringByDeletingLastPathComponent
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    BOOL ok = [data writeToFile:self.journalPath options:NSDataWritingAtomic error:error];
    if (ok) [[NSNotificationCenter defaultCenter] postNotificationName:CAConversationMigrationJournalDidChangeNotification object:nil];
    return ok;
}

+ (BOOL)appendMigration:(CAConversationMigration *)migration error:(NSError **)error
{
    if (!migration.conversationId.length) {
        if (error) *error = [NSError errorWithDomain:@"CodexApp.Migration" code:400
                                            userInfo:@{ NSLocalizedDescriptionKey: @"migration missing conversationId" }];
        return NO;
    }
    NSMutableArray<CAConversationMigration *> *journal = [[self loadJournal] mutableCopy];
    [journal addObject:migration];
    return [self writeMigrations:journal error:error];
}

+ (BOOL)clearJournal:(NSError **)error
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.journalPath]) return YES;
    BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:self.journalPath error:error];
    if (ok) [[NSNotificationCenter defaultCenter] postNotificationName:CAConversationMigrationJournalDidChangeNotification object:nil];
    return ok;
}

+ (nullable instancetype)migrationFromDictionary:(NSDictionary *)dictionary
{
    if (![dictionary isKindOfClass:NSDictionary.class]) return nil;
    NSString *conversationId = dictionary[@"conversationId"] ?: dictionary[@"conversation_id"];
    if (!conversationId.length) return nil;
    CAConversationMigration *migration = [self new];
    migration.conversationId = conversationId;
    migration.source = dictionary[@"source"];
    migration.target = dictionary[@"target"];
    migration.phase = dictionary[@"phase"] ?: @"pending";
    migration.version = [dictionary[@"version"] respondsToSelector:@selector(integerValue)] ? [dictionary[@"version"] integerValue] : 1;
    // phase 必须在合法集合里
    BOOL valid = NO;
    for (NSUInteger i = 0; i < sizeof(CAConversationMigrationValidPhases) / sizeof(*CAConversationMigrationValidPhases); i++) {
        if ([migration.phase isEqualToString:CAConversationMigrationValidPhases[i]]) { valid = YES; break; }
    }
    if (!valid) migration.phase = @"pending";
    return migration;
}

- (NSDictionary *)toDictionary
{
    return @{
        @"version": @(self.version ?: 1),
        @"conversationId": self.conversationId ?: @"",
        @"source": self.source ?: @"",
        @"target": self.target ?: @"",
        @"phase": self.phase ?: @"pending",
    };
}

- (BOOL)isTerminalPhase
{
    return [self.phase isEqualToString:@"committed"] || [self.phase isEqualToString:@"failed"];
}

@end
