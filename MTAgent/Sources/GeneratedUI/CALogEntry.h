//
//  CALogEntry — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString;

@interface CALogEntry : NSObject
    - (NSString *)category;
    - (id)detailText;
    - (id)entryWithLine:(id)arg1;
    - (bool)isError;
    - (bool)isWarning;
    - (NSString *)level;
    - (NSString *)message;
    - (NSString *)pid;
    - (NSString *)raw;
    - (NSString *)searchText;
    - (void)setCategory:(id)arg1;
    - (void)setIsError:(id)arg1;
    - (void)setIsWarning:(id)arg1;
    - (void)setLevel:(id)arg1;
    - (void)setMessage:(id)arg1;
    - (void)setPid:(id)arg1;
    - (void)setRaw:(id)arg1;
    - (void)setSearchText:(id)arg1;
    - (void)setTime:(id)arg1;
    - (id)shortTime;
    - (NSString *)time;

@end

NS_ASSUME_NONNULL_END
