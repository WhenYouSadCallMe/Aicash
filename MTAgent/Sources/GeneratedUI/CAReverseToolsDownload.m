#import "CAReverseToolsDownload.h"
#import "CAUpdateProgress.h"

@interface CAReverseToolsDownload ()
@property(nonatomic,copy) NSString *destinationValue;
@property(nonatomic,strong) dispatch_semaphore_t doneValue;
@property(nonatomic,strong) NSError *errorValue;
@property(nonatomic,strong) CAUpdateProgress *progressValue;
@property(nonatomic,assign) double lastProgressTimeValue;
@property(nonatomic,assign) BOOL successValue;
@end

@implementation CAReverseToolsDownload
- (instancetype)init { if ((self=[super init])) _doneValue=dispatch_semaphore_create(0); return self; }
- (NSString *)destination{return _destinationValue;} - (void)setDestination:(id)v{_destinationValue=[v copy];}
- (id)done{return _doneValue;} - (void)setDone:(id)v{_doneValue=(dispatch_semaphore_t)v;}
- (NSError *)error{return _errorValue;} - (void)setError:(id)v{_errorValue=[v isKindOfClass:NSError.class]?v:nil;}
- (double)lastProgressTime{return _lastProgressTimeValue;} - (void)setLastProgressTime:(id)v{_lastProgressTimeValue=[v doubleValue];}
- (id)progress{return _progressValue;} - (void)setProgress:(id)v{_progressValue=[v isKindOfClass:CAUpdateProgress.class]?v:nil;}
- (void)setSuccess:(id)v{_successValue=[v boolValue];} - (bool)success{return _successValue;}
- (void)finish:(BOOL)ok error:(NSError *)error{_successValue=ok;_errorValue=error;if(_doneValue)dispatch_semaphore_signal(_doneValue);}
- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)t didWriteData:(int64_t)w totalBytesWritten:(int64_t)tw totalBytesExpectedToWrite:(int64_t)te{double f=te>0?(double)tw/(double)te:0;if(!_progressValue)_progressValue=[CAUpdateProgress progressWithStage:CAUpdateStageDownload fraction:f status:@"下载中"];[_progressValue applyStage:CAUpdateStageDownload fraction:f completedBytes:tw totalBytes:te status:@"下载中"];_lastProgressTimeValue=NSDate.date.timeIntervalSince1970;}
- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)t didFinishDownloadingToURL:(NSURL *)location{if(!_destinationValue.length||!location){_errorValue=[NSError errorWithDomain:@"CodexApp.Download" code:400 userInfo:@{NSLocalizedDescriptionKey:@"download destination missing"}];return;}[[NSFileManager defaultManager] removeItemAtPath:_destinationValue error:NULL];[[NSFileManager defaultManager] createDirectoryAtPath:_destinationValue.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];NSError *error=nil;_successValue=[[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:_destinationValue] error:&error];_errorValue=error;if(_successValue&&_progressValue)[_progressValue applyStage:CAUpdateStageDownload fraction:1 completedBytes:_progressValue.totalBytes totalBytes:_progressValue.totalBytes status:@"下载完成"];}
- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)error{if(error&&!_successValue)_errorValue=error;if(!_successValue&&!_errorValue)_errorValue=[NSError errorWithDomain:@"CodexApp.Download" code:500 userInfo:@{NSLocalizedDescriptionKey:@"download failed"}];if(_doneValue)dispatch_semaphore_signal(_doneValue);}
@end
