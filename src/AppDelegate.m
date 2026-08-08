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

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
  (void)notification;
  [self buildMenu];
  [self performSelector:@selector (openUntitledDocumentIfNeeded) withObject:nil afterDelay:0.0];
}

- (void)openUntitledDocumentIfNeeded
{
  NSDocumentController *controller = [NSDocumentController sharedDocumentController];
  if (!_receivedOpenRequest && [[controller documents] count] == 0)
    {
      NSError *error = nil;
      NSDocument *document = [controller openUntitledDocumentAndDisplay:YES error:&error];
      if (!document && error)
        {
          [controller presentError:error];
        }
    }
}

- (BOOL)openDocumentAtPath:(NSString *)path
{
  if ([path length] == 0)
    return NO;
  _receivedOpenRequest = YES;
  NSError *error = nil;
  NSDocumentController *controller = [NSDocumentController sharedDocumentController];
  NSDocument *document = [controller openDocumentWithContentsOfURL:[NSURL fileURLWithPath:path]
                                                           display:YES
                                                             error:&error];
  if (!document && error)
    [controller presentError:error];
  return document != nil;
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
  return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
  (void)notification;
  for (NSDocument *document in [[NSDocumentController sharedDocumentController] documents])
    {
      if ([document isKindOfClass:[ScoreMakerDocument class]])
        {
          [(ScoreMakerDocument *)document stopCurrentPlayback];
        }
    }
}

- (void)dealloc
{
  [_recentDocumentsMenu release];
  [super dealloc];
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
  NSMenuItem *appItem = [[[NSMenuItem alloc] initWithTitle:@"ScoreMaker"
                                                    action:NULL
                                             keyEquivalent:@""] autorelease];
  [mainMenu addItem:appItem];

  NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@"ScoreMaker"] autorelease];
  NSMenuItem *quitItem = [[[NSMenuItem alloc] initWithTitle:@"Quit ScoreMaker"
                                                     action:@selector (terminate:)
                                              keyEquivalent:@"q"] autorelease];
  [appMenu addItem:quitItem];
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
                                                action:@selector (undo:)
                                         keyEquivalent:@"z"] autorelease]];
  [editMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Redo"
                                                action:@selector (redo:)
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

  NSMenuItem *scoreItem = [[[NSMenuItem alloc] initWithTitle:@"Score" action:NULL
                                               keyEquivalent:@""] autorelease];
  [mainMenu addItem:scoreItem];
  NSMenu *scoreMenu = [[[NSMenu alloc] initWithTitle:@"Score"] autorelease];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Play"
                                                 action:@selector (playScore:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Stop"
                                                 action:@selector (stopPlayback:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Loop Selection"
                                                 action:@selector (toggleLoopSelection:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[NSMenuItem separatorItem]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"MIDI Output..."
                                                 action:@selector (chooseMIDIOutput:)
                                          keyEquivalent:@""] autorelease]];
  NSMenuItem *dspItem = [[[NSMenuItem alloc] initWithTitle:@"Use Real-Time DSP"
                                                    action:@selector (toggleRealtimeDSP:)
                                             keyEquivalent:@""] autorelease];
  [dspItem setTarget:nil];
  [scoreMenu addItem:dspItem];
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
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Edit Title..."
                                                 action:@selector (editScoreTitle:)
                                          keyEquivalent:@""] autorelease]];
  [scoreMenu addItem:[[[NSMenuItem alloc] initWithTitle:@"Choose Title Font..."
                                                 action:@selector (chooseTitleFont:)
                                          keyEquivalent:@""] autorelease]];
  [scoreItem setSubmenu:scoreMenu];

  [NSApp setMainMenu:mainMenu];
}

@end
