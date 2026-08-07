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

#import "ScoreMakerDocument.h"
#import "MusicEngine.h"
#import "MidiParser.h"
#import "MusicXMLParser.h"
#import "ScorefileParser.h"
#import "ScoreProjectSerializer.h"
#import <float.h>
#import <math.h>
#import <AVFoundation/AVFoundation.h>

@interface AVMIDIPlayer (ScoreMakerPlaybackStatus)
- (BOOL)isPlaying;
- (NSError *)error;
- (NSTimeInterval)currentPosition;
- (void)setCurrentPosition:(NSTimeInterval)position;
@end

static CGFloat const InspectorWidth = 320.0;
static CGFloat const InspectorPadding = 18.0;
static CGFloat const PlaybackMonitorHeight = 150.0;
static CGFloat const InspectorContentHeight = 1060.0;

#if defined(__APPLE__)
static NSString *
ScoreMakerMIDIEndpointName (MIDIEndpointRef endpoint)
{
  CFStringRef value = NULL;
  if (MIDIObjectGetStringProperty (endpoint, kMIDIPropertyDisplayName, &value) != noErr || !value)
    {
      MIDIObjectGetStringProperty (endpoint, kMIDIPropertyName, &value);
    }
  if (!value)
    return @"MIDI Instrument";
  return [(NSString *)value autorelease];
}

static void
ScoreMakerSendAllNotesOff (MIDIEndpointRef endpoint)
{
  if (!endpoint)
    return;
  MIDIClientRef client = 0;
  MIDIPortRef port = 0;
  if (MIDIClientCreate (CFSTR ("ScoreMaker"), NULL, NULL, &client) != noErr)
    return;
  if (MIDIOutputPortCreate (client, CFSTR ("Playback Safety"), &port) == noErr)
    {
      Byte packetStorage[1024];
      MIDIPacketList *packetList = (MIDIPacketList *)packetStorage;
      MIDIPacket *packet = MIDIPacketListInit (packetList);
      for (UInt8 channel = 0; channel < 16; channel++)
        {
          Byte message[] = { (Byte)(0xb0 | channel), 123, 0 };
          packet = MIDIPacketListAdd (packetList, sizeof (packetStorage), packet, 0,
                                      sizeof (message), message);
          if (!packet)
            break;
        }
      MIDISend (port, endpoint, packetList);
      MIDIPortDispose (port);
    }
  MIDIClientDispose (client);
}
#endif

@class ScoreMakerDocument;

@interface ScorePaletteItemView : NSView
{
  ScoreMakerDocument *_document;
  NSString *_item;
  NSString *_label;
  NSUInteger _denominator;
}
- (id)initWithFrame:(NSRect)frame
           document:(ScoreMakerDocument *)document
               item:(NSString *)item
              label:(NSString *)label
        denominator:(NSUInteger)denominator;
@end

@interface ScoreMakerDocument (Palette)
- (NSString *)palettePayloadForItem:(NSString *)item denominator:(NSUInteger)denominator;
@end

@interface ScoreMakerDocument (Playback)
- (BOOL)restartPlaybackAtTick:(NSUInteger)tick;
- (void)startPlaybackHighlightAtTick:(NSUInteger)tick;
- (void)stopAudition;
- (void)auditionPitch:(NSInteger)pitch;
- (void)finishAudition:(NSTimer *)timer;
- (void)reloadMIDIInputs;
- (void)stopMIDIRecording;
- (void)handleMIDIInputEvent:(NSDictionary *)event;
- (void)midiDevicesChanged:(id)sender;
- (void)registerUndoSnapshotWithName:(NSString *)name;
- (void)restoreScoreSnapshot:(ScoreDocument *)snapshot;
- (void)commitUndoBaseline;
- (void)restoreAudioUnitInstrument;
- (void)captureAudioUnitState;
- (void)showGenericAudioUnitEditor;
- (void)audioUnitParameterChanged:(id)sender;
- (BOOL)prepareDSPPlaybackAtTick:(NSUInteger)tick error:(NSError **)error;
@end

@implementation ScorePaletteItemView

- (id)initWithFrame:(NSRect)frame
           document:(ScoreMakerDocument *)document
               item:(NSString *)item
              label:(NSString *)label
        denominator:(NSUInteger)denominator
{
  self = [super initWithFrame:frame];
  if (self)
    {
      _document = document;
      _item = [item retain];
      _label = [label retain];
      _denominator = denominator;
    }
  return self;
}

- (void)dealloc
{
  [_item release];
  [_label release];
  [super dealloc];
}

- (BOOL)isFlipped
{
  return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
  (void)dirtyRect;
  NSRect bounds = [self bounds];
  [[NSColor colorWithCalibratedWhite:0.98 alpha:1.0] setFill];
  NSRectFill (bounds);
  [[NSColor colorWithCalibratedWhite:0.7 alpha:1.0] setStroke];
  NSFrameRect (bounds);

  if (![_item isEqualToString:@"note"] && ![_item isEqualToString:@"rest"])
    {
      NSDictionary *toolAttrs = [NSDictionary
        dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:10.0], NSFontAttributeName,
                                     [NSColor blackColor], NSForegroundColorAttributeName, nil];
      [_label drawAtPoint:NSMakePoint (5.0, 7.0) withAttributes:toolAttrs];
      return;
    }

  [[NSColor blackColor] setStroke];
  [[NSColor blackColor] setFill];
  CGFloat x = 22.0;
  CGFloat y = 20.0;
  if ([_item isEqualToString:@"rest"])
    {
      if (_denominator == 1)
        {
          NSRectFill (NSMakeRect (x - 8.0, y - 1.0, 16.0, 5.0));
        }
      else if (_denominator == 2)
        {
          NSRectFill (NSMakeRect (x - 8.0, y - 6.0, 16.0, 5.0));
        }
      else
        {
          [self drawRestGlyphAtX:x y:y denominator:_denominator];
        }
    }
  else
    {
      BOOL filled = (_denominator >= 4);
      NSBezierPath *head =
        [NSBezierPath bezierPathWithOvalInRect:NSMakeRect (x - 6.0, y - 4.0, 12.0, 8.0)];
      filled ? [head fill] : [head stroke];
      if (_denominator > 1)
        {
          [NSBezierPath strokeLineFromPoint:NSMakePoint (x + 6.0, y)
                                    toPoint:NSMakePoint (x + 6.0, y - 18.0)];
          [self drawFlagsFromX:x + 6.0 stemEnd:y - 18.0 denominator:_denominator];
        }
    }

  NSDictionary *attrs = [NSDictionary
    dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:12.0], NSFontAttributeName,
                                 [NSColor blackColor], NSForegroundColorAttributeName, nil];
  [_label drawAtPoint:NSMakePoint (44.0, 12.0) withAttributes:attrs];
}

- (NSImage *)dragImage
{
  NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize (54.0, 42.0)] autorelease];
  NSBitmapImageRep *rep =
    [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                             pixelsWide:54
                                             pixelsHigh:42
                                          bitsPerSample:8
                                        samplesPerPixel:4
                                               hasAlpha:YES
                                               isPlanar:NO
                                         colorSpaceName:NSCalibratedRGBColorSpace
                                            bytesPerRow:0
                                           bitsPerPixel:0] autorelease];
  if (!rep)
    {
      return image;
    }

  memset ([rep bitmapData], 0, (size_t)[rep bytesPerRow] * (size_t)[rep pixelsHigh]);
  [NSGraphicsContext saveGraphicsState];
  [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
  [[NSColor blackColor] setStroke];
  [[NSColor blackColor] setFill];
  if ([_item isEqualToString:@"sharp"] || [_item isEqualToString:@"flat"] ||
      [_item isEqualToString:@"natural"])
    {
      NSString *symbol =
        [_item isEqualToString:@"sharp"] ? @"♯" : ([_item isEqualToString:@"flat"] ? @"♭" : @"♮");
      NSFont *font = [NSFont fontWithName:@"Times New Roman" size:30.0];
      if (!font)
        font = [NSFont systemFontOfSize:27.0];
      NSDictionary *attrs =
        [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, [NSColor blackColor],
                                                   NSForegroundColorAttributeName, nil];
      NSSize symbolSize = [symbol sizeWithAttributes:attrs];
      [symbol drawAtPoint:NSMakePoint ((54.0 - symbolSize.width) / 2.0,
                                       (42.0 - symbolSize.height) / 2.0)
           withAttributes:attrs];
    }
  else if ([_item isEqualToString:@"slur"] || [_item isEqualToString:@"tie"])
    {
      NSBezierPath *slur = [NSBezierPath bezierPath];
      [slur moveToPoint:NSMakePoint (7.0, 13.0)];
      [slur curveToPoint:NSMakePoint (47.0, 13.0)
           controlPoint1:NSMakePoint (17.0, 31.0)
           controlPoint2:NSMakePoint (37.0, 31.0)];
      [slur setLineWidth:2.5];
      [slur stroke];
    }
  else if (![_item isEqualToString:@"note"] && ![_item isEqualToString:@"rest"])
    {
      NSDictionary *attrs = [NSDictionary
        dictionaryWithObjectsAndKeys:[NSFont boldSystemFontOfSize:16.0], NSFontAttributeName,
                                     [NSColor blackColor], NSForegroundColorAttributeName, nil];
      [_label drawAtPoint:NSMakePoint (8.0, 11.0) withAttributes:attrs];
    }
  else if ([_item isEqualToString:@"rest"])
    {
      if (_denominator == 2)
        {
          NSRectFill (NSMakeRect (18.0, 14.0, 18.0, 6.0));
        }
      else
        {
          NSRectFill (NSMakeRect (18.0, 20.0, 18.0, 6.0));
        }
    }
  else
    {
      NSBezierPath *head =
        [NSBezierPath bezierPathWithOvalInRect:NSMakeRect (20.0, 20.0, 12.0, 8.0)];
      if (_denominator >= 4)
        {
          [head fill];
        }
      else
        {
          [head stroke];
        }
      if (_denominator > 1)
        {
          [NSBezierPath strokeLineFromPoint:NSMakePoint (32.0, 24.0)
                                    toPoint:NSMakePoint (32.0, 5.0)];
        }
    }
  [NSGraphicsContext restoreGraphicsState];
  [image addRepresentation:rep];
  return image;
}

- (void)drawFlagsFromX:(CGFloat)x stemEnd:(CGFloat)stemEnd denominator:(NSUInteger)denominator
{
  NSUInteger flags = 0;
  for (NSUInteger value = denominator; value > 4; value /= 2)
    {
      flags++;
    }
  for (NSUInteger i = 0; i < flags; i++)
    {
      CGFloat y = stemEnd + (CGFloat)i * 6.0;
      NSBezierPath *flag = [NSBezierPath bezierPath];
      [flag moveToPoint:NSMakePoint (x, y)];
      [flag curveToPoint:NSMakePoint (x + 12.0, y + 9.0)
           controlPoint1:NSMakePoint (x + 10.0, y + 1.0)
           controlPoint2:NSMakePoint (x + 12.0, y + 7.0)];
      [flag stroke];
    }
}

- (void)drawRestGlyphAtX:(CGFloat)x y:(CGFloat)y denominator:(NSUInteger)denominator
{
  NSUInteger flags = 0;
  for (NSUInteger value = denominator; value > 4; value /= 2)
    {
      flags++;
    }
  NSBezierPath *path = [NSBezierPath bezierPath];
  [path moveToPoint:NSMakePoint (x - 4.0, y - 14.0)];
  [path curveToPoint:NSMakePoint (x + 5.0, y + 4.0)
       controlPoint1:NSMakePoint (x + 8.0, y - 9.0)
       controlPoint2:NSMakePoint (x - 8.0, y - 2.0)];
  [path setLineWidth:2.0];
  [path stroke];
  for (NSUInteger i = 1; i < flags; i++)
    {
      CGFloat offset = (CGFloat)i * 6.0;
      [NSBezierPath strokeLineFromPoint:NSMakePoint (x + 1.0, y - 8.0 + offset)
                                toPoint:NSMakePoint (x + 9.0, y - 3.0 + offset)];
    }
}

- (void)mouseDragged:(NSEvent *)event
{
  NSString *payload = [_document palettePayloadForItem:_item denominator:_denominator];
  if ([payload length] == 0)
    {
      return;
    }
  NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSDragPboard];
  [pasteboard declareTypes:[NSArray arrayWithObject:ScorePalettePasteboardType] owner:nil];
  [pasteboard setString:payload forType:ScorePalettePasteboardType];
  [self dragImage:[self dragImage]
               at:NSMakePoint (4.0, 4.0)
           offset:NSZeroSize
            event:event
       pasteboard:pasteboard
           source:self
        slideBack:YES];
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
  (void)isLocal;
  return NSDragOperationCopy;
}

@end

@implementation ScoreMakerDocument

+ (BOOL)autosavesInPlace
{
  return YES;
}

- (id)init
{
  self = [super init];
  if (self)
    {
      _realtimeDSP = [[ScoreRealtimeDSP alloc] init];
      _realtimeDSPPitch = -1;
      _audioUnitPartTrack = -1;
      ScoreDocument *document = [[[ScoreDocument alloc] init] autorelease];
      [document setTitle:@"Untitled"];
      [self setScoreDocument:document];
#if defined(__APPLE__)
      _useBuiltInMIDIOutput = NO;
#endif
    }
  return self;
}

- (NSWindow *)window
{
  return _documentWindow;
}

- (void)setWindow:(NSWindow *)window
{
  _documentWindow = window;
}

- (NSWindowController *)windowController
{
  return _windowController;
}

- (void)setWindowController:(NSWindowController *)windowController
{
  _windowController = windowController;
}

- (NSScrollView *)scrollView
{
  return _scrollView;
}

- (void)setScrollView:(NSScrollView *)scrollView
{
  if (_scrollView != scrollView)
    {
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
  if (_scoreView != scoreView)
    {
      [_scoreView release];
      _scoreView = [scoreView retain];
    }
}

- (NSView *)inspectorView
{
  return _inspectorView;
}

- (void)setInspectorView:(NSView *)inspectorView
{
  if (_inspectorView != inspectorView)
    {
      [_inspectorView release];
      _inspectorView = [inspectorView retain];
    }
}

- (ScoreDocument *)scoreDocument
{
  return _scoreDocument;
}

- (void)commitUndoBaseline
{
  [_undoBaseline release];
  _undoBaseline = _scoreDocument ? [_scoreDocument copy] : nil;
}

- (void)registerUndoSnapshotWithName:(NSString *)name
{
  if (_restoringUndo || !_scoreDocument)
    return;
  ScoreDocument *snapshot = [[_scoreDocument copy] autorelease];
  [[[self undoManager] prepareWithInvocationTarget:self] restoreScoreSnapshot:snapshot];
  [[self undoManager] setActionName:name ?: @"Edit Score"];
}

- (void)restoreScoreSnapshot:(ScoreDocument *)snapshot
{
  if (!snapshot)
    return;
  ScoreDocument *redoSnapshot = [[_scoreDocument copy] autorelease];
  [[[self undoManager] prepareWithInvocationTarget:self] restoreScoreSnapshot:redoSnapshot];
  _restoringUndo = YES;
  [self setScoreDocument:[[snapshot copy] autorelease]];
  _restoringUndo = NO;
  [[self scoreView] reloadDocument];
  [self refreshInspector];
  [self restoreAudioUnitInstrument];
  [self commitUndoBaseline];
}

- (void)setScoreDocument:(ScoreDocument *)document
{
  if (_scoreDocument != document)
    {
      [_scoreDocument release];
      _scoreDocument = [document retain];
    }
  if (!_restoringUndo)
    [self commitUndoBaseline];
  [[self scoreView] setDocument:_scoreDocument];
  [_playbackMonitorView setDocument:_scoreDocument];
  if ([self window])
    {
      [[self window] setTitle:[self displayName]];
    }
  [self refreshInspector];
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self stopCurrentPlayback];
  [self stopAudition];
  [self stopMIDIRecording];
  [_midiInputManager disconnect];
  [_midiInputManager setTarget:nil];
  [_scoreDocument release];
  [_realtimeDSP stop];
  [_realtimeDSP release];
  [_audioUnitEditorWindow close];
  [_audioUnitEditorWindow release];
  [_audioUnitParameterAddresses release];
  [_scrollView release];
  [_scoreView release];
  [_inspectorScrollView release];
  [_inspectorView release];
  [_playbackMonitorView release];
  [_tempoField release];
  [_tempoSlider release];
  [_timeNumeratorField release];
  [_timeDenominatorField release];
  [_notePitchField release];
  [_noteStartField release];
  [_noteDurationField release];
  [_noteTypePopUp release];
  [_noteValuePopUp release];
  [_partPopUp release];
  [_instrumentPopUp release];
  [_addPartButton release];
  [_separatePartsButton release];
  [_addNoteButton release];
  [_keySignaturePopUp release];
  [_repeatStartButton release];
  [_repeatEndButton release];
  [_tieStartButton release];
  [_tieEndButton release];
  [_tupletPopUp release];
  [_dynamicPopUp release];
  [_articulationPopUp release];
  [_playButton release];
  [_pauseButton release];
  [_stopButton release];
  [_midiInputPopUp release];
  [_midiQuantizePopUp release];
  [_midiRoutingPopUp release];
  [_recordButton release];
  [_midiInputManager release];
  [_midiActiveNotes release];
  [_midiHeldStepNotes release];
  [_midiSustainedNotes release];
  [_midiMetronomeSound release];
  [_undoBaseline release];
  [_midiRecordingUndoSnapshot release];
  [_annotationTextView release];

  [super dealloc];
}

- (void)close
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self stopCurrentPlayback];
  [self stopAudition];
  [self stopMIDIRecording];
  [_midiInputManager disconnect];
  [_midiInputManager setTarget:nil];
  [super close];
}

