//
//  CAWorkspaceManager — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class CAWorkspaceManager;

@interface CAWorkspaceManager : NSObject
    - (bool)activateWorkspaceWithPath:(id)arg1 name:(id)arg2 error:(id)arg3;
    - (NSString *)activeWorkspacePath;
    - (void)addWorkspaceWithPath:(id)arg1 name:(id)arg2;
    - (id)createProjectNamed:(id)arg1 inDirectory:(id)arg2 error:(id)arg3;
    - (NSString *)documentsDirectory;
    - (id)filzaURLForPath:(id)arg1;
    - (CAWorkspaceManager *)initWithDefaults:(id)arg1 documentsDirectory:(id)arg2;
    - (NSMutableArray *)internalWorkspaces;
    - (void)loadWorkspaces;
    - (id)normalizedDirectory:(id)arg1 error:(id)arg2;
    - (void)openInFilza:(id)arg1 completion:(id)arg2;
    - (NSUserDefaults *)preferences;
    - (NSArray *)projectWorkspaces;
    - (void)removeWorkspaceAtIndex:(id)arg1;
    - (bool)renameWorkspaceAtPath:(id)arg1 displayName:(id)arg2;
    - (void)saveWorkspaces;
    - (void)setActiveWorkspaceIndex:(id)arg1;
    - (void)setActiveWorkspacePath:(id)arg1;
    - (void)setDocumentsDirectory:(id)arg1;
    - (void)setInternalWorkspaces:(id)arg1;
    - (void)setPreferences:(id)arg1;
    - (id)sharedManager;
    - (NSArray *)workspaces;

@end

NS_ASSUME_NONNULL_END
