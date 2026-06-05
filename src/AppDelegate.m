#import "AppDelegate.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
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
    return NO;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    return YES;
}

- (void)dealloc
{
    [_recentDocumentsMenu release];
    [super dealloc];
}

- (void)openRecentDocument:(id)sender
{
    NSURL *url = [sender representedObject];
    if (!url) {
        return;
    }

    NSError *error = nil;
    NSDocumentController *controller = [NSDocumentController sharedDocumentController];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
    NSDocument *document = [controller openDocumentWithContentsOfURL:url display:YES error:&error];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
    if (!document && error) {
        [controller presentError:error];
    }
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    if (menu != _recentDocumentsMenu) {
        return;
    }

    while ([menu numberOfItems] > 0) {
        [menu removeItemAtIndex:0];
    }

    NSArray *urls = [[NSDocumentController sharedDocumentController] recentDocumentURLs];
    for (NSURL *url in urls) {
        NSString *title = [[url path] lastPathComponent];
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title
                                                       action:@selector(openRecentDocument:)
                                                keyEquivalent:@""] autorelease];
        [item setTarget:self];
        [item setRepresentedObject:url];
        [menu addItem:item];
    }

    if ([urls count] == 0) {
        NSMenuItem *emptyItem = [[[NSMenuItem alloc] initWithTitle:@"No Recent Documents"
                                                            action:NULL
                                                     keyEquivalent:@""] autorelease];
        [emptyItem setEnabled:NO];
        [menu addItem:emptyItem];
    }

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *clearItem = [[[NSMenuItem alloc] initWithTitle:@"Clear Menu"
                                                        action:@selector(clearRecentDocuments:)
                                                 keyEquivalent:@""] autorelease];
    [clearItem setTarget:[NSDocumentController sharedDocumentController]];
    [clearItem setEnabled:([urls count] > 0)];
    [menu addItem:clearItem];
}

- (void)buildMenu
{
    NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@"ScoreMaker"] autorelease];
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
    NSMenuItem *recentItem = [[[NSMenuItem alloc] initWithTitle:@"Open Recent"
                                                         action:NULL
                                                  keyEquivalent:@""] autorelease];
    [fileMenu addItem:recentItem];
    _recentDocumentsMenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    [_recentDocumentsMenu setDelegate:self];
    [recentItem setSubmenu:_recentDocumentsMenu];
    [self menuNeedsUpdate:_recentDocumentsMenu];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Save"
                                                  action:@selector(saveDocument:)
                                           keyEquivalent:@"s"] autorelease]];
    [fileMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Save As..."
                                                  action:@selector(saveDocumentAs:)
                                           keyEquivalent:@"S"] autorelease]];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Print..."
                                                  action:@selector(printDocument:)
                                           keyEquivalent:@"p"] autorelease]];
    [fileItem setSubmenu:fileMenu];

    NSMenuItem *scoreItem = [[[NSMenuItem alloc] initWithTitle:@"Score" action:NULL keyEquivalent:@""] autorelease];
    [mainMenu addItem:scoreItem];
    NSMenu *scoreMenu = [[[NSMenu alloc] initWithTitle:@"Score"] autorelease];
    [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Play"
                                                   action:@selector(playScore:)
                                            keyEquivalent:@""] autorelease]];
    [scoreItem setSubmenu:scoreMenu];

    [NSApp setMainMenu:mainMenu];
}

@end
