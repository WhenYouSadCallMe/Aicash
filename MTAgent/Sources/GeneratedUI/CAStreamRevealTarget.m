//
//  CAStreamRevealTarget — AUTO-GENERATED（选择器与返回值取自 SPEC/method_types.json，参数类型统一占位 id）
//  TODO(parity): 行为按原包实现补全（SPEC/复刻规格书.md）
//
//  聊天主流程实装：CADisplayLink 的弱引用代理目标（避免 display link 强引用视图造成循环引用）。
//  由 CAStreamingTextView 持有，display link 的 target 是本对象，view 为 weak。
//

#import "CAStreamRevealTarget.h"
#import "CAStreamingTextView.h"

@interface CAStreamRevealTarget ()
@property (nonatomic, weak) CAStreamingTextView *view;
@end

@implementation CAStreamRevealTarget

- (void)tick:(id)arg1
{
    CAStreamingTextView *view = self.view;
    if (!view) return;
    [view advanceReveal:arg1];
}

@end
