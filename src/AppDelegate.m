/*
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This file is part of ScoreMaker.
 *
 * ScoreMaker is free software: you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or (at
 * your option) any later version.
 *
 * ScoreMaker is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
 * License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with ScoreMaker.  If not, see <https://www.gnu.org/licenses/>.
 */

#import "AppDelegate.h"
#import "ScoreMakerDocument.h"

#if defined(__APPLE__)
#define ScoreMakerPanelStyle (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
#else
#define ScoreMakerPanelStyle (NSTitledWindowMask | NSClosableWindowMask)
#endif

@interface ScoreMakerInfoView : NSView
@end

static void
ScoreMakerDrawText (NSString *text, NSRect rect, NSFont *font, NSColor *color,
                    NSTextAlignment alignment)
{
  NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
  [style setAlignment:alignment];
  [style setLineBreakMode:NSLineBreakByWordWrapping];
  NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
    font, NSFontAttributeName, color, NSForegroundColorAttributeName,
    style, NSParagraphStyleAttributeName, nil];
  [text drawInRect:rect withAttributes:attributes];
}

@implementation ScoreMakerInfoView

- (BOOL)isFlipped
{
  return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
  (void)dirtyRect;
  NSRect bounds = [self bounds];
  [[NSColor colorWithCalibratedRed:0.965 green:0.945 blue:0.895 alpha:1.0] setFill];
  NSRectFill (bounds);

  /* A dark concert-poster header, softened by a small warm color field. */
  [[NSColor colorWithCalibratedRed:0.075 green:0.078 blue:0.095 alpha:1.0] setFill];
  NSRectFill (NSMakeRect (0.0, 0.0, NSWidth (bounds), 238.0));
  [[NSColor colorWithCalibratedRed:0.91 green:0.29 blue:0.22 alpha:1.0] setFill];
  NSRectFill (NSMakeRect (0.0, 0.0, 9.0, 238.0));

  /* Oversized staff: the lines continue behind the title like a score cover. */
  NSColor *staffColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.15];
  [staffColor setStroke];
  for (NSInteger line = 0; line < 5; line++)
    {
      NSBezierPath *staff = [NSBezierPath bezierPath];
      [staff setLineWidth:1.0];
      [staff moveToPoint:NSMakePoint (286.0, 58.5 + line * 18.0)];
      [staff lineToPoint:NSMakePoint (620.0, 58.5 + line * 18.0)];
      [staff stroke];
    }

  /* Hand-drawn note constellation. */
  NSArray *notes = [NSArray arrayWithObjects:
    [NSValue valueWithPoint:NSMakePoint (328.0, 112.0)],
    [NSValue valueWithPoint:NSMakePoint (397.0, 76.0)],
    [NSValue valueWithPoint:NSMakePoint (466.0, 130.0)],
    [NSValue valueWithPoint:NSMakePoint (542.0, 94.0)], nil];
  NSArray *noteColors = [NSArray arrayWithObjects:
    [NSColor colorWithCalibratedRed:0.96 green:0.36 blue:0.28 alpha:1.0],
    [NSColor colorWithCalibratedRed:0.33 green:0.58 blue:0.98 alpha:1.0],
    [NSColor colorWithCalibratedRed:0.96 green:0.72 blue:0.22 alpha:1.0],
    [NSColor colorWithCalibratedRed:0.62 green:0.42 blue:0.95 alpha:1.0], nil];
  for (NSUInteger index = 0; index < [notes count]; index++)
    {
      NSPoint point = [[notes objectAtIndex:index] pointValue];
      NSColor *color = [noteColors objectAtIndex:index];
      [color setFill];
      NSBezierPath *head = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect (point.x, point.y, 24.0, 16.0)];
      NSAffineTransform *rotation = [NSAffineTransform transform];
      [rotation translateXBy:point.x + 12.0 yBy:point.y + 8.0];
      [rotation rotateByDegrees:-18.0];
      [rotation translateXBy:-(point.x + 12.0) yBy:-(point.y + 8.0)];
      [head transformUsingAffineTransform:rotation];
      [head fill];
      NSBezierPath *stem = [NSBezierPath bezierPath];
      [stem setLineWidth:3.0];
      [color setStroke];
      [stem moveToPoint:NSMakePoint (point.x + 21.0, point.y + 5.0)];
      [stem lineToPoint:NSMakePoint (point.x + 21.0, point.y - 48.0)];
      [stem stroke];
    }

  NSColor *paper = [NSColor colorWithCalibratedRed:0.965 green:0.945 blue:0.895 alpha:1.0];
  ScoreMakerDrawText (@"SCORE", NSMakeRect (44.0, 42.0, 230.0, 54.0),
                      [NSFont boldSystemFontOfSize:46.0], paper, NSTextAlignmentLeft);
  ScoreMakerDrawText (@"MAKER", NSMakeRect (44.0, 89.0, 230.0, 54.0),
                      [NSFont boldSystemFontOfSize:46.0], paper, NSTextAlignmentLeft);
  ScoreMakerDrawText (@"COMPOSE  ·  ENGRAVE  ·  PLAY",
                      NSMakeRect (47.0, 161.0, 260.0, 22.0),
                      [NSFont boldSystemFontOfSize:11.0],
                      [NSColor colorWithCalibratedRed:0.96 green:0.54 blue:0.39 alpha:1.0],
                      NSTextAlignmentLeft);

  NSColor *ink = [NSColor colorWithCalibratedRed:0.10 green:0.105 blue:0.12 alpha:1.0];
  ScoreMakerDrawText (@"A studio for ideas in motion.", NSMakeRect (44.0, 278.0, 520.0, 38.0),
                      [NSFont boldSystemFontOfSize:27.0], ink, NSTextAlignmentLeft);
  ScoreMakerDrawText (@"Shape notation, sculpt sound, and hear every phrase take flight — from the first mark on the staff to the final resonance.",
                      NSMakeRect (44.0, 326.0, 510.0, 52.0),
                      [NSFont systemFontOfSize:14.0],
                      [NSColor colorWithCalibratedWhite:0.25 alpha:1.0], NSTextAlignmentLeft);

  [[NSColor colorWithCalibratedRed:0.80 green:0.76 blue:0.67 alpha:1.0] setStroke];
  NSBezierPath *rule = [NSBezierPath bezierPath];
  [rule moveToPoint:NSMakePoint (44.0, 405.5)];
  [rule lineToPoint:NSMakePoint (576.0, 405.5)];
  [rule stroke];

  ScoreMakerDrawText (@"VERSION", NSMakeRect (44.0, 430.0, 80.0, 18.0),
                      [NSFont boldSystemFontOfSize:10.0],
                      [NSColor colorWithCalibratedRed:0.55 green:0.27 blue:0.22 alpha:1.0], NSTextAlignmentLeft);
  NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
  ScoreMakerDrawText (version ? version : @"1.0", NSMakeRect (44.0, 450.0, 80.0, 22.0),
                      [NSFont systemFontOfSize:14.0], ink, NSTextAlignmentLeft);
  ScoreMakerDrawText (@"CRAFT", NSMakeRect (178.0, 430.0, 80.0, 18.0),
                      [NSFont boldSystemFontOfSize:10.0],
                      [NSColor colorWithCalibratedRed:0.55 green:0.27 blue:0.22 alpha:1.0], NSTextAlignmentLeft);
  ScoreMakerDrawText (@"Native AppKit", NSMakeRect (178.0, 450.0, 130.0, 22.0),
                      [NSFont systemFontOfSize:14.0], ink, NSTextAlignmentLeft);
  ScoreMakerDrawText (@"♪", NSMakeRect (535.0, 426.0, 40.0, 50.0),
                      [NSFont systemFontOfSize:34.0],
                      [NSColor colorWithCalibratedRed:0.91 green:0.29 blue:0.22 alpha:1.0], NSTextAlignmentCenter);

  ScoreMakerDrawText (@"Designed for musicians who think in color, gesture, and time.",
                      NSMakeRect (44.0, 498.0, 532.0, 22.0),
                      [[NSFontManager sharedFontManager]
                        convertFont:[NSFont systemFontOfSize:12.0]
                        toHaveTrait:NSItalicFontMask],
                      [NSColor colorWithCalibratedWhite:0.38 alpha:1.0], NSTextAlignmentCenter);
}

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  (void)notification;
  _playlistPaths = [[NSMutableArray alloc] init];
  [[NSNotificationCenter defaultCenter]
    addObserver:self selector:@selector (playlistDocumentDidFinish:)
           name:ScoreMakerDocumentPlaybackDidFinishNotification object:nil];
  [self buildMenu];
}