- (void)makeWindowControllers
{
  NSRect frame = NSMakeRect (100.0, 100.0, 1320.0, 880.0);
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  NSUInteger style = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask
                     | NSResizableWindowMask;
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
  [self setWindow:[[[NSWindow alloc] initWithContentRect:frame
                                               styleMask:style
                                                 backing:NSBackingStoreBuffered
                                                   defer:NO] autorelease]];
  [[self window] setReleasedWhenClosed:NO];
  [[self window] setTitle:[self displayName]];

  [self setScoreView:[[[ScoreView alloc] initWithFrame:NSMakeRect (0.0, 0.0, 980.0, 760.0)]
                       autorelease]];
  [[self scoreView] setDocument:[self scoreDocument]];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector (scoreViewDidEditScore:)
                                               name:ScoreViewDidEditScoreNotification
                                             object:[self scoreView]];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector (scoreViewSelectionDidChange:)
                                               name:ScoreViewSelectionDidChangeNotification
                                             object:[self scoreView]];
  NSRect contentBounds = [[[self window] contentView] bounds];
  NSRect scoreFrame
    = NSMakeRect (0.0, PlaybackMonitorHeight, contentBounds.size.width,
                  MAX ((CGFloat)300.0, contentBounds.size.height - PlaybackMonitorHeight));
  scoreFrame.size.width = MAX ((CGFloat)300.0, scoreFrame.size.width - InspectorWidth);
  NSRect inspectorFrame = NSMakeRect (NSMaxX (scoreFrame), PlaybackMonitorHeight, InspectorWidth,
                                      scoreFrame.size.height);

  [self setScrollView:[[[NSScrollView alloc] initWithFrame:scoreFrame] autorelease]];
  [[self scrollView] setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [[self scrollView] setHasVerticalScroller:YES];
  [[self scrollView] setHasHorizontalScroller:YES];
  [[self scrollView] setDocumentView:[self scoreView]];

  [[[self window] contentView] addSubview:[self scrollView]];
  _midiInputManager = [[MIDIInputManager alloc] init];
  [_midiInputManager setTarget:self];
  [_midiInputManager setAction:@selector (handleMIDIInputEvent:)];
  [_midiInputManager setChangeAction:@selector (midiDevicesChanged:)];
  _midiActiveNotes = [[NSMutableDictionary alloc] init];
  _midiHeldStepNotes = [[NSMutableSet alloc] init];
  _midiSustainedNotes = [[NSMutableSet alloc] init];

  CGFloat inspectorContentHeight = MAX (InspectorContentHeight, inspectorFrame.size.height);
  [self buildInspectorWithFrame:NSMakeRect (0.0, 0.0, InspectorWidth, inspectorContentHeight)];
  _inspectorScrollView = [[NSScrollView alloc] initWithFrame:inspectorFrame];
  [_inspectorScrollView setAutoresizingMask:NSViewMinXMargin | NSViewHeightSizable];
  [_inspectorScrollView setHasVerticalScroller:YES];
  [_inspectorScrollView setHasHorizontalScroller:NO];
  [_inspectorScrollView setBorderType:NSNoBorder];
  [_inspectorScrollView setDocumentView:[self inspectorView]];
  [[[self window] contentView] addSubview:_inspectorScrollView];
  NSClipView *inspectorClip = [_inspectorScrollView contentView];
  [inspectorClip
    scrollToPoint:NSMakePoint (0.0, MAX ((CGFloat)0.0, inspectorContentHeight
                                                         - NSHeight ([inspectorClip bounds])))];
  [_inspectorScrollView reflectScrolledClipView:inspectorClip];
  _playbackMonitorView = [[PlaybackMonitorView alloc]
    initWithFrame:NSMakeRect (0.0, 0.0, contentBounds.size.width, PlaybackMonitorHeight)];
  [_playbackMonitorView setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [_playbackMonitorView setDocument:[self scoreDocument]];
  [_playbackMonitorView setTarget:self];
  [_playbackMonitorView setAction:@selector (pianoKeyPressed:)];
  [[[self window] contentView] addSubview:_playbackMonitorView];
  [self refreshInspector];
  [self restoreAudioUnitInstrument];
  [self
    setWindowController:[[[NSWindowController alloc] initWithWindow:[self window]] autorelease]];
  [self addWindowController:[self windowController]];
}

- (NSTextField *)labelWithString:(NSString *)string frame:(NSRect)frame
{
  NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
  [label setStringValue:string];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [label setFont:[NSFont boldSystemFontOfSize:12.0]];
  return label;
}

- (NSTextField *)metadataFieldWithFrame:(NSRect)frame
{
  NSTextField *field = [[[NSTextField alloc] initWithFrame:frame] autorelease];
  [field setTarget:self];
  [field setAction:@selector (scoreMetadataDidChange:)];
  [field setDelegate:self];
  return field;
}

- (void)buildInspectorWithFrame:(NSRect)frame
{
  [self setInspectorView:[[[NSView alloc] initWithFrame:frame] autorelease]];
  [[self inspectorView] setAutoresizingMask:NSViewWidthSizable];

  NSTextField *title =
    [self labelWithString:@"Score"
                    frame:NSMakeRect (InspectorPadding, frame.size.height - 36.0, 220.0, 20.0)];
  [title setFont:[NSFont boldSystemFontOfSize:15.0]];
  [title setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:title];

  _playButton =
    [[NSButton alloc] initWithFrame:NSMakeRect (frame.size.width - InspectorPadding - 176.0,
                                                frame.size.height - 42.0, 54.0, 28.0)];
  [_playButton setTitle:@"Play"];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  [_playButton setButtonType:NSMomentaryPushInButton];
  [_playButton setBezelStyle:NSRoundedBezelStyle];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
  [_playButton setTarget:self];
  [_playButton setAction:@selector (playScore:)];
  [_playButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
  [[self inspectorView] addSubview:_playButton];

  _pauseButton =
    [[NSButton alloc] initWithFrame:NSMakeRect (frame.size.width - InspectorPadding - 118.0,
                                                frame.size.height - 42.0, 62.0, 28.0)];
  [_pauseButton setTitle:@"Pause"];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  [_pauseButton setButtonType:NSMomentaryPushInButton];
  [_pauseButton setBezelStyle:NSRoundedBezelStyle];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
  [_pauseButton setTarget:self];
  [_pauseButton setAction:@selector (pausePlayback:)];
  [_pauseButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
  [[self inspectorView] addSubview:_pauseButton];

  _stopButton =
    [[NSButton alloc] initWithFrame:NSMakeRect (frame.size.width - InspectorPadding - 52.0,
                                                frame.size.height - 42.0, 52.0, 28.0)];
  [_stopButton setTitle:@"Stop"];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  [_stopButton setButtonType:NSMomentaryPushInButton];
  [_stopButton setBezelStyle:NSRoundedBezelStyle];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
  [_stopButton setTarget:self];
  [_stopButton setAction:@selector (stopPlayback:)];
  [_stopButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
  [[self inspectorView] addSubview:_stopButton];

  NSTextField *tempoLabel =
    [self labelWithString:@"Tempo (BPM)"
                    frame:NSMakeRect (InspectorPadding, frame.size.height - 76.0, 120.0, 18.0)];
  [tempoLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:tempoLabel];
  _tempoField = [[self
    metadataFieldWithFrame:NSMakeRect (InspectorPadding, frame.size.height - 104.0, 92.0, 24.0)]
    retain];
  [_tempoField setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_tempoField];
  _tempoSlider = [[NSSlider alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 104.0, frame.size.height - 105.0, 140.0, 24.0)];
  [_tempoSlider setMinValue:1.0];
  [_tempoSlider setMaxValue:400.0];
  [_tempoSlider setNumberOfTickMarks:0];
  [_tempoSlider setContinuous:YES];
  [_tempoSlider setTarget:self];
  [_tempoSlider setAction:@selector (tempoSliderDidChange:)];
  [_tempoSlider setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_tempoSlider];

  NSTextField *timeLabel =
    [self labelWithString:@"Timing"
                    frame:NSMakeRect (InspectorPadding, frame.size.height - 144.0, 120.0, 18.0)];
  [timeLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:timeLabel];
  _timeNumeratorField = [[self
    metadataFieldWithFrame:NSMakeRect (InspectorPadding, frame.size.height - 172.0, 48.0, 24.0)]
    retain];
  [_timeNumeratorField setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_timeNumeratorField];
  NSTextField *slash = [self
    labelWithString:@"/"
              frame:NSMakeRect (InspectorPadding + 56.0, frame.size.height - 170.0, 10.0, 18.0)];
  [slash setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:slash];
  _timeDenominatorField =
    [[self metadataFieldWithFrame:NSMakeRect (InspectorPadding + 70.0, frame.size.height - 172.0,
                                              48.0, 24.0)] retain];
  [_timeDenominatorField setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_timeDenominatorField];

  NSTextField *addNoteLabel =
    [self labelWithString:@"Add Note"
                    frame:NSMakeRect (InspectorPadding, frame.size.height - 214.0, 120.0, 18.0)];
  [addNoteLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:addNoteLabel];

  NSTextField *typeLabel =
    [self labelWithString:@"Type"
                    frame:NSMakeRect (InspectorPadding, frame.size.height - 242.0, 48.0, 18.0)];
  [typeLabel setFont:[NSFont systemFontOfSize:11.0]];
  [typeLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:typeLabel];
  _noteTypePopUp = [[NSPopUpButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding, frame.size.height - 270.0, 70.0, 26.0)
        pullsDown:NO];
  [_noteTypePopUp addItemWithTitle:@"Note"];
  [_noteTypePopUp addItemWithTitle:@"Rest"];
  [_noteTypePopUp setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_noteTypePopUp];

  NSTextField *valueLabel = [self
    labelWithString:@"Value"
              frame:NSMakeRect (InspectorPadding + 82.0, frame.size.height - 242.0, 48.0, 18.0)];
  [valueLabel setFont:[NSFont systemFontOfSize:11.0]];
  [valueLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:valueLabel];
  _noteValuePopUp = [[NSPopUpButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 82.0, frame.size.height - 270.0, 74.0, 26.0)
        pullsDown:NO];
  [_noteValuePopUp addItemWithTitle:@"Whole"];
  [_noteValuePopUp addItemWithTitle:@"Half"];
  [_noteValuePopUp addItemWithTitle:@"1/4"];
  [_noteValuePopUp addItemWithTitle:@"1/8"];
  [_noteValuePopUp addItemWithTitle:@"1/16"];
  [_noteValuePopUp addItemWithTitle:@"1/32"];
  [_noteValuePopUp setTarget:self];
  [_noteValuePopUp setAction:@selector (noteValueDidChange:)];
  [_noteValuePopUp setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_noteValuePopUp];

  NSTextField *pitchLabel = [self
    labelWithString:@"Pitch"
              frame:NSMakeRect (InspectorPadding + 168.0, frame.size.height - 242.0, 48.0, 18.0)];
  [pitchLabel setFont:[NSFont systemFontOfSize:11.0]];
  [pitchLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:pitchLabel];
  _notePitchField =
    [[self metadataFieldWithFrame:NSMakeRect (InspectorPadding + 168.0, frame.size.height - 270.0,
                                              66.0, 24.0)] retain];
  [_notePitchField setStringValue:@"C4"];
  [_notePitchField setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_notePitchField];

  NSTextField *startLabel =
    [self labelWithString:@"Start"
                    frame:NSMakeRect (InspectorPadding, frame.size.height - 304.0, 48.0, 18.0)];
  [startLabel setFont:[NSFont systemFontOfSize:11.0]];
  [startLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:startLabel];
  _noteStartField = [[self
    metadataFieldWithFrame:NSMakeRect (InspectorPadding, frame.size.height - 332.0, 58.0, 24.0)]
    retain];
  [_noteStartField setStringValue:@"0"];
  [_noteStartField setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_noteStartField];

  NSTextField *durationLabel = [self
    labelWithString:@"Beats"
              frame:NSMakeRect (InspectorPadding + 70.0, frame.size.height - 304.0, 48.0, 18.0)];
  [durationLabel setFont:[NSFont systemFontOfSize:11.0]];
  [durationLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:durationLabel];
  _noteDurationField =
    [[self metadataFieldWithFrame:NSMakeRect (InspectorPadding + 70.0, frame.size.height - 332.0,
                                              58.0, 24.0)] retain];
  [_noteDurationField setStringValue:@"1"];
  [_noteDurationField setEditable:NO];
  [_noteDurationField setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_noteDurationField];

  NSTextField *partLabel = [self
    labelWithString:@"Part"
              frame:NSMakeRect (InspectorPadding + 140.0, frame.size.height - 304.0, 48.0, 18.0)];
  [partLabel setFont:[NSFont systemFontOfSize:11.0]];
  [partLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:partLabel];
  _partPopUp = [[NSPopUpButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 140.0, frame.size.height - 332.0, 88.0, 26.0)
        pullsDown:NO];
  [_partPopUp setTarget:self];
  [_partPopUp setAction:@selector (partDidChange:)];
  [_partPopUp setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_partPopUp];
  _addPartButton = [[NSButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 230.0, frame.size.height - 332.0, 32.0, 26.0)];
  [_addPartButton setTitle:@"+"];
  [_addPartButton setToolTip:@"Add Part"];
  [_addPartButton setTarget:self];
  [_addPartButton setAction:@selector (addPart:)];
  [_addPartButton setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_addPartButton];

  _addNoteButton = [[NSButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 188.0, frame.size.height - 220.0, 74.0, 24.0)];
  [_addNoteButton setTitle:@"Add"];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  [_addNoteButton setButtonType:NSMomentaryPushInButton];
  [_addNoteButton setBezelStyle:NSRoundedBezelStyle];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
  [_addNoteButton setTarget:self];
  [_addNoteButton setAction:@selector (addNote:)];
  [_addNoteButton setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_addNoteButton];

  NSTextField *instrumentLabel =
    [self labelWithString:@"Part Instrument"
                    frame:NSMakeRect (InspectorPadding, frame.size.height - 362.0, 120.0, 18.0)];
  [instrumentLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:instrumentLabel];
  _instrumentPopUp = [[NSPopUpButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding, frame.size.height - 392.0, 244.0, 26.0)
        pullsDown:NO];
  [_instrumentPopUp addItemsWithTitles:[MidiParser generalMidiProgramNames]];
  [_instrumentPopUp setTarget:self];
  [_instrumentPopUp setAction:@selector (instrumentDidChange:)];
  [_instrumentPopUp setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_instrumentPopUp];

  _separatePartsButton = [[NSButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 132.0, frame.size.height - 364.0, 132.0, 20.0)];
  [_separatePartsButton setTitle:@"Separate Part Staves"];
  [_separatePartsButton setButtonType:NSSwitchButton];
  [_separatePartsButton setState:NSOnState];
  [_separatePartsButton setTarget:self];
  [_separatePartsButton setAction:@selector (scoreDisplayModeDidChange:)];
  [_separatePartsButton setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_separatePartsButton];

  NSTextField *midiInputLabel =
    [self labelWithString:@"MIDI Input"
                    frame:NSMakeRect (InspectorPadding, frame.size.height - 424.0, 120.0, 18.0)];
  [midiInputLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:midiInputLabel];
  NSTextField *gridLabel = [self
    labelWithString:@"Grid"
              frame:NSMakeRect (InspectorPadding + 156.0, frame.size.height - 424.0, 50.0, 18.0)];
  [gridLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:gridLabel];
  _midiInputPopUp = [[NSPopUpButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding, frame.size.height - 452.0, 150.0, 26.0)
        pullsDown:NO];
  [_midiInputPopUp setTarget:self];
  [_midiInputPopUp setAction:@selector (midiInputDidChange:)];
  [_midiInputPopUp setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_midiInputPopUp];
  _midiQuantizePopUp = [[NSPopUpButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 156.0, frame.size.height - 452.0, 62.0, 26.0)
        pullsDown:NO];
  [_midiQuantizePopUp addItemsWithTitles:[NSArray arrayWithObjects:@"1/8", @"1/16", @"1/32", nil]];
  [_midiQuantizePopUp selectItemWithTitle:@"1/16"];
  [_midiQuantizePopUp setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_midiQuantizePopUp];
  _recordButton = [[NSButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 224.0, frame.size.height - 452.0, 60.0, 26.0)];
  [_recordButton setTitle:@"Record"];
  [_recordButton setTarget:self];
  [_recordButton setAction:@selector (toggleMIDIRecording:)];
  [_recordButton setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_recordButton];
  [self reloadMIDIInputs];

  NSTextField *routingLabel =
    [self labelWithString:@"Input Routing"
                    frame:NSMakeRect (InspectorPadding, frame.size.height - 482.0, 120.0, 18.0)];
  [routingLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:routingLabel];
  _midiRoutingPopUp = [[NSPopUpButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding, frame.size.height - 510.0, 218.0, 26.0)
        pullsDown:NO];
  [_midiRoutingPopUp addItemWithTitle:@"Selected Part"];
  [[_midiRoutingPopUp lastItem] setRepresentedObject:@"selected"];
  [_midiRoutingPopUp addItemWithTitle:@"MIDI Channel → Part"];
  [[_midiRoutingPopUp lastItem] setRepresentedObject:@"channel"];
  [_midiRoutingPopUp setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_midiRoutingPopUp];

  NSTextField *notationLabel =
    [self labelWithString:@"Selected Note / Measure"
                    frame:NSMakeRect (InspectorPadding, frame.size.height - 548.0, 190.0, 18.0)];
  [notationLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:notationLabel];

  _keySignaturePopUp = [[NSPopUpButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding, frame.size.height - 578.0, 132.0, 26.0)
        pullsDown:NO];
  NSArray *keyNames =
    [NSArray arrayWithObjects:@"C / A minor", @"1♯ G / E minor", @"2♯ D / B minor",
                              @"3♯ A / F♯ minor", @"4♯ E / C♯ minor", @"5♯ B / G♯ minor",
                              @"6♯ F♯ / D♯ minor", @"7♯ C♯ / A♯ minor", @"1♭ F / D minor",
                              @"2♭ B♭ / G minor", @"3♭ E♭ / C minor", @"4♭ A♭ / F minor",
                              @"5♭ D♭ / B♭ minor", @"6♭ G♭ / E♭ minor", @"7♭ C♭ / A♭ minor", nil];
  NSInteger keyValues[] = { 0, 1, 2, 3, 4, 5, 6, 7, -1, -2, -3, -4, -5, -6, -7 };
  for (NSUInteger i = 0; i < [keyNames count]; i++)
    {
      [_keySignaturePopUp addItemWithTitle:[keyNames objectAtIndex:i]];
      [[_keySignaturePopUp lastItem]
        setRepresentedObject:[NSNumber numberWithInteger:keyValues[i]]];
    }
  [_keySignaturePopUp setTarget:self];
  [_keySignaturePopUp setAction:@selector (notationDidChange:)];
  [_keySignaturePopUp setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_keySignaturePopUp];
  _repeatStartButton = [[NSButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 138.0, frame.size.height - 578.0, 72.0, 24.0)];
  [_repeatStartButton setTitle:@"Start |:"];
  [_repeatStartButton setButtonType:NSSwitchButton];
  [_repeatStartButton setTarget:self];
  [_repeatStartButton setAction:@selector (notationDidChange:)];
  [_repeatStartButton setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_repeatStartButton];
  _repeatEndButton = [[NSButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 210.0, frame.size.height - 578.0, 72.0, 24.0)];
  [_repeatEndButton setTitle:@"End :|"];
  [_repeatEndButton setButtonType:NSSwitchButton];
  [_repeatEndButton setTarget:self];
  [_repeatEndButton setAction:@selector (notationDidChange:)];
  [_repeatEndButton setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_repeatEndButton];

  _tieStartButton = [[NSButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding, frame.size.height - 606.0, 72.0, 24.0)];
  [_tieStartButton setTitle:@"Tie start"];
  [_tieStartButton setButtonType:NSSwitchButton];
  [_tieStartButton setTarget:self];
  [_tieStartButton setAction:@selector (notationDidChange:)];
  [_tieStartButton setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_tieStartButton];
  _tieEndButton = [[NSButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 76.0, frame.size.height - 606.0, 70.0, 24.0)];
  [_tieEndButton setTitle:@"Tie end"];
  [_tieEndButton setButtonType:NSSwitchButton];
  [_tieEndButton setTarget:self];
  [_tieEndButton setAction:@selector (notationDidChange:)];
  [_tieEndButton setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_tieEndButton];
  _tupletPopUp = [[NSPopUpButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 150.0, frame.size.height - 606.0, 68.0, 26.0)
        pullsDown:NO];
  [_tupletPopUp addItemsWithTitles:[NSArray arrayWithObjects:@"No tuplet", @"3:2", @"5:4", @"6:4",
                                                             @"7:4", nil]];
  [_tupletPopUp setTarget:self];
  [_tupletPopUp setAction:@selector (notationDidChange:)];
  [_tupletPopUp setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_tupletPopUp];
  _dynamicPopUp = [[NSPopUpButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding, frame.size.height - 636.0, 86.0, 26.0)
        pullsDown:NO];
  [_dynamicPopUp
    addItemsWithTitles:[NSArray arrayWithObjects:@"No dynamic", @"ppp", @"pp", @"p", @"mp", @"mf",
                                                 @"f", @"ff", @"fff", @"sfz", nil]];
  [_dynamicPopUp setTarget:self];
  [_dynamicPopUp setAction:@selector (notationDidChange:)];
  [_dynamicPopUp setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_dynamicPopUp];
  _articulationPopUp = [[NSPopUpButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 92.0, frame.size.height - 636.0, 126.0, 26.0)
        pullsDown:NO];
  [_articulationPopUp
    addItemsWithTitles:[NSArray arrayWithObjects:@"No articulation", @"Staccato", @"Accent",
                                                 @"Tenuto", @"Strong accent", nil]];
  [_articulationPopUp setTarget:self];
  [_articulationPopUp setAction:@selector (notationDidChange:)];
  [_articulationPopUp setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_articulationPopUp];

  NSTextField *paletteLabel =
    [self labelWithString:@"Palette"
                    frame:NSMakeRect (InspectorPadding, frame.size.height - 674.0, 120.0, 18.0)];
  [paletteLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:paletteLabel];

  NSArray *toolItems =
    [NSArray arrayWithObjects:@"sharp", @"flat", @"natural", @"slur", @"tie", @"triplet", @"mf",
                              @"staccato", @"accent", @"tenuto", nil];
  NSArray *toolLabels = [NSArray
    arrayWithObjects:@"♯", @"♭", @"♮", @"Slur", @"Tie", @"3", @"mf", @"Stacc.", @">", @"Ten.", nil];
  for (NSUInteger i = 0; i < [toolItems count]; i++)
    {
      ScorePaletteItemView *toolPalette = [[[ScorePaletteItemView alloc]
        initWithFrame:NSMakeRect (InspectorPadding + (CGFloat)(i % 5) * 53.0,
                                  frame.size.height - 702.0 - (CGFloat)(i / 5) * 29.0, 50.0, 27.0)
             document:self
                 item:[toolItems objectAtIndex:i]
                label:[toolLabels objectAtIndex:i]
          denominator:4] autorelease];
      [toolPalette setAutoresizingMask:NSViewMinYMargin];
      [[self inspectorView] addSubview:toolPalette];
    }

  NSArray *denominators = [NSArray
    arrayWithObjects:[NSNumber numberWithUnsignedInteger:1], [NSNumber numberWithUnsignedInteger:2],
                     [NSNumber numberWithUnsignedInteger:4], [NSNumber numberWithUnsignedInteger:8],
                     [NSNumber numberWithUnsignedInteger:16],
                     [NSNumber numberWithUnsignedInteger:32], nil];
  for (NSUInteger i = 0; i < [denominators count]; i++)
    {
      NSUInteger denominator = [[denominators objectAtIndex:i] unsignedIntegerValue];
      NSString *valueLabel
        = denominator == 1
            ? @"Whole"
            : (denominator == 2 ? @"Half"
                                : [NSString stringWithFormat:@"1/%lu", (unsigned long)denominator]);
      NSString *noteLabel = [NSString stringWithFormat:@"%@ Note", valueLabel];
      ScorePaletteItemView *notePalette = [[[ScorePaletteItemView alloc]
        initWithFrame:NSMakeRect (InspectorPadding, frame.size.height - 766.0 - (CGFloat)i * 27.0,
                                  110.0, 24.0)
             document:self
                 item:@"note"
                label:noteLabel
          denominator:denominator] autorelease];
      [notePalette setAutoresizingMask:NSViewMinYMargin];
      [[self inspectorView] addSubview:notePalette];

      NSString *restLabel = [NSString stringWithFormat:@"%@ Rest", valueLabel];
      ScorePaletteItemView *restPalette = [[[ScorePaletteItemView alloc]
        initWithFrame:NSMakeRect (InspectorPadding + 122.0,
                                  frame.size.height - 766.0 - (CGFloat)i * 27.0, 110.0, 24.0)
             document:self
                 item:@"rest"
                label:restLabel
          denominator:denominator] autorelease];
      [restPalette setAutoresizingMask:NSViewMinYMargin];
      [[self inspectorView] addSubview:restPalette];
    }

  NSTextField *notesLabel =
    [self labelWithString:@"Score Notes"
                    frame:NSMakeRect (InspectorPadding, frame.size.height - 944.0, 120.0, 18.0)];
  [notesLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:notesLabel];

  NSScrollView *notesScroll =
    [[[NSScrollView alloc] initWithFrame:NSMakeRect (InspectorPadding, InspectorPadding,
                                                     frame.size.width - 2.0 * InspectorPadding,
                                                     frame.size.height - 978.0)] autorelease];
  [notesScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [notesScroll setHasVerticalScroller:YES];
  [notesScroll setBorderType:NSBezelBorder];

  _annotationTextView = [[NSTextView alloc] initWithFrame:[[notesScroll contentView] bounds]];
  [_annotationTextView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [_annotationTextView setMinSize:NSMakeSize (0.0, 0.0)];
  [_annotationTextView setMaxSize:NSMakeSize (FLT_MAX, FLT_MAX)];
  [_annotationTextView setVerticallyResizable:YES];
  [_annotationTextView setHorizontallyResizable:NO];
  [[_annotationTextView textContainer]
    setContainerSize:NSMakeSize ([notesScroll contentSize].width, FLT_MAX)];
  [[_annotationTextView textContainer] setWidthTracksTextView:YES];
  [_annotationTextView setFont:[NSFont systemFontOfSize:12.0]];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector (annotationTextDidChange:)
                                               name:NSTextDidChangeNotification
                                             object:_annotationTextView];
  [notesScroll setDocumentView:_annotationTextView];
  [[self inspectorView] addSubview:notesScroll];
}

- (void)refreshInspector
{
  ScoreDocument *document = [self scoreDocument];
  BOOL hasDocument = (document != nil);
  [_tempoField setEnabled:hasDocument];
  [_tempoSlider setEnabled:hasDocument];
  [_timeNumeratorField setEnabled:hasDocument];
  [_timeDenominatorField setEnabled:hasDocument];
  [_notePitchField setEnabled:hasDocument];
  [_noteStartField setEnabled:hasDocument];
  [_noteDurationField setEnabled:hasDocument];
  [_partPopUp setEnabled:hasDocument];
  [_instrumentPopUp setEnabled:hasDocument];
  [_addPartButton setEnabled:hasDocument];
  [_separatePartsButton setEnabled:hasDocument];
  [_noteTypePopUp setEnabled:hasDocument];
  [_noteValuePopUp setEnabled:hasDocument];
  [_addNoteButton setEnabled:hasDocument];
  [_playButton setEnabled:hasDocument];
  [_pauseButton setEnabled:hasDocument && (_playbackTimer || _playbackPaused)];
  [_stopButton setEnabled:hasDocument];
  [_recordButton setEnabled:hasDocument && [_midiInputPopUp indexOfSelectedItem] > 0];
  [_midiQuantizePopUp setEnabled:hasDocument];
  [_annotationTextView setEditable:hasDocument];

  if (!hasDocument)
    {
      [_tempoField setStringValue:@""];
      [_tempoSlider setDoubleValue:120.0];
      [_timeNumeratorField setStringValue:@""];
      [_timeDenominatorField setStringValue:@""];
      _updatingInspector = YES;
      [_annotationTextView setString:@""];
      _updatingInspector = NO;
      return;
    }

  NSUInteger tempo = [document tempoMicrosecondsPerQuarter];
  NSUInteger beatsPerMinute = tempo > 0 ? (NSUInteger)((60000000.0 / (double)tempo) + 0.5) : 120;
  [_tempoField setIntegerValue:(NSInteger)beatsPerMinute];
  [_tempoSlider setIntegerValue:(NSInteger)beatsPerMinute];
  [_timeNumeratorField setIntegerValue:(NSInteger)[document timeSignatureNumerator]];
  [_timeDenominatorField setIntegerValue:(NSInteger)[document timeSignatureDenominator]];
  [_noteDurationField
    setDoubleValue:[self beatsForNoteValueDenominator:[self denominatorForSelectedNoteValue]]];

  ScoreNote *selectedNote = [[self scoreView] selectedNote];
  ScoreMeasure *selectedMeasure
    = selectedNote ? [document measureContainingTick:[selectedNote startTick]]
                   : ([[document measures] count] ? [[document measures] objectAtIndex:0] : nil);
  [_keySignaturePopUp setEnabled:selectedMeasure != nil];
  [_repeatStartButton setEnabled:selectedMeasure != nil];
  [_repeatEndButton setEnabled:selectedMeasure != nil];
  [_tieStartButton setEnabled:selectedNote != nil && ![selectedNote isRest]];
  [_tieEndButton setEnabled:selectedNote != nil && ![selectedNote isRest]];
  [_tupletPopUp setEnabled:selectedNote != nil];
  [_dynamicPopUp setEnabled:selectedNote != nil];
  [_articulationPopUp setEnabled:selectedNote != nil && ![selectedNote isRest]];
  if (selectedMeasure)
    {
      for (NSMenuItem *item in [_keySignaturePopUp itemArray])
        if ([[item representedObject] integerValue] == [selectedMeasure keySignatureFifths])
          {
            [_keySignaturePopUp selectItem:item];
            break;
          }
      [_repeatStartButton setState:[selectedMeasure repeatStart] ? NSOnState : NSOffState];
      [_repeatEndButton setState:[selectedMeasure repeatEnd] ? NSOnState : NSOffState];
    }
  [_tieStartButton setState:selectedNote && [selectedNote tieStart] ? NSOnState : NSOffState];
  [_tieEndButton setState:selectedNote && [selectedNote tieEnd] ? NSOnState : NSOffState];
  NSString *tuplet
    = selectedNote && [selectedNote tupletActual]
        ? [NSString stringWithFormat:@"%lu:%lu", (unsigned long)[selectedNote tupletActual],
                                     (unsigned long)[selectedNote tupletNormal]]
        : @"No tuplet";
  [_tupletPopUp selectItemWithTitle:tuplet];
  [_dynamicPopUp selectItemWithTitle:selectedNote && [[selectedNote dynamic] length]
                                       ? [selectedNote dynamic]
                                       : @"No dynamic"];
  NSDictionary *articulationTitles = [NSDictionary
    dictionaryWithObjectsAndKeys:@"Staccato", @"staccato", @"Accent", @"accent", @"Tenuto",
                                 @"tenuto", @"Strong accent", @"strong-accent", nil];
  [_articulationPopUp
    selectItemWithTitle:selectedNote && [[selectedNote articulation] length]
                          ? [articulationTitles objectForKey:[selectedNote articulation]]
                          : @"No articulation"];
  NSNumber *viewedPart = [[_partPopUp selectedItem] representedObject];
  NSMutableSet *partSet = [NSMutableSet set];
  [partSet addObjectsFromArray:[[document partNames] allKeys]];
  [partSet addObjectsFromArray:[[document trackPrograms] allKeys]];
  NSEnumerator *partNoteEnumerator = [[document notes] objectEnumerator];
  ScoreNote *partNote = nil;
  NSInteger firstNoteTrack = NSIntegerMax;
  while ((partNote = [partNoteEnumerator nextObject]) != nil)
    {
      [partSet addObject:[NSNumber numberWithInteger:[partNote track]]];
      firstNoteTrack = MIN (firstNoteTrack, [partNote track]);
    }
  if ([partSet count] == 0)
    [partSet addObject:[NSNumber numberWithInteger:0]];
  NSInteger selectedPart
    = viewedPart ? [viewedPart integerValue]
                 : (selectedNote
                      ? [selectedNote track]
                      : (firstNoteTrack != NSIntegerMax
                           ? firstNoteTrack
                           : [[[[partSet allObjects] sortedArrayUsingSelector:@selector (compare:)]
                               objectAtIndex:0] integerValue]));
  if (![partSet containsObject:[NSNumber numberWithInteger:selectedPart]])
    selectedPart = [[[[partSet allObjects] sortedArrayUsingSelector:@selector (compare:)]
      objectAtIndex:0] integerValue];
  NSArray *parts = [[partSet allObjects] sortedArrayUsingSelector:@selector (compare:)];
  [_partPopUp removeAllItems];
  NSEnumerator *partEnumerator = [parts objectEnumerator];
  NSNumber *partNumber = nil;
  while ((partNumber = [partEnumerator nextObject]) != nil)
    {
      NSInteger track = [partNumber integerValue];
      NSString *partName = [document nameForTrack:track];
      if ([partName length] == 0)
        {
          partName = [NSString stringWithFormat:@"Part %ld", (long)(track + 1)];
        }
      [_partPopUp addItemWithTitle:partName];
      [[_partPopUp lastItem] setRepresentedObject:partNumber];
      if (track == selectedPart)
        {
          [_partPopUp selectItem:[_partPopUp lastItem]];
        }
    }
  NSNumber *program = [document programForTrack:selectedPart];
  [_instrumentPopUp selectItemAtIndex:program ? [program integerValue] : 0];
  [_playbackMonitorView setSelectedTrack:selectedPart];

  if (selectedNote)
    {
      NSUInteger ticksPerQuarter = MAX ((NSUInteger)1, [document ticksPerQuarter]);
      double durationBeats = (double)[selectedNote durationTicks] / (double)ticksPerQuarter;
      [_noteTypePopUp selectItemWithTitle:[selectedNote isRest] ? @"Rest" : @"Note"];
      if (![selectedNote isRest])
        {
          static NSString *pitchNames[]
            = { @"C", @"C#", @"D", @"D#", @"E", @"F", @"F#", @"G", @"G#", @"A", @"A#", @"B" };
          NSInteger pitch = [selectedNote pitch];
          NSInteger accidental = [selectedNote accidental];
          NSInteger naturalPitch = pitch - accidental;
          NSInteger pitchClass = naturalPitch % 12;
          if (pitchClass < 0)
            pitchClass += 12;
          NSString *name = pitchNames[pitchClass];
          if (accidental > 0)
            {
              name = [name stringByAppendingString:@"#"];
            }
          else if (accidental < 0)
            {
              name = [name stringByAppendingString:@"b"];
            }
          NSInteger octave = naturalPitch / 12 - 1;
          [_notePitchField setStringValue:[NSString stringWithFormat:@"%@%ld", name, (long)octave]];
        }
      [_noteStartField setDoubleValue:(double)[selectedNote startTick] / (double)ticksPerQuarter];
      [_noteDurationField setDoubleValue:durationBeats];

      NSArray *valueTitles =
        [NSArray arrayWithObjects:@"Whole", @"Half", @"1/4", @"1/8", @"1/16", @"1/32", nil];
      double valueBeats[] = { 4.0, 2.0, 1.0, 0.5, 0.25, 0.125 };
      NSUInteger closestIndex = 0;
      double closestDifference = DBL_MAX;
      for (NSUInteger i = 0; i < [valueTitles count]; i++)
        {
          double difference = fabs (durationBeats - valueBeats[i]);
          if (difference < closestDifference)
            {
              closestDifference = difference;
              closestIndex = i;
            }
        }
      [_noteValuePopUp selectItemWithTitle:[valueTitles objectAtIndex:closestIndex]];
    }

  _updatingInspector = YES;
  [_annotationTextView setString:[document annotationText] ? [document annotationText] : @""];
  _updatingInspector = NO;
}

- (NSInteger)selectedPartNumber
{
  NSNumber *part = [[_partPopUp selectedItem] representedObject];
  return part ? [part integerValue] : 0;
}

- (void)addPart:(id)sender
{
  (void)sender;
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    return;
  [self registerUndoSnapshotWithName:@"Add Part"];

  NSInteger highestPart = -1;
  NSEnumerator *noteEnumerator = [[document notes] objectEnumerator];
  ScoreNote *note = nil;
  while ((note = [noteEnumerator nextObject]) != nil)
    {
      highestPart = MAX (highestPart, [note track]);
    }
  NSEnumerator *keyEnumerator = [[[document partNames] allKeys] objectEnumerator];
  NSNumber *key = nil;
  while ((key = [keyEnumerator nextObject]) != nil)
    highestPart = MAX (highestPart, [key integerValue]);
  keyEnumerator = [[[document trackPrograms] allKeys] objectEnumerator];
  while ((key = [keyEnumerator nextObject]) != nil)
    highestPart = MAX (highestPart, [key integerValue]);

  NSInteger newPart = highestPart + 1;
  [document setName:[NSString stringWithFormat:@"Part %ld", (long)(newPart + 1)] forTrack:newPart];
  [document setProgram:[NSNumber numberWithInteger:0] forTrack:newPart];
  [self updateChangeCount:NSChangeDone];
  [self refreshInspector];
  NSEnumerator *itemEnumerator = [[_partPopUp itemArray] objectEnumerator];
  NSMenuItem *item = nil;
  while ((item = [itemEnumerator nextObject]) != nil)
    {
      if ([[item representedObject] integerValue] == newPart)
        {
          [_partPopUp selectItem:item];
          break;
        }
    }
  [_instrumentPopUp selectItemAtIndex:0];
  [self commitUndoBaseline];
}

- (void)partDidChange:(id)sender
{
  (void)sender;
  NSInteger part = [self selectedPartNumber];
  NSNumber *program = [[self scoreDocument] programForTrack:part];
  [_instrumentPopUp selectItemAtIndex:program ? [program integerValue] : 0];
  [_playbackMonitorView setSelectedTrack:part];
  for (ScorePartDefinition *definition in [[self scoreDocument] parts])
    if ([definition legacyTrack] == part)
      {
        [_realtimeDSP configureEffectsFromGraph:[definition synthesisGraph] error:NULL];
        if ([[_realtimeDSP effectConfiguration] count])
          _useRealtimeDSP = YES;
        break;
      }
}

- (void)scoreDisplayModeDidChange:(id)sender
{
  (void)sender;
  [[self scoreView] setSeparateParts:[_separatePartsButton state] == NSOnState];
}

- (void)instrumentDidChange:(id)sender
{
  (void)sender;
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    return;
  [self registerUndoSnapshotWithName:@"Change Instrument"];
  [document setProgram:[NSNumber numberWithInteger:[_instrumentPopUp indexOfSelectedItem]]
              forTrack:[self selectedPartNumber]];
  [_playbackMonitorView setNeedsDisplay:YES];
  [self updateChangeCount:NSChangeDone];
  [self commitUndoBaseline];
}

- (BOOL)isSupportedTimeSignatureDenominator:(NSUInteger)denominator
{
  switch (denominator)
    {
    case 1:
    case 2:
    case 4:
    case 8:
    case 16:
    case 32:
    case 64:
      return YES;
    default:
      return NO;
    }
}

- (void)syncInspectorMetadataMarkingChange:(BOOL)markChange
{
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    {
      return;
    }
  if (markChange)
    [self registerUndoSnapshotWithName:@"Edit Score Metadata"];

  NSUInteger oldTempo = [document tempoMicrosecondsPerQuarter];
  NSUInteger oldNumerator = [document timeSignatureNumerator];
  NSUInteger oldDenominator = [document timeSignatureDenominator];
  BOOL playbackActive = (_playbackTimer != nil || _playbackPaused);
  NSTimeInterval playbackElapsed
    = _playbackPaused ? _playbackPausedElapsed
                      : ([NSDate timeIntervalSinceReferenceDate] - _playbackStartTime);
  double oldSecondsPerQuarter = oldTempo > 0 ? (double)oldTempo / 1000000.0 : 0.5;
  NSUInteger playbackTick = playbackActive
                              ? (NSUInteger)floor ((playbackElapsed / oldSecondsPerQuarter)
                                                   * (double)[document ticksPerQuarter])
                              : 0;

  NSInteger bpm = [_tempoField integerValue];
  if (bpm < 1)
    bpm = 1;
  if (bpm > 400)
    bpm = 400;
  [document setTempoMicrosecondsPerQuarter:(NSUInteger)(60000000.0 / (double)bpm)];

  NSInteger numerator = [_timeNumeratorField integerValue];
  NSInteger denominator = [_timeDenominatorField integerValue];
  if (numerator < 1)
    numerator = 1;
  if (numerator > 64)
    numerator = 64;
  if (![self isSupportedTimeSignatureDenominator:(NSUInteger)denominator])
    {
      denominator = 4;
    }
  [document setTimeSignatureNumerator:(NSUInteger)numerator];
  [document setTimeSignatureDenominator:(NSUInteger)denominator];
  if (oldNumerator != (NSUInteger)numerator || oldDenominator != (NSUInteger)denominator)
    {
      [document buildDefaultMeasures];
    }

  BOOL tempoChanged = oldTempo != [document tempoMicrosecondsPerQuarter];

  if (markChange)
    {
      [self updateChangeCount:NSChangeDone];
    }
  [self refreshInspector];
  [[self scoreView] setNeedsDisplay:YES];
  if (playbackActive && tempoChanged)
    {
      [self restartPlaybackAtTick:playbackTick];
    }
  if (markChange)
    [self commitUndoBaseline];
}

- (void)scoreMetadataDidChange:(id)sender
{
  (void)sender;
  [self syncInspectorMetadataMarkingChange:YES];
}

- (void)tempoSliderDidChange:(id)sender
{
  (void)sender;
  NSInteger bpm = [_tempoSlider integerValue];
  [_tempoField setIntegerValue:bpm];
  [self syncInspectorMetadataMarkingChange:YES];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
  (void)notification;
  [self syncInspectorMetadataMarkingChange:YES];
}

- (void)annotationTextDidChange:(NSNotification *)notification
{
  (void)notification;
  if (_updatingInspector)
    {
      return;
    }
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    {
      return;
    }

  [self registerUndoSnapshotWithName:@"Edit Score Notes"];
  [document setAnnotationText:[_annotationTextView string]];
  [self updateChangeCount:NSChangeDone];
  [self commitUndoBaseline];
}

- (void)scoreViewDidEditScore:(NSNotification *)notification
{
  (void)notification;
  if (!_restoringUndo && _undoBaseline)
    {
      [[[self undoManager] prepareWithInvocationTarget:self] restoreScoreSnapshot:_undoBaseline];
      [[self undoManager] setActionName:@"Edit Score"];
    }
  [[self scoreView] reloadDocument];
  [self updateChangeCount:NSChangeDone];
  [self refreshInspector];
  [self commitUndoBaseline];
}

- (void)scoreViewSelectionDidChange:(NSNotification *)notification
{
  (void)notification;
  [self refreshInspector];
}

- (void)noteValueDidChange:(id)sender
{
  (void)sender;
  [_noteDurationField
    setDoubleValue:[self beatsForNoteValueDenominator:[self denominatorForSelectedNoteValue]]];
}

- (void)notationDidChange:(id)sender
{
  (void)sender;
  if (_updatingInspector)
    return;
  ScoreDocument *document = [self scoreDocument];
  ScoreNote *note = [[self scoreView] selectedNote];
  ScoreMeasure *measure
    = note ? [document measureContainingTick:[note startTick]]
           : ([[document measures] count] ? [[document measures] objectAtIndex:0] : nil);
  if (!document || (!note && !measure))
    return;
  [self registerUndoSnapshotWithName:@"Edit Notation"];
  if (measure)
    {
      [measure
        setKeySignatureFifths:[[[_keySignaturePopUp selectedItem] representedObject] integerValue]];
      [measure setRepeatStart:[_repeatStartButton state] == NSOnState];
      [measure setRepeatEnd:[_repeatEndButton state] == NSOnState];
    }
  if (note)
    {
      [note setTieStart:[_tieStartButton state] == NSOnState];
      [note setTieEnd:[_tieEndButton state] == NSOnState];
      NSString *tuplet = [_tupletPopUp titleOfSelectedItem];
      NSArray *ratio = [tuplet componentsSeparatedByString:@":"];
      [note setTupletActual:[ratio count] == 2 ? [[ratio objectAtIndex:0] integerValue] : 0];
      [note setTupletNormal:[ratio count] == 2 ? [[ratio objectAtIndex:1] integerValue] : 0];
      NSString *dynamic = [_dynamicPopUp titleOfSelectedItem];
      [note setDynamic:[dynamic isEqualToString:@"No dynamic"] ? nil : dynamic];
      NSDictionary *articulations = [NSDictionary
        dictionaryWithObjectsAndKeys:@"staccato", @"Staccato", @"accent", @"Accent", @"tenuto",
                                     @"Tenuto", @"strong-accent", @"Strong accent", nil];
      [note setArticulation:[articulations objectForKey:[_articulationPopUp titleOfSelectedItem]]];
    }
  [[self scoreView] reloadDocument];
  [self updateChangeCount:NSChangeDone];
  [self commitUndoBaseline];
}

- (NSUInteger)denominatorForSelectedNoteValue
{
  NSString *title = [_noteValuePopUp titleOfSelectedItem];
  if ([title isEqualToString:@"Whole"])
    {
      return 1;
    }
  if ([title isEqualToString:@"Half"])
    {
      return 2;
    }
  NSRange slash = [title rangeOfString:@"/"];
  if (slash.location != NSNotFound && slash.location + 1 < [title length])
    {
      NSInteger denominator = [[title substringFromIndex:slash.location + 1] integerValue];
      if (denominator > 0)
        {
          return (NSUInteger)denominator;
        }
    }
  return 4;
}

- (double)beatsForNoteValueDenominator:(NSUInteger)denominator
{
  if (denominator == 0)
    {
      denominator = 4;
    }
  return 4.0 / (double)denominator;
}

- (NSUInteger)durationTicksForNoteValueDenominator:(NSUInteger)denominator
{
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    {
      return 1;
    }
  return MAX ((NSUInteger)1, (NSUInteger)llround ([self beatsForNoteValueDenominator:denominator]
                                                  * (double)[document ticksPerQuarter]));
}

- (NSString *)palettePayloadForItem:(NSString *)item denominator:(NSUInteger)denominator
{
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    {
      return nil;
    }

  NSInteger trackNumber = [self selectedPartNumber];

  NSUInteger durationTicks = [self durationTicksForNoteValueDenominator:denominator];
  NSInteger pitch = -1;
  return [NSString stringWithFormat:@"%@:%ld:%lu:%ld", item, (long)pitch,
                                    (unsigned long)durationTicks, (long)trackNumber];
}

#if defined(__APPLE__)
- (NSArray *)availableMIDIOutputs
{
  NSMutableArray *outputs = [NSMutableArray array];
  ItemCount count = MIDIGetNumberOfDestinations ();
  for (ItemCount index = 0; index < count; index++)
    {
      MIDIEndpointRef endpoint = MIDIGetDestination (index);
      if (!endpoint)
        continue;
      [outputs
        addObject:[NSDictionary
                    dictionaryWithObjectsAndKeys:ScoreMakerMIDIEndpointName (endpoint), @"name",
                                                 [NSNumber numberWithUnsignedInt:endpoint],
                                                 @"endpoint", nil]];
    }
  return outputs;
}

- (MIDIEndpointRef)resolvedMIDIOutputEndpoint
{
  if (_useBuiltInMIDIOutput)
    return 0;

  NSArray *outputs = [self availableMIDIOutputs];
  for (NSDictionary *output in outputs)
    {
      MIDIEndpointRef endpoint = [[output objectForKey:@"endpoint"] unsignedIntValue];
      if (_midiOutputEndpoint == endpoint
          || (_midiOutputName && [[output objectForKey:@"name"] isEqualToString:_midiOutputName]))
        {
          _midiOutputEndpoint = endpoint;
          return endpoint;
        }
    }

  NSDictionary *firstOutput = [outputs count] ? [outputs objectAtIndex:0] : nil;
  _midiOutputEndpoint = [[firstOutput objectForKey:@"endpoint"] unsignedIntValue];
  [_midiOutputName release];
  _midiOutputName = [[firstOutput objectForKey:@"name"] copy];
  return _midiOutputEndpoint;
}

- (void)chooseMIDIOutput:(id)sender
{
  (void)sender;
  NSArray *outputs = [self availableMIDIOutputs];
  NSPopUpButton *outputPopUp =
    [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (0.0, 0.0, 360.0, 26.0)
                                pullsDown:NO] autorelease];
  [outputPopUp addItemWithTitle:@"Built-in Synthesizer"];
  [[outputPopUp lastItem] setRepresentedObject:[NSNumber numberWithUnsignedInt:0]];
  for (NSDictionary *output in outputs)
    {
      [outputPopUp addItemWithTitle:[output objectForKey:@"name"]];
      [[outputPopUp lastItem] setRepresentedObject:[output objectForKey:@"endpoint"]];
      if (!_useBuiltInMIDIOutput &&
          [[output objectForKey:@"endpoint"] unsignedIntValue] == [self resolvedMIDIOutputEndpoint])
        {
          [outputPopUp selectItem:[outputPopUp lastItem]];
        }
    }
  if (_useBuiltInMIDIOutput)
    [outputPopUp selectItemAtIndex:0];

  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"MIDI Output"];
  [alert setInformativeText:
           [outputs count]
             ? @"Choose a connected MIDI instrument or the built-in synthesizer."
             : @"No external MIDI instruments were detected. Connect one and reopen this chooser."];
  [alert setAccessoryView:outputPopUp];
  [alert addButtonWithTitle:@"Use Output"];
  [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] != NSAlertFirstButtonReturn)
    return;

  MIDIEndpointRef endpoint = [[[outputPopUp selectedItem] representedObject] unsignedIntValue];
  _useBuiltInMIDIOutput = (endpoint == 0);
  _midiOutputEndpoint = endpoint;
  [_midiOutputName release];
  _midiOutputName = _useBuiltInMIDIOutput ? nil : [[[outputPopUp selectedItem] title] copy];
  if (_playbackTimer || _playbackPaused)
    {
      NSTimeInterval elapsed = _playbackPaused
                                 ? _playbackPausedElapsed
                                 : ([NSDate timeIntervalSinceReferenceDate] - _playbackStartTime);
      ScoreScheduler *scheduler =
        [[[ScoreScheduler alloc] initWithDocument:[self scoreDocument]] autorelease];
      NSUInteger tick = [scheduler tickForTime:elapsed];
      [self restartPlaybackAtTick:tick];
    }
}

- (BOOL)playMIDIData:(NSData *)midiData toOutput:(MIDIEndpointRef)endpoint error:(NSError **)error
{
  OSStatus status = NewMusicSequence (&_externalMusicSequence);
  if (status == noErr)
    {
      status = MusicSequenceFileLoadData (_externalMusicSequence, (CFDataRef)midiData,
                                          kMusicSequenceFile_MIDIType,
                                          kMusicSequenceLoadSMF_ChannelsToTracks);
    }
  if (status == noErr)
    status = MusicSequenceSetMIDIEndpoint (_externalMusicSequence, endpoint);
  if (status == noErr)
    status = NewMusicPlayer (&_externalMusicPlayer);
  if (status == noErr)
    status = MusicPlayerSetSequence (_externalMusicPlayer, _externalMusicSequence);
  if (status == noErr)
    status = MusicPlayerPreroll (_externalMusicPlayer);
  if (status == noErr)
    status = MusicPlayerStart (_externalMusicPlayer);
  if (status == noErr)
    {
      _externalPlaybackTime = 0;
      return YES;
    }

  if (_externalMusicPlayer)
    {
      DisposeMusicPlayer (_externalMusicPlayer);
      _externalMusicPlayer = NULL;
    }
  if (_externalMusicSequence)
    {
      DisposeMusicSequence (_externalMusicSequence);
      _externalMusicSequence = NULL;
    }
  if (error)
    {
      NSString *message = [NSString
        stringWithFormat:@"The connected MIDI instrument could not start playback (error %d).",
                         (int)status];
      *error =
        [NSError errorWithDomain:@"ScoreMakerPlayback"
                            code:5
                        userInfo:[NSDictionary dictionaryWithObject:message
                                                             forKey:NSLocalizedDescriptionKey]];
    }
  return NO;
}
#endif

- (void)stopPlaybackAudioOnly
{
#if defined(__APPLE__)
  if (_externalMusicPlayer)
    {
      MusicPlayerStop (_externalMusicPlayer);
      ScoreMakerSendAllNotesOff (_midiOutputEndpoint);
      DisposeMusicPlayer (_externalMusicPlayer);
      _externalMusicPlayer = NULL;
    }
  if (_externalMusicSequence)
    {
      DisposeMusicSequence (_externalMusicSequence);
      _externalMusicSequence = NULL;
    }
  _externalPlaybackTime = 0;
#endif
  [_playbackSound stop];
  [_playbackSound release];
  _playbackSound = nil;
  [(AVMIDIPlayer *)_midiPlayer stop];
  [_midiPlayer release];
  _midiPlayer = nil;
  [_realtimeDSP allNotesOff];
  if (_useRealtimeDSP)
    [_realtimeDSP stop];
}

- (BOOL)prepareDSPPlaybackAtTick:(NSUInteger)tick error:(NSError **)error
{
  ScoreScheduler *scheduler =
    [[[ScoreScheduler alloc] initWithDocument:[self scoreDocument]] autorelease];
  NSTimeInterval origin = [scheduler timeForTick:tick];
  NSMutableArray *timeline = [NSMutableArray array];
  for (ScoreNote *note in [[self scoreDocument] notes])
    if (![note isRest] && [note startTick]<tick && [note startTick] + [note durationTicks]> tick)
      [timeline addObject:@{
        @"time" : @0,
        @"pitch" : [NSNumber numberWithInteger:[note pitch]],
        @"velocity" : [NSNumber numberWithUnsignedInteger:[note velocity]],
        @"on" : @YES
      }];
  for (ScoreScheduledEvent *event in [scheduler eventsFromTick:tick
                                                   throughTick:[[self scoreDocument] totalTicks]])
    {
      ScoreNote *note = [event note];
      [timeline addObject:@{
        @"time" : [NSNumber numberWithDouble:MAX (0.0, [event time] - origin)],
        @"pitch" : [NSNumber numberWithInteger:[note pitch]],
        @"velocity" : [NSNumber numberWithUnsignedInteger:[note velocity]],
        @"on" : [NSNumber numberWithBool:![event noteOff]]
      }];
    }
  return [_realtimeDSP scheduleEvents:timeline error:error];
}

- (BOOL)restartPlaybackAtTick:(NSUInteger)tick
{
  ScoreDocument *source = [self scoreDocument];
  if (!source || tick >= [source totalTicks])
    return NO;

  BOOL wasPaused = _playbackPaused;
  ScoreDocument *remainder = [[[ScoreDocument alloc] init] autorelease];
  [remainder setTitle:[source title]];
  [remainder setTitleFontName:[source titleFontName]];
  [remainder setComposer:[source composer]];
  [remainder setAnnotationText:[source annotationText]];
  [remainder setTicksPerQuarter:[source ticksPerQuarter]];
  [remainder setTempoMicrosecondsPerQuarter:[source tempoMicrosecondsPerQuarter]];
  [remainder setTimeSignatureNumerator:[source timeSignatureNumerator]];
  [remainder setTimeSignatureDenominator:[source timeSignatureDenominator]];
  [remainder setPartNames:[[[source partNames] mutableCopy] autorelease]];
  [remainder setTrackPrograms:[[[source trackPrograms] mutableCopy] autorelease]];
  [remainder setMeasures:[[[source measures] mutableCopy] autorelease]];

  for (ScoreNote *note in [source notes])
    {
      NSUInteger noteEnd = [note startTick] + [note durationTicks];
      if (noteEnd <= tick)
        continue;
      NSUInteger clippedStart = MAX ([note startTick], tick);
      ScoreNote *copy = [[[ScoreNote alloc] init] autorelease];
      [copy setPitch:[note pitch]];
      [copy setAccidental:[note accidental]];
      [copy setRest:[note isRest]];
      [copy setChannel:[note channel]];
      [copy setTrack:[note track]];
      [copy setStartTick:clippedStart - tick];
      [copy setDurationTicks:noteEnd - clippedStart];
      [copy setSlurStart:[note slurStart]];
      [copy setSlurEnd:[note slurEnd]];
      [copy setVoice:[note voice]];
      [copy setMeasureIndex:[note measureIndex]];
      [copy setVelocity:[note velocity]];
      [[remainder notes] addObject:copy];
      [remainder
        setTotalTicks:MAX ([remainder totalTicks], [copy startTick] + [copy durationTicks])];
    }

  NSError *error = nil;
  if (_useRealtimeDSP)
    {
      [self stopPlaybackAudioOnly];
      if (![self prepareDSPPlaybackAtTick:tick error:&error])
        {
          [[NSDocumentController sharedDocumentController] presentError:error];
          [self stopCurrentPlayback];
          return NO;
        }
      ScoreScheduler *scheduler = [[[ScoreScheduler alloc] initWithDocument:source] autorelease];
      NSTimeInterval adjustedElapsed = [scheduler timeForTick:tick];
      _playbackStartTime = [NSDate timeIntervalSinceReferenceDate] - adjustedElapsed;
      _playbackPausedElapsed = adjustedElapsed;
      return YES;
    }
  NSData *midiData = [MidiParser dataForDocument:remainder error:&error];
  if (!midiData)
    {
      [[NSDocumentController sharedDocumentController] presentError:error];
      [self stopCurrentPlayback];
      return NO;
    }

  [self stopPlaybackAudioOnly];
  if (![self playMIDIDataDirectly:midiData error:&error])
    {
      [[NSDocumentController sharedDocumentController] presentError:error];
      [self stopCurrentPlayback];
      return NO;
    }

  ScoreScheduler *scheduler = [[[ScoreScheduler alloc] initWithDocument:source] autorelease];
  NSTimeInterval adjustedElapsed = [scheduler timeForTick:tick];
  _playbackStartTime = [NSDate timeIntervalSinceReferenceDate] - adjustedElapsed;
  _playbackPausedElapsed = adjustedElapsed;

  if (wasPaused)
    {
      if (_midiPlayer)
        {
          [(AVMIDIPlayer *)_midiPlayer stop];
          [(AVMIDIPlayer *)_midiPlayer setCurrentPosition:0.0];
        }
      [_playbackSound pause];
      _playbackPaused = YES;
      [_pauseButton setTitle:@"Resume"];
    }
  return YES;
}

- (void)stopCurrentPlayback
{
  [_playbackTimer invalidate];
  [_playbackTimer release];
  _playbackTimer = nil;
  _playbackPaused = NO;
  _playbackPausedElapsed = 0.0;
  [_pauseButton setTitle:@"Pause"];
  [_pauseButton setEnabled:NO];
  [[self scoreView] clearPlayback];
  [_playbackMonitorView clearPlayback];
  [self stopPlaybackAudioOnly];
  [self stopAudition];
}

- (void)schedulePlaybackTimer
{
  [_playbackTimer invalidate];
  [_playbackTimer release];
  _playbackTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                     target:self
                                                   selector:@selector (updatePlaybackHighlight:)
                                                   userInfo:nil
                                                    repeats:YES] retain];
}

