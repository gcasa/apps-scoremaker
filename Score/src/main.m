#import <AppKit/AppKit.h>
#import "AppDelegate.h"

int main(int argc, const char *argv[])
{
    (void)argc;
    (void)argv;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSApplication *application = [NSApplication sharedApplication];
    AppDelegate *delegate = [[[AppDelegate alloc] init] autorelease];
    [application setDelegate:delegate];
    [application run];
    [pool drain];
    return 0;
}