- (BOOL)openDocumentAtPath:(NSString *)path
{
  if ([path length] == 0)
    return NO;
  NSDocumentController *controller = [NSDocumentController sharedDocumentController];
#if defined(__APPLE__)
  [controller openDocumentWithContentsOfURL:[NSURL fileURLWithPath:path]
                                    display:YES
                          completionHandler:^(NSDocument *document, BOOL alreadyOpen, NSError *error) {
    (void)document;
    (void)alreadyOpen;
    if (error)
      [controller presentError:error];
  }];
  return YES;
#else
  NSError *error = nil;
  NSDocument *document = [controller openDocumentWithContentsOfURL:[NSURL fileURLWithPath:path]
                                                           display:YES
                                                             error:&error];
  if (!document && error)
    [controller presentError:error];
  return document != nil;
#endif
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename
{
  (void)sender;
  return [self openDocumentAtPath:filename];
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames
{
  BOOL success = YES;
  for (NSString *filename in filenames)
    {
      if (![self openDocumentAtPath:filename])
        success = NO;
    }
  [sender replyToOpenOrPrint:success ? NSApplicationDelegateReplySuccess
                                     : NSApplicationDelegateReplyFailure];
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
  return NO;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
  (void)sender;
  return NO;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
  (void)notification;
  [self stopPlaylist:nil];
  for (NSDocument *document in [[NSDocumentController sharedDocumentController] documents])
    {
      if ([document isKindOfClass:[ScoreMakerDocument class]])
        {
          [(ScoreMakerDocument *)document prepareForApplicationTermination];
        }
    }
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [_playlistDelayTimer invalidate];
  [_playlistDelayTimer release];
  [_playlistDocument release];
  [_playlistPaths release];
  [_playlistPanel release];
  [_recentDocumentsMenu release];
  [_infoPanel release];
  [super dealloc];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
  return tableView == _playlistTable ? (NSInteger)[_playlistPaths count] : 0;
}

- (id)tableView:(NSTableView *)tableView
 objectValueForTableColumn:(NSTableColumn *)column
             row:(NSInteger)row
{
  (void)tableView;
  (void)column;
  if (row < 0 || (NSUInteger)row >= [_playlistPaths count])
    return @"";
  return [[_playlistPaths objectAtIndex:(NSUInteger)row] lastPathComponent];
}

- (NSButton *)playlistButtonWithTitle:(NSString *)title frame:(NSRect)frame action:(SEL)action
{
  NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
  [button setTitle:title];
  [button setTarget:self];
  [button setAction:action];
  return button;
}

- (void)showPlaylist:(id)sender
{
  (void)sender;
  if (!_playlistPanel)
    {
      NSRect frame = NSMakeRect (0.0, 0.0, 560.0, 410.0);
      _playlistPanel = [[NSPanel alloc] initWithContentRect:frame
                                                 styleMask:ScoreMakerPanelStyle
                                                   backing:NSBackingStoreBuffered defer:NO];
      [_playlistPanel setTitle:@"Playlist"];
      [_playlistPanel setReleasedWhenClosed:NO];
      NSView *content = [_playlistPanel contentView];
      NSScrollView *scroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect (20.0, 92.0, 520.0, 290.0)] autorelease];
      [scroll setHasVerticalScroller:YES];
      [scroll setBorderType:NSBezelBorder];
      _playlistTable = [[NSTableView alloc] initWithFrame:[scroll bounds]];
      NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"music"] autorelease];
      [[column headerCell] setStringValue:@"Music"];
      [column setWidth:500.0];
      [_playlistTable addTableColumn:column];
      [_playlistTable setHeaderView:nil];
      [_playlistTable setDataSource:self];
      [_playlistTable setDelegate:self];
      [scroll setDocumentView:_playlistTable];
      [content addSubview:scroll];

      [content addSubview:[self playlistButtonWithTitle:@"Add..." frame:NSMakeRect (20, 52, 72, 28)
                                                  action:@selector (addPlaylistItems:)]];
      [content addSubview:[self playlistButtonWithTitle:@"Remove" frame:NSMakeRect (98, 52, 72, 28)
                                                  action:@selector (removePlaylistItem:)]];
      [content addSubview:[self playlistButtonWithTitle:@"Up" frame:NSMakeRect (176, 52, 54, 28)
                                                  action:@selector (movePlaylistItemUp:)]];
      [content addSubview:[self playlistButtonWithTitle:@"Down" frame:NSMakeRect (236, 52, 58, 28)
                                                  action:@selector (movePlaylistItemDown:)]];
      NSTextField *delayLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect (310, 57, 105, 20)] autorelease];
      [delayLabel setStringValue:@"Delay (seconds):"];
      [delayLabel setEditable:NO]; [delayLabel setBordered:NO]; [delayLabel setDrawsBackground:NO];
      [content addSubview:delayLabel];
      _playlistDelayField = [[NSTextField alloc] initWithFrame:NSMakeRect (418, 53, 58, 26)];
      [_playlistDelayField setDoubleValue:2.0];
      [content addSubview:_playlistDelayField];
      [content addSubview:[self playlistButtonWithTitle:@"Play" frame:NSMakeRect (20, 14, 72, 28)
                                                  action:@selector (playPlaylist:)]];
      [content addSubview:[self playlistButtonWithTitle:@"Stop" frame:NSMakeRect (98, 14, 72, 28)
                                                  action:@selector (stopPlaylist:)]];
      [content addSubview:[self playlistButtonWithTitle:@"Save..." frame:NSMakeRect (176, 14, 72, 28)
                                                  action:@selector (savePlaylist:)]];
      [content addSubview:[self playlistButtonWithTitle:@"Load..." frame:NSMakeRect (254, 14, 72, 28)
                                                  action:@selector (loadPlaylist:)]];
      _playlistStatusField = [[NSTextField alloc] initWithFrame:NSMakeRect (340, 19, 200, 20)];
      [_playlistStatusField setStringValue:@"Not playing"];
      [_playlistStatusField setEditable:NO]; [_playlistStatusField setBordered:NO];
      [_playlistStatusField setDrawsBackground:NO];
      [content addSubview:_playlistStatusField];
    }
  [_playlistPanel center];
  [_playlistPanel makeKeyAndOrderFront:self];
}

