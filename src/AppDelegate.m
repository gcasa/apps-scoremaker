#import "AppDelegate.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    [self buildMenu];

    NSDocumentController *controller = [NSDocumentController sharedDocumentController];
    if ([[controller documents] count] == 0) {
        NSError *error = nil;
        NSDocument *document = [controller openUntitledDocumentAndDisplay:YES error:&error];
        if (!document && error) {
            [controller presentError:error];
        }
    }
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    (void)sender;
    return NO;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

- (void)buildMenu
{
    NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@"Main Menu"] autorelease];
    NSMenuItem *appItem = [[[NSMenuItem alloc] initWithTitle:@"ScoreMaker" action:NULL keyEquivalent:@""] autorelease];
    [mainMenu addItem:appItem];

    NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@"ScoreMaker"] autorelease];
    NSMenuItem *quitItem = [[[NSMenuItem alloc] initWithTitle:@"Quit ScoreMaker"
                                                       action:@selector(terminate:)
                                                keyEquivalent:@"q"] autorelease];
    [appMenu addItem:quitItem];
    [appItem setSubmenu:appMenu];

    NSMenuItem *fileItem = [[[NSMenuItem alloc] initWithTitle:@"File" action:NULL keyEquivalent:@""] autorelease];
    [mainMenu addItem:fileItem];
    NSMenu *fileMenu = [[[NSMenu alloc] initWithTitle:@"File"] autorelease];

    [fileMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"New"
                                                  action:@selector(newDocument:)
                                           keyEquivalent:@"n"] autorelease]];
    [fileMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Open..."
                                                  action:@selector(openDocument:)
                                           keyEquivalent:@"o"] autorelease]];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Save"
                                                  action:@selector(saveDocument:)
                                           keyEquivalent:@"s"] autorelease]];
    [fileMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Save As..."
                                                  action:@selector(saveDocumentAs:)
                                           keyEquivalent:@"S"] autorelease]];
    [fileItem setSubmenu:fileMenu];

    [NSApp setMainMenu:mainMenu];
}

@end