- (void)updatePlaybackHighlight:(NSTimer *)timer
{
  (void)timer;
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    {
      [self stopCurrentPlayback];
      return;
    }

  NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - _playbackStartTime;
  ScoreScheduler *scheduler = [[[ScoreScheduler alloc] initWithDocument:document] autorelease];
  NSUInteger tick = [scheduler tickForTime:elapsed];

  if (tick >= [document totalTicks])
    {
      [_playbackTimer invalidate];
      [_playbackTimer release];
      _playbackTimer = nil;
      [[self scoreView] clearPlayback];
      [_playbackMonitorView clearPlayback];
      [_pauseButton setTitle:@"Pause"];
      [_pauseButton setEnabled:NO];
      [_realtimeDSP allNotesOff];
      return;
    }

  [[self scoreView] setPlaybackTick:tick];
  [[self scoreView] scrollPlaybackTickToVisible:tick];
  [_playbackMonitorView setPlaybackTick:tick];
}

- (void)startPlaybackHighlightAtTick:(NSUInteger)tick
{
  ScoreDocument *document = [self scoreDocument];
  ScoreScheduler *scheduler = [[[ScoreScheduler alloc] initWithDocument:document] autorelease];
  NSTimeInterval elapsed = [scheduler timeForTick:tick];
  _playbackStartTime = [NSDate timeIntervalSinceReferenceDate] - elapsed;
  [[self scoreView] setPlaybackTick:tick];
  [[self scoreView] scrollPlaybackTickToVisible:tick];
  [_playbackMonitorView setPlaybackTick:tick];
  _playbackPaused = NO;
  _playbackPausedElapsed = elapsed;
  [_pauseButton setTitle:@"Pause"];
  [_pauseButton setEnabled:YES];
  [self schedulePlaybackTimer];
}