- (void)addPlaylistItems:(id)sender
{
  (void)sender;
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  [panel setAllowsMultipleSelection:YES];
  [panel setCanChooseDirectories:NO];
  if ([panel runModal] != NSModalResponseOK)
    return;
  for (NSURL *url in [panel URLs])
    if (![_playlistPaths containsObject:[url path]])
      [_playlistPaths addObject:[url path]];
  [_playlistTable reloadData];
}

- (void)savePlaylist:(id)sender
{
  (void)sender;
  NSSavePanel *panel = [NSSavePanel savePanel];
  [panel setNameFieldStringValue:@"Playlist.scoreplaylist"];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  [panel setAllowedFileTypes:@[ @"scoreplaylist" ]];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
  if ([panel runModal] != NSModalResponseOK) return;

  NSDictionary *playlist = @{
    @"version" : @1,
    @"delay" : @([_playlistDelayField doubleValue]),
    @"items" : _playlistPaths
  };
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:playlist
                                                  options:NSJSONWritingPrettyPrinted error:&error];
  if (!data || ![data writeToURL:[panel URL] options:NSDataWritingAtomic error:&error])
    [[NSDocumentController sharedDocumentController] presentError:error];
}

- (void)loadPlaylist:(id)sender
{
  (void)sender;
  NSOpenPanel *panel = [NSOpenPanel openPanel];
  [panel setAllowsMultipleSelection:NO];
  [panel setCanChooseDirectories:NO];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  [panel setAllowedFileTypes:@[ @"scoreplaylist" ]];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
  if ([panel runModal] != NSModalResponseOK) return;

  NSError *error = nil;
  NSData *data = [NSData dataWithContentsOfURL:[panel URL] options:0 error:&error];
  id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
  NSArray *items = [object isKindOfClass:[NSDictionary class]] ? [object objectForKey:@"items"] : nil;
  NSNumber *version = [object isKindOfClass:[NSDictionary class]]
    ? [object objectForKey:@"version"] : nil;
  NSNumber *delay = [object isKindOfClass:[NSDictionary class]]
    ? [object objectForKey:@"delay"] : nil;
  BOOL valid = [version isKindOfClass:[NSNumber class]] && [version integerValue] == 1
    && [items isKindOfClass:[NSArray class]] && [delay isKindOfClass:[NSNumber class]];
  if (valid)
    for (id item in items)
      if (![item isKindOfClass:[NSString class]]) { valid = NO; break; }
  if (!valid)
    {
      if (!error)
        error = [NSError errorWithDomain:@"ScoreMakerPlaylistError" code:1
                                userInfo:@{ NSLocalizedDescriptionKey :
                                  @"The selected file is not a supported ScoreMaker playlist." }];
      [[NSDocumentController sharedDocumentController] presentError:error];
      return;
    }

  [self stopPlaylist:nil];
  [_playlistPaths setArray:items];
  [_playlistDelayField setDoubleValue:MAX (0.0, [delay doubleValue])];
  [_playlistTable reloadData];
}

