//
//  CAStorageViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CAStorageViewController : UIViewController
    - (void)completeScanKey:(id)arg1 value:(id)arg2 generation:(id)arg3;
    - (void)confirmAndClearDownloads;
    - (void)deleteRuntimeAtRow:(id)arg1;
    - (void)finishOperationWithMessage:(id)arg1;
    - (id)formattedBytes:(id)arg1;
    - (signed __int64)numberOfSectionsInTableView:(id)arg1;
    - (NSString *)operationStatus;
    - (NSMutableSet *)pendingScanKeys;
    - (void)performFactoryReset;
    - (bool)resetting;
    - (void)scan;
    - (unsigned __int64)scanGeneration;
    - (void)setOperationStatus:(id)arg1;
    - (void)setPendingScanKeys:(id)arg1;
    - (void)setResetting:(id)arg1;
    - (void)setScanGeneration:(id)arg1;
    - (void)setSnapshot:(id)arg1;
    - (void)setWorking:(id)arg1;
    - (void)showToast:(id)arg1;
    - (NSDictionary *)snapshot;
    - (id)storageKeys;
    - (id)storageTitles;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2;
    - (double)tableView:(id)arg1 heightForFooterInSection:(id)arg2;
    - (signed __int64)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2;
    - (void)viewDidLoad;
    - (bool)working;

@end

NS_ASSUME_NONNULL_END