- (void)startPlaybackHighlight
{
  [self startPlaybackHighlightAtTick:0];
}

- (void)pausePlayback:(id)sender
{
  (void)sender;
  if (!_playbackTimer && !_playbackPaused)
    return;

  if (!_playbackPaused)
    {
      _playbackPausedElapsed = [NSDate timeIntervalSinceReferenceDate] - _playbackStartTime;
      [_playbackTimer invalidate];
      [_playbackTimer release];
      _playbackTimer = nil;
      if (_midiPlayer)
        {
          NSTimeInterval position = [(AVMIDIPlayer *)_midiPlayer currentPosition];
          [(AVMIDIPlayer *)_midiPlayer stop];
          [(AVMIDIPlayer *)_midiPlayer setCurrentPosition:position];
        }
      [_playbackSound pause];
      if (_useRealtimeDSP)
        {
          [_realtimeDSP allNotesOff];
          [_realtimeDSP stop];
        }
      _playbackPaused = YES;
      [_pauseButton setTitle:@"Resume"];
    }
  else
    {
      if (_midiPlayer)
        [(AVMIDIPlayer *)_midiPlayer play:nil];
      [_playbackSound resume];
      if (_useRealtimeDSP)
        {
          ScoreScheduler *scheduler =
            [[[ScoreScheduler alloc] initWithDocument:[self scoreDocument]] autorelease];
          NSUInteger tick = [scheduler tickForTime:_playbackPausedElapsed];
          NSError *error = nil;
          if (![self prepareDSPPlaybackAtTick:tick error:&error])
            {
              [[NSDocumentController sharedDocumentController] presentError:error];
              [self stopCurrentPlayback];
              return;
            }
        }
      _playbackStartTime = [NSDate timeIntervalSinceReferenceDate] - _playbackPausedElapsed;
      _playbackPaused = NO;
      [_pauseButton setTitle:@"Pause"];
      [self schedulePlaybackTimer];
    }
}