- (void)removePlaylistItem:(id)sender
{
  (void)sender;
  NSInteger row = [_playlistTable selectedRow];
  if (row >= 0 && (NSUInteger)row < [_playlistPaths count])
    { [_playlistPaths removeObjectAtIndex:(NSUInteger)row]; [_playlistTable reloadData]; }
}

- (void)movePlaylistItemBy:(NSInteger)offset
{
  NSInteger row = [_playlistTable selectedRow], target = row + offset;
  if (row < 0 || target < 0 || (NSUInteger)target >= [_playlistPaths count]) return;
  [_playlistPaths exchangeObjectAtIndex:(NSUInteger)row withObjectAtIndex:(NSUInteger)target];
  [_playlistTable reloadData];
  [_playlistTable selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)target]
             byExtendingSelection:NO];
}
- (void)movePlaylistItemUp:(id)sender { (void)sender; [self movePlaylistItemBy:-1]; }
- (void)movePlaylistItemDown:(id)sender { (void)sender; [self movePlaylistItemBy:1]; }

- (void)setPlaylistDocument:(NSDocument *)document
{
  if (_playlistDocument == document) return;
  NSDocument *previousDocument = _playlistDocument;
  _playlistDocument = [document retain];
  if (previousDocument)
    {
      [previousDocument close];
      [previousDocument release];
    }
}

