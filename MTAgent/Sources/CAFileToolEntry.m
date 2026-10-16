//
//  CAFileToolEntry.m — Helpers/ca-filetool 的 main（原包：单二进制多调用名，按 argv[0] 分派）
//

#import <Foundation/Foundation.h>

int CAFileToolMain(int argc, char **argv);

int main(int argc, char **argv)
{
    @autoreleasepool {
        return CAFileToolMain(argc, argv);
    }
}