- (void)stopPlayback:(id)sender
{
  (void)sender;
  [self stopCurrentPlayback];
}

- (BOOL)playMIDIDataDirectly:(NSData *)midiData error:(NSError **)error
{
  NSError *playerError = nil;
  AVMIDIPlayer *player = [[[AVMIDIPlayer alloc] initWithData:midiData
                                                soundBankURL:nil
                                                       error:&playerError] autorelease];
  if (player)
    {
      [player prepareToPlay];
      [player play:nil];
      if ([player respondsToSelector:@selector (isPlaying)] && ![player isPlaying])
        {
          if (error)
            {
              NSError *playbackError =
                [player respondsToSelector:@selector (error)] ? [player error] : nil;
              NSString *description
                = playbackError
                    ? [playbackError localizedDescription]
                    : @"The generated MIDI was loaded, but MIDI playback could not start.";
              NSDictionary *userInfo =
                [NSDictionary dictionaryWithObject:description forKey:NSLocalizedDescriptionKey];
              *error = [NSError errorWithDomain:@"ScoreMakerPlayback" code:2 userInfo:userInfo];
            }
          return NO;
        }
      _midiPlayer = [player retain];
      return YES;
    }

  NSSound *sound = [[[NSSound alloc] initWithData:midiData] autorelease];
  if (!sound)
    {
      if (error)
        {
          NSString *description
            = @"The generated MIDI could not be loaded by the system MIDI player.";
          if (playerError)
            {
              description =
                [description stringByAppendingFormat:@" %@", [playerError localizedDescription]];
            }
          NSDictionary *userInfo = [NSDictionary dictionaryWithObject:description
                                                               forKey:NSLocalizedDescriptionKey];
          *error = [NSError errorWithDomain:@"ScoreMakerPlayback" code:1 userInfo:userInfo];
        }
      return NO;
    }

  if (![sound play])
    {
      if (error)
        {
          NSDictionary *userInfo = [NSDictionary
            dictionaryWithObject:
              @"The generated MIDI was loaded, but the system MIDI player could not start playback."
                          forKey:NSLocalizedDescriptionKey];
          *error = [NSError errorWithDomain:@"ScoreMakerPlayback" code:2 userInfo:userInfo];
        }
      return NO;
    }

  _playbackSound = [sound retain];
  return YES;
}

- (void)playScore:(id)sender
{
  (void)sender;
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    {
      return;
    }

  [self stopCurrentPlayback];

  [self syncInspectorMetadataMarkingChange:NO];
  ScoreNote *selectedNote = [[self scoreView] selectedNote];
  NSUInteger startTick = selectedNote ? [selectedNote startTick] : 0;

  if (startTick > 0)
    {
      if ([self restartPlaybackAtTick:startTick])
        {
          [self startPlaybackHighlightAtTick:startTick];
        }
      return;
    }

  NSError *error = nil;
  if (_useRealtimeDSP)
    {
      if (![self prepareDSPPlaybackAtTick:0 error:&error])
        {
          [[NSDocumentController sharedDocumentController] presentError:error];
          return;
        }
      [self startPlaybackHighlight];
      return;
    }
  NSData *midiData = [MidiParser dataForDocument:document error:&error];
  if (!midiData)
    {
      [[NSDocumentController sharedDocumentController] presentError:error];
      return;
    }

  if (![self playMIDIDataDirectly:midiData error:&error])
    {
      [[NSDocumentController sharedDocumentController] presentError:error];
      return;
    }
  [self startPlaybackHighlight];
}

- (BOOL)pitchString:(NSString *)string toMidiPitch:(NSInteger *)pitch
{
  NSString *trimmed =
    [[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
      lowercaseString];
  if ([trimmed length] == 0)
    {
      return NO;
    }

  NSScanner *numberScanner = [NSScanner scannerWithString:trimmed];
  NSInteger numericPitch = 0;
  if ([numberScanner scanInteger:&numericPitch] && [numberScanner isAtEnd])
    {
      if (numericPitch < 0 || numericPitch > 127)
        {
          return NO;
        }
      if (pitch)
        *pitch = numericPitch;
      return YES;
    }

  unichar letter = [trimmed characterAtIndex:0];
  NSInteger semitone = 0;
  switch (letter)
    {
    case 'c':
      semitone = 0;
      break;
    case 'd':
      semitone = 2;
      break;
    case 'e':
      semitone = 4;
      break;
    case 'f':
      semitone = 5;
      break;
    case 'g':
      semitone = 7;
      break;
    case 'a':
      semitone = 9;
      break;
    case 'b':
      semitone = 11;
      break;
    default:
      return NO;
    }

  NSUInteger index = 1;
  if (index < [trimmed length])
    {
      unichar accidental = [trimmed characterAtIndex:index];
      if (accidental == '#' || accidental == 's')
        {
          semitone++;
          index++;
        }
      else if (accidental == 'b' || accidental == 'f')
        {
          semitone--;
          index++;
        }
    }

  if (index >= [trimmed length])
    {
      return NO;
    }
  NSString *octaveString = [trimmed substringFromIndex:index];
  NSScanner *octaveScanner = [NSScanner scannerWithString:octaveString];
  NSInteger octave = 0;
  if (![octaveScanner scanInteger:&octave] || ![octaveScanner isAtEnd])
    {
      return NO;
    }

  NSInteger midiPitch = (octave + 1) * 12 + semitone;
  if (midiPitch < 0 || midiPitch > 127)
    {
      return NO;
    }
  if (pitch)
    *pitch = midiPitch;
  return YES;
}

- (NSInteger)accidentalForPitchString:(NSString *)string
{
  NSString *trimmed =
    [[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]
      lowercaseString];
  if ([trimmed length] < 2)
    {
      return 0;
    }
  unichar accidental = [trimmed characterAtIndex:1];
  if (accidental == '#' || accidental == 's')
    return 1;
  if (accidental == 'b' || accidental == 'f')
    return -1;
  return 0;
}

- (void)addNote:(id)sender
{
  (void)sender;
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    {
      return;
    }
  BOOL rest = [[_noteTypePopUp titleOfSelectedItem] isEqualToString:@"Rest"];
  NSInteger pitch = 0;
  if (!rest && ![self pitchString:[_notePitchField stringValue] toMidiPitch:&pitch])
    {
      NSAlert *alert = [[[NSAlert alloc] init] autorelease];
      [alert setMessageText:@"The note pitch is not valid"];
      [alert
        setInformativeText:@"Use a MIDI pitch from 0 to 127 or a pitch name like C4, F#3, or Bb5."];
      [alert runModal];
      return;
    }
  [self registerUndoSnapshotWithName:@"Add Note"];

  double startBeats = [_noteStartField doubleValue];
  NSUInteger denominator = [self denominatorForSelectedNoteValue];
  double durationBeats = [self beatsForNoteValueDenominator:denominator];
  NSInteger trackNumber = [self selectedPartNumber] + 1;
  if (startBeats < 0.0)
    startBeats = 0.0;
  if (trackNumber < 1)
    trackNumber = 1;

  NSUInteger startTick = (NSUInteger)llround (startBeats * (double)[document ticksPerQuarter]);
  NSUInteger durationTicks = [self durationTicksForNoteValueDenominator:denominator];
  ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
  [note setRest:rest];
  [note setPitch:rest ? 60 : pitch];
  if (!rest)
    {
      [note setAccidental:[self accidentalForPitchString:[_notePitchField stringValue]]];
    }
  [note setChannel:(trackNumber - 1) % 16];
  [note setTrack:trackNumber - 1];
  [note setStartTick:startTick];
  [note setDurationTicks:durationTicks];
  [note setTieStart:[_tieStartButton state] == NSOnState];
  [note setTieEnd:[_tieEndButton state] == NSOnState];
  NSArray *tupletRatio = [[_tupletPopUp titleOfSelectedItem] componentsSeparatedByString:@":"];
  if ([tupletRatio count] == 2)
    {
      [note setTupletActual:[[tupletRatio objectAtIndex:0] integerValue]];
      [note setTupletNormal:[[tupletRatio objectAtIndex:1] integerValue]];
    }
  NSString *dynamic = [_dynamicPopUp titleOfSelectedItem];
  if (![dynamic isEqualToString:@"No dynamic"])
    [note setDynamic:dynamic];
  NSDictionary *newArticulations = [NSDictionary
    dictionaryWithObjectsAndKeys:@"staccato", @"Staccato", @"accent", @"Accent", @"tenuto",
                                 @"Tenuto", @"strong-accent", @"Strong accent", nil];
  [note setArticulation:[newArticulations objectForKey:[_articulationPopUp titleOfSelectedItem]]];
  [[document notes] addObject:note];
  [[document notes] sortUsingSelector:@selector (compareScoreNote:)];

  NSUInteger noteEnd = startTick + durationTicks;
  if (noteEnd > [document totalTicks])
    {
      [document setTotalTicks:noteEnd];
    }
  ScoreMeasure *measure = [document ensureMeasureContainingTick:startTick];
  [measure
    setKeySignatureFifths:[[[_keySignaturePopUp selectedItem] representedObject] integerValue]];
  [measure setRepeatStart:[_repeatStartButton state] == NSOnState];
  [measure setRepeatEnd:[_repeatEndButton state] == NSOnState];
  [note setMeasureIndex:(NSInteger)[[document measures] indexOfObjectIdenticalTo:measure]];
  if (![document nameForTrack:trackNumber - 1])
    {
      [document setName:[NSString stringWithFormat:@"Part %ld", (long)trackNumber]
               forTrack:trackNumber - 1];
    }

  [_noteStartField setDoubleValue:startBeats + durationBeats];
  [_noteDurationField setDoubleValue:durationBeats];
  [[self scoreView] reloadDocument];
  [self updateChangeCount:NSChangeDone];
  [self refreshInspector];
  [self commitUndoBaseline];
}

- (void)pianoKeyPressed:(id)sender
{
  NSInteger pitch = [(PlaybackMonitorView *)sender inputPitch];
  if (pitch < 0 || pitch > 127 || ![self scoreDocument] || _playbackTimer || _playbackPaused)
    return;
  if (_useRealtimeDSP)
    {
      if (![_realtimeDSP isRunning])
        {
          NSError *error = nil;
          if (![_realtimeDSP startWithError:&error])
            {
              [[NSDocumentController sharedDocumentController] presentError:error];
              return;
            }
        }
      [self stopAudition];
      [_realtimeDSP noteOn:pitch velocity:100];
      _realtimeDSPPitch = pitch;
      _auditionResetTimer = [[NSTimer scheduledTimerWithTimeInterval:0.5
                                                              target:self
                                                            selector:@selector (finishAudition:)
                                                            userInfo:nil
                                                             repeats:NO] retain];
    }
  else
    [self auditionPitch:pitch];
  [_noteTypePopUp selectItemWithTitle:@"Note"];
  static NSString *pitchNames[]
    = { @"C", @"C#", @"D", @"D#", @"E", @"F", @"F#", @"G", @"G#", @"A", @"A#", @"B" };
  NSInteger pitchClass = pitch % 12;
  NSInteger octave = pitch / 12 - 1;
  [_notePitchField
    setStringValue:[NSString stringWithFormat:@"%@%ld", pitchNames[pitchClass], (long)octave]];
  [self addNote:sender];
}

- (void)stopAudition
{
  if (_realtimeDSPPitch >= 0)
    {
      [_realtimeDSP noteOff:_realtimeDSPPitch];
      _realtimeDSPPitch = -1;
    }
  [_auditionResetTimer invalidate];
  [_auditionResetTimer release];
  _auditionResetTimer = nil;
  [(AVMIDIPlayer *)_auditionPlayer stop];
  [_auditionPlayer release];
  _auditionPlayer = nil;
  [_auditionSound stop];
  [_auditionSound release];
  _auditionSound = nil;
  [_playbackMonitorView resetInputPitch];
}

- (void)toggleRealtimeDSP:(id)sender
{
  if (!_useRealtimeDSP)
    {
      NSError *error = nil;
      if (![_realtimeDSP startWithError:&error])
        {
          [[NSDocumentController sharedDocumentController] presentError:error];
          return;
        }
      _useRealtimeDSP = YES;
    }
  else
    {
      [self stopAudition];
      [_realtimeDSP stop];
      _useRealtimeDSP = NO;
    }
  if ([sender respondsToSelector:@selector (setState:)])
    [sender setState:_useRealtimeDSP ? NSOnState : NSOffState];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
  if ([menuItem action] == @selector (toggleRealtimeDSP:))
    [menuItem setState:_useRealtimeDSP ? NSOnState : NSOffState];
  return YES;
}

- (void)chooseAudioUnitInstrument:(id)sender
{
  (void)sender;
  NSArray *instruments = [ScoreRealtimeDSP availableAudioUnitInstruments];
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"Choose Audio Unit Instrument"];
  [alert setInformativeText:[instruments count]
                              ? @"The instrument will receive notes from the virtual keyboard "
                                @"through the real-time DSP engine."
                              : @"No Audio Unit music devices are installed. The internal "
                                @"synthesizer remains available."];
  [alert addButtonWithTitle:@"Use Instrument"];
  [alert addButtonWithTitle:@"Cancel"];

  NSPopUpButton *popUp = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (0, 0, 380, 26)
                                                     pullsDown:NO] autorelease];
  [popUp addItemWithTitle:@"Internal ScoreMaker Synthesizer"];
  [[popUp lastItem] setRepresentedObject:[NSNull null]];
  for (NSDictionary *instrument in instruments)
    {
      BOOL blacklisted = [ScoreRealtimeDSP isAudioUnitBlacklisted:instrument];
      NSString *title = [NSString
        stringWithFormat:@"%@ — %@%@", [instrument objectForKey:@"name"],
                         [instrument objectForKey:@"manufacturer"],
                         blacklisted ? @" (blacklisted)" : @""];
      [popUp addItemWithTitle:title];
      [[popUp lastItem] setRepresentedObject:instrument];
      [[popUp lastItem] setEnabled:!blacklisted];
    }
  [alert setAccessoryView:popUp];
  if ([alert runModal] != NSAlertFirstButtonReturn)
    return;

  id selection = [[popUp selectedItem] representedObject];
  if (selection == [NSNull null])
    {
      [_realtimeDSP useInternalSynthesizer];
      _audioUnitPartTrack = -1;
      NSError *error = nil;
      if (_useRealtimeDSP && ![_realtimeDSP startWithError:&error])
        [[NSDocumentController sharedDocumentController] presentError:error];
      ScoreDocument *document = [self scoreDocument];
      NSInteger track = [self selectedPartNumber];
      for (ScorePartDefinition *part in [document parts])
        if ([part legacyTrack] == track)
          {
            [[part instrument] setBackendIdentifier:nil];
            [[part instrument] setParameters:[NSMutableDictionary dictionary]];
            [self updateChangeCount:NSChangeDone];
            break;
          }
      return;
    }