- (void)highlightCurrentPlaylistItem
{
  if (!_playlistTable || _playlistIndex >= [_playlistPaths count]) return;
  [_playlistTable selectRowIndexes:[NSIndexSet indexSetWithIndex:_playlistIndex]
             byExtendingSelection:NO];
  [_playlistTable scrollRowToVisible:(NSInteger)_playlistIndex];
}

- (void)playPlaylistItem
{
  if (!_playlistPlaying || _playlistIndex >= [_playlistPaths count])
    { [self stopPlaylist:nil]; return; }
  NSString *path = [_playlistPaths objectAtIndex:_playlistIndex];
  [_playlistStatusField setStringValue:[NSString stringWithFormat:@"Playing %lu of %lu: %@",
    (unsigned long)(_playlistIndex + 1), (unsigned long)[_playlistPaths count], [path lastPathComponent]]];
  NSDocumentController *controller = [NSDocumentController sharedDocumentController];
#if defined(__APPLE__)
  [controller openDocumentWithContentsOfURL:[NSURL fileURLWithPath:path] display:YES
    completionHandler:^(NSDocument *document, BOOL alreadyOpen, NSError *error) {
      (void)alreadyOpen;
      if (error) { [controller presentError:error]; [self stopPlaylist:nil]; return; }
      if (_playlistPlaying && [document isKindOfClass:[ScoreMakerDocument class]])
        {
          [self setPlaylistDocument:document];
          [self highlightCurrentPlaylistItem];
          [[(ScoreMakerDocument *)document scoreView] selectNote:nil scrollToVisible:NO];
          [(ScoreMakerDocument *)document playScore:self];
        }
    }];
#else
  NSError *error = nil;
  NSDocument *document = [controller openDocumentWithContentsOfURL:[NSURL fileURLWithPath:path]
                                                           display:YES error:&error];
  if ([document isKindOfClass:[ScoreMakerDocument class]])
    {
      [self setPlaylistDocument:document];
      [self highlightCurrentPlaylistItem];
      [[(ScoreMakerDocument *)document scoreView] selectNote:nil scrollToVisible:NO];
      [(ScoreMakerDocument *)document playScore:self];
    }
  else { if (error) [controller presentError:error]; [self stopPlaylist:nil]; }
#endif
}

- (void)playPlaylist:(id)sender
{
  (void)sender;
  if (![_playlistPaths count]) { NSBeep (); return; }
  NSInteger selectedRow = [_playlistTable selectedRow];
  [self stopPlaylist:nil];
  _playlistPlaying = YES;
  _playlistIndex = selectedRow >= 0 && (NSUInteger)selectedRow < [_playlistPaths count]
    ? (NSUInteger)selectedRow : 0;
  [self playPlaylistItem];
}

- (void)playlistDocumentDidFinish:(NSNotification *)notification
{
  if (!_playlistPlaying) return;
  NSString *expected = [_playlistPaths objectAtIndex:_playlistIndex];
  NSString *finished = [[(ScoreMakerDocument *)[notification object] fileURL] path];
  if (finished && ![[expected stringByStandardizingPath] isEqualToString:[finished stringByStandardizingPath]]) return;
  [_playlistTable deselectAll:self];
  _playlistIndex++;
  if (_playlistIndex >= [_playlistPaths count]) { [self stopPlaylist:nil]; return; }
  NSTimeInterval delay = MAX (0.0, [_playlistDelayField doubleValue]);
  [_playlistStatusField setStringValue:[NSString stringWithFormat:@"Next track in %.1f seconds", delay]];
  _playlistDelayTimer = [[NSTimer scheduledTimerWithTimeInterval:MAX (0.001, delay) target:self
    selector:@selector (playlistDelayDidFire:) userInfo:nil repeats:NO] retain];
}

