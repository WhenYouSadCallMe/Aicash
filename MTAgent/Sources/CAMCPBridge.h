//
//  CAMCPBridge.h — 本机内部 MCP 桥（127.0.0.1:27018/mcp）
//  原包观测：codex 侧 rmcp 传输日志 "rmcp::transport::worker"、URL "127.0.0.1:27018/mcp"，
//           失败时上报 reportedInternalMCPTransportFailure。
//  本实现提供同端点的 JSON-RPC(HTTP) MCP 服务，暴露应用自有的原生工具。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol CAMCPBridgeToolProvider <NSObject>
- (NSArray<NSDictionary *> *)mcpToolDescriptors;                                  // {name, description, inputSchema}
- (NSDictionary *)mcpCallTool:(NSString *)name arguments:(NSDictionary *)arguments; // MCP tools/call 结果
@end

@interface CAMCPBridge : NSObject

@property (nonatomic, weak, nullable) id<CAMCPBridgeToolProvider> toolProvider;
@property (nonatomic, assign, readonly) uint16_t port;
@property (nonatomic, assign, readonly) BOOL running;
@property (nonatomic, assign) BOOL reportedInternalMCPTransportFailure;

+ (instancetype)sharedBridge;

- (BOOL)startOnPort:(uint16_t)port error:(NSError **)error;
- (void)stop;

@end

extern NSString *const CAMCPProtocolVersion;   // 2025-06-18

NS_ASSUME_NONNULL_END