#if defined(__APPLE__)
  [_realtimeDSP
    loadAudioUnitInstrument:selection
                 completion:^(BOOL success, NSError *error) {
                   if (!success)
                     {
                       [[NSDocumentController sharedDocumentController] presentError:error];
                       return;
                     }
                   _useRealtimeDSP = YES;
                   ScoreDocument *document = [self scoreDocument];
                   [self registerUndoSnapshotWithName:@"Change Audio Unit Instrument"];
                   if ([[document parts] count] == 0)
                     [document rebuildStructuredPartsFromLegacyTracks];
                   NSInteger track = [self selectedPartNumber];
                   _audioUnitPartTrack = track;
                   for (ScorePartDefinition *part in [document parts])
                     if ([part legacyTrack] == track)
                       {
                         ScoreInstrumentDefinition *instrument = [part instrument];
                         [instrument
                           setBackendIdentifier:
                             [NSString
                               stringWithFormat:@"audio-unit:%u:%u:%u",
                                                [[selection objectForKey:@"type"] unsignedIntValue],
                                                [[selection objectForKey:@"subtype"]
                                                  unsignedIntValue],
                                                [[selection objectForKey:@"manufacturerCode"]
                                                  unsignedIntValue]]];
                         [instrument
                           setParameters:[NSMutableDictionary dictionaryWithDictionary:selection]];
                         break;
                       }
                   [self updateChangeCount:NSChangeDone];
                 }];
#else
  NSError *error =
    [NSError errorWithDomain:@"ScoreMakerDSP"
                        code:1
                    userInfo:@{
                      NSLocalizedDescriptionKey : @"Audio Unit hosting is available only on macOS."
                    }];
  [[NSDocumentController sharedDocumentController] presentError:error];
#endif
}

- (void)showAudioUnitEditor:(id)sender
{
  (void)sender;
#if defined(__APPLE__)
  [_realtimeDSP requestAudioUnitViewController:^(NSViewController *controller, NSError *error) {
    if (error)
      {
        [[NSDocumentController sharedDocumentController] presentError:error];
        return;
      }
    if (!controller)
      {
        [self showGenericAudioUnitEditor];
        return;
      }
    [_audioUnitEditorWindow close];
    [_audioUnitEditorWindow release];
    NSSize size = [[controller view] fittingSize];
    if (size.width < 420.0 || size.height < 260.0)
      size = NSMakeSize (MAX (420.0, size.width), MAX (260.0, size.height));
    _audioUnitEditorWindow = [[NSWindow alloc]
      initWithContentRect:NSMakeRect (0, 0, size.width, size.height)
                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                           | NSWindowStyleMaskResizable)
                  backing:NSBackingStoreBuffered
                    defer:NO];
    [_audioUnitEditorWindow setTitle:@"Audio Unit Editor"];
    [_audioUnitEditorWindow setContentViewController:controller];
    [_audioUnitEditorWindow center];
    [_audioUnitEditorWindow makeKeyAndOrderFront:self];
  }];
#else
  [self showGenericAudioUnitEditor];
#endif
}

- (void)showGenericAudioUnitEditor
{
  NSArray *parameters = [_realtimeDSP audioUnitParameters];
  if (![parameters count])
    {
      NSAlert *alert = [[[NSAlert alloc] init] autorelease];
      [alert setMessageText:@"No Editable Parameters"];
      [alert setInformativeText:@"The loaded instrument exposes neither a vendor interface nor an editable parameter tree."];
      [alert runModal];
      return;
    }
  [_audioUnitEditorWindow close];
  [_audioUnitEditorWindow release];
  [_audioUnitParameterAddresses release];
  _audioUnitParameterAddresses = [[NSMutableDictionary alloc] init];
  CGFloat height = MAX (300.0, 42.0 * [parameters count] + 20.0);
  NSView *documentView = [[[NSView alloc] initWithFrame:NSMakeRect (0, 0, 560, height)] autorelease];
  for (NSUInteger index = 0; index < [parameters count]; index++)
    {
      NSDictionary *parameter = [parameters objectAtIndex:index];
      CGFloat y = height - 38.0 - 42.0 * index;
      NSTextField *label = [[[NSTextField alloc] initWithFrame:NSMakeRect (12, y, 205, 22)] autorelease];
      [label setStringValue:[parameter objectForKey:@"name"]];
      [label setEditable:NO];
      [label setBordered:NO];
      [label setDrawsBackground:NO];
      [documentView addSubview:label];
      NSSlider *slider = [[[NSSlider alloc] initWithFrame:NSMakeRect (220, y, 325, 22)] autorelease];
      [slider setMinValue:[[parameter objectForKey:@"minimum"] doubleValue]];
      [slider setMaxValue:[[parameter objectForKey:@"maximum"] doubleValue]];
      [slider setDoubleValue:[[parameter objectForKey:@"value"] doubleValue]];
      [slider setTag:(NSInteger)index + 1];
      [slider setTarget:self];
      [slider setAction:@selector (audioUnitParameterChanged:)];
      [_audioUnitParameterAddresses setObject:[parameter objectForKey:@"address"]
                                       forKey:[NSNumber numberWithInteger:(NSInteger)index + 1]];
      [documentView addSubview:slider];
    }
  NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect (0, 0, 560, 420)] autorelease];
  [scroll setHasVerticalScroller:YES];
  [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [scroll setDocumentView:documentView];
  _audioUnitEditorWindow = [[NSWindow alloc]
    initWithContentRect:NSMakeRect (0, 0, 560, 420)
              styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                         | NSWindowStyleMaskResizable)
                backing:NSBackingStoreBuffered
                  defer:NO];
  [_audioUnitEditorWindow setTitle:@"Audio Unit Parameters"];
  [_audioUnitEditorWindow setContentView:scroll];
  [_audioUnitEditorWindow center];
  [_audioUnitEditorWindow makeKeyAndOrderFront:self];
}

- (void)audioUnitParameterChanged:(id)sender
{
  NSNumber *address = [_audioUnitParameterAddresses
    objectForKey:[NSNumber numberWithInteger:[sender tag]]];
  NSError *error = nil;
  if (address && ![_realtimeDSP setAudioUnitParameter:[address unsignedLongLongValue]
                                                value:[sender doubleValue]
                                                error:&error])
    [[NSDocumentController sharedDocumentController] presentError:error];
}

- (void)manageAudioUnitPresets:(id)sender
{
  (void)sender;
  NSDictionary *description = [_realtimeDSP audioUnitInstrumentDescription];
  if (!description)
    return;
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"Audio Unit Presets"];
  [alert setInformativeText:@"Save the current state, or load or delete a user preset."];
  [alert addButtonWithTitle:@"Save"];
  [alert addButtonWithTitle:@"Load"];
  [alert addButtonWithTitle:@"Delete"];
  [alert addButtonWithTitle:@"Cancel"];
  NSView *accessory = [[[NSView alloc] initWithFrame:NSMakeRect (0, 0, 380, 62)] autorelease];
  NSTextField *name = [[[NSTextField alloc] initWithFrame:NSMakeRect (0, 36, 380, 24)] autorelease];
  [name setPlaceholderString:@"New preset name"];
  [accessory addSubview:name];
  NSPopUpButton *presets = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (0, 2, 380, 26)
                                                       pullsDown:NO] autorelease];
  [presets addItemsWithTitles:[ScoreRealtimeDSP userPresetsForAudioUnit:description]];
  [accessory addSubview:presets];
  [alert setAccessoryView:accessory];
  NSInteger result = [alert runModal];
  NSError *error = nil;
  BOOL success = YES;
  if (result == NSAlertFirstButtonReturn)
    success = [_realtimeDSP saveUserPreset:[name stringValue] error:&error];
  else if (result == NSAlertSecondButtonReturn)
    success = [_realtimeDSP loadUserPreset:[presets titleOfSelectedItem] error:&error];
  else if (result == NSAlertThirdButtonReturn)
    success = [ScoreRealtimeDSP removeUserPreset:[presets titleOfSelectedItem]
                                    forAudioUnit:description
                                           error:&error];
  if (!success && error)
    [[NSDocumentController sharedDocumentController] presentError:error];
}

- (void)relinkAudioUnitInstrument:(id)sender
{
  (void)sender;
  ScorePartDefinition *selectedPart = nil;
  for (ScorePartDefinition *part in [[self scoreDocument] parts])
    if ([part legacyTrack] == [self selectedPartNumber])
      {
        selectedPart = part;
        break;
      }
  NSDictionary *missing = [[selectedPart instrument] parameters];
  if (![missing objectForKey:@"type"])
    return;
  NSArray *recommended = [ScoreRealtimeDSP relinkCandidatesForAudioUnit:missing];
  NSArray *installed = [ScoreRealtimeDSP availableAudioUnitInstruments];
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"Relink or Substitute Audio Unit"];
  [alert setInformativeText:@"Recommended matches preserve vendor and product identity. Any installed instrument may be selected as an intentional substitution."];
  [alert addButtonWithTitle:@"Relink"];
  [alert addButtonWithTitle:@"Cancel"];
  NSPopUpButton *choices = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (0, 0, 420, 26)
                                                      pullsDown:NO] autorelease];
  NSMutableSet *added = [NSMutableSet set];
  for (NSDictionary *candidate in recommended)
    {
      NSString *identifier = [ScoreRealtimeDSP identifierForAudioUnitDescription:candidate];
      [choices addItemWithTitle:[NSString stringWithFormat:@"Recommended: %@ — %@",
                                                          [candidate objectForKey:@"name"],
                                                          [candidate objectForKey:@"manufacturer"]]];
      [[choices lastItem] setRepresentedObject:candidate];
      [added addObject:identifier];
    }
  for (NSDictionary *candidate in installed)
    {
      NSString *identifier = [ScoreRealtimeDSP identifierForAudioUnitDescription:candidate];
      if ([added containsObject:identifier])
        continue;
      [choices addItemWithTitle:[NSString stringWithFormat:@"Substitute: %@ — %@",
                                                          [candidate objectForKey:@"name"],
                                                          [candidate objectForKey:@"manufacturer"]]];
      [[choices lastItem] setRepresentedObject:candidate];
    }
  [alert setAccessoryView:choices];
  if (![installed count] || [alert runModal] != NSAlertFirstButtonReturn)
    return;
  NSDictionary *selection = [[choices selectedItem] representedObject];
  [_realtimeDSP
    loadAudioUnitInstrument:selection
                 completion:^(BOOL success, NSError *error) {
                   if (!success)
                     {
                       [[NSDocumentController sharedDocumentController] presentError:error];
                       return;
                     }
                   [self registerUndoSnapshotWithName:@"Relink Audio Unit Instrument"];
                   _audioUnitPartTrack = [selectedPart legacyTrack];
                   _useRealtimeDSP = YES;
                   ScoreInstrumentDefinition *instrument = [selectedPart instrument];
                   [instrument
                     setBackendIdentifier:
                       [NSString stringWithFormat:@"audio-unit:%u:%u:%u",
                                                  [[selection objectForKey:@"type"] unsignedIntValue],
                                                  [[selection objectForKey:@"subtype"] unsignedIntValue],
                                                  [[selection objectForKey:@"manufacturerCode"] unsignedIntValue]]];
                   NSMutableDictionary *parameters =
                     [NSMutableDictionary dictionaryWithDictionary:selection];
                   [parameters setObject:[NSNumber numberWithBool:YES] forKey:@"intentionalSubstitution"];
                   [instrument setParameters:parameters];
                   [self updateChangeCount:NSChangeDone];
                 }];
}

- (void)showAudioUnitCompatibilityReport:(id)sender
{
  (void)sender;
  NSArray *report = [ScoreRealtimeDSP audioUnitCompatibilityReport];
  NSMutableString *text = [NSMutableString string];
  for (NSDictionary *entry in report)
    [text appendFormat:@"%@ — %@\n  %@ %@ · %@ · %@\n\n", [entry objectForKey:@"name"],
                       [entry objectForKey:@"manufacturer"], [entry objectForKey:@"format"],
                       [entry objectForKey:@"version"], [entry objectForKey:@"status"],
                       [[entry objectForKey:@"hasCustomView"] boolValue] ? @"vendor editor"
                                                                         : @"generic editor"];
  if (![text length])
    [text appendString:@"No Audio Unit music devices are installed."];
  NSTextView *view = [[[NSTextView alloc] initWithFrame:NSMakeRect (0, 0, 560, 330)] autorelease];
  [view setString:text];
  [view setEditable:NO];
  NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect (0, 0, 560, 330)] autorelease];
  [scroll setHasVerticalScroller:YES];
  [scroll setDocumentView:view];
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"Audio Unit Compatibility Report"];
  [alert setInformativeText:@"Apple validation status and host compatibility for installed music devices. Runtime failures are isolated and three consecutive failures trigger blacklisting."];
  [alert setAccessoryView:scroll];
  [alert addButtonWithTitle:@"Done"];
  [alert addButtonWithTitle:@"Clear Blacklist"];
  if ([alert runModal] == NSAlertSecondButtonReturn)
    [ScoreRealtimeDSP clearAudioUnitBlacklist];
}