- (void)playlistDelayDidFire:(NSTimer *)timer
{
  (void)timer;
  [_playlistDelayTimer release]; _playlistDelayTimer = nil;
  [self playPlaylistItem];
}

- (void)stopPlaylist:(id)sender
{
  (void)sender;
  _playlistPlaying = NO;
  [_playlistDelayTimer invalidate]; [_playlistDelayTimer release]; _playlistDelayTimer = nil;
  for (NSDocument *document in [[NSDocumentController sharedDocumentController] documents])
    if ([document isKindOfClass:[ScoreMakerDocument class]])
      [(ScoreMakerDocument *)document stopCurrentPlayback];
  [_playlistTable deselectAll:self];
  [_playlistStatusField setStringValue:@"Not playing"];
}

- (void)showInfoPanel:(id)sender
{
  (void)sender;
  if (!_infoPanel)
    {
      NSRect frame = NSMakeRect (0.0, 0.0, 620.0, 540.0);
      _infoPanel = [[NSPanel alloc] initWithContentRect:frame
                                             styleMask:ScoreMakerPanelStyle
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
      [_infoPanel setTitle:@"About ScoreMaker"];
      [_infoPanel setReleasedWhenClosed:NO];
      [_infoPanel setFloatingPanel:YES];
      [_infoPanel setHidesOnDeactivate:NO];
      [_infoPanel setContentView:[[[ScoreMakerInfoView alloc] initWithFrame:frame] autorelease]];
      if ([_infoPanel respondsToSelector:@selector (setAccessibilityTitle:)])
        [_infoPanel setAccessibilityTitle:@"About ScoreMaker"];
    }
  [_infoPanel center];
  [_infoPanel makeKeyAndOrderFront:self];
}

- (void)openRecentDocument:(id)sender
{
  NSURL *url = [sender representedObject];
  if (!url)
    {
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
  if (!document && error)
    {
      [controller presentError:error];
    }
  [self menuNeedsUpdate:_recentDocumentsMenu];
}

- (void)clearRecentDocuments:(id)sender
{
  (void)sender;
  [[NSDocumentController sharedDocumentController] clearRecentDocuments:self];
  [self menuNeedsUpdate:_recentDocumentsMenu];
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
  if (menu != _recentDocumentsMenu)
    {
      return;
    }

  while ([menu numberOfItems] > 0)
    {
      [menu removeItemAtIndex:0];
    }

  NSArray *urls = [[NSDocumentController sharedDocumentController] recentDocumentURLs];
  for (NSURL *url in urls)
    {
      NSString *title = [[url path] lastPathComponent];
      NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title
                                                     action:@selector (openRecentDocument:)
                                              keyEquivalent:@""] autorelease];
      [item setTarget:self];
      [item setRepresentedObject:url];
      [menu addItem:item];
    }

  if ([urls count] == 0)
    {
      NSMenuItem *emptyItem = [[[NSMenuItem alloc] initWithTitle:@"No Recent Documents"
                                                          action:NULL
                                                   keyEquivalent:@""] autorelease];
      [emptyItem setEnabled:NO];
      [menu addItem:emptyItem];
    }

  [menu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *clearItem = [[[NSMenuItem alloc] initWithTitle:@"Clear Menu"
                                                      action:@selector (clearRecentDocuments:)
                                               keyEquivalent:@""] autorelease];
  [clearItem setTarget:self];
  [clearItem setEnabled:([urls count] > 0)];
  [menu addItem:clearItem];
}

- (void)buildMenu
{
  NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@"ScoreMaker"] autorelease];
#if !defined(__APPLE__)
  NSMenuItem *appItem = [[[NSMenuItem alloc] initWithTitle:@"Info"
                                                    action:NULL
                                             keyEquivalent:@""] autorelease];
  [mainMenu addItem:appItem];

  NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@"Info"] autorelease];
#else
  NSMenuItem *appItem = [[[NSMenuItem alloc] initWithTitle:@"ScoreMaker"
                                                    action:NULL
                                             keyEquivalent:@""] autorelease];
  [mainMenu addItem:appItem];

  NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@"ScoreMaker"] autorelease];
