#import <AppKit/AppKit.h>
#import "AppDelegate.h"
#import "ScoreMakerDocumentController.h"

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    [ScoreMakerDocumentController sharedDocumentController];
    NSApplication *application = [NSApplication sharedApplication];
    AppDelegate *delegate = [[[AppDelegate alloc] init] autorelease];
    [application setDelegate:delegate];
    [application run];

    [pool release];

    return 0;
}