- (void)editEffects:(id)sender
{
  (void)sender;
  ScorePartDefinition *selectedPart = nil;
  for (ScorePartDefinition *part in [[self scoreDocument] parts])
    if ([part legacyTrack] == [self selectedPartNumber])
      {
        selectedPart = part;
        break;
      }
  if (!selectedPart)
    return;
  ScoreSynthesisGraph *graph = [selectedPart synthesisGraph];
  NSArray *specifications = @[
    @{ @"type" : @"gain", @"name" : @"Gain", @"key" : @"decibels", @"minimum" : @-24.0,
       @"maximum" : @12.0, @"default" : @0.0 },
    @{ @"type" : @"lowpass", @"name" : @"Low-Pass", @"key" : @"cutoff", @"minimum" : @200.0,
       @"maximum" : @20000.0, @"default" : @12000.0 },
    @{ @"type" : @"compressor", @"name" : @"Compressor", @"key" : @"threshold",
       @"minimum" : @-60.0, @"maximum" : @0.0, @"default" : @-12.0 },
    @{ @"type" : @"delay", @"name" : @"Delay", @"key" : @"mix", @"minimum" : @0.0,
       @"maximum" : @1.0, @"default" : @0.2 },
    @{ @"type" : @"reverb", @"name" : @"Reverb", @"key" : @"mix", @"minimum" : @0.0,
       @"maximum" : @1.0, @"default" : @0.2 }
  ];
  NSMutableDictionary *existing = [NSMutableDictionary dictionary];
  for (ScoreSynthesisNode *node in [graph nodes])
    [existing setObject:node forKey:[node typeIdentifier] ?: @""];
  NSView *accessory = [[[NSView alloc] initWithFrame:NSMakeRect (0, 0, 500, 230)] autorelease];
  NSMutableArray *controls = [NSMutableArray array];
  for (NSUInteger index = 0; index < [specifications count]; index++)
    {
      NSDictionary *specification = [specifications objectAtIndex:index];
      ScoreSynthesisNode *node = [existing objectForKey:[specification objectForKey:@"type"]];
      CGFloat y = 190.0 - index * 42.0;
      NSButton *enabled = [[[NSButton alloc] initWithFrame:NSMakeRect (0, y, 135, 24)] autorelease];
      [enabled setButtonType:NSButtonTypeSwitch];
      [enabled setTitle:[specification objectForKey:@"name"]];
      [enabled setState:node ? NSControlStateValueOn : NSControlStateValueOff];
      [accessory addSubview:enabled];
      NSSlider *value = [[[NSSlider alloc] initWithFrame:NSMakeRect (140, y, 350, 24)] autorelease];
      [value setMinValue:[[specification objectForKey:@"minimum"] doubleValue]];
      [value setMaxValue:[[specification objectForKey:@"maximum"] doubleValue]];
      NSNumber *saved = [[node parameters] objectForKey:[specification objectForKey:@"key"]];
      [value setDoubleValue:saved ? [saved doubleValue]
                                  : [[specification objectForKey:@"default"] doubleValue]];
      [accessory addSubview:value];
      [controls addObject:@{ @"enabled" : enabled, @"value" : value, @"specification" : specification }];
    }
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:[NSString stringWithFormat:@"Effects — %@", [selectedPart name] ?: @"Part"]];
  [alert setInformativeText:@"These effects are stored with the part and applied during real-time playback and offline rendering."];
  [alert setAccessoryView:accessory];
  [alert addButtonWithTitle:@"Apply"];
  [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] != NSAlertFirstButtonReturn)
    return;
  [self registerUndoSnapshotWithName:@"Change Part Effects"];
  NSMutableSet *removedIdentifiers = [NSMutableSet set];
  NSIndexSet *effectIndexes = [[graph nodes]
    indexesOfObjectsPassingTest:^BOOL (ScoreSynthesisNode *node, NSUInteger index, BOOL *stop) {
      (void)index;
      (void)stop;
      for (NSDictionary *specification in specifications)
        if ([[node typeIdentifier] isEqualToString:[specification objectForKey:@"type"]])
          {
            [removedIdentifiers addObject:[node identifier]];
            return YES;
          }
      return NO;
    }];
  [[graph nodes] removeObjectsAtIndexes:effectIndexes];
  NSIndexSet *connectionIndexes = [[graph connections]
    indexesOfObjectsPassingTest:^BOOL (ScoreSynthesisConnection *connection, NSUInteger index,
                                       BOOL *stop) {
      (void)index;
      (void)stop;
      return [removedIdentifiers containsObject:[connection sourceNodeIdentifier]]
             || [removedIdentifiers containsObject:[connection destinationNodeIdentifier]];
    }];
  [[graph connections] removeObjectsAtIndexes:connectionIndexes];
  ScoreSynthesisNode *previous = nil;
  for (NSDictionary *control in controls)
    {
      if ([[control objectForKey:@"enabled"] state] != NSControlStateValueOn)
        continue;
      NSDictionary *specification = [control objectForKey:@"specification"];
      ScoreSynthesisNode *node = [[[ScoreSynthesisNode alloc] init] autorelease];
      [node setTypeIdentifier:[specification objectForKey:@"type"]];
      [[node parameters]
        setObject:[NSNumber numberWithDouble:[[control objectForKey:@"value"] doubleValue]]
           forKey:[specification objectForKey:@"key"]];
      if ([[node typeIdentifier] isEqualToString:@"compressor"])
        [[node parameters] setObject:@4.0 forKey:@"ratio"];
      else if ([[node typeIdentifier] isEqualToString:@"delay"])
        {
          [[node parameters] setObject:@0.3 forKey:@"time"];
          [[node parameters] setObject:@0.35 forKey:@"feedback"];
        }
      else if ([[node typeIdentifier] isEqualToString:@"reverb"])
        [[node parameters] setObject:@0.35 forKey:@"roomSize"];
      [[graph nodes] addObject:node];
      if (previous)
        {
          ScoreSynthesisConnection *connection =
            [[[ScoreSynthesisConnection alloc] init] autorelease];
          [connection setSourceNodeIdentifier:[previous identifier]];
          [connection setSourcePort:@"audio"];
          [connection setDestinationNodeIdentifier:[node identifier]];
          [connection setDestinationPort:@"audio"];
          [[graph connections] addObject:connection];
        }
      previous = node;
    }
  NSError *error = nil;
  if (![_realtimeDSP configureEffectsFromGraph:graph error:&error])
    [[NSDocumentController sharedDocumentController] presentError:error];
  else if ([[_realtimeDSP effectConfiguration] count])
    _useRealtimeDSP = YES;
  [self updateChangeCount:NSChangeDone];
}

- (void)restoreAudioUnitInstrument
{
  [_realtimeDSP useInternalSynthesizer];
  _audioUnitPartTrack = -1;
  _useRealtimeDSP = NO;
  ScoreDocument *document = [self scoreDocument];
  ScorePartDefinition *effectPart = nil;
  for (ScorePartDefinition *part in [document parts])
    if ([part legacyTrack] == [self selectedPartNumber])
      {
        effectPart = part;
        break;
      }
  if (!effectPart && [[document parts] count])
    effectPart = [[document parts] objectAtIndex:0];
  if (effectPart)
    {
      [_realtimeDSP configureEffectsFromGraph:[effectPart synthesisGraph] error:NULL];
      if ([[_realtimeDSP effectConfiguration] count])
        _useRealtimeDSP = YES;
    }
  for (ScorePartDefinition *part in [document parts])
    {
      ScoreInstrumentDefinition *instrument = [part instrument];
      if ([[instrument backendIdentifier] hasPrefix:@"audio-unit:"])
        {
          _audioUnitPartTrack = [part legacyTrack];
          NSDictionary *description = [instrument parameters];
#if defined(__APPLE__)
          if ([description objectForKey:@"type"] && [description objectForKey:@"subtype"] &&
              [description objectForKey:@"manufacturerCode"])
            [_realtimeDSP
              loadAudioUnitInstrument:description
                           completion:^(BOOL success, NSError *error) {
                             if (success)
                               _useRealtimeDSP = YES;
                             else if (error)
                               [[NSDocumentController sharedDocumentController] presentError:error];
                           }];
#else
          (void)description;
#endif
          break;
        }
    }
}

- (void)captureAudioUnitState
{
  NSDictionary *state = [_realtimeDSP audioUnitFullState];
  if (!state)
    return;
  NSInteger track = [self selectedPartNumber];
  if (_audioUnitPartTrack >= 0)
    track = _audioUnitPartTrack;
  for (ScorePartDefinition *part in [[self scoreDocument] parts])
    if ([part legacyTrack] == track &&
        [[[part instrument] backendIdentifier] hasPrefix:@"audio-unit:"])
      {
        NSMutableDictionary *parameters =
          [NSMutableDictionary dictionaryWithDictionary:[[part instrument] parameters]];
        [parameters setObject:state forKey:@"state"];
        [[part instrument] setParameters:parameters];
        break;
      }
}

- (void)renderOfflineAudio:(id)sender
{
  (void)sender;
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    return;
  NSPopUpButton *scope = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (0, 0, 340, 26)
                                                     pullsDown:NO] autorelease];
  [scope addItemWithTitle:@"Full Mix"];
  [scope addItemWithTitle:@"Current Part Stem"];
  NSAlert *scopeAlert = [[[NSAlert alloc] init] autorelease];
  [scopeAlert setMessageText:@"Offline Audio Render"];
  [scopeAlert setInformativeText:
                @"Render the complete score or the currently selected part as a separate stem."];
  [scopeAlert setAccessoryView:scope];
  [scopeAlert addButtonWithTitle:@"Continue"];
  [scopeAlert addButtonWithTitle:@"Cancel"];
  if ([scopeAlert runModal] != NSAlertFirstButtonReturn)
    return;
  BOOL renderCurrentPart = [scope indexOfSelectedItem] == 1;
  NSInteger renderedTrack = [self selectedPartNumber];
  for (ScorePartDefinition *part in [document parts])
    if ([part legacyTrack] == renderedTrack)
      {
        [_realtimeDSP configureEffectsFromGraph:[part synthesisGraph] error:NULL];
        break;
      }
  NSSavePanel *panel = [NSSavePanel savePanel];
  [panel setNameFieldStringValue:renderCurrentPart ? @"ScoreMaker Part Stem.caf"
                                                   : @"ScoreMaker Render.caf"];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  [panel setAllowedFileTypes:[NSArray arrayWithObject:@"caf"]];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
  if ([panel runModal] != NSModalResponseOK)
    return;

  ScoreScheduler *scheduler = [[[ScoreScheduler alloc] initWithDocument:document] autorelease];
  NSMutableArray *timeline = [NSMutableArray array];
  for (ScoreScheduledEvent *event in [scheduler eventsFromTick:0 throughTick:[document totalTicks]])
    {
      ScoreNote *note = [event note];
      if (renderCurrentPart && [note track] != renderedTrack)
        continue;
      [timeline addObject:@{
        @"time" : [NSNumber numberWithDouble:[event time]],
        @"pitch" : [NSNumber numberWithInteger:[note pitch]],
        @"velocity" : [NSNumber numberWithUnsignedInteger:[note velocity]],
        @"on" : [NSNumber numberWithBool:![event noteOff]]
      }];
    }
  NSError *error = nil;
  NSTimeInterval duration = [scheduler timeForTick:[document totalTicks]] + 1.0;
  if (![_realtimeDSP renderEvents:timeline duration:duration toURL:[panel URL] error:&error])
    [[NSDocumentController sharedDocumentController] presentError:error];
}

- (void)auditionPitch:(NSInteger)pitch
{
  [self stopAudition];
  [_playbackMonitorView setInputPitch:pitch];
  ScoreDocument *source = [self scoreDocument];
  if (!source)
    {
      [_playbackMonitorView resetInputPitch];
      return;
    }

  ScoreDocument *audition = [[[ScoreDocument alloc] init] autorelease];
  [audition setTicksPerQuarter:[source ticksPerQuarter]];
  [audition setTempoMicrosecondsPerQuarter:[source tempoMicrosecondsPerQuarter]];
  NSInteger sourceTrack = [self selectedPartNumber];
  NSNumber *program = [source programForTrack:sourceTrack];
  if (program)
    [audition setProgram:program forTrack:0];
  ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
  [note setPitch:pitch];
  [note setTrack:0];
  [note setChannel:sourceTrack % 16];
  [note
    setDurationTicks:[self
                       durationTicksForNoteValueDenominator:[self
                                                              denominatorForSelectedNoteValue]]];
  [note setVelocity:96];
  [[audition notes] addObject:note];
  [audition setTotalTicks:[note durationTicks]];

  NSData *data = [MidiParser dataForDocument:audition error:NULL];
  if (!data)
    {
      [_playbackMonitorView resetInputPitch];
      return;
    }
  BOOL started = NO;
  AVMIDIPlayer *player = [[[AVMIDIPlayer alloc] initWithData:data soundBankURL:nil
                                                       error:NULL] autorelease];
  if (player)
    {
      [player prepareToPlay];
      [player play:nil];
      _auditionPlayer = [player retain];
      started = YES;
    }
  else
    {
      NSSound *sound = [[[NSSound alloc] initWithData:data] autorelease];
      if (sound && [sound play])
        {
          _auditionSound = [sound retain];
          started = YES;
        }
    }
  if (!started)
    {
      [_playbackMonitorView resetInputPitch];
      return;
    }
  double secondsPerQuarter = (double)[audition tempoMicrosecondsPerQuarter] / 1000000.0;
  NSTimeInterval duration
    = ((double)[note durationTicks] / (double)MAX ((NSUInteger)1, [audition ticksPerQuarter]))
      * MAX (secondsPerQuarter, 0.001);
  _auditionResetTimer =
    [[NSTimer scheduledTimerWithTimeInterval:MAX ((NSTimeInterval)0.05, duration)
                                      target:self
                                    selector:@selector (finishAudition:)
                                    userInfo:nil
                                     repeats:NO] retain];
}

- (void)finishAudition:(NSTimer *)timer
{
  (void)timer;
  [self stopAudition];
}

- (void)reloadMIDIInputs
{
  if (!_midiInputPopUp)
    return;
  [_midiInputPopUp removeAllItems];
  [_midiInputPopUp addItemWithTitle:@"None (Step Entry Off)"];
  [[_midiInputPopUp lastItem] setRepresentedObject:[NSNumber numberWithUnsignedInt:0]];
  for (NSDictionary *source in [_midiInputManager availableSources])
    {
      [_midiInputPopUp addItemWithTitle:[source objectForKey:@"name"]];
      [[_midiInputPopUp lastItem] setRepresentedObject:[source objectForKey:@"endpoint"]];
    }
}

- (void)midiDevicesChanged:(id)sender
{
  (void)sender;
  if (!_midiInputPopUp)
    return;
  unsigned int selectedEndpoint =
    [[[_midiInputPopUp selectedItem] representedObject] unsignedIntValue];
  [self reloadMIDIInputs];
  NSMenuItem *matchingItem = nil;
  for (NSMenuItem *item in [_midiInputPopUp itemArray])
    {
      if ([[item representedObject] unsignedIntValue] == selectedEndpoint && selectedEndpoint != 0)
        {
          matchingItem = item;
          break;
        }
    }
  if (matchingItem)
    {
      [_midiInputPopUp selectItem:matchingItem];
      [_midiInputManager connectToSource:selectedEndpoint];
    }
  else
    {
      [self stopMIDIRecording];
      [_midiInputManager connectToSource:0];
      [_midiInputPopUp selectItemAtIndex:0];
    }
  [self refreshInspector];
}

- (void)midiInputDidChange:(id)sender
{
  (void)sender;
  [self stopMIDIRecording];
  unsigned int endpoint = [[[_midiInputPopUp selectedItem] representedObject] unsignedIntValue];
  if (![_midiInputManager connectToSource:endpoint])
    {
      [_midiInputPopUp selectItemAtIndex:0];
      NSAlert *alert = [[[NSAlert alloc] init] autorelease];
      [alert setMessageText:@"The MIDI input could not be opened"];
      [alert setInformativeText:@"Disconnect and reconnect the keyboard, then choose it again."];
      [alert runModal];
    }
  else if (endpoint && ![_realtimeDSP isRunning])
    {
      /* Warm the persistent audition engine before the first MIDI key press. */
      NSError *error = nil;
      if (![_realtimeDSP startWithError:&error])
        NSLog (@"Could not prepare MIDI input audition: %@", error);
    }
  [self refreshInspector];
}

- (NSUInteger)midiQuantizationTicks
{
  NSString *title = [_midiQuantizePopUp titleOfSelectedItem];
  NSInteger denominator =
    [[title substringFromIndex:MIN ((NSUInteger)2, [title length])] integerValue];
  if (denominator <= 0)
    denominator = 16;
  return MAX ((NSUInteger)1,
              ([[self scoreDocument] ticksPerQuarter] * 4) / (NSUInteger)denominator);
}

- (NSUInteger)quantizedTick:(NSUInteger)tick
{
  NSUInteger quantum = [self midiQuantizationTicks];
  return ((tick + quantum / 2) / quantum) * quantum;
}

- (ScoreNote *)appendMIDINotePitch:(NSInteger)pitch
                          velocity:(NSUInteger)velocity
                             track:(NSInteger)track
                         startTick:(NSUInteger)startTick
                     durationTicks:(NSUInteger)durationTicks
{
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    return nil;
  ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
  [note setPitch:pitch];
  [note setVelocity:velocity];
  [note setTrack:track];
  [note setChannel:track % 16];
  [note setVoice:1];
  [note setStartTick:startTick];
  [note setDurationTicks:MAX ((NSUInteger)1, durationTicks)];
  [[document notes] addObject:note];
  NSUInteger end = startTick + [note durationTicks];
  [document setTotalTicks:MAX ([document totalTicks], end)];
  ScoreMeasure *measure = [document ensureMeasureContainingTick:startTick];
  [note setMeasureIndex:(NSInteger)[[document measures] indexOfObjectIdenticalTo:measure]];
  if (![document nameForTrack:track])
    [document setName:[NSString stringWithFormat:@"Part %ld", (long)(track + 1)] forTrack:track];
  return note;
}

- (NSUInteger)midiTickForTime:(NSTimeInterval)time
{
  ScoreDocument *document = [self scoreDocument];
  double secondsPerQuarter = (double)[document tempoMicrosecondsPerQuarter] / 1000000.0;
  if (secondsPerQuarter <= 0.0)
    secondsPerQuarter = 0.5;
  NSTimeInterval elapsed = MAX ((NSTimeInterval)0.0, time - _midiRecordStartTime);
  return _midiRecordStartTick
         + (NSUInteger)llround ((elapsed / secondsPerQuarter) * [document ticksPerQuarter]);
}

- (void)finishRecordedMIDIKey:(NSString *)key atTime:(NSTimeInterval)endTime
{
  NSDictionary *active = [_midiActiveNotes objectForKey:key];
  if (!active)
    return;
  NSUInteger rawStart = [self midiTickForTime:[[active objectForKey:@"time"] doubleValue]];
  NSUInteger rawEnd = [self midiTickForTime:endTime];
  NSUInteger start = [self quantizedTick:rawStart];
  NSUInteger end = [self quantizedTick:rawEnd];
  NSUInteger quantum = [self midiQuantizationTicks];
  if (end <= start)
    end = start + quantum;
  [self appendMIDINotePitch:[[active objectForKey:@"pitch"] integerValue]
                   velocity:[[active objectForKey:@"velocity"] unsignedIntegerValue]
                      track:[[active objectForKey:@"track"] integerValue]
                  startTick:start
              durationTicks:end - start];
  [_midiActiveNotes removeObjectForKey:key];
  [_midiSustainedNotes removeObject:key];
  _midiRecordedNotes = YES;
}