#endif
  NSMenuItem *aboutItem = [[[NSMenuItem alloc] initWithTitle:@"About ScoreMaker"
                                                      action:@selector (showInfoPanel:)
                                               keyEquivalent:@""] autorelease];
  [aboutItem setTarget:self];
  [appMenu addItem:aboutItem];
#if defined(__APPLE__)
  [appMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *quitItem = [[[NSMenuItem alloc] initWithTitle:@"Quit ScoreMaker"
                                                     action:@selector (terminate:)
                                              keyEquivalent:@"q"] autorelease];
  [appMenu addItem:quitItem];
#endif
  [appItem setSubmenu:appMenu];

  NSMenuItem *fileItem = [[[NSMenuItem alloc] initWithTitle:@"File" action:NULL
                                              keyEquivalent:@""] autorelease];
  [mainMenu addItem:fileItem];
  NSMenu *fileMenu = [[[NSMenu alloc] initWithTitle:@"File"] autorelease];

  [fileMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"New"
                                                action:@selector (newDocument:)
                                         keyEquivalent:@"n"] autorelease]];
  [fileMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Open..."
                                                action:@selector (openDocument:)
                                         keyEquivalent:@"o"] autorelease]];
  NSMenuItem *playlistItem = [[[NSMenuItem alloc] initWithTitle:@"Playlist..."
                                                        action:@selector (showPlaylist:)
                                                 keyEquivalent:@""] autorelease];
  [playlistItem setTarget:self];
  [fileMenu addItem:playlistItem];
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
                                                action:@selector (saveDocument:)
                                         keyEquivalent:@"s"] autorelease]];
  [fileMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Save As..."
                                                action:@selector (saveDocumentAs:)
                                         keyEquivalent:@"S"] autorelease]];
  [fileMenu addItem:[NSMenuItem separatorItem]];
  [fileMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Print..."
                                                action:@selector (printDocument:)
                                         keyEquivalent:@"p"] autorelease]];
  [fileItem setSubmenu:fileMenu];

  NSMenuItem *editItem = [[[NSMenuItem alloc] initWithTitle:@"Edit" action:NULL
                                              keyEquivalent:@""] autorelease];
  [mainMenu addItem:editItem];
  NSMenu *editMenu = [[[NSMenu alloc] initWithTitle:@"Edit"] autorelease];
  [editMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Undo"
                                                action:NSSelectorFromString (@"undo:")
                                         keyEquivalent:@"z"] autorelease]];
  [editMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Redo"
                                                action:NSSelectorFromString (@"redo:")
                                         keyEquivalent:@"Z"] autorelease]];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [editMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Cut"
                                                action:@selector (cut:)
                                         keyEquivalent:@"x"] autorelease]];
  [editMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Copy"
                                                action:@selector (copy:)
                                         keyEquivalent:@"c"] autorelease]];
  [editMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Paste"
                                                action:@selector (paste:)
                                         keyEquivalent:@"v"] autorelease]];
  [editItem setSubmenu:editMenu];

  NSMenuItem *viewItem = [[[NSMenuItem alloc] initWithTitle:@"View" action:NULL
                                               keyEquivalent:@""] autorelease];
  [mainMenu addItem:viewItem];
  NSMenu *viewMenu = [[[NSMenu alloc] initWithTitle:@"View"] autorelease];
  for (NSNumber *percent in @[ @50, @75, @100, @125, @150, @200 ])
    {
      NSMenuItem *zoom = [[[NSMenuItem alloc]
        initWithTitle:[NSString stringWithFormat:@"%@%%", percent]
               action:@selector (setScoreZoom:) keyEquivalent:@""] autorelease];
      [zoom setTag:[percent integerValue]];
      [viewMenu addItem:zoom];
    }
  [viewMenu addItem:[NSMenuItem separatorItem]];
  [viewMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Fit Width"
                                                  action:@selector (fitScoreWidth:)
                                           keyEquivalent:@"0"] autorelease]];
  [viewMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Fit Page"
                                                  action:@selector (fitScorePage:)
                                           keyEquivalent:@"9"] autorelease]];
  [viewItem setSubmenu:viewMenu];

  NSMenuItem *scoreItem = [[[NSMenuItem alloc] initWithTitle:@"Score" action:NULL
                                               keyEquivalent:@""] autorelease];
  [mainMenu addItem:scoreItem];
  NSMenu *scoreMenu = [[[NSMenu alloc] initWithTitle:@"Score"] autorelease];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Play"
                                                 action:@selector (playScore:)
                                          keyEquivalent:@" "] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Play from Selection"
                                                 action:@selector (playFromSelection:)
                                          keyEquivalent:@"return"] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Stop"
                                                 action:@selector (stopPlayback:)
                                          keyEquivalent:@"."] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Rewind"
                                                 action:@selector (rewindScore:)
                                          keyEquivalent:@"["] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Go to Measure..."
                                                 action:@selector (goToMeasure:)
                                          keyEquivalent:@"g"] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Loop Selection"
                                                 action:@selector (toggleLoopSelection:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Metronome"
                                                 action:@selector (toggleMetronome:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Written Pitch"
                                                 action:@selector (toggleWrittenPitch:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *templateItem = [[[NSMenuItem alloc] initWithTitle:@"Templates"
                                                         action:NULL keyEquivalent:@""] autorelease];
  NSMenu *templateMenu = [[[NSMenu alloc] initWithTitle:@"Templates"] autorelease];
  for (NSString *name in @[ @"Piano", @"Choir (SATB)", @"String Quartet",
                             @"Concert Band", @"Orchestra" ])
    {
      NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:name
                                                     action:@selector (applyScoreTemplate:)
                                              keyEquivalent:@""] autorelease];
      [item setRepresentedObject:name];
      [templateMenu addItem:item];
    }
  [templateItem setSubmenu:templateMenu];
  [scoreMenu addItem:templateItem];
  [scoreMenu addItem:[NSMenuItem separatorItem]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Voices to Parts"
                                                 action:@selector (convertVoicesToParts:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Parts to Voices"
                                                 action:@selector (convertPartsToVoices:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *transposeUp = [[[NSMenuItem alloc] initWithTitle:@"Transpose Up Semitone"
                                                        action:@selector (transposeSelection:)
                                                 keyEquivalent:@""] autorelease];
  [transposeUp setTag:1];
  [scoreMenu addItem:transposeUp];
  NSMenuItem *transposeDown = [[[NSMenuItem alloc] initWithTitle:@"Transpose Down Semitone"
                                                          action:@selector (transposeSelection:)
                                                   keyEquivalent:@""] autorelease];
  [transposeDown setTag:-1];
  [scoreMenu addItem:transposeDown];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Quantize Selection"
                                                 action:@selector (quantizeSelection:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[NSMenuItem separatorItem]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Routing Matrix..."
                                                 action:@selector (chooseMIDIOutput:)
                                          keyEquivalent:@""] autorelease]];
  NSMenuItem *dspItem = [[[NSMenuItem alloc] initWithTitle:@"Use Real-Time DSP"
                                                    action:@selector (toggleRealtimeDSP:)
                                             keyEquivalent:@""] autorelease];
  [dspItem setTarget:nil];
  [scoreMenu addItem:dspItem];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Internal Synth Patch Editor..."
                                                 action:@selector (showInternalSynthPatchEditor:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Choose Audio Unit Instrument..."
                                                 action:@selector (chooseAudioUnitInstrument:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Show Audio Unit Editor..."
                                                 action:@selector (showAudioUnitEditor:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Audio Unit Presets..."
                                                 action:@selector (manageAudioUnitPresets:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Relink or Substitute Audio Unit..."
                                                 action:@selector (relinkAudioUnitInstrument:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Audio Unit Compatibility Report..."
                                                 action:@selector (showAudioUnitCompatibilityReport:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Effects..."
                                                 action:@selector (editEffects:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Render Internal DSP Audio..."
                                                 action:@selector (renderOfflineAudio:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[NSMenuItem separatorItem]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Page Layout..."
                                                 action:@selector (editPageLayout:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Export PDF..."
                                                 action:@selector (exportPDF:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Export Compatibility Report..."
                                                 action:@selector (showExportCompatibilityReport:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[NSMenuItem separatorItem]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Edit Score Source..."
                                                 action:@selector (showScoreSourceEditor:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[NSMenuItem separatorItem]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Edit Title..."
                                                 action:@selector (editScoreTitle:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Choose Title Font..."
                                                 action:@selector (chooseTitleFont:)
                                          keyEquivalent:@""] autorelease]];
  [scoreItem setSubmenu:scoreMenu];

#if !defined(__APPLE__)
  NSMenuItem *quitItem = [[[NSMenuItem alloc] initWithTitle:@"Quit ScoreMaker"
                                                     action:@selector (terminate:)
                                              keyEquivalent:@"q"] autorelease];
  [mainMenu addItem:quitItem];
#endif

  [NSApp setMainMenu:mainMenu];
}

@end
