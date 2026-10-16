//
//  CAArchiveExtractor.h — 归档解包（tar.gz / deb），带路径逃逸防护
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^CAArchiveProgressHandler)(double fraction, NSString * _Nullable stage);

@interface CAArchiveExtractor : NSObject

// 解 gzip 压缩的 tar 到指定目录；expectedExpandedSize 为 0 表示不限制
+ (BOOL)extractTarGzip:(NSString *)archivePath
           toDirectory:(NSString *)destination
  expectedExpandedSize:(unsigned long long)expectedExpandedSize
              progress:(nullable CAArchiveProgressHandler)progress
                 error:(NSError **)error;

// 解 .deb（ar 容器 → data.tar.{gz,xz,zst}）
+ (BOOL)extractRuntimeFromDeb:(NSString *)debPath
                  toDirectory:(NSString *)destination
                     progress:(nullable CAArchiveProgressHandler)progress
                        error:(NSError **)error;

// 解 tar（不带压缩层，供 tar 工具与 deb 复用）
+ (BOOL)extractTarData:(NSData *)tarData
           toDirectory:(NSString *)destination
              progress:(nullable CAArchiveProgressHandler)progress
                 error:(NSError **)error;

// 安全校验：相对路径不得逃出根目录
+ (nullable NSString *)safeRelativePath:(NSString *)relative inRoot:(NSString *)root error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
