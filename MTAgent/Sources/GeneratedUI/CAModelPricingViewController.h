//
//  CAModelPricingViewController — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class UIActivityIndicatorView;

@class NSArray;
@class NSDictionary;
@class UISearchController;

@interface CAModelPricingViewController : UIViewController
    - (void)applyTheme;
    - (id)candidateTitle:(id)arg1;
    - (void)closePage;
    - (id)modelAtIndexPath:(id)arg1;
    - (signed long long)numberOfSectionsInTableView:(id)arg1;
    - (NSDictionary *)officialDisplaySnapshot;
    - (NSArray *)officialModels;
    - (void)prepareDisplaySnapshots;
    - (id)priceText:(id)arg1;
    - (void)pricingDidChange:(id)arg1;
    - (id)providerAtIndexPath:(id)arg1;
    - (void)reloadRows;
    - (UISearchController *)searchController;
    - (void)setOfficialDisplaySnapshot:(id)arg1;
    - (void)setOfficialModels:(id)arg1;
    - (void)setSearchController:(id)arg1;
    - (void)setSnapshotGeneration:(id)arg1;
    - (void)setSyncItem:(id)arg1;
    - (void)setSyncSpinner:(id)arg1;
    - (void)setSyncSpinnerItem:(id)arg1;
    - (void)setThirdPartyDisplaySnapshot:(id)arg1;
    - (void)setThirdPartyModels:(id)arg1;
    - (unsigned long long)snapshotGeneration;
    - (id)syncItem;
    - (void)syncPricing;
    - (id)syncSpinner;
    - (id)syncSpinnerItem;
    - (id)tableView:(id)arg1 cellForRowAtIndexPath:(id)arg2;
    - (void)tableView:(id)arg1 didSelectRowAtIndexPath:(id)arg2;
    - (signed long long)tableView:(id)arg1 numberOfRowsInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForFooterInSection:(id)arg2;
    - (id)tableView:(id)arg1 titleForHeaderInSection:(id)arg2;
    - (void)themeDidChange;
    - (NSDictionary *)thirdPartyDisplaySnapshot;
    - (NSArray *)thirdPartyModels;
    - (void)updateSearchResultsForSearchController:(id)arg1;
    - (void)viewDidLoad;

@end

NS_ASSUME_NONNULL_END
