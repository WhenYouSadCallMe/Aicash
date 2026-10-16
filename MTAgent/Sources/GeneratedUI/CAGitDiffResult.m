//
//  CAGitDiffResult.m — `git diff` 结果（状态码 / 预览文本 / 落盘文件 / 截断标记）
//
//  原包 ivar：_error / _fileURL / _preview / _status / _truncated。
//  预览文本直接给 CAGitDiffViewController 的 UITextView 用；
//  文件 URL 给「分享」按钮用（把完整 diff 写到临时文件后分享）。
//

#import "CAGitDiffResult.h"

@interface CAGitDiffResult ()
{
    NSString *_error;
    NSURL *_fileURL;
    NSString *_preview;
    int _status;
    BOOL _truncated;
}
@end

@implementation CAGitDiffResult

- (NSString *)error { return _error; }
- (void)setError:(id)arg1 { _error = [(NSString *)arg1 copy]; }

- (NSURL *)fileURL { return _fileURL; }
- (void)setFileURL:(id)arg1 { _fileURL = [arg1 isKindOfClass:NSURL.class] ? (NSURL *)arg1 : nil; }

- (NSString *)preview { return _preview ?: @""; }
- (void)setPreview:(id)arg1 { _preview = [(NSString *)arg1 copy]; }

- (int)status { return _status; }
- (void)setStatus:(id)arg1 { _status = [(NSNumber *)arg1 respondsToSelector:@selector(intValue)] ? [(NSNumber *)arg1 intValue] : 0; }

- (bool)truncated { return _truncated; }
- (void)setTruncated:(id)arg1 { _truncated = [(NSNumber *)arg1 respondsToSelector:@selector(boolValue)] ? [(NSNumber *)arg1 boolValue] : NO; }

@end
