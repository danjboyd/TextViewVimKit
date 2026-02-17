#import <AppKit/AppKit.h>

#import "RAAppDelegate.h"

int main(int argc, const char **argv)
{
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        RAAppDelegate *delegate = [[RAAppDelegate alloc] init];
        [application setDelegate:delegate];
        [application run];
    }

    return 0;
}