- (void)handleMIDIInputEvent:(NSDictionary *)event
{
  NSInteger type = [[event objectForKey:@"type"] integerValue];
  NSInteger channel = [[event objectForKey:@"channel"] integerValue];
  NSInteger data1 = [[event objectForKey:@"data1"] integerValue];
  NSInteger data2 = [[event objectForKey:@"data2"] integerValue];
  NSTimeInterval time = [[event objectForKey:@"time"] doubleValue];
  NSInteger voice = 1;
  NSString *routing = [[_midiRoutingPopUp selectedItem] representedObject];
  NSInteger destinationTrack =
    [routing isEqualToString:@"channel"] ? channel : [self selectedPartNumber];

  if (type == 0xb0 && data1 == 64)
    {
      BOOL wasDown = _midiSustainDown;
      _midiSustainDown = data2 >= 64;
      if (wasDown && !_midiSustainDown && _midiRecording && !_midiCountingIn)
        {
          NSArray *keys = [[_midiSustainedNotes allObjects] copy];
          for (NSString *key in keys)
            [self finishRecordedMIDIKey:key atTime:time];
          [keys release];
        }
      return;
    }

  BOOL noteOn = type == 0x90 && data2 > 0;
  BOOL noteOff = type == 0x80 || (type == 0x90 && data2 == 0);
  if (!noteOn && !noteOff)
    return;
  NSString *key = [NSString stringWithFormat:@"%ld:%ld", (long)channel, (long)data1];

  if (noteOn)
    {
      [_playbackMonitorView liveNoteOn:data1 voice:voice velocity:data2];
      if (_midiRecording)
        {
          if (!_midiCountingIn)
            {
              if ([_midiActiveNotes objectForKey:key])
                [self finishRecordedMIDIKey:key atTime:time];
              [_midiActiveNotes
                setObject:[NSDictionary
                            dictionaryWithObjectsAndKeys:[NSNumber numberWithDouble:time], @"time",
                                                         [NSNumber numberWithInteger:data1],
                                                         @"pitch",
                                                         [NSNumber numberWithInteger:data2],
                                                         @"velocity",
                                                         [NSNumber
                                                           numberWithInteger:destinationTrack],
                                                         @"track", nil]
                   forKey:key];
            }
        }
      else if (![_midiHeldStepNotes containsObject:key])
        {
          /*
           * MIDI input is already delivered on the main thread.  Do not use
           * auditionPitch: here: it serializes a MIDI file and constructs and
           * prepares a new AVMIDIPlayer for every key press, blocking delivery
           * of the following MIDI events.  The realtime engine is persistent
           * and accepts polyphonic note events without that setup cost.
           */
          if (![_realtimeDSP isRunning])
            {
              NSError *error = nil;
              if (![_realtimeDSP startWithError:&error])
                NSLog (@"Could not start MIDI input audition: %@", error);
            }
          if ([_realtimeDSP isRunning])
            [_realtimeDSP noteOn:data1 velocity:(NSUInteger)data2];
          if ([_midiHeldStepNotes count] == 0)
            {
              [self registerUndoSnapshotWithName:@"MIDI Step Entry"];
              _midiStepStartTick = (NSUInteger)llround (MAX (0.0, [_noteStartField doubleValue]) *
                                                        [[self scoreDocument] ticksPerQuarter]);
            }
          [self appendMIDINotePitch:data1
                           velocity:data2
                              track:destinationTrack
                          startTick:_midiStepStartTick
                      durationTicks:[self durationTicksForNoteValueDenominator:
                                            [self denominatorForSelectedNoteValue]]];
          [_midiHeldStepNotes addObject:key];
          [[[self scoreDocument] notes] sortUsingSelector:@selector (compareScoreNote:)];
          [self updateChangeCount:NSChangeDone];
        }
      return;
    }

  [_playbackMonitorView liveNoteOff:data1];
  if (_midiRecording)
    {
      if (!_midiCountingIn)
        {
          if (_midiSustainDown)
            [_midiSustainedNotes addObject:key];
          else
            [self finishRecordedMIDIKey:key atTime:time];
        }
    }
  else
    {
      if ([_realtimeDSP isRunning])
        [_realtimeDSP noteOff:data1];
      [_midiHeldStepNotes removeObject:key];
      if ([_midiHeldStepNotes count] == 0)
        {
          double durationBeats =
            [self beatsForNoteValueDenominator:[self denominatorForSelectedNoteValue]];
          [_noteStartField
            setDoubleValue:(double)_midiStepStartTick / [[self scoreDocument] ticksPerQuarter] +
                           durationBeats];
          /* Re-engrave once for the completed note or chord, not per key. */
          [[self scoreView] reloadDocument];
          [self commitUndoBaseline];
        }
    }
}

- (void)midiMetronomeTick:(NSTimer *)timer
{
  (void)timer;
  if (_midiMetronomeSound)
    [_midiMetronomeSound play];
  else
    NSBeep ();
  if (_midiCountingIn)
    {
      NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
      if (now + 0.001 >= _midiRecordStartTime)
        {
          _midiCountingIn = NO;
          _midiCountInBeatsRemaining = 0;
          [_recordButton setTitle:@"Stop"];
        }
      else if (_midiCountInBeatsRemaining > 0)
        {
          _midiCountInBeatsRemaining--;
          [_recordButton
            setTitle:[NSString stringWithFormat:@"%lu", (unsigned long)_midiCountInBeatsRemaining]];
        }
    }
}

- (void)toggleMIDIRecording:(id)sender
{
  (void)sender;
  if (_midiRecording)
    {
      [self stopMIDIRecording];
      return;
    }
  if (![self scoreDocument] || [_midiInputPopUp indexOfSelectedItem] <= 0)
    return;
  [self stopCurrentPlayback];
  [_midiActiveNotes removeAllObjects];
  [_midiSustainedNotes removeAllObjects];
  _midiSustainDown = NO;
  _midiRecordedNotes = NO;
  [_midiRecordingUndoSnapshot release];
  _midiRecordingUndoSnapshot = [[self scoreDocument] copy];
  _midiRecording = YES;
  _midiCountingIn = YES;
  _midiRecordStartTick = (NSUInteger)llround (MAX (0.0, [_noteStartField doubleValue]) *
                                              [[self scoreDocument] ticksPerQuarter]);
  NSUInteger beats = MAX ((NSUInteger)1, [[self scoreDocument] timeSignatureNumerator]);
  _midiCountInBeatsRemaining = beats;
  NSTimeInterval beatDuration
    = (double)[[self scoreDocument] tempoMicrosecondsPerQuarter] / 1000000.0;
  if (beatDuration <= 0.0)
    beatDuration = 0.5;
  _midiRecordStartTime = [NSDate timeIntervalSinceReferenceDate] + beatDuration * beats;
  [_recordButton setTitle:[NSString stringWithFormat:@"%lu", (unsigned long)beats]];
  _midiMetronomeSound = [[NSSound soundNamed:@"Tink"] retain];
  _midiMetronomeTimer = [[NSTimer scheduledTimerWithTimeInterval:beatDuration
                                                          target:self
                                                        selector:@selector (midiMetronomeTick:)
                                                        userInfo:nil
                                                         repeats:YES] retain];
  [self midiMetronomeTick:_midiMetronomeTimer];
}

- (void)stopMIDIRecording
{
  if (!_midiRecording && !_midiMetronomeTimer)
    {
      [_midiHeldStepNotes removeAllObjects];
      [_playbackMonitorView clearLiveNotes];
      return;
    }
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  if (_midiRecording && !_midiCountingIn)
    {
      NSArray *keys = [[_midiActiveNotes allKeys] copy];
      for (NSString *key in keys)
        [self finishRecordedMIDIKey:key atTime:now];
      [keys release];
    }
  [_midiMetronomeTimer invalidate];
  [_midiMetronomeTimer release];
  _midiMetronomeTimer = nil;
  [_midiMetronomeSound stop];
  [_midiMetronomeSound release];
  _midiMetronomeSound = nil;
  _midiRecording = NO;
  _midiCountingIn = NO;
  _midiSustainDown = NO;
  [_midiActiveNotes removeAllObjects];
  [_midiSustainedNotes removeAllObjects];
  [_midiHeldStepNotes removeAllObjects];
  [_playbackMonitorView clearLiveNotes];
  [_recordButton setTitle:@"Record"];
  if (_midiRecordedNotes && [self scoreDocument])
    {
      if (_midiRecordingUndoSnapshot)
        {
          [[[self undoManager] prepareWithInvocationTarget:self]
            restoreScoreSnapshot:_midiRecordingUndoSnapshot];
          [[self undoManager] setActionName:@"MIDI Recording"];
        }
      [[[self scoreDocument] notes] sortUsingSelector:@selector (compareScoreNote:)];
      [[self scoreView] reloadDocument];
      [self updateChangeCount:NSChangeDone];
      [self refreshInspector];
      [self commitUndoBaseline];
    }
  [_midiRecordingUndoSnapshot release];
  _midiRecordingUndoSnapshot = nil;
  _midiRecordedNotes = NO;
}

- (void)printDocument:(id)sender
{
  (void)sender;
  if (![self scoreView])
    {
      return;
    }

  NSPopUpButton *scope = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (0.0, 0.0, 340.0, 26.0)
                                                     pullsDown:NO] autorelease];
  [scope addItemWithTitle:@"Full Score"];
  NSString *partName = [[self scoreDocument] nameForTrack:[self selectedPartNumber]];
  if (![partName length])
    partName = [NSString stringWithFormat:@"Part %ld", (long)([self selectedPartNumber] + 1)];
  [scope addItemWithTitle:[NSString stringWithFormat:@"Current Part — %@", partName]];
  NSAlert *scopeAlert = [[[NSAlert alloc] init] autorelease];
  [scopeAlert setMessageText:@"Publish Sheet Music"];
  [scopeAlert
    setInformativeText:@"Print the full score or independently reflow the currently viewed part."];
  [scopeAlert setAccessoryView:scope];
  [scopeAlert addButtonWithTitle:@"Continue"];
  [scopeAlert addButtonWithTitle:@"Cancel"];
  if ([scopeAlert runModal] != NSAlertFirstButtonReturn)
    return;
  NSNumber *previousTrack = [[[self scoreView] publicationTrack] retain];
  if ([scope indexOfSelectedItem] == 1)
    [[self scoreView] setPublicationTrack:[NSNumber numberWithInteger:[self selectedPartNumber]]];

  NSPrintInfo *printInfo = [[[self printInfo] copy] autorelease];
#if defined(__APPLE__)
  [printInfo setOrientation:NSPaperOrientationPortrait];
  [printInfo setHorizontalPagination:NSPrintingPaginationModeClip];
  [printInfo setVerticalPagination:NSPrintingPaginationModeClip];
#else
  [printInfo setOrientation:NSPortraitOrientation];
  [printInfo setHorizontalPagination:NSClipPagination];
  [printInfo setVerticalPagination:NSClipPagination];
#endif
  [printInfo setHorizontallyCentered:YES];
  [printInfo setVerticallyCentered:NO];
  [printInfo setLeftMargin:24.0];
  [printInfo setRightMargin:24.0];
  [printInfo setTopMargin:24.0];
  [printInfo setBottomMargin:24.0];

  // ScoreView performs the final fit in its print drawing transform. AppKit
  // can replace NSPrintInfo's scaling factor when the print panel closes.
  [printInfo setScalingFactor:1.0];

  NSPrintOperation *operation = [NSPrintOperation printOperationWithView:[self scoreView]
                                                               printInfo:printInfo];
  [operation setShowsPrintPanel:YES];
  [operation setShowsProgressPanel:YES];
  [operation runOperation];
  [[self scoreView] setPublicationTrack:previousTrack];
  [previousTrack release];
}

- (void)editScoreTitle:(id)sender
{
  (void)sender;
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    return;

  NSTextField *titleField =
    [[[NSTextField alloc] initWithFrame:NSMakeRect (0.0, 0.0, 360.0, 24.0)] autorelease];
  [titleField setStringValue:[document title] ?: @""];
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"Edit Score Title"];
  [alert
    setInformativeText:@"This title is shown on the score and is independent of the filename."];
  [alert setAccessoryView:titleField];
  [alert addButtonWithTitle:@"Save"];
  [alert addButtonWithTitle:@"Cancel"];
  [[alert window] setInitialFirstResponder:titleField];
  if ([alert runModal] != NSAlertFirstButtonReturn)
    return;

  [self registerUndoSnapshotWithName:@"Edit Title"];
  [document setTitle:[titleField stringValue]];
  [self updateChangeCount:NSChangeDone];
  [[self scoreView] setNeedsDisplay:YES];
  [self commitUndoBaseline];
}

- (void)chooseTitleFont:(id)sender
{
  (void)sender;
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    return;

  NSFont *font = [NSFont fontWithName:[document titleFontName] size:24.0];
  if (!font)
    font = [NSFont boldSystemFontOfSize:24.0];
  NSFontManager *manager = [NSFontManager sharedFontManager];
  [manager setTarget:self];
  [manager setSelectedFont:font isMultiple:NO];
  [manager orderFrontFontPanel:self];
}

- (void)changeFont:(id)sender
{
  NSFont *currentFont = [NSFont fontWithName:[[self scoreDocument] titleFontName] size:24.0];
  if (!currentFont)
    currentFont = [NSFont boldSystemFontOfSize:24.0];
  NSFont *convertedFont = [sender convertFont:currentFont];
  if (!convertedFont)
    return;

  [self registerUndoSnapshotWithName:@"Change Title Font"];
  [[self scoreDocument] setTitleFontName:[convertedFont fontName]];
  [self updateChangeCount:NSChangeDone];
  [[self scoreView] setNeedsDisplay:YES];
  [self commitUndoBaseline];
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error
{
  (void)typeName;
  NSString *path = [url path];
  NSString *extension = [[path pathExtension] lowercaseString];
  ScoreDocument *document = nil;
  if ([extension isEqualToString:@"scoremaker"])
    {
      NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
      document = data ? [ScoreProjectSerializer documentFromData:data error:error] : nil;
    }
  else if ([extension isEqualToString:@"score"])
    {
      document = [ScorefileParser parseFileAtPath:path error:error];
    }
  else if ([extension isEqualToString:@"musicxml"] || [extension isEqualToString:@"xml"])
    {
      document = [MusicXMLParser parseFileAtPath:path error:error];
    }
  else
    {
      document = [MidiParser parseFileAtPath:path error:error];
    }
  if (!document)
    {
      return NO;
    }
  [self setScoreDocument:document];
  [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:url];
  return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)error
{
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    {
      if (error)
        {
          NSDictionary *info = [NSDictionary dictionaryWithObject:@"There is no score to save."
                                                           forKey:NSLocalizedDescriptionKey];
          *error = [NSError errorWithDomain:@"ScoreMakerDocument" code:1 userInfo:info];
        }
      return nil;
    }
  [self syncInspectorMetadataMarkingChange:NO];
  [self captureAudioUnitState];
  [document setAnnotationText:[_annotationTextView string]];

  NSString *lowerType = [typeName lowercaseString];
  if ([lowerType rangeOfString:@"scoremaker project"].location != NSNotFound)
    return [ScoreProjectSerializer dataForDocument:document error:error];
  if ([lowerType rangeOfString:@"midi"].location != NSNotFound)
    {
      return [MidiParser dataForDocument:document error:error];
    }
  if ([lowerType rangeOfString:@"musicxml"].location != NSNotFound ||
      [lowerType isEqualToString:@"xml"])
    {
      return [MusicXMLParser dataForDocument:document error:error];
    }
  return [ScorefileParser dataForDocument:document error:error];
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error
{
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    {
      if (error)
        {
          NSDictionary *info = [NSDictionary dictionaryWithObject:@"There is no score to save."
                                                           forKey:NSLocalizedDescriptionKey];
          *error = [NSError errorWithDomain:@"ScoreMakerDocument" code:1 userInfo:info];
        }
      return NO;
    }

  [self syncInspectorMetadataMarkingChange:NO];
  [self captureAudioUnitState];
  if (_annotationTextView)
    {
      [document setAnnotationText:[_annotationTextView string]];
    }

  NSString *lowerType = [typeName lowercaseString];
  NSString *extension = [[[url path] pathExtension] lowercaseString];
  NSData *data = nil;
  if ([extension isEqualToString:@"scoremaker"] ||
      [lowerType rangeOfString:@"scoremaker project"].location != NSNotFound)
    {
      data = [ScoreProjectSerializer dataForDocument:document error:error];
    }
  else if ([extension isEqualToString:@"musicxml"] || [extension isEqualToString:@"xml"] ||
           [lowerType rangeOfString:@"musicxml"].location != NSNotFound)
    {
      data = [MusicXMLParser dataForDocument:document error:error];
    }
  else if ([extension isEqualToString:@"mid"] || [extension isEqualToString:@"midi"] ||
           [lowerType rangeOfString:@"midi"].location != NSNotFound)
    {
      data = [MidiParser dataForDocument:document error:error];
    }
  else
    {
      data = [ScorefileParser dataForDocument:document error:error];
    }
  if (!data)
    return NO;
  return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

- (NSArray *)writableTypesForSaveOperation:(NSSaveOperationType)saveOperation
{
  (void)saveOperation;
  return [NSArray arrayWithObjects:@"ScoreMaker Project", @"MusicKit Scorefile", @"MIDI File",
                                   @"MusicXML File", nil];
}

- (NSString *)fileNameExtensionForType:(NSString *)typeName
                         saveOperation:(NSSaveOperationType)saveOperation
{
  (void)saveOperation;
  if ([[typeName lowercaseString] rangeOfString:@"scoremaker project"].location != NSNotFound)
    return @"scoremaker";
  if ([[typeName lowercaseString] rangeOfString:@"midi"].location != NSNotFound)
    {
      return @"mid";
    }
  if ([[typeName lowercaseString] rangeOfString:@"musicxml"].location != NSNotFound)
    {
      return @"musicxml";
    }
  return @"score";
}

- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel
{
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  [savePanel setAllowedFileTypes:[NSArray arrayWithObjects:@"scoremaker", @"score", @"mid", @"midi",
                                                           @"musicxml", @"xml", nil]];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
  NSString *suggestedName =
    [self fileURL] ? [[[self fileURL] path] lastPathComponent] : @"Untitled.scoremaker";
  [savePanel setNameFieldStringValue:suggestedName];
  return [super prepareSavePanel:savePanel];
}

- (NSString *)displayName
{
  return [super displayName];
}

- (void)setFileURL:(NSURL *)absoluteURL
{
  [super setFileURL:absoluteURL];
  if (absoluteURL)
    {
      [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:absoluteURL];
    }
}

@end
