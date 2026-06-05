#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScoreMakerDocumentController.h"

int main(int argc, const char *argv[])
{
    (void)argc;
    (void)argv;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    [ScoreMakerDocumentController sharedDocumentController];
    NSApplication *application = [NSApplication sharedApplication];
    AppDelegate *delegate = [[AppDelegate alloc] init];
    [application setDelegate:delegate];
    [application run];

    [application setDelegate:nil];
    [delegate release];
    [pool release];

    return 0;
}
