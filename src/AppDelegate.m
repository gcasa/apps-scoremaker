#import "AppDelegate.h"
#import "MidiParser.h"
#import "ScorefileParser.h"

@implementation AppDelegate

- (NSWindow *)window
{
    return _window;
}

- (void)setWindow:(NSWindow *)window
{
    if (_window != window) {
        [_window release];
        _window = [window retain];
    }
}

- (NSScrollView *)scrollView
{
    return _scrollView;
}

- (void)setScrollView:(NSScrollView *)scrollView
{
    if (_scrollView != scrollView) {
        [_scrollView release];
        _scrollView = [scrollView retain];
    }
}

- (ScoreView *)scoreView
{
    return _scoreView;
}

- (void)setScoreView:(ScoreView *)scoreView
{
    if (_scoreView != scoreView) {
        [_scoreView release];
        _scoreView = [scoreView retain];
    }
}

- (NSString *)currentPath
{
    return _currentPath;
}

- (void)setCurrentPath:(NSString *)currentPath
{
    if (_currentPath != currentPath) {
        [_currentPath release];
        _currentPath = [currentPath retain];
    }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    [self buildMenu];
    [self buildWindow];

    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    if ([arguments count] > 1) {
        [self openScoreAtPath:[arguments objectAtIndex:1]];
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

- (void)dealloc
{
    [_window release];
    [_scrollView release];
    [_scoreView release];
    [_currentPath release];
    [super dealloc];
}

- (void)buildMenu
{
    NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@"Main Menu"] autorelease];
    NSMenuItem *appItem = [[[NSMenuItem alloc] initWithTitle:@"ScoreMaker" action:NULL keyEquivalent:@""] autorelease];
    [mainMenu addItem:appItem];

    NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@"ScoreMaker"] autorelease];
    NSString *quitTitle = @"Quit ScoreMaker";
    NSMenuItem *quitItem = [[[NSMenuItem alloc] initWithTitle:quitTitle
                                                       action:@selector(terminate:)
                                                keyEquivalent:@"q"] autorelease];
    [appMenu addItem:quitItem];
    [appItem setSubmenu:appMenu];

    NSMenuItem *fileItem = [[[NSMenuItem alloc] initWithTitle:@"File" action:NULL keyEquivalent:@""] autorelease];
    [mainMenu addItem:fileItem];
    NSMenu *fileMenu = [[[NSMenu alloc] initWithTitle:@"File"] autorelease];
    NSMenuItem *openItem = [[[NSMenuItem alloc] initWithTitle:@"Open..."
                                                       action:@selector(openDocument:)
                                                keyEquivalent:@"o"] autorelease];
    [openItem setTarget:self];
    [fileMenu addItem:openItem];
    NSMenuItem *saveItem = [[[NSMenuItem alloc] initWithTitle:@"Save Score As..."
                                                       action:@selector(saveDocumentAs:)
                                                keyEquivalent:@"S"] autorelease];
    [saveItem setTarget:self];
    [fileMenu addItem:saveItem];
    [fileItem setSubmenu:fileMenu];

    [NSApp setMainMenu:mainMenu];
}

- (void)buildWindow
{
    NSRect frame = NSMakeRect(100.0, 100.0, 1040.0, 760.0);
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
    NSUInteger style = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask;
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
    [self setWindow:[[[NSWindow alloc] initWithContentRect:frame
                                                 styleMask:style
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO] autorelease]];
    [[self window] setTitle:@"ScoreMaker"];

    [self setScoreView:[[[ScoreView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 980.0, 760.0)] autorelease]];
    [self setScrollView:[[[NSScrollView alloc] initWithFrame:[[[self window] contentView] bounds]] autorelease]];
    [[self scrollView] setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[self scrollView] setHasVerticalScroller:YES];
    [[self scrollView] setHasHorizontalScroller:YES];
    [[self scrollView] setDocumentView:[self scoreView]];

    [[[self window] contentView] addSubview:[self scrollView]];
    [[self window] makeKeyAndOrderFront:nil];
}

- (void)openDocument:(id)sender
{
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:NO];
    [panel setCanChooseFiles:YES];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
    [panel setAllowedFileTypes:[NSArray arrayWithObjects:@"mid", @"midi", @"score", nil]];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif

    NSInteger result = [panel runModal];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
    BOOL accepted = (result == NSOKButton);
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
    if (accepted) {
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
        NSArray *filenames = [panel filenames];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
        if ([filenames count] > 0) {
            [self openScoreAtPath:[filenames objectAtIndex:0]];
        }
    }
}

- (void)saveDocumentAs:(id)sender
{
    (void)sender;
    if (![[self scoreView] document]) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"There is no score to save"];
        [alert runModal];
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
    [panel setAllowedFileTypes:[NSArray arrayWithObject:@"score"]];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
    NSString *defaultName = @"Untitled.score";
    if ([[self currentPath] length] > 0) {
        defaultName = [[[[self currentPath] lastPathComponent] stringByDeletingPathExtension] stringByAppendingPathExtension:@"score"];
    }
    [panel setNameFieldStringValue:defaultName];

    NSInteger result = [panel runModal];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
    BOOL accepted = (result == NSOKButton);
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
    if (accepted) {
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
        NSString *filename = [panel filename];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
        NSError *error = nil;
        if (![ScorefileParser writeDocument:[[self scoreView] document] toFileAtPath:filename error:&error]) {
            NSAlert *alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText:@"Could not save scorefile"];
            [alert setInformativeText:error ? [error localizedDescription] : @"Unknown error"];
            [alert runModal];
            return;
        }
        [self setCurrentPath:filename];
        [[self window] setTitle:[NSString stringWithFormat:@"ScoreMaker - %@", [filename lastPathComponent]]];
    }
}

- (void)openScoreAtPath:(NSString *)path
{
    NSError *error = nil;
    NSString *extension = [[path pathExtension] lowercaseString];
    ScoreDocument *document = nil;
    if ([extension isEqualToString:@"score"]) {
        document = [ScorefileParser parseFileAtPath:path error:&error];
    } else {
        document = [MidiParser parseFileAtPath:path error:&error];
    }
    if (!document) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"Could not open file"];
        [alert setInformativeText:error ? [error localizedDescription] : @"Unknown error"];
        [alert runModal];
        return;
    }

    [[self scoreView] setDocument:document];
    [self setCurrentPath:path];
    [[self window] setTitle:[NSString stringWithFormat:@"ScoreMaker - %@", [path lastPathComponent]]];
}

@end
