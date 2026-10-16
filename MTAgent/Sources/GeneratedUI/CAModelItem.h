//
//  CAModelItem — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSArray;
@class NSString;

@interface CAModelItem : NSObject
    - (unsigned long long)contextWindowTokens;
    - (NSString *)defaultLevel;
    - (NSString *)desc;
    - (NSString *)displayName;
    - (unsigned long long)effectiveContextWindowPercent;
    - (unsigned long long)maxContextWindowTokens;
    - (void)setContextWindowTokens:(id)arg1;
    - (void)setDefaultLevel:(id)arg1;
    - (void)setDesc:(id)arg1;
    - (void)setDisplayName:(id)arg1;
    - (void)setEffectiveContextWindowPercent:(id)arg1;
    - (void)setMaxContextWindowTokens:(id)arg1;
    - (void)setSlug:(id)arg1;
    - (void)setSupportedLevels:(id)arg1;
    - (void)setSupportsReasoning:(id)arg1;
    - (NSString *)shortName;
    - (NSString *)slug;
    - (NSArray *)supportedLevels;
    - (bool)supportsReasoning;

@end

NS_ASSUME_NONNULL_END
