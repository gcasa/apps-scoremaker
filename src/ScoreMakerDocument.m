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
static NSString *const ScoreMakerInternalPatchPresetsKey = @"ScoreMakerInternalPatchPresets";

#if defined(__APPLE__)
#define ScoreMakerSwitchButton NSButtonTypeSwitch
#define ScoreMakerStateOn NSControlStateValueOn
#define ScoreMakerStateOff NSControlStateValueOff
#define ScoreMakerWindowTitled NSWindowStyleMaskTitled
#define ScoreMakerWindowClosable NSWindowStyleMaskClosable
#define ScoreMakerWindowMiniaturizable NSWindowStyleMaskMiniaturizable
#define ScoreMakerWindowResizable NSWindowStyleMaskResizable
#else
#define ScoreMakerSwitchButton NSSwitchButton
#define ScoreMakerStateOn NSOnState
#define ScoreMakerStateOff NSOffState
#define ScoreMakerWindowTitled NSTitledWindowMask
#define ScoreMakerWindowClosable NSClosableWindowMask
#define ScoreMakerWindowMiniaturizable NSMiniaturizableWindowMask
#define ScoreMakerWindowResizable NSResizableWindowMask
#endif

static NSRange
ScoreMakerSourceLineRangeForRange (NSString *source, NSRange range)
{
  NSUInteger length = [source length];
  if (length == 0)
    return NSMakeRange (0, 0);

  if (range.location > length)
    range.location = length;
  if (NSMaxRange (range) > length)
    range.length = length - range.location;

  NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];
  while (range.length > 0 &&
         [whitespace characterIsMember:[source characterAtIndex:range.location]])
    {
      range.location++;
      range.length--;
    }
  while (range.length > 0 &&
         [whitespace characterIsMember:[source characterAtIndex:NSMaxRange (range) - 1]])
    range.length--;

  if (range.location >= length)
    return NSMakeRange (length, 0);
  return [source lineRangeForRange:range];
}

#if !defined(__APPLE__)
static NSRange
ScoreMakerSourceRangeCoveringRanges (NSArray *ranges)
{
  if (![ranges count])
    return NSMakeRange (0, 0);

  NSRange covered = [[ranges objectAtIndex:0] rangeValue];
  for (NSUInteger index = 1; index < [ranges count]; index++)
    covered = NSUnionRange (covered, [[ranges objectAtIndex:index] rangeValue]);
  return covered;
}

static NSRange
ScoreMakerSourceRangeWithLookahead (NSString *source, NSRange range, NSUInteger lineCount)
{
  NSUInteger length = [source length];
  if (range.location > length)
    range.location = length;
  if (NSMaxRange (range) > length)
    range.length = length - range.location;

  NSUInteger end = NSMaxRange (range);
  for (NSUInteger line = 0; line < lineCount && end < length; line++)
    {
      NSRange lineRange = [source lineRangeForRange:NSMakeRange (end, 0)];
      NSUInteger nextEnd = NSMaxRange (lineRange);
      if (nextEnd <= end)
        break;
      end = nextEnd;
    }
  range.length = end - range.location;
  return range;
}
#endif

static void
ScoreMakerSetAccessibilityLabel (id control, NSString *label)
{
  SEL selector = NSSelectorFromString (@"setAccessibilityLabel:");
  if ([control respondsToSelector:selector])
    [control performSelector:selector withObject:label];
}

static NSImage *
ScoreMakerTransportImage (NSString *kind)
{
  NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize (16.0, 16.0)] autorelease];
  [image lockFocus];
  [[NSColor blackColor] setFill];
  if ([kind isEqualToString:@"play"])
    {
      NSBezierPath *path = [NSBezierPath bezierPath];
      [path moveToPoint:NSMakePoint (4.0, 2.0)];
      [path lineToPoint:NSMakePoint (13.0, 8.0)];
      [path lineToPoint:NSMakePoint (4.0, 14.0)];
      [path closePath];
      [path fill];
    }
  else if ([kind isEqualToString:@"resume"])
    {
      NSRectFill (NSMakeRect (2.0, 2.0, 2.5, 12.0));
      NSBezierPath *path = [NSBezierPath bezierPath];
      [path moveToPoint:NSMakePoint (6.0, 2.0)];
      [path lineToPoint:NSMakePoint (14.0, 8.0)];
      [path lineToPoint:NSMakePoint (6.0, 14.0)];
      [path closePath];
      [path fill];
    }
  else if ([kind isEqualToString:@"pause"])
    {
      NSRectFill (NSMakeRect (3.0, 2.0, 4.0, 12.0));
      NSRectFill (NSMakeRect (9.0, 2.0, 4.0, 12.0));
    }
  else
    NSRectFill (NSMakeRect (3.0, 3.0, 10.0, 10.0));
  [image unlockFocus];
#if defined(__APPLE__)
  if ([image respondsToSelector:@selector (setTemplate:)])
    [image setTemplate:YES];
#endif
  return image;
}

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

@interface ScorePaletteItemView : NSView <NSDraggingSource>
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

@interface ScoreRoutingRowsView : NSView
@end

@implementation ScoreRoutingRowsView
- (BOOL)isFlipped
{
  return YES;
}
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
- (void)refreshRoutingMatrix;
- (void)registerUndoSnapshotWithName:(NSString *)name;
- (void)restoreScoreSnapshot:(ScoreDocument *)snapshot;
- (void)commitUndoBaseline;
- (void)restoreAudioUnitInstrument;
- (void)captureAudioUnitState;
- (NSString *)generatedScoreSourceWithError:(NSError **)error;
- (void)updateScoreSourceSyntaxHighlighting;
- (void)scoreSourceTextDidChange:(NSNotification *)notification;
- (void)scoreSourceSelectionDidChange:(NSNotification *)notification;
- (ScoreNote *)scoreNoteForSourceLocation:(NSUInteger)location;
- (NSValue *)sourceRangeForScoreNote:(ScoreNote *)note;
- (void)updateScoreSourcePlaybackHighlightAtTick:(NSUInteger)tick;
- (void)updateScoreSourceMIDIInputHighlight;
- (void)clearScoreSourcePlaybackHighlight;
#if !defined(__APPLE__)
- (void)setScoreSourceSelectedRange:(NSRange)range
                     selectionColor:(NSColor *)color
        preservingHorizontalScroll:(BOOL)preserveHorizontalScroll;
- (void)scrollScoreSourceRangesToVisible:(NSArray *)ranges
              preservingHorizontalScroll:(BOOL)preserveHorizontalScroll;
#endif
- (void)resetScoreSourceRangeCache;
- (void)closeAuxiliaryWindows;
- (void)refreshScoreSourceEditorFromScoreIfClean;
- (void)positionScoreSourceEditorBesideDocument;
- (void)positionAuxiliaryWindowBesideDocument:(NSWindow *)auxiliaryWindow;
- (void)arrangeScoreAuxiliaryWindows;
- (void)updatePauseButtonForPaused:(BOOL)paused;
- (void)clearScoreSourceErrorHighlight;
- (void)showScoreSourceError:(NSError *)error;
- (void)showGenericAudioUnitEditor;
- (ScorePartDefinition *)selectedStructuredPartCreatingIfNeeded:(BOOL)create;
- (NSDictionary *)patchForPart:(ScorePartDefinition *)part;
- (NSDictionary *)patchForPart:(ScorePartDefinition *)part voice:(NSInteger)voice;
- (NSInteger)selectedPatchVoice;
- (void)configureVoicePatchesForPart:(ScorePartDefinition *)part;
- (void)loadPatchEditorControls;
- (void)patchControlChanged:(id)sender;
- (void)resetInternalSynthPatch:(id)sender;
- (void)previewInternalSynthPatch:(id)sender;
- (void)patchVoiceChanged:(id)sender;
- (void)patchPresetChanged:(id)sender;
- (void)reloadPatchPresetPopUpSelectingName:(NSString *)name;
- (NSDictionary *)availableInternalSynthPatchLibrary;
- (void)rebuildInstrumentPopUpSelectingCurrentSound;
- (void)instrumentVoiceDidChange:(id)sender;
- (void)saveInternalSynthPatchPreset:(id)sender;
- (void)loadInternalSynthPatchPreset:(id)sender;
- (void)editInternalSynthPatchEffects:(id)sender;
- (void)editInternalSynthFilterEnvelope:(id)sender;
- (void)showInternalSynthPatchBrowser:(id)sender;
- (void)refreshPatchBrowser:(id)sender;
- (void)auditionPatchBrowserSelection:(id)sender;
- (void)usePatchBrowserSelection:(id)sender;
- (void)restorePatchAfterBrowserAudition:(NSTimer *)timer;
- (void)audioUnitParameterChanged:(id)sender;
- (BOOL)prepareDSPPlaybackAtTick:(NSUInteger)tick error:(NSError **)error;
@end

@interface ScorePatchEnvelopeView : NSView
{
  NSDictionary *_patch;
}
- (void)setPatch:(NSDictionary *)patch;
@end

@implementation ScorePatchEnvelopeView

- (void)dealloc
{
  [_patch release];
  [super dealloc];
}

- (void)setPatch:(NSDictionary *)patch
{
  if (_patch != patch)
    {
      [_patch release];
      _patch = [patch copy];
    }
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
  (void)dirtyRect;
  NSRect bounds = NSInsetRect ([self bounds], 0.5, 0.5);
  [[NSColor colorWithCalibratedWhite:0.12 alpha:0.08] setFill];
  NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:7 yRadius:7];
  [background fill];
  [[NSColor colorWithCalibratedWhite:0.45 alpha:0.28] setStroke];
  [background stroke];

  NSRect graph = NSInsetRect (bounds, 14.0, 14.0);
  [[NSColor colorWithCalibratedWhite:0.55 alpha:0.18] setStroke];
  for (NSInteger row = 0; row <= 4; row++)
    {
      CGFloat y = NSMinY (graph) + NSHeight (graph) * row / 4.0;
      NSBezierPath *line = [NSBezierPath bezierPath];
      [line moveToPoint:NSMakePoint (NSMinX (graph), y)];
      [line lineToPoint:NSMakePoint (NSMaxX (graph), y)];
      [line stroke];
    }

  double attack = MAX (0.0, [[_patch objectForKey:@"attack"] doubleValue]);
  double decay = MAX (0.0, [[_patch objectForKey:@"decay"] doubleValue]);
  double sustain = MIN (1.0, MAX (0.0, [[_patch objectForKey:@"sustain"] doubleValue]));
  double release = MAX (0.0, [[_patch objectForKey:@"release"] doubleValue]);
  double held = MAX (0.5, (attack + decay + release) * 0.28);
  double total = MAX (0.01, attack + decay + held + release);
  CGFloat x0 = NSMinX (graph);
  CGFloat x1 = x0 + NSWidth (graph) * attack / total;
  CGFloat x2 = x1 + NSWidth (graph) * decay / total;
  CGFloat x3 = x2 + NSWidth (graph) * held / total;
  CGFloat x4 = NSMaxX (graph);
  CGFloat y0 = NSMinY (graph);
  CGFloat peak = NSMaxY (graph);
  CGFloat sustainY = y0 + NSHeight (graph) * sustain;

  NSBezierPath *fill = [NSBezierPath bezierPath];
  [fill moveToPoint:NSMakePoint (x0, y0)];
  [fill lineToPoint:NSMakePoint (x1, peak)];
  [fill lineToPoint:NSMakePoint (x2, sustainY)];
  [fill lineToPoint:NSMakePoint (x3, sustainY)];
  [fill lineToPoint:NSMakePoint (x4, y0)];
  [fill closePath];
  [[NSColor colorWithCalibratedRed:0.10 green:0.48 blue:0.95 alpha:0.18] setFill];
  [fill fill];

  NSBezierPath *curve = [NSBezierPath bezierPath];
  [curve moveToPoint:NSMakePoint (x0, y0)];
  [curve lineToPoint:NSMakePoint (x1, peak)];
  [curve lineToPoint:NSMakePoint (x2, sustainY)];
  [curve lineToPoint:NSMakePoint (x3, sustainY)];
  [curve lineToPoint:NSMakePoint (x4, y0)];
  [curve setLineWidth:2.25];
  [[NSColor colorWithCalibratedRed:0.08 green:0.42 blue:0.92 alpha:0.95] setStroke];
  [curve stroke];
}

@end

@interface ScoreFilterEnvelopeView : NSView
{
  NSDictionary *_controls;
  NSDictionary *_valueLabels;
}
- (void)setControls:(NSDictionary *)controls valueLabels:(NSDictionary *)labels;
- (void)controlChanged:(id)sender;
@end

@implementation ScoreFilterEnvelopeView

- (void)dealloc
{
  [_controls release];
  [_valueLabels release];
  [super dealloc];
}

- (void)setControls:(NSDictionary *)controls valueLabels:(NSDictionary *)labels
{
  [_controls release];
  [_valueLabels release];
  _controls = [controls copy];
  _valueLabels = [labels copy];
  [self setNeedsDisplay:YES];
}

- (void)controlChanged:(id)sender
{
  (void)sender;
  for (NSString *key in _valueLabels)
    [[_valueLabels objectForKey:key]
      setStringValue:[NSString stringWithFormat:@"%.2f",
                                                 [[_controls objectForKey:key] doubleValue]]];
  [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
  (void)dirtyRect;
  NSRect bounds = NSInsetRect ([self bounds], 0.5, 0.5);
  [[NSColor colorWithCalibratedWhite:0.12 alpha:0.08] setFill];
  NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:7 yRadius:7];
  [background fill];
  [[NSColor colorWithCalibratedWhite:0.45 alpha:0.28] setStroke];
  [background stroke];
  NSRect graph = NSInsetRect (bounds, 14.0, 12.0);
  double attack = [[_controls objectForKey:@"filterAttack"] doubleValue];
  double decay = [[_controls objectForKey:@"filterDecay"] doubleValue];
  double sustain = [[_controls objectForKey:@"filterSustain"] doubleValue];
  double release = [[_controls objectForKey:@"filterRelease"] doubleValue];
  double held = MAX (0.5, (attack + decay + release) * 0.28);
  double total = MAX (0.01, attack + decay + held + release);
  CGFloat x0 = NSMinX (graph);
  CGFloat x1 = x0 + NSWidth (graph) * attack / total;
  CGFloat x2 = x1 + NSWidth (graph) * decay / total;
  CGFloat x3 = x2 + NSWidth (graph) * held / total;
  CGFloat x4 = NSMaxX (graph);
  CGFloat y0 = NSMinY (graph);
  CGFloat peak = NSMaxY (graph);
  CGFloat sustainY = y0 + NSHeight (graph) * MIN (1.0, MAX (0.0, sustain));
  NSBezierPath *fill = [NSBezierPath bezierPath];
  [fill moveToPoint:NSMakePoint (x0, y0)];
  [fill lineToPoint:NSMakePoint (x1, peak)];
  [fill lineToPoint:NSMakePoint (x2, sustainY)];
  [fill lineToPoint:NSMakePoint (x3, sustainY)];
  [fill lineToPoint:NSMakePoint (x4, y0)];
  [fill closePath];
  [[NSColor colorWithCalibratedRed:0.12 green:0.67 blue:0.42 alpha:0.18] setFill];
  [fill fill];
  [fill setLineWidth:2.25];
  [[NSColor colorWithCalibratedRed:0.08 green:0.58 blue:0.34 alpha:0.95] setStroke];
  [fill stroke];
}

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
#if defined(__APPLE__)
  NSPasteboardItem *pasteboardItem = [[[NSPasteboardItem alloc] init] autorelease];
  [pasteboardItem setString:payload forType:ScorePalettePasteboardType];
  NSDraggingItem *draggingItem = [[[NSDraggingItem alloc]
    initWithPasteboardWriter:pasteboardItem] autorelease];
  NSImage *image = [self dragImage];
  [draggingItem setDraggingFrame:NSMakeRect (4.0, 4.0, [image size].width, [image size].height)
                        contents:image];
  [self beginDraggingSessionWithItems:@[ draggingItem ] event:event source:self];
#else
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
#endif
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
  (void)isLocal;
  return NSDragOperationCopy;
}

#if defined(__APPLE__)
- (NSDragOperation)draggingSession:(NSDraggingSession *)session
  sourceOperationMaskForDraggingContext:(NSDraggingContext)context
{
  (void)session;
  (void)context;
  return NSDragOperationCopy;
}
#endif

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
      _realtimeDSPVoice = 1;
      _audioUnitPartTrack = -1;
      ScoreDocument *document = [[[ScoreDocument alloc] init] autorelease];
      [document setTitle:@"Untitled"];
      [self setScoreDocument:document];
#if defined(__APPLE__)
      _externalMIDIPlaybacks = [[NSMutableArray alloc] init];
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
  if (_patchEditorWindow)
    [self loadPatchEditorControls];
  if (_routingMatrixWindow && [_routingMatrixWindow isVisible])
    [self refreshRoutingMatrix];
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

- (void)updateChangeCount:(NSDocumentChangeType)change
{
  [super updateChangeCount:change];
  if (!_applyingScoreSource && change == NSChangeDone)
    {
      _scoreSourceIsAuthoritative = NO;
      [self refreshScoreSourceEditorFromScoreIfClean];
    }
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [_scoreDocument release];
  [_realtimeDSP stop];
  [_realtimeDSP release];
  [_audioUnitEditorWindow release];
  [_audioUnitParameterAddresses release];
  [_patchEditorWindow release];
  [_patchWaveformPopUp release];
  [_patchVoicePopUp release];
  [_patchPresetPopUp release];
  [_patchControls release];
  [_patchValueLabels release];
  [_patchFilterValues release];
  [_patchEnvelopeView release];
  [_patchBrowserWindow release];
  [_patchBrowserTable release];
  [_patchBrowserCategoryPopUp release];
  [_patchBrowserRows release];
  [_routingMatrixWindow release];
  [_routingMatrixRowsView release];
  [_routingMatrixSummaryLabel release];
  [_routingMatrixSelection release];
  [_routingBulkDevicePopUp release];
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
  [_instrumentVoicePopUp release];
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
  [_midiHeldStepScoreNotes release];
  [_midiSustainedNotes release];
  [_midiMetronomeSound release];
  [_undoBaseline release];
  [_midiRecordingUndoSnapshot release];
  [_annotationTextView release];
  [_scoreSourceEditorWindow release];
  [_scoreSourceTextView release];
  [_scoreSourceStatusLabel release];
  [_scoreSourceText release];
  [_scoreSourceNoteRangeCache release];
  [_scoreSourceRangeMappings release];
  [_scoreSourcePlaybackRanges release];
  [_scoreSourcePlaybackSignature release];
  [_scoreSourceErrorRange release];
  [_scoreSourceActivePlaybackNotes release];
#if defined(__APPLE__)
  [_externalMIDIPlaybacks release];
#endif

  [super dealloc];
}

- (void)close
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self closeAuxiliaryWindows];
  [self stopCurrentPlayback];
  [self stopAudition];
  [self stopMIDIRecording];
  [_midiInputManager disconnect];
  [_midiInputManager setTarget:nil];
  [super close];
}

- (void)closeAuxiliaryWindows
{
  NSAssert ([NSThread isMainThread], @"ScoreMaker windows must close on the main thread");
  [_audioUnitEditorWindow close];
  NSWindow *patchParent = [_patchEditorWindow parentWindow];
  if (patchParent)
    [patchParent removeChildWindow:_patchEditorWindow];
  [_patchEditorWindow close];
  [_patchBrowserWindow close];
  [_routingMatrixWindow close];
  NSWindow *sourceParent = [_scoreSourceEditorWindow parentWindow];
  if (sourceParent)
    [sourceParent removeChildWindow:_scoreSourceEditorWindow];
  [_scoreSourceEditorWindow close];
}

- (void)prepareForApplicationTermination
{
  NSAssert ([NSThread isMainThread], @"Application termination must run on the main thread");
  [self stopCurrentPlayback];
  [self stopAudition];
  [self stopMIDIRecording];
  [_midiInputManager disconnect];
  [_midiInputManager setTarget:nil];
  [self closeAuxiliaryWindows];
}

- (void)makeWindowControllers
{
  NSRect frame = NSMakeRect (100.0, 100.0, 1320.0, 880.0);
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  NSUInteger style = ScoreMakerWindowTitled | ScoreMakerWindowClosable | ScoreMakerWindowMiniaturizable
                     | ScoreMakerWindowResizable;
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
  _midiHeldStepScoreNotes = [[NSMutableDictionary alloc] init];
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
  [_playButton setTitle:@""];
  [_playButton setImage:ScoreMakerTransportImage (@"play")];
  [_playButton setImagePosition:NSImageOnly];
  [_playButton setToolTip:@"Play"];
  ScoreMakerSetAccessibilityLabel (_playButton, @"Play");
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
  [_pauseButton setTitle:@""];
  [_pauseButton setImagePosition:NSImageOnly];
  [self updatePauseButtonForPaused:NO];
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
  [_stopButton setTitle:@""];
  [_stopButton setImage:ScoreMakerTransportImage (@"stop")];
  [_stopButton setImagePosition:NSImageOnly];
  [_stopButton setToolTip:@"Stop"];
  ScoreMakerSetAccessibilityLabel (_stopButton, @"Stop");
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

  NSButton *sourceButton = [[[NSButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 134.0, frame.size.height - 174.0, 128.0, 27.0)]
    autorelease];
  [sourceButton setTitle:@"Edit Source..."];
  [sourceButton setTarget:self];
  [sourceButton setAction:@selector (showScoreSourceEditor:)];
  [sourceButton setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:sourceButton];

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
    [self labelWithString:@"Instrument"
                    frame:NSMakeRect (InspectorPadding, frame.size.height - 362.0, 120.0, 18.0)];
  [instrumentLabel setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:instrumentLabel];
  _instrumentPopUp = [[NSPopUpButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding, frame.size.height - 392.0, 180.0, 26.0)
        pullsDown:NO];
  [_instrumentPopUp setTarget:self];
  [_instrumentPopUp setAction:@selector (instrumentDidChange:)];
  [_instrumentPopUp setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_instrumentPopUp];
  _instrumentVoicePopUp = [[NSPopUpButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 184.0, frame.size.height - 392.0, 78.0, 26.0)
        pullsDown:NO];
  for (NSInteger voice = 1; voice <= 16; voice++)
    [_instrumentVoicePopUp addItemWithTitle:[NSString stringWithFormat:@"V%ld", (long)voice]];
  [_instrumentVoicePopUp setToolTip:@"Notation voice whose sound is being selected"];
  [_instrumentVoicePopUp setTarget:self];
  [_instrumentVoicePopUp setAction:@selector (instrumentVoiceDidChange:)];
  [_instrumentVoicePopUp setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_instrumentVoicePopUp];
  [self rebuildInstrumentPopUpSelectingCurrentSound];

  _separatePartsButton = [[NSButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 132.0, frame.size.height - 364.0, 132.0, 20.0)];
  [_separatePartsButton setTitle:@"Separate Part Staves"];
  [_separatePartsButton setButtonType:ScoreMakerSwitchButton];
  [_separatePartsButton setState:ScoreMakerStateOn];
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
    initWithFrame:NSMakeRect (InspectorPadding, frame.size.height - 578.0, 128.0, 26.0)
        pullsDown:NO];
  NSArray *keyNames = [NSArray arrayWithObjects:
    @"C major", @"G major", @"D major", @"A major", @"E major", @"B major", @"F♯ major",
    @"C♯ major", @"F major", @"B♭ major", @"E♭ major", @"A♭ major", @"D♭ major",
    @"G♭ major", @"C♭ major", @"A minor", @"E minor", @"B minor", @"F♯ minor",
    @"C♯ minor", @"G♯ minor", @"D♯ minor", @"A♯ minor", @"D minor", @"G minor",
    @"C minor", @"F minor", @"B♭ minor", @"E♭ minor", @"A♭ minor", nil];
  NSInteger keyValues[] = { 0, 1, 2, 3, 4, 5, 6, 7, -1, -2, -3, -4, -5, -6, -7,
                            0, 1, 2, 3, 4, 5, 6, 7, -1, -2, -3, -4, -5, -6, -7 };
  for (NSUInteger i = 0; i < [keyNames count]; i++)
    {
      [_keySignaturePopUp addItemWithTitle:[keyNames objectAtIndex:i]];
      [[_keySignaturePopUp lastItem] setRepresentedObject:
        [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInteger:keyValues[i]],
                                                   @"fifths", i < 15 ? @"major" : @"minor",
                                                   @"mode", nil]];
    }
  [_keySignaturePopUp setTarget:self];
  [_keySignaturePopUp setAction:@selector (notationDidChange:)];
  [_keySignaturePopUp setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_keySignaturePopUp];
  _repeatStartButton = [[NSButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 138.0, frame.size.height - 578.0, 72.0, 24.0)];
  [_repeatStartButton setTitle:@"Start |:"];
  [_repeatStartButton setButtonType:ScoreMakerSwitchButton];
  [_repeatStartButton setTarget:self];
  [_repeatStartButton setAction:@selector (notationDidChange:)];
  [_repeatStartButton setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_repeatStartButton];
  _repeatEndButton = [[NSButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 210.0, frame.size.height - 578.0, 72.0, 24.0)];
  [_repeatEndButton setTitle:@"End :|"];
  [_repeatEndButton setButtonType:ScoreMakerSwitchButton];
  [_repeatEndButton setTarget:self];
  [_repeatEndButton setAction:@selector (notationDidChange:)];
  [_repeatEndButton setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_repeatEndButton];

  _tieStartButton = [[NSButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding, frame.size.height - 606.0, 72.0, 24.0)];
  [_tieStartButton setTitle:@"Tie start"];
  [_tieStartButton setButtonType:ScoreMakerSwitchButton];
  [_tieStartButton setTarget:self];
  [_tieStartButton setAction:@selector (notationDidChange:)];
  [_tieStartButton setAutoresizingMask:NSViewMinYMargin];
  [[self inspectorView] addSubview:_tieStartButton];
  _tieEndButton = [[NSButton alloc]
    initWithFrame:NSMakeRect (InspectorPadding + 76.0, frame.size.height - 606.0, 70.0, 24.0)];
  [_tieEndButton setTitle:@"Tie end"];
  [_tieEndButton setButtonType:ScoreMakerSwitchButton];
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
  [_instrumentVoicePopUp setEnabled:hasDocument];
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
        if ([[[item representedObject] objectForKey:@"fifths"] integerValue]
              == [selectedMeasure keySignatureFifths] &&
            [[[item representedObject] objectForKey:@"mode"] isEqualToString:[selectedMeasure keyMode]])
          {
            [_keySignaturePopUp selectItem:item];
            break;
          }
      [_repeatStartButton setState:[selectedMeasure repeatStart] ? ScoreMakerStateOn : ScoreMakerStateOff];
      [_repeatEndButton setState:[selectedMeasure repeatEnd] ? ScoreMakerStateOn : ScoreMakerStateOff];
    }
  [_tieStartButton setState:selectedNote && [selectedNote tieStart] ? ScoreMakerStateOn : ScoreMakerStateOff];
  [_tieEndButton setState:selectedNote && [selectedNote tieEnd] ? ScoreMakerStateOn : ScoreMakerStateOff];
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
  NSMutableSet *noteTrackSet = [NSMutableSet set];
  [partSet addObjectsFromArray:[[document partNames] allKeys]];
  [partSet addObjectsFromArray:[[document trackPrograms] allKeys]];
  NSEnumerator *partNoteEnumerator = [[document notes] objectEnumerator];
  ScoreNote *partNote = nil;
  NSInteger firstNoteTrack = NSIntegerMax;
  while ((partNote = [partNoteEnumerator nextObject]) != nil)
    {
      [partSet addObject:[NSNumber numberWithInteger:[partNote track]]];
      [noteTrackSet addObject:[NSNumber numberWithInteger:[partNote track]]];
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
  if (viewedPart && [noteTrackSet count] && ![noteTrackSet containsObject:viewedPart])
    selectedPart = [[[[noteTrackSet allObjects] sortedArrayUsingSelector:@selector (compare:)]
      objectAtIndex:0] integerValue];
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
  [self rebuildInstrumentPopUpSelectingCurrentSound];
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
  [self rebuildInstrumentPopUpSelectingCurrentSound];
  [self commitUndoBaseline];
}

- (void)partDidChange:(id)sender
{
  (void)sender;
  NSInteger part = [self selectedPartNumber];
  [self rebuildInstrumentPopUpSelectingCurrentSound];
  [_playbackMonitorView setSelectedTrack:part];
  for (ScorePartDefinition *definition in [[self scoreDocument] parts])
    if ([definition legacyTrack] == part)
      {
        [_realtimeDSP configureEffectsFromGraph:[definition synthesisGraph] error:NULL];
        NSString *backend = [[definition instrument] backendIdentifier];
        if ([backend isEqualToString:@"scoremaker-internal-synth"])
          {
            [_realtimeDSP useInternalSynthesizer];
            [self configureVoicePatchesForPart:definition];
            _audioUnitPartTrack = -1;
            _useRealtimeDSP = YES;
          }
        if ([[_realtimeDSP effectConfiguration] count])
          _useRealtimeDSP = YES;
        break;
      }
  if (_patchEditorWindow)
    [self loadPatchEditorControls];
}

- (void)scoreDisplayModeDidChange:(id)sender
{
  (void)sender;
  [[self scoreView] setSeparateParts:[_separatePartsButton state] == ScoreMakerStateOn];
}

- (void)instrumentDidChange:(id)sender
{
  (void)sender;
  ScoreDocument *document = [self scoreDocument];
  if (!document)
    return;
  NSDictionary *selection = [[_instrumentPopUp selectedItem] representedObject];
  NSString *kind = [selection objectForKey:@"kind"];
  if ([kind isEqualToString:@"audio-unit"])
    {
      [self chooseAudioUnitInstrument:self];
      [self rebuildInstrumentPopUpSelectingCurrentSound];
      return;
    }
  if ([kind isEqualToString:@"custom"] || !kind)
    return;
  [self registerUndoSnapshotWithName:@"Change Instrument"];
  ScorePartDefinition *part = [self selectedStructuredPartCreatingIfNeeded:YES];
  if ([kind isEqualToString:@"gm"])
    {
      [document setProgram:[selection objectForKey:@"program"] forTrack:[self selectedPartNumber]];
      [[part instrument] setBackendIdentifier:@"general-midi"];
    }
  else if ([kind isEqualToString:@"synth"])
    {
      NSString *name = [selection objectForKey:@"name"];
      NSDictionary *patch = [[self availableInternalSynthPatchLibrary] objectForKey:name];
      NSInteger voice = [self selectedPatchVoice];
      [_realtimeDSP useInternalSynthesizer];
      [_realtimeDSP configureInternalSynthPatch:patch forVoice:voice error:NULL];
      NSMutableDictionary *parameters = [NSMutableDictionary
        dictionaryWithDictionary:[[part instrument] parameters] ?: [NSDictionary dictionary]];
      NSMutableDictionary *patches = [NSMutableDictionary
        dictionaryWithDictionary:[parameters objectForKey:@"internalSynthPatches"]
                                   ?: [NSDictionary dictionary]];
      NSDictionary *normalized = [_realtimeDSP internalSynthPatchForVoice:voice];
      [patches setObject:normalized forKey:[NSString stringWithFormat:@"%ld", (long)voice]];
      [parameters setObject:patches forKey:@"internalSynthPatches"];
      if (voice == 1)
        [parameters setObject:normalized forKey:@"internalSynthPatch"];
      [[part instrument] setParameters:parameters];
      [[part instrument] setBackendIdentifier:@"scoremaker-internal-synth"];
      _audioUnitPartTrack = -1;
      _useRealtimeDSP = YES;
      if (_patchEditorWindow)
        [self loadPatchEditorControls];
    }
  [_playbackMonitorView setNeedsDisplay:YES];
  [self updateChangeCount:NSChangeDone];
  [self commitUndoBaseline];
  [self rebuildInstrumentPopUpSelectingCurrentSound];
}

- (void)instrumentVoiceDidChange:(id)sender
{
  (void)sender;
  if (_patchVoicePopUp)
    [_patchVoicePopUp selectItemAtIndex:[_instrumentVoicePopUp indexOfSelectedItem]];
  if (_patchEditorWindow)
    [self loadPatchEditorControls];
  [self rebuildInstrumentPopUpSelectingCurrentSound];
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
  ScoreNote *note = [[self scoreView] selectedNote];
  if (note && ![note isRest])
    [_playbackMonitorView setInputPitch:[note pitch]];
  else
    [_playbackMonitorView resetInputPitch];
  if (_scoreSourceEditorWindow && [_scoreSourceEditorWindow isVisible] &&
      !_scoreSourceEditorDirty)
    {
      NSValue *value = [self sourceRangeForScoreNote:note];
      if (value)
        {
          _updatingScoreSourceEditor = YES;
#if defined(__APPLE__)
          [_scoreSourceTextView setSelectedRange:[value rangeValue]];
          [_scoreSourceTextView scrollRangeToVisible:[value rangeValue]];
#else
          [self setScoreSourceSelectedRange:[value rangeValue]
                             selectionColor:nil
                preservingHorizontalScroll:YES];
#endif
          _updatingScoreSourceEditor = NO;
        }
    }
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
      NSDictionary *key = [[_keySignaturePopUp selectedItem] representedObject];
      [measure setKeySignatureFifths:[[key objectForKey:@"fifths"] integerValue]];
      [measure setKeyMode:[key objectForKey:@"mode"]];
      [measure setRepeatStart:[_repeatStartButton state] == ScoreMakerStateOn];
      [measure setRepeatEnd:[_repeatEndButton state] == ScoreMakerStateOn];
    }
  if (note)
    {
      [note setTieStart:[_tieStartButton state] == ScoreMakerStateOn];
      [note setTieEnd:[_tieEndButton state] == ScoreMakerStateOn];
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
      SInt32 uniqueID = 0;
      MIDIObjectGetIntegerProperty (endpoint, kMIDIPropertyUniqueID, &uniqueID);
      [outputs
        addObject:[NSDictionary
                    dictionaryWithObjectsAndKeys:ScoreMakerMIDIEndpointName (endpoint), @"name",
                                                 [NSNumber numberWithUnsignedInt:endpoint],
                                                 @"endpoint",
                                                 [NSNumber numberWithInt:uniqueID], @"uniqueID", nil]];
    }
  return outputs;
}

- (MIDIEndpointRef)resolvedMIDIEndpointWithUniqueID:(NSInteger)uniqueID name:(NSString *)name
{
  if (uniqueID == 0)
    return 0;
  NSArray *outputs = [self availableMIDIOutputs];
  for (NSDictionary *output in outputs)
    if ([[output objectForKey:@"uniqueID"] integerValue] == uniqueID)
      return [[output objectForKey:@"endpoint"] unsignedIntValue];
  for (NSDictionary *output in outputs)
    if ([name length] && [[output objectForKey:@"name"] isEqualToString:name])
      return [[output objectForKey:@"endpoint"] unsignedIntValue];
  return 0;
}

- (MIDIEndpointRef)resolvedPrimaryMIDIOutputForPart:(ScorePartDefinition *)part
{
  return part ? [self resolvedMIDIEndpointWithUniqueID:[part midiOutputUniqueID]
                                                  name:[part midiOutputName]] : 0;
}

- (BOOL)routingPrimaryIsAvailableForPart:(ScorePartDefinition *)part
{
  return part && ([part midiOutputUniqueID] == 0
                  || [self resolvedPrimaryMIDIOutputForPart:part] != 0);
}

- (BOOL)routingShouldMutePart:(ScorePartDefinition *)part
{
  if ([self routingPrimaryIsAvailableForPart:part])
    return NO;
  if ([[part midiFallbackMode] isEqualToString:@"silent"])
    return YES;
  return [[part midiFallbackMode] isEqualToString:@"device"]
         && [self resolvedMIDIEndpointWithUniqueID:[part midiFallbackUniqueID]
                                              name:[part midiFallbackName]] == 0;
}

- (MIDIEndpointRef)resolvedMIDIOutputForPart:(ScorePartDefinition *)part
{
  if (!part || [part midiOutputUniqueID] == 0)
    return 0;
  MIDIEndpointRef primary = [self resolvedPrimaryMIDIOutputForPart:part];
  if (primary || [self routingPrimaryIsAvailableForPart:part])
    return primary;
  if ([[part midiFallbackMode] isEqualToString:@"device"])
    return [self resolvedMIDIEndpointWithUniqueID:[part midiFallbackUniqueID]
                                             name:[part midiFallbackName]];
  return 0;
}

- (NSInteger)routingChannelForPart:(ScorePartDefinition *)part
{
  for (ScoreNote *note in [[self scoreDocument] notes])
    if ([note track] == [part legacyTrack])
      return MIN ((NSInteger)15, MAX ((NSInteger)0, [note channel]));
  return MIN ((NSInteger)15, MAX ((NSInteger)0, [part legacyTrack] % 16));
}

- (void)restartPlaybackAfterRoutingChange
{
  if (_playbackTimer || _playbackPaused)
    {
      NSTimeInterval elapsed = _playbackPaused
                                 ? _playbackPausedElapsed
                                 : ([NSDate timeIntervalSinceReferenceDate] - _playbackStartTime);
      ScoreScheduler *scheduler =
        [[[ScoreScheduler alloc] initWithDocument:[self scoreDocument]] autorelease];
      [self restartPlaybackAtTick:[scheduler tickForTime:elapsed]];
    }
}

- (void)routingDeviceChanged:(NSPopUpButton *)sender
{
  NSInteger row = [sender tag];
  if (row < 0 || row >= (NSInteger)[[[self scoreDocument] parts] count])
    return;
  ScorePartDefinition *part = [[[self scoreDocument] parts] objectAtIndex:(NSUInteger)row];
  NSDictionary *selection = [[sender selectedItem] representedObject];
  NSInteger uniqueID = [[selection objectForKey:@"uniqueID"] integerValue];
  NSString *name = [selection objectForKey:@"name"];
  if ([part midiOutputUniqueID] == uniqueID
      && ((![[part midiOutputName] length] && ![name length])
          || [[part midiOutputName] isEqualToString:name]))
    return;
  [self registerUndoSnapshotWithName:@"Change MIDI Routing"];
  [part setMidiOutputUniqueID:uniqueID];
  [part setMidiOutputName:[name length] ? name : nil];
  [self updateChangeCount:NSChangeDone];
  [self commitUndoBaseline];
  [self refreshRoutingMatrix];
  [self restartPlaybackAfterRoutingChange];
}

- (void)routingChannelChanged:(NSPopUpButton *)sender
{
  NSInteger row = [sender tag];
  if (row < 0 || row >= (NSInteger)[[[self scoreDocument] parts] count])
    return;
  ScorePartDefinition *part = [[[self scoreDocument] parts] objectAtIndex:(NSUInteger)row];
  NSInteger channel = [sender indexOfSelectedItem];
  if ([self routingChannelForPart:part] == channel)
    return;
  [self registerUndoSnapshotWithName:@"Change MIDI Channel"];
  for (ScoreNote *note in [[self scoreDocument] notes])
    if ([note track] == [part legacyTrack])
      [note setChannel:channel];
  for (ScoreMIDIRoute *route in [[self scoreDocument] midiRoutes])
    if ([[route destinationPartIdentifier] isEqualToString:[part identifier]])
      [route setDestinationChannel:channel];
  [self updateChangeCount:NSChangeDone];
  [self commitUndoBaseline];
  [[self scoreView] reloadDocument];
  [self restartPlaybackAfterRoutingChange];
}

- (void)routingProgramChanged:(NSPopUpButton *)sender
{
  NSInteger row = [sender tag];
  if (row < 0 || row >= (NSInteger)[[[self scoreDocument] parts] count])
    return;
  ScorePartDefinition *part = [[[self scoreDocument] parts] objectAtIndex:(NSUInteger)row];
  NSInteger program = [sender indexOfSelectedItem];
  if ([[[self scoreDocument] programForTrack:[part legacyTrack]] integerValue] == program)
    return;
  [self registerUndoSnapshotWithName:@"Change MIDI Program"];
  [[self scoreDocument] setProgram:[NSNumber numberWithInteger:program]
                          forTrack:[part legacyTrack]];
  [[part instrument] setProgram:program];
  [self updateChangeCount:NSChangeDone];
  [self commitUndoBaseline];
  [self refreshInspector];
  [self restartPlaybackAfterRoutingChange];
}

- (void)routingFallbackChanged:(NSPopUpButton *)sender
{
  NSInteger row = [sender tag];
  if (row < 0 || row >= (NSInteger)[[[self scoreDocument] parts] count])
    return;
  ScorePartDefinition *part = [[[self scoreDocument] parts] objectAtIndex:(NSUInteger)row];
  NSDictionary *selection = [[sender selectedItem] representedObject];
  [self registerUndoSnapshotWithName:@"Change MIDI Fallback"];
  [part setMidiFallbackMode:[selection objectForKey:@"mode"] ?: @"builtin"];
  [part setMidiFallbackUniqueID:[[selection objectForKey:@"uniqueID"] integerValue]];
  NSString *name = [selection objectForKey:@"name"];
  [part setMidiFallbackName:[name length] ? name : nil];
  [self updateChangeCount:NSChangeDone];
  [self commitUndoBaseline];
  [self refreshRoutingMatrix];
  [self restartPlaybackAfterRoutingChange];
}

- (void)routingSelectionChanged:(NSButton *)sender
{
  if (!_routingMatrixSelection)
    _routingMatrixSelection = [[NSMutableIndexSet alloc] init];
  if ([sender state] == NSControlStateValueOn)
    [_routingMatrixSelection addIndex:(NSUInteger)[sender tag]];
  else
    [_routingMatrixSelection removeIndex:(NSUInteger)[sender tag]];
}

- (void)routingSelectAll:(id)sender
{
  (void)sender;
  if (!_routingMatrixSelection)
    _routingMatrixSelection = [[NSMutableIndexSet alloc] init];
  NSUInteger count = [[[self scoreDocument] parts] count];
  if ([_routingMatrixSelection count] == count)
    [_routingMatrixSelection removeAllIndexes];
  else
    {
      [_routingMatrixSelection removeAllIndexes];
      if (count)
        [_routingMatrixSelection addIndexesInRange:NSMakeRange (0, count)];
    }
  [self refreshRoutingMatrix];
}

- (BOOL)routingRequireBulkSelection
{
  if ([_routingMatrixSelection count])
    return YES;
  NSBeep ();
  [_routingMatrixSummaryLabel setStringValue:@"Select one or more parts before applying a bulk action."];
  return NO;
}

- (void)routingApplyBulkDevice:(id)sender
{
  (void)sender;
  if (![self routingRequireBulkSelection])
    return;
  NSDictionary *selection = [[_routingBulkDevicePopUp selectedItem] representedObject];
  [self registerUndoSnapshotWithName:@"Route Selected Parts"];
  NSArray *parts = [[self scoreDocument] parts];
  NSUInteger row = [_routingMatrixSelection firstIndex];
  while (row != NSNotFound)
    {
      ScorePartDefinition *part = [parts objectAtIndex:row];
      [part setMidiOutputUniqueID:[[selection objectForKey:@"uniqueID"] integerValue]];
      NSString *name = [selection objectForKey:@"name"];
      [part setMidiOutputName:[name length] ? name : nil];
      row = [_routingMatrixSelection indexGreaterThanIndex:row];
    }
  [self updateChangeCount:NSChangeDone];
  [self commitUndoBaseline];
  [self refreshRoutingMatrix];
  [self restartPlaybackAfterRoutingChange];
}

- (void)setRoutingChannel:(NSInteger)channel forPart:(ScorePartDefinition *)part
{
  for (ScoreNote *note in [[self scoreDocument] notes])
    if ([note track] == [part legacyTrack])
      [note setChannel:channel];
  for (ScoreMIDIRoute *route in [[self scoreDocument] midiRoutes])
    if ([[route destinationPartIdentifier] isEqualToString:[part identifier]])
      [route setDestinationChannel:channel];
}

- (void)routingAssignSequentialChannels:(id)sender
{
  (void)sender;
  if (![self routingRequireBulkSelection])
    return;
  [self registerUndoSnapshotWithName:@"Assign Sequential MIDI Channels"];
  NSArray *parts = [[self scoreDocument] parts];
  NSUInteger sequence = 0;
  NSUInteger row = [_routingMatrixSelection firstIndex];
  while (row != NSNotFound)
    {
      [self setRoutingChannel:(NSInteger)(sequence % 16) forPart:[parts objectAtIndex:row]];
      sequence++;
      row = [_routingMatrixSelection indexGreaterThanIndex:row];
    }
  [self updateChangeCount:NSChangeDone];
  [self commitUndoBaseline];
  [[self scoreView] reloadDocument];
  [self refreshRoutingMatrix];
  [self restartPlaybackAfterRoutingChange];
}

- (void)routingResetSelected:(id)sender
{
  (void)sender;
  if (![self routingRequireBulkSelection])
    return;
  [self registerUndoSnapshotWithName:@"Reset MIDI Routing"];
  NSArray *parts = [[self scoreDocument] parts];
  NSUInteger row = [_routingMatrixSelection firstIndex];
  while (row != NSNotFound)
    {
      ScorePartDefinition *part = [parts objectAtIndex:row];
      [part setMidiOutputUniqueID:0];
      [part setMidiOutputName:nil];
      [part setMidiFallbackMode:@"builtin"];
      [part setMidiFallbackUniqueID:0];
      [part setMidiFallbackName:nil];
      [self setRoutingChannel:[part legacyTrack] % 16 forPart:part];
      row = [_routingMatrixSelection indexGreaterThanIndex:row];
    }
  [self updateChangeCount:NSChangeDone];
  [self commitUndoBaseline];
  [[self scoreView] reloadDocument];
  [self refreshRoutingMatrix];
  [self restartPlaybackAfterRoutingChange];
}

- (NSTextField *)routingLabelWithFrame:(NSRect)frame
                                  text:(NSString *)text
                                  font:(NSFont *)font
                                 color:(NSColor *)color
{
  NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
  [label setStringValue:text ?: @""];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setBordered:NO];
  [label setDrawsBackground:NO];
  [label setFont:font];
  [label setTextColor:color ?: [NSColor labelColor]];
  return label;
}

- (void)refreshRoutingMatrix
{
  if (!_routingMatrixRowsView)
    return;
  for (NSView *view in [[[_routingMatrixRowsView subviews] copy] autorelease])
    [view removeFromSuperview];

  NSArray *parts = [[self scoreDocument] parts];
  NSArray *outputs = [self availableMIDIOutputs];
  NSArray *programNames = [MidiParser generalMidiProgramNames];
  CGFloat rowHeight = 48.0;
  CGFloat width = 1080.0;
  [_routingMatrixRowsView setFrameSize:NSMakeSize (width, MAX (rowHeight, rowHeight * [parts count]))];
  if (!_routingMatrixSelection)
    _routingMatrixSelection = [[NSMutableIndexSet alloc] init];
  [_routingMatrixSelection removeIndexesInRange:NSMakeRange ([parts count],
                                                              NSUIntegerMax - [parts count])];
  NSMutableDictionary *routeCounts = [NSMutableDictionary dictionary];
  for (ScorePartDefinition *part in parts)
    {
      if ([self routingShouldMutePart:part])
        continue;
      NSInteger effectiveDevice = [part midiOutputUniqueID];
      if (![self routingPrimaryIsAvailableForPart:part])
        effectiveDevice = ([[part midiFallbackMode] isEqualToString:@"device"]
                           && [self resolvedMIDIOutputForPart:part] != 0)
                            ? [part midiFallbackUniqueID] : 0;
      NSString *key = [NSString stringWithFormat:@"%ld:%ld", (long)effectiveDevice,
                                                       (long)[self routingChannelForPart:part]];
      [routeCounts setObject:@([[routeCounts objectForKey:key] unsignedIntegerValue] + 1)
                     forKey:key];
    }
  NSUInteger connectedCount = 0;
  NSUInteger conflictCount = 0;
  for (NSUInteger row = 0; row < [parts count]; row++)
    {
      ScorePartDefinition *part = [parts objectAtIndex:row];
      CGFloat y = row * rowHeight;
      if (row % 2)
        {
          NSBox *stripe = [[[NSBox alloc] initWithFrame:NSMakeRect (0, y, width, rowHeight)] autorelease];
          [stripe setBoxType:NSBoxCustom];
          [stripe setBorderWidth:0.0];
          NSArray *alternatingColors = [NSColor alternatingContentBackgroundColors];
          [stripe setFillColor:[alternatingColors count] > 1
                                 ? [alternatingColors objectAtIndex:1]
                                 : [NSColor controlBackgroundColor]];
          [stripe setTitlePosition:NSNoTitle];
          [_routingMatrixRowsView addSubview:stripe];
        }
      NSString *partName = [[part name] length] ? [part name]
                                                 : [NSString stringWithFormat:@"Part %lu", (unsigned long)row + 1];
      NSButton *selected = [[[NSButton alloc] initWithFrame:NSMakeRect (8, y + 11, 22, 24)] autorelease];
      [selected setButtonType:ScoreMakerSwitchButton];
      [selected setTitle:@""];
      [selected setState:[_routingMatrixSelection containsIndex:row] ? NSControlStateValueOn
                                                                     : NSControlStateValueOff];
      [selected setTag:(NSInteger)row];
      [selected setTarget:self];
      [selected setAction:@selector (routingSelectionChanged:)];
      [_routingMatrixRowsView addSubview:selected];
      [_routingMatrixRowsView addSubview:[self routingLabelWithFrame:NSMakeRect (36, y + 14, 148, 20)
                                                               text:partName
                                                               font:[NSFont systemFontOfSize:13.0]
                                                              color:nil]];

      NSPopUpButton *device = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (184, y + 9, 250, 28)
                                                          pullsDown:NO] autorelease];
      [device addItemWithTitle:@"Built-in Synthesizer"];
      [[device lastItem] setRepresentedObject:@{ @"uniqueID" : @0, @"name" : @"" }];
      BOOL found = ([part midiOutputUniqueID] == 0);
      for (NSDictionary *output in outputs)
        {
          [device addItemWithTitle:[output objectForKey:@"name"]];
          [[device lastItem] setRepresentedObject:output];
          if ([[output objectForKey:@"uniqueID"] integerValue] == [part midiOutputUniqueID])
            {
              found = YES;
              [device selectItem:[device lastItem]];
            }
        }
      if (!found)
        {
          NSString *name = [[part midiOutputName] length] ? [part midiOutputName] : @"Unknown device";
          [device addItemWithTitle:[NSString stringWithFormat:@"Missing — %@", name]];
          [[device lastItem] setRepresentedObject:@{ @"uniqueID" : @([part midiOutputUniqueID]),
                                                      @"name" : name }];
          [device selectItem:[device lastItem]];
        }
      else if ([part midiOutputUniqueID] == 0)
        [device selectItemAtIndex:0];
      [device setTag:(NSInteger)row];
      [device setTarget:self];
      [device setAction:@selector (routingDeviceChanged:)];
      [_routingMatrixRowsView addSubview:device];

      NSPopUpButton *channel = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (446, y + 9, 88, 28)
                                                           pullsDown:NO] autorelease];
      for (NSInteger index = 1; index <= 16; index++)
        [channel addItemWithTitle:[NSString stringWithFormat:@"Ch %ld", (long)index]];
      [channel selectItemAtIndex:[self routingChannelForPart:part]];
      [channel setTag:(NSInteger)row];
      [channel setTarget:self];
      [channel setAction:@selector (routingChannelChanged:)];
      [_routingMatrixRowsView addSubview:channel];

      NSPopUpButton *program = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (546, y + 9, 216, 28)
                                                           pullsDown:NO] autorelease];
      for (NSUInteger index = 0; index < [programNames count]; index++)
        [program addItemWithTitle:[NSString stringWithFormat:@"%lu · %@", (unsigned long)index + 1,
                                                            [programNames objectAtIndex:index]]];
      NSInteger selectedProgram = [[[self scoreDocument] programForTrack:[part legacyTrack]] integerValue];
      [program selectItemAtIndex:MIN ((NSInteger)127, MAX ((NSInteger)0, selectedProgram))];
      [program setTag:(NSInteger)row];
      [program setTarget:self];
      [program setAction:@selector (routingProgramChanged:)];
      [_routingMatrixRowsView addSubview:program];

      BOOL internal = [part midiOutputUniqueID] == 0;
      BOOL primaryAvailable = [self routingPrimaryIsAvailableForPart:part];
      BOOL connected = primaryAvailable || [self resolvedMIDIOutputForPart:part] != 0
                       || (![[part midiFallbackMode] isEqualToString:@"silent"]
                           && ![[part midiFallbackMode] isEqualToString:@"device"]);
      if (connected)
        connectedCount++;
      NSInteger effectiveDevice = [part midiOutputUniqueID];
      if (!primaryAvailable)
        effectiveDevice = ([[part midiFallbackMode] isEqualToString:@"device"]
                           && [self resolvedMIDIOutputForPart:part] != 0)
                            ? [part midiFallbackUniqueID] : 0;
      NSString *routeKey = [NSString stringWithFormat:@"%ld:%ld", (long)effectiveDevice,
                                                            (long)[self routingChannelForPart:part]];
      BOOL conflict = ![self routingShouldMutePart:part]
                      && [[routeCounts objectForKey:routeKey] unsignedIntegerValue] > 1;
      if (conflict)
        conflictCount++;
      NSString *status = conflict
                           ? [NSString stringWithFormat:@"⚠ Ch %ld conflict",
                                                        (long)[self routingChannelForPart:part] + 1]
                           : (internal ? @"●  Internal"
                                       : (primaryAvailable ? @"●  Connected"
                                                           : ([self routingShouldMutePart:part]
                                                                ? @"●  Muted" : @"●  Fallback")));
      NSColor *statusColor = conflict ? [NSColor systemOrangeColor]
                                      : (connected ? [NSColor systemGreenColor]
                                                   : [NSColor systemRedColor]);
      [_routingMatrixRowsView addSubview:[self routingLabelWithFrame:NSMakeRect (778, y + 14, 126, 20)
                                                               text:status
                                                               font:[NSFont systemFontOfSize:12.0]
                                                              color:statusColor]];
      NSPopUpButton *fallback = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (914, y + 9, 154, 28)
                                                            pullsDown:NO] autorelease];
      [fallback addItemWithTitle:@"Built-in Synth"];
      [[fallback lastItem] setRepresentedObject:@{ @"mode" : @"builtin", @"uniqueID" : @0,
                                                    @"name" : @"" }];
      [fallback addItemWithTitle:@"Mute Part"];
      [[fallback lastItem] setRepresentedObject:@{ @"mode" : @"silent", @"uniqueID" : @0,
                                                    @"name" : @"" }];
      for (NSDictionary *output in outputs)
        {
          [fallback addItemWithTitle:[output objectForKey:@"name"]];
          [[fallback lastItem] setRepresentedObject:@{ @"mode" : @"device",
                                                        @"uniqueID" : [output objectForKey:@"uniqueID"],
                                                        @"name" : [output objectForKey:@"name"] }];
          if ([[part midiFallbackMode] isEqualToString:@"device"]
              && [[output objectForKey:@"uniqueID"] integerValue] == [part midiFallbackUniqueID])
            [fallback selectItem:[fallback lastItem]];
        }
      if ([[part midiFallbackMode] isEqualToString:@"silent"])
        [fallback selectItemAtIndex:1];
      else if (![[part midiFallbackMode] isEqualToString:@"device"])
        [fallback selectItemAtIndex:0];
      else if ([part midiFallbackUniqueID] != 0
               && [self resolvedMIDIEndpointWithUniqueID:[part midiFallbackUniqueID]
                                                    name:[part midiFallbackName]] == 0)
        {
          NSString *name = [[part midiFallbackName] length] ? [part midiFallbackName] : @"Unknown device";
          [fallback addItemWithTitle:[NSString stringWithFormat:@"Missing — %@", name]];
          [[fallback lastItem] setRepresentedObject:@{ @"mode" : @"device",
                                                        @"uniqueID" : @([part midiFallbackUniqueID]),
                                                        @"name" : name }];
          [fallback selectItem:[fallback lastItem]];
        }
      [fallback setEnabled:!internal];
      [fallback setTag:(NSInteger)row];
      [fallback setTarget:self];
      [fallback setAction:@selector (routingFallbackChanged:)];
      [_routingMatrixRowsView addSubview:fallback];
    }
  if (_routingBulkDevicePopUp)
    {
      NSInteger previousID = [[[_routingBulkDevicePopUp selectedItem] representedObject][@"uniqueID"] integerValue];
      [_routingBulkDevicePopUp removeAllItems];
      [_routingBulkDevicePopUp addItemWithTitle:@"Built-in Synthesizer"];
      [[_routingBulkDevicePopUp lastItem] setRepresentedObject:@{ @"uniqueID" : @0, @"name" : @"" }];
      for (NSDictionary *output in outputs)
        {
          [_routingBulkDevicePopUp addItemWithTitle:[output objectForKey:@"name"]];
          [[_routingBulkDevicePopUp lastItem] setRepresentedObject:output];
          if ([[output objectForKey:@"uniqueID"] integerValue] == previousID)
            [_routingBulkDevicePopUp selectItem:[_routingBulkDevicePopUp lastItem]];
        }
    }
  [_routingMatrixSummaryLabel
    setStringValue:[NSString stringWithFormat:@"%lu parts · %lu active · %lu conflicts · %lu devices",
                                              (unsigned long)[parts count], (unsigned long)connectedCount,
                                              (unsigned long)conflictCount, (unsigned long)[outputs count]]];
}

- (void)chooseMIDIOutput:(id)sender
{
  (void)sender;
  if (!_routingMatrixWindow)
    {
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
      NSUInteger style = ScoreMakerWindowTitled | ScoreMakerWindowClosable | ScoreMakerWindowResizable;
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
      _routingMatrixWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect (160, 160, 1080, 560)
                                                         styleMask:style
                                                           backing:NSBackingStoreBuffered
                                                             defer:NO];
      [_routingMatrixWindow setReleasedWhenClosed:NO];
      [_routingMatrixWindow setMinSize:NSMakeSize (900, 360)];
      [_routingMatrixWindow setTitle:@"Routing Matrix"];
      NSView *content = [_routingMatrixWindow contentView];
      NSTextField *title = [self routingLabelWithFrame:NSMakeRect (20, 516, 500, 28)
                                                  text:@"Score routing"
                                                  font:[NSFont boldSystemFontOfSize:20.0]
                                                 color:nil];
      [title setAutoresizingMask:NSViewMinYMargin];
      [content addSubview:title];
      NSTextField *subtitle = [self routingLabelWithFrame:NSMakeRect (20, 492, 760, 20)
                                                     text:@"Route every part without leaving the score. Changes are saved with this project."
                                                     font:[NSFont systemFontOfSize:12.0]
                                                    color:[NSColor secondaryLabelColor]];
      [subtitle setAutoresizingMask:NSViewMinYMargin];
      [content addSubview:subtitle];
      NSArray *headers = @[ @[ @"PART", @12, @172 ], @[ @"DEVICE", @184, @250 ],
                             @[ @"CHANNEL", @446, @88 ], @[ @"PROGRAM", @546, @216 ],
                             @[ @"CONNECTION", @778, @126 ], @[ @"FALLBACK", @914, @154 ] ];
      for (NSArray *header in headers)
        {
          NSTextField *label = [self routingLabelWithFrame:NSMakeRect ([[header objectAtIndex:1] doubleValue], 460,
                                                                       [[header objectAtIndex:2] doubleValue], 18)
                                                       text:[header objectAtIndex:0]
                                                       font:[NSFont boldSystemFontOfSize:10.0]
                                                      color:[NSColor secondaryLabelColor]];
          [label setAutoresizingMask:NSViewMinYMargin];
          [content addSubview:label];
        }
      NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect (0, 54, 1080, 400)] autorelease];
      [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [scroll setHasVerticalScroller:YES];
      [scroll setHasHorizontalScroller:YES];
      [scroll setBorderType:NSBezelBorder];
      _routingMatrixRowsView = [[ScoreRoutingRowsView alloc] initWithFrame:NSMakeRect (0, 0, 1080, 400)];
      [scroll setDocumentView:_routingMatrixRowsView];
      [content addSubview:scroll];
      _routingMatrixSummaryLabel = [[self routingLabelWithFrame:NSMakeRect (20, 18, 760, 20)
                                                           text:@""
                                                           font:[NSFont systemFontOfSize:12.0]
                                                          color:[NSColor secondaryLabelColor]] retain];
      [_routingMatrixSummaryLabel setAutoresizingMask:NSViewMaxYMargin];
      [content addSubview:_routingMatrixSummaryLabel];
      [_routingMatrixSummaryLabel setFrameSize:NSMakeSize (290, 20)];
      NSButton *selectAll = [[[NSButton alloc] initWithFrame:NSMakeRect (310, 12, 82, 30)] autorelease];
      [selectAll setTitle:@"Select All"];
      [selectAll setTarget:self];
      [selectAll setAction:@selector (routingSelectAll:)];
      [selectAll setAutoresizingMask:NSViewMaxYMargin];
      [content addSubview:selectAll];
      _routingBulkDevicePopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect (400, 13, 190, 28)
                                                              pullsDown:NO];
      [_routingBulkDevicePopUp setAutoresizingMask:NSViewMaxYMargin];
      [content addSubview:_routingBulkDevicePopUp];
      NSButton *apply = [[[NSButton alloc] initWithFrame:NSMakeRect (596, 12, 72, 30)] autorelease];
      [apply setTitle:@"Apply"];
      [apply setToolTip:@"Route every selected part to this device"];
      [apply setTarget:self];
      [apply setAction:@selector (routingApplyBulkDevice:)];
      [apply setAutoresizingMask:NSViewMaxYMargin];
      [content addSubview:apply];
      NSButton *channels = [[[NSButton alloc] initWithFrame:NSMakeRect (674, 12, 142, 30)] autorelease];
      [channels setTitle:@"Sequential Channels"];
      [channels setTarget:self];
      [channels setAction:@selector (routingAssignSequentialChannels:)];
      [channels setAutoresizingMask:NSViewMaxYMargin];
      [content addSubview:channels];
      NSButton *reset = [[[NSButton alloc] initWithFrame:NSMakeRect (822, 12, 94, 30)] autorelease];
      [reset setTitle:@"Reset Routes"];
      [reset setTarget:self];
      [reset setAction:@selector (routingResetSelected:)];
      [reset setAutoresizingMask:NSViewMaxYMargin];
      [content addSubview:reset];
      NSButton *refresh = [[[NSButton alloc] initWithFrame:NSMakeRect (922, 12, 138, 30)] autorelease];
      [refresh setTitle:@"Refresh Devices"];
      [refresh setTarget:self];
      [refresh setAction:@selector (chooseMIDIOutput:)];
      [refresh setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
      [content addSubview:refresh];
    }
  [self refreshRoutingMatrix];
  [_routingMatrixWindow makeKeyAndOrderFront:self];
}

- (BOOL)playMIDIData:(NSData *)midiData toOutput:(MIDIEndpointRef)endpoint error:(NSError **)error
{
  MusicSequence sequence = NULL;
  MusicPlayer player = NULL;
  OSStatus status = NewMusicSequence (&sequence);
  if (status == noErr)
    {
      status = MusicSequenceFileLoadData (sequence, (CFDataRef)midiData,
                                          kMusicSequenceFile_MIDIType,
                                          kMusicSequenceLoadSMF_ChannelsToTracks);
    }
  if (status == noErr)
    status = MusicSequenceSetMIDIEndpoint (sequence, endpoint);
  if (status == noErr)
    status = NewMusicPlayer (&player);
  if (status == noErr)
    status = MusicPlayerSetSequence (player, sequence);
  if (status == noErr)
    status = MusicPlayerPreroll (player);
  if (status == noErr)
    status = MusicPlayerStart (player);
  if (status == noErr)
    {
      [_externalMIDIPlaybacks addObject:@{
        @"player" : [NSValue valueWithPointer:player],
        @"sequence" : [NSValue valueWithPointer:sequence],
        @"endpoint" : [NSNumber numberWithUnsignedInt:endpoint]
      }];
      _externalPlaybackTime = 0;
      return YES;
    }

  if (player)
    DisposeMusicPlayer (player);
  if (sequence)
    DisposeMusicSequence (sequence);
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
#else
- (void)chooseMIDIOutput:(id)sender
{
  (void)sender;
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"Physical MIDI output is unavailable"];
  [alert setInformativeText:@"This GNUstep build continues to use its configured system MIDI player."];
  [alert runModal];
}
#endif

- (void)stopPlaybackAudioOnly
{
#if defined(__APPLE__)
  for (NSDictionary *playback in [[_externalMIDIPlaybacks copy] autorelease])
    {
      MusicPlayer player = (MusicPlayer)[[playback objectForKey:@"player"] pointerValue];
      MusicSequence sequence =
        (MusicSequence)[[playback objectForKey:@"sequence"] pointerValue];
      MIDIEndpointRef endpoint = [[playback objectForKey:@"endpoint"] unsignedIntValue];
      if (player)
        {
          MusicPlayerStop (player);
          DisposeMusicPlayer (player);
        }
      ScoreMakerSendAllNotesOff (endpoint);
      if (sequence)
        DisposeMusicSequence (sequence);
    }
  [_externalMIDIPlaybacks removeAllObjects];
  _externalPlaybackTime = 0;
#endif
  [_playbackSound stop];
  [_playbackSound release];
  _playbackSound = nil;
  [(AVMIDIPlayer *)_midiPlayer stop];
  [_midiPlayer release];
  _midiPlayer = nil;
  [_realtimeDSP allNotesOff];
  if (_playbackUsesRealtimeDSP)
    [_realtimeDSP stop];
  _playbackUsesRealtimeDSP = NO;
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
        @"on" : @YES,
        @"voice" : [NSNumber numberWithInteger:[note voice]]
      }];
  for (ScoreScheduledEvent *event in [scheduler eventsFromTick:tick
                                                   throughTick:[[self scoreDocument] totalTicks]])
    {
      ScoreNote *note = [event note];
      [timeline addObject:@{
        @"time" : [NSNumber numberWithDouble:MAX (0.0, [event time] - origin)],
        @"pitch" : [NSNumber numberWithInteger:[note pitch]],
        @"velocity" : [NSNumber numberWithUnsignedInteger:[note velocity]],
        @"on" : [NSNumber numberWithBool:![event noteOff]],
        @"voice" : [NSNumber numberWithInteger:[note voice]]
      }];
    }
  return [_realtimeDSP scheduleEvents:timeline error:error];
}

#if defined(__APPLE__)
- (BOOL)documentHasPhysicalMIDIRouting:(ScoreDocument *)document
{
  for (ScorePartDefinition *part in [document parts])
    if ([part midiOutputUniqueID] != 0
        || [[part midiFallbackMode] isEqualToString:@"device"])
      return YES;
  return NO;
}

- (ScoreDocument *)documentFromDocument:(ScoreDocument *)source keepingTracks:(NSSet *)tracks
{
  ScoreDocument *filtered = [[source copy] autorelease];
  NSMutableArray *notes = [NSMutableArray array];
  for (ScoreNote *note in [filtered notes])
    if ([tracks containsObject:[NSNumber numberWithInteger:[note track]]])
      [notes addObject:note];
  [filtered setNotes:notes];

  NSMutableDictionary *names = [NSMutableDictionary dictionary];
  NSMutableDictionary *programs = [NSMutableDictionary dictionary];
  for (NSNumber *track in tracks)
    {
      NSString *name = [source nameForTrack:[track integerValue]];
      NSNumber *program = [source programForTrack:[track integerValue]];
      if (name)
        [names setObject:name forKey:track];
      if (program)
        [programs setObject:program forKey:track];
    }
  [filtered setPartNames:names];
  [filtered setTrackPrograms:programs];
  NSMutableArray *parts = [NSMutableArray array];
  for (ScorePartDefinition *part in [source parts])
    if ([tracks containsObject:[NSNumber numberWithInteger:[part legacyTrack]]])
      [parts addObject:[[part copy] autorelease]];
  [filtered setParts:parts];
  return filtered;
}

- (BOOL)playDocumentWithMIDIRouting:(ScoreDocument *)document error:(NSError **)error
{
  NSMutableDictionary *partByTrack = [NSMutableDictionary dictionary];
  for (ScorePartDefinition *part in [document parts])
    [partByTrack setObject:part
                    forKey:[NSNumber numberWithInteger:[part legacyTrack]]];

  NSMutableDictionary *tracksByEndpoint = [NSMutableDictionary dictionary];
  for (ScoreNote *note in [document notes])
    {
      if ([note isRest])
        continue;
      NSNumber *track = [NSNumber numberWithInteger:[note track]];
      ScorePartDefinition *part = [partByTrack objectForKey:track];
      if ([self routingShouldMutePart:part])
        continue;
      MIDIEndpointRef endpoint = [self resolvedMIDIOutputForPart:part];
      NSNumber *endpointKey = [NSNumber numberWithUnsignedInt:endpoint];
      NSMutableSet *tracks = [tracksByEndpoint objectForKey:endpointKey];
      if (!tracks)
        {
          tracks = [NSMutableSet set];
          [tracksByEndpoint setObject:tracks forKey:endpointKey];
        }
      [tracks addObject:track];
    }

  NSMutableArray *payloads = [NSMutableArray array];
  for (NSNumber *endpointKey in tracksByEndpoint)
    {
      ScoreDocument *filtered =
        [self documentFromDocument:document
                    keepingTracks:[tracksByEndpoint objectForKey:endpointKey]];
      NSData *midiData = [MidiParser dataForDocument:filtered error:error];
      if (!midiData)
        return NO;
      [payloads addObject:@{ @"endpoint" : endpointKey, @"data" : midiData }];
    }

  /* Build every endpoint's MIDI data before starting any player. This keeps large scores from
     making the first device audibly lead later devices while their filtered files are encoded. */
  [payloads sortUsingComparator:^NSComparisonResult (NSDictionary *left, NSDictionary *right) {
    return [[left objectForKey:@"endpoint"] compare:[right objectForKey:@"endpoint"]];
  }];
  for (NSDictionary *payload in payloads)
    {
      NSData *midiData = [payload objectForKey:@"data"];
      NSNumber *endpointKey = [payload objectForKey:@"endpoint"];
      MIDIEndpointRef endpoint = [endpointKey unsignedIntValue];
      BOOL started = endpoint ? [self playMIDIData:midiData toOutput:endpoint error:error]
                              : [self playMIDIDataDirectly:midiData error:error];
      if (!started)
        return NO;
    }
  /* A score whose unavailable routes explicitly fall back to Mute is still a valid playback.
     The document timer and visual playhead should continue even when there is no MIDI payload. */
  return YES;
}
#endif

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
  [remainder setParts:[[[NSMutableArray alloc] initWithArray:[source parts] copyItems:YES]
                         autorelease]];

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
  BOOL useRealtimeDSPForPlayback = _useRealtimeDSP;
#if defined(__APPLE__)
  if ([self documentHasPhysicalMIDIRouting:source])
    useRealtimeDSPForPlayback = NO;
#endif
  if (useRealtimeDSPForPlayback)
    {
      [self stopPlaybackAudioOnly];
      _playbackUsesRealtimeDSP = YES;
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
#if !defined(__APPLE__)
  NSData *midiData = [MidiParser dataForDocument:remainder error:&error];
  if (!midiData)
    {
      [[NSDocumentController sharedDocumentController] presentError:error];
      [self stopCurrentPlayback];
      return NO;
    }
#endif

  [self stopPlaybackAudioOnly];
#if defined(__APPLE__)
  if (![self playDocumentWithMIDIRouting:remainder error:&error])
#else
  if (![self playMIDIDataDirectly:midiData error:&error])
#endif
    {
      [[NSDocumentController sharedDocumentController] presentError:error];
      [self stopCurrentPlayback];
      return NO;
    }

  ScoreScheduler *scheduler = [[[ScoreScheduler alloc] initWithDocument:source] autorelease];
  NSTimeInterval adjustedElapsed = [scheduler timeForTick:tick];
  _playbackMIDIOriginTime = adjustedElapsed;
  _playbackStartTime = [NSDate timeIntervalSinceReferenceDate] - adjustedElapsed;
  _playbackPausedElapsed = adjustedElapsed;

  if (wasPaused)
    {
      if (_midiPlayer)
        {
          [(AVMIDIPlayer *)_midiPlayer stop];
          [(AVMIDIPlayer *)_midiPlayer setCurrentPosition:0.0];
        }
#if defined(__APPLE__)
      for (NSDictionary *playback in _externalMIDIPlaybacks)
        {
          MusicPlayer player = (MusicPlayer)[[playback objectForKey:@"player"] pointerValue];
          if (player)
            {
              MusicPlayerStop (player);
              MusicPlayerSetTime (player, 0);
            }
          ScoreMakerSendAllNotesOff ([[playback objectForKey:@"endpoint"] unsignedIntValue]);
        }
#endif
      [_playbackSound pause];
      _playbackPaused = YES;
      [self updatePauseButtonForPaused:YES];
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
  _playbackMIDIOriginTime = 0.0;
  [self updatePauseButtonForPaused:NO];
  [_pauseButton setEnabled:NO];
  [[self scoreView] clearPlayback];
  [_playbackMonitorView clearPlayback];
  [self clearScoreSourcePlaybackHighlight];
  [_scoreSourceActivePlaybackNotes removeAllObjects];
  _scoreSourcePlaybackNoteIndex = 0;
  _scoreSourceLastPlaybackTick = NSNotFound;
  [self stopPlaybackAudioOnly];
  [self stopAudition];
}

- (void)updatePauseButtonForPaused:(BOOL)paused
{
  NSString *label = paused ? @"Resume" : @"Pause";
  [_pauseButton setImage:ScoreMakerTransportImage (paused ? @"resume" : @"pause")];
  [_pauseButton setToolTip:label];
  ScoreMakerSetAccessibilityLabel (_pauseButton, label);
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
  if (_midiPlayer && [(AVMIDIPlayer *)_midiPlayer respondsToSelector:@selector (currentPosition)] &&
      [(AVMIDIPlayer *)_midiPlayer isPlaying])
    elapsed = _playbackMIDIOriginTime + [(AVMIDIPlayer *)_midiPlayer currentPosition];
  ScoreScheduler *scheduler = [[[ScoreScheduler alloc] initWithDocument:document] autorelease];
  NSUInteger tick = [scheduler tickForTime:elapsed];

  if (_loopSelectionEnabled && [[self scoreView] hasLoopSelection]
      && tick >= [[self scoreView] loopEndTick])
    {
      NSUInteger loopStart = [[self scoreView] loopStartTick];
      if (![self restartPlaybackAtTick:loopStart])
        {
          [self stopCurrentPlayback];
          return;
        }
      [[self scoreView] setPlaybackTick:loopStart];
      [[self scoreView] scrollPlaybackTickToVisible:loopStart];
      [_playbackMonitorView setPlaybackTick:loopStart];
      [self updateScoreSourcePlaybackHighlightAtTick:loopStart];
      return;
    }

  if (tick >= [document totalTicks])
    {
      [_playbackTimer invalidate];
      [_playbackTimer release];
      _playbackTimer = nil;
      [[self scoreView] clearPlayback];
      [_playbackMonitorView clearPlayback];
      [self clearScoreSourcePlaybackHighlight];
      [self updatePauseButtonForPaused:NO];
      [_pauseButton setEnabled:NO];
      [_realtimeDSP allNotesOff];
      return;
    }

  [[self scoreView] setPlaybackTick:tick];
  [[self scoreView] scrollPlaybackTickToVisible:tick];
  [_playbackMonitorView setPlaybackTick:tick];
  [self updateScoreSourcePlaybackHighlightAtTick:tick];
}

- (void)startPlaybackHighlightAtTick:(NSUInteger)tick
{
  ScoreDocument *document = [self scoreDocument];
  ScoreScheduler *scheduler = [[[ScoreScheduler alloc] initWithDocument:document] autorelease];
  NSTimeInterval elapsed = [scheduler timeForTick:tick];
  _playbackMIDIOriginTime = elapsed;
  _playbackStartTime = [NSDate timeIntervalSinceReferenceDate] - elapsed;
  [_scoreSourceActivePlaybackNotes removeAllObjects];
  _scoreSourcePlaybackNoteIndex = 0;
  _scoreSourceLastPlaybackTick = NSNotFound;
  [[self scoreView] setPlaybackTick:tick];
  [[self scoreView] scrollPlaybackTickToVisible:tick];
  [_playbackMonitorView setPlaybackTick:tick];
  [self updateScoreSourcePlaybackHighlightAtTick:tick];
  _playbackPaused = NO;
  _playbackPausedElapsed = elapsed;
  [self updatePauseButtonForPaused:NO];
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
#if defined(__APPLE__)
      for (NSDictionary *playback in _externalMIDIPlaybacks)
        {
          MusicPlayer player = (MusicPlayer)[[playback objectForKey:@"player"] pointerValue];
          if (player)
            MusicPlayerStop (player);
          ScoreMakerSendAllNotesOff ([[playback objectForKey:@"endpoint"] unsignedIntValue]);
        }
#endif
      if (_playbackUsesRealtimeDSP)
        {
          [_realtimeDSP allNotesOff];
          [_realtimeDSP stop];
        }
      _playbackPaused = YES;
      [self updatePauseButtonForPaused:YES];
    }
  else
    {
      if (_midiPlayer)
        [(AVMIDIPlayer *)_midiPlayer play:nil];
      [_playbackSound resume];
#if defined(__APPLE__)
      for (NSDictionary *playback in _externalMIDIPlaybacks)
        {
          MusicPlayer player = (MusicPlayer)[[playback objectForKey:@"player"] pointerValue];
          if (player)
            MusicPlayerStart (player);
        }
#endif
      if (_playbackUsesRealtimeDSP)
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
      [self updatePauseButtonForPaused:NO];
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
  NSUInteger startTick = _loopSelectionEnabled && [[self scoreView] hasLoopSelection]
                           ? [[self scoreView] loopStartTick]
                           : (selectedNote ? [selectedNote startTick] : 0);

  if (startTick > 0)
    {
      if ([self restartPlaybackAtTick:startTick])
        {
          [self startPlaybackHighlightAtTick:startTick];
        }
      return;
    }

  NSError *error = nil;
  BOOL useRealtimeDSPForPlayback = _useRealtimeDSP;
#if defined(__APPLE__)
  if ([self documentHasPhysicalMIDIRouting:document])
    useRealtimeDSPForPlayback = NO;
#endif
  _playbackUsesRealtimeDSP = useRealtimeDSPForPlayback;
  if (useRealtimeDSPForPlayback)
    {
      if (![self prepareDSPPlaybackAtTick:0 error:&error])
        {
          [[NSDocumentController sharedDocumentController] presentError:error];
          return;
        }
      [self startPlaybackHighlight];
      return;
    }
#if !defined(__APPLE__)
  NSData *midiData = [MidiParser dataForDocument:document error:&error];
  if (!midiData)
    {
      [[NSDocumentController sharedDocumentController] presentError:error];
      return;
    }
#endif

#if defined(__APPLE__)
  if (![self playDocumentWithMIDIRouting:document error:&error])
#else
  if (![self playMIDIDataDirectly:midiData error:&error])
#endif
    {
      [[NSDocumentController sharedDocumentController] presentError:error];
      return;
    }
  [self startPlaybackHighlight];
}

- (void)toggleLoopSelection:(id)sender
{
  if (![[self scoreView] hasLoopSelection])
    {
      NSBeep ();
      _loopSelectionEnabled = NO;
    }
  else
    {
      _loopSelectionEnabled = !_loopSelectionEnabled;
    }
  if ([sender respondsToSelector:@selector (setState:)])
    [sender setState:_loopSelectionEnabled ? ScoreMakerStateOn : ScoreMakerStateOff];
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
  [note setTieStart:[_tieStartButton state] == ScoreMakerStateOn];
  [note setTieEnd:[_tieEndButton state] == ScoreMakerStateOn];
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
  [measure setRepeatStart:[_repeatStartButton state] == ScoreMakerStateOn];
  [measure setRepeatEnd:[_repeatEndButton state] == ScoreMakerStateOn];
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
      [_realtimeDSP noteOn:pitch voice:1 velocity:100];
      _realtimeDSPPitch = pitch;
      _realtimeDSPVoice = 1;
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
      [_realtimeDSP noteOff:_realtimeDSPPitch voice:_realtimeDSPVoice];
      _realtimeDSPPitch = -1;
      _realtimeDSPVoice = 1;
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
    [sender setState:_useRealtimeDSP ? ScoreMakerStateOn : ScoreMakerStateOff];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
  if ([menuItem action] == @selector (toggleRealtimeDSP:))
    [menuItem setState:_useRealtimeDSP ? ScoreMakerStateOn : ScoreMakerStateOff];
  if ([menuItem action] == @selector (toggleLoopSelection:))
    {
      BOOL hasSelection = [[self scoreView] hasLoopSelection];
      [menuItem setState:_loopSelectionEnabled && hasSelection ? ScoreMakerStateOn : ScoreMakerStateOff];
      return hasSelection;
    }
  return YES;
}

- (ScorePartDefinition *)selectedStructuredPartCreatingIfNeeded:(BOOL)create
{
  ScoreDocument *document = [self scoreDocument];
  if (create && [[document parts] count] == 0)
    [document rebuildStructuredPartsFromLegacyTracks];
  NSInteger track = [self selectedPartNumber];
  for (ScorePartDefinition *part in [document parts])
    if ([part legacyTrack] == track)
      return part;
  return [[document parts] count] ? [[document parts] objectAtIndex:0] : nil;
}

- (NSDictionary *)patchForPart:(ScorePartDefinition *)part
{
  return [self patchForPart:part voice:1];
}

- (NSDictionary *)patchForPart:(ScorePartDefinition *)part voice:(NSInteger)voice
{
  NSDictionary *parameters = [[part instrument] parameters];
  NSDictionary *patches = [parameters objectForKey:@"internalSynthPatches"];
  NSDictionary *patch = [patches objectForKey:[NSString stringWithFormat:@"%ld", (long)voice]];
  if (![patch isKindOfClass:[NSDictionary class]] && voice == 1)
    patch = [parameters objectForKey:@"internalSynthPatch"];
  return [patch isKindOfClass:[NSDictionary class]] ? patch
                                                     : [ScoreRealtimeDSP defaultInternalSynthPatch];
}

- (NSInteger)selectedPatchVoice
{
  if (_instrumentVoicePopUp)
    return MAX ((NSInteger)1, [_instrumentVoicePopUp indexOfSelectedItem] + 1);
  return _patchVoicePopUp ? MAX ((NSInteger)1, [_patchVoicePopUp indexOfSelectedItem] + 1) : 1;
}

- (void)configureVoicePatchesForPart:(ScorePartDefinition *)part
{
  for (NSInteger voice = 1; voice <= 16; voice++)
    [_realtimeDSP configureInternalSynthPatch:[self patchForPart:part voice:voice]
                                     forVoice:voice
                                        error:NULL];
}

- (void)loadPatchEditorControls
{
  NSDictionary *patch = [self patchForPart:[self selectedStructuredPartCreatingIfNeeded:YES]
                                     voice:[self selectedPatchVoice]];
  [_realtimeDSP configureInternalSynthPatch:patch
                                   forVoice:[self selectedPatchVoice]
                                      error:NULL];
  [_patchWaveformPopUp selectItemWithTitle:[patch objectForKey:@"waveform"] ?: @"Sine"];
  for (NSString *key in _patchControls)
    {
      NSSlider *slider = [_patchControls objectForKey:key];
      [slider setDoubleValue:[[patch objectForKey:key] doubleValue]];
      NSTextField *value = [_patchValueLabels objectForKey:key];
      [value setStringValue:[NSString stringWithFormat:@"%.2f", [slider doubleValue]]];
    }
  if (!_patchFilterValues)
    _patchFilterValues = [[NSMutableDictionary alloc] init];
  for (NSString *key in @[ @"filterCutoff", @"filterResonance", @"filterAttack",
                            @"filterDecay", @"filterSustain", @"filterRelease",
                            @"filterEnvelopeAmount", @"velocityToAmplitude",
                            @"velocityToFilter" ])
    [_patchFilterValues setObject:[patch objectForKey:key]
                                  ?: [[ScoreRealtimeDSP defaultInternalSynthPatch] objectForKey:key]
                           forKey:key];
  [(ScorePatchEnvelopeView *)_patchEnvelopeView setPatch:patch];
  [self reloadPatchPresetPopUpSelectingName:[patch objectForKey:@"name"]];
}

- (void)reloadPatchPresetPopUpSelectingName:(NSString *)name
{
  if (!_patchPresetPopUp)
    return;
  [_patchPresetPopUp removeAllItems];
  [_patchPresetPopUp addItemWithTitle:@"Custom Patch"];
  [[_patchPresetPopUp lastItem] setRepresentedObject:[NSNull null]];
  NSDictionary *presets = [self availableInternalSynthPatchLibrary];
  NSArray *names = [[presets allKeys]
    sortedArrayUsingSelector:@selector (localizedCaseInsensitiveCompare:)];
  for (NSString *presetName in names)
    {
      [_patchPresetPopUp addItemWithTitle:presetName];
      [[_patchPresetPopUp lastItem] setRepresentedObject:presetName];
    }
  if ([name length] && [names containsObject:name])
    [_patchPresetPopUp selectItemWithTitle:name];
  else
    [_patchPresetPopUp selectItemAtIndex:0];
}

- (NSDictionary *)availableInternalSynthPatchLibrary
{
  NSMutableDictionary *library = [NSMutableDictionary
    dictionaryWithDictionary:[ScoreRealtimeDSP factoryInternalSynthPatches]];
  NSDictionary *userPatches = [[NSUserDefaults standardUserDefaults]
    dictionaryForKey:ScoreMakerInternalPatchPresetsKey];
  if (userPatches)
    [library addEntriesFromDictionary:userPatches];
  return library;
}

- (void)rebuildInstrumentPopUpSelectingCurrentSound
{
  if (!_instrumentPopUp)
    return;
  [_instrumentPopUp removeAllItems];
  [_instrumentPopUp addItemWithTitle:@"General MIDI"];
  [[_instrumentPopUp lastItem] setEnabled:NO];
  NSArray *programNames = [MidiParser generalMidiProgramNames];
  for (NSUInteger program = 0; program < [programNames count]; program++)
    {
      [_instrumentPopUp addItemWithTitle:[programNames objectAtIndex:program]];
      [[_instrumentPopUp lastItem]
        setRepresentedObject:@{ @"kind" : @"gm", @"program" : [NSNumber numberWithUnsignedInteger:program] }];
    }
  [[_instrumentPopUp menu] addItem:[NSMenuItem separatorItem]];
  [_instrumentPopUp addItemWithTitle:@"ScoreMaker Synth"];
  [[_instrumentPopUp lastItem] setEnabled:NO];
  NSDictionary *library = [self availableInternalSynthPatchLibrary];
  NSArray *patchNames = [[library allKeys]
    sortedArrayUsingSelector:@selector (localizedCaseInsensitiveCompare:)];
  for (NSString *name in patchNames)
    {
      NSDictionary *patch = [library objectForKey:name];
      NSString *category = [patch objectForKey:@"category"] ?: @"Uncategorized";
      [_instrumentPopUp addItemWithTitle:[NSString stringWithFormat:@"%@ — %@", category, name]];
      [[_instrumentPopUp lastItem] setRepresentedObject:@{ @"kind" : @"synth", @"name" : name }];
    }
  [[_instrumentPopUp menu] addItem:[NSMenuItem separatorItem]];
  [_instrumentPopUp addItemWithTitle:@"Choose Audio Unit..."];
  [[_instrumentPopUp lastItem] setRepresentedObject:@{ @"kind" : @"audio-unit" }];

  ScorePartDefinition *part = [self selectedStructuredPartCreatingIfNeeded:NO];
  NSString *backend = [[part instrument] backendIdentifier];
  NSInteger voice = [self selectedPatchVoice];
  NSString *patchName = [[self patchForPart:part voice:voice] objectForKey:@"name"];
  NSNumber *program = [[self scoreDocument] programForTrack:[self selectedPartNumber]];
  NSMenuItem *selection = nil;
  for (NSMenuItem *item in [_instrumentPopUp itemArray])
    {
      NSDictionary *represented = [item representedObject];
      NSString *kind = [represented objectForKey:@"kind"];
      if ([backend isEqualToString:@"scoremaker-internal-synth"]
          && [kind isEqualToString:@"synth"]
          && [[represented objectForKey:@"name"] isEqualToString:patchName])
        selection = item;
      else if (![backend isEqualToString:@"scoremaker-internal-synth"]
               && ![backend hasPrefix:@"audio-unit:"] && [kind isEqualToString:@"gm"]
               && [[represented objectForKey:@"program"] integerValue] == [program integerValue])
        selection = item;
    }
  if (selection)
    [_instrumentPopUp selectItem:selection];
  else if ([backend isEqualToString:@"scoremaker-internal-synth"])
    {
      NSInteger synthHeaderIndex = [_instrumentPopUp indexOfItemWithTitle:@"ScoreMaker Synth"];
      NSInteger customIndex = synthHeaderIndex == -1 ? 0 : synthHeaderIndex + 1;
      [_instrumentPopUp insertItemWithTitle:@"Custom Synth Patch" atIndex:customIndex];
      NSMenuItem *custom = [_instrumentPopUp itemAtIndex:customIndex];
      [custom setRepresentedObject:@{ @"kind" : @"custom" }];
      [_instrumentPopUp selectItem:custom];
    }
  else if ([backend hasPrefix:@"audio-unit:"])
    [_instrumentPopUp selectItemWithTitle:@"Choose Audio Unit..."];
  else if ([_instrumentPopUp numberOfItems] > 1)
    [_instrumentPopUp selectItemAtIndex:1];
}

- (void)showInternalSynthPatchEditor:(id)sender
{
  (void)sender;
  if (!_patchEditorWindow)
    {
      NSUInteger style = ScoreMakerWindowTitled | ScoreMakerWindowClosable | ScoreMakerWindowMiniaturizable;
      _patchEditorWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect (0, 0, 650, 530)
                                                       styleMask:style
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
      [_patchEditorWindow setReleasedWhenClosed:NO];
      [_patchEditorWindow setTitle:@"Internal Synth Patch Editor"];
      NSView *content = [_patchEditorWindow contentView];

      NSTextField *heading = [[[NSTextField alloc] initWithFrame:NSMakeRect (22, 484, 606, 28)] autorelease];
      [heading setEditable:NO];
      [heading setBordered:NO];
      [heading setDrawsBackground:NO];
      [heading setFont:[NSFont boldSystemFontOfSize:18.0]];
      [heading setStringValue:@"ScoreMaker Internal Synthesizer"];
      [content addSubview:heading];

      NSTextField *waveLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect (24, 446, 88, 22)] autorelease];
      [waveLabel setEditable:NO];
      [waveLabel setBordered:NO];
      [waveLabel setDrawsBackground:NO];
      [waveLabel setStringValue:@"Oscillator"];
      [content addSubview:waveLabel];
      _patchWaveformPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect (112, 442, 180, 28)
                                                       pullsDown:NO];
      [_patchWaveformPopUp addItemsWithTitles:@[ @"Sine", @"Triangle", @"Saw", @"Square" ]];
      [_patchWaveformPopUp setTarget:self];
      [_patchWaveformPopUp setAction:@selector (patchControlChanged:)];
      [content addSubview:_patchWaveformPopUp];

      NSTextField *voiceLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect (24, 408, 88, 22)] autorelease];
      [voiceLabel setEditable:NO];
      [voiceLabel setBordered:NO];
      [voiceLabel setDrawsBackground:NO];
      [voiceLabel setStringValue:@"Score Voice"];
      [content addSubview:voiceLabel];
      _patchVoicePopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect (112, 404, 180, 28)
                                                    pullsDown:NO];
      for (NSInteger voice = 1; voice <= 16; voice++)
        [_patchVoicePopUp addItemWithTitle:[NSString stringWithFormat:@"Voice %ld", (long)voice]];
      if (_instrumentVoicePopUp)
        [_patchVoicePopUp selectItemAtIndex:[_instrumentVoicePopUp indexOfSelectedItem]];
      [_patchVoicePopUp setTarget:self];
      [_patchVoicePopUp setAction:@selector (patchVoiceChanged:)];
      [content addSubview:_patchVoicePopUp];

      NSTextField *patchLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect (24, 370, 88, 22)] autorelease];
      [patchLabel setEditable:NO];
      [patchLabel setBordered:NO];
      [patchLabel setDrawsBackground:NO];
      [patchLabel setStringValue:@"Named Patch"];
      [content addSubview:patchLabel];
      _patchPresetPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect (112, 366, 180, 28)
                                                     pullsDown:NO];
      [_patchPresetPopUp setTarget:self];
      [_patchPresetPopUp setAction:@selector (patchPresetChanged:)];
      [content addSubview:_patchPresetPopUp];

      NSTextField *graphLabel = [[[NSTextField alloc] initWithFrame:NSMakeRect (340, 446, 278, 22)] autorelease];
      [graphLabel setEditable:NO];
      [graphLabel setBordered:NO];
      [graphLabel setDrawsBackground:NO];
      [graphLabel setFont:[NSFont boldSystemFontOfSize:13.0]];
      [graphLabel setStringValue:@"ADSR Shape"];
      [content addSubview:graphLabel];
      _patchEnvelopeView = [[ScorePatchEnvelopeView alloc] initWithFrame:NSMakeRect (340, 308, 278, 128)];
      [content addSubview:_patchEnvelopeView];

      NSTextField *envelopeHeading = [[[NSTextField alloc] initWithFrame:NSMakeRect (24, 278, 280, 22)] autorelease];
      [envelopeHeading setEditable:NO];
      [envelopeHeading setBordered:NO];
      [envelopeHeading setDrawsBackground:NO];
      [envelopeHeading setFont:[NSFont boldSystemFontOfSize:13.0]];
      [envelopeHeading setStringValue:@"Amplitude Envelope"];
      [content addSubview:envelopeHeading];
      NSTextField *lfoHeading = [[[NSTextField alloc] initWithFrame:NSMakeRect (340, 278, 280, 22)] autorelease];
      [lfoHeading setEditable:NO];
      [lfoHeading setBordered:NO];
      [lfoHeading setDrawsBackground:NO];
      [lfoHeading setFont:[NSFont boldSystemFontOfSize:13.0]];
      [lfoHeading setStringValue:@"Pitch LFO"];
      [content addSubview:lfoHeading];

      _patchControls = [[NSMutableDictionary alloc] init];
      _patchValueLabels = [[NSMutableDictionary alloc] init];
      NSArray *specifications = @[
        @{ @"key" : @"attack", @"title" : @"Attack", @"min" : @0.0, @"max" : @5.0,
           @"x" : @24, @"y" : @236 },
        @{ @"key" : @"decay", @"title" : @"Decay", @"min" : @0.0, @"max" : @5.0,
           @"x" : @24, @"y" : @190 },
        @{ @"key" : @"sustain", @"title" : @"Sustain", @"min" : @0.0, @"max" : @1.0,
           @"x" : @24, @"y" : @144 },
        @{ @"key" : @"release", @"title" : @"Release", @"min" : @0.0, @"max" : @8.0,
           @"x" : @24, @"y" : @98 },
        @{ @"key" : @"lfoRate", @"title" : @"Rate Hz", @"min" : @0.1, @"max" : @20.0,
           @"x" : @340, @"y" : @236 },
        @{ @"key" : @"lfoDepth", @"title" : @"Depth st", @"min" : @0.0, @"max" : @2.0,
           @"x" : @340, @"y" : @190 },
        @{ @"key" : @"lfoDelay", @"title" : @"Delay", @"min" : @0.0, @"max" : @5.0,
           @"x" : @340, @"y" : @144 }
      ];
      for (NSDictionary *specification in specifications)
        {
          CGFloat x = [[specification objectForKey:@"x"] doubleValue];
          CGFloat y = [[specification objectForKey:@"y"] doubleValue];
          NSString *key = [specification objectForKey:@"key"];
          NSTextField *label = [[[NSTextField alloc] initWithFrame:NSMakeRect (x, y, 72, 22)] autorelease];
          [label setEditable:NO];
          [label setBordered:NO];
          [label setDrawsBackground:NO];
          [label setStringValue:[specification objectForKey:@"title"]];
          [content addSubview:label];
          NSSlider *slider = [[[NSSlider alloc] initWithFrame:NSMakeRect (x + 72, y - 1, 166, 24)] autorelease];
          [slider setMinValue:[[specification objectForKey:@"min"] doubleValue]];
          [slider setMaxValue:[[specification objectForKey:@"max"] doubleValue]];
          [slider setContinuous:NO];
          [slider setTarget:self];
          [slider setAction:@selector (patchControlChanged:)];
          [content addSubview:slider];
          [_patchControls setObject:slider forKey:key];
          NSTextField *value = [[[NSTextField alloc] initWithFrame:NSMakeRect (x + 242, y, 55, 22)] autorelease];
          [value setEditable:NO];
          [value setBordered:NO];
          [value setDrawsBackground:NO];
          [value setAlignment:NSTextAlignmentRight];
          [content addSubview:value];
          [_patchValueLabels setObject:value forKey:key];
        }

      NSButton *preview = [[[NSButton alloc] initWithFrame:NSMakeRect (340, 92, 64, 30)] autorelease];
      [preview setTitle:@"Preview"];
      [preview setTarget:self];
      [preview setAction:@selector (previewInternalSynthPatch:)];
      [content addSubview:preview];
      NSButton *filter = [[[NSButton alloc] initWithFrame:NSMakeRect (410, 92, 64, 30)] autorelease];
      [filter setTitle:@"Filter..."];
      [filter setTarget:self];
      [filter setAction:@selector (editInternalSynthFilterEnvelope:)];
      [content addSubview:filter];
      NSButton *effects = [[[NSButton alloc] initWithFrame:NSMakeRect (480, 92, 64, 30)] autorelease];
      [effects setTitle:@"Effects..."];
      [effects setTarget:self];
      [effects setAction:@selector (editInternalSynthPatchEffects:)];
      [content addSubview:effects];
      NSButton *reset = [[[NSButton alloc] initWithFrame:NSMakeRect (550, 92, 68, 30)] autorelease];
      [reset setTitle:@"Reset Patch"];
      [reset setTarget:self];
      [reset setAction:@selector (resetInternalSynthPatch:)];
      [content addSubview:reset];

      NSButton *savePreset = [[[NSButton alloc] initWithFrame:NSMakeRect (340, 54, 132, 30)] autorelease];
      [savePreset setTitle:@"Save Patch..."];
      [savePreset setTarget:self];
      [savePreset setAction:@selector (saveInternalSynthPatchPreset:)];
      [content addSubview:savePreset];
      NSButton *loadPreset = [[[NSButton alloc] initWithFrame:NSMakeRect (486, 54, 132, 30)] autorelease];
      [loadPreset setTitle:@"Browse Patches..."];
      [loadPreset setTarget:self];
      [loadPreset setAction:@selector (showInternalSynthPatchBrowser:)];
      [content addSubview:loadPreset];

      NSTextField *help = [[[NSTextField alloc] initWithFrame:NSMakeRect (24, 22, 292, 58)] autorelease];
      [help setEditable:NO];
      [help setBordered:NO];
      [help setDrawsBackground:NO];
      [help setTextColor:[NSColor secondaryLabelColor]];
      [help setStringValue:@"Each score voice can use its own patch. Saved patches are global and can be loaded into any score."];
      [content addSubview:help];
    }
  [self loadPatchEditorControls];
  [self positionAuxiliaryWindowBesideDocument:_patchEditorWindow];
  [_patchEditorWindow makeKeyAndOrderFront:nil];
  [self arrangeScoreAuxiliaryWindows];
}

- (void)patchControlChanged:(id)sender
{
  (void)sender;
  NSInteger voice = [self selectedPatchVoice];
  NSMutableDictionary *patch = [NSMutableDictionary dictionary];
  [patch setObject:[_patchWaveformPopUp titleOfSelectedItem] forKey:@"waveform"];
  for (NSString *key in _patchControls)
    {
      NSSlider *slider = [_patchControls objectForKey:key];
      [patch setObject:[NSNumber numberWithDouble:[slider doubleValue]] forKey:key];
      [[_patchValueLabels objectForKey:key]
        setStringValue:[NSString stringWithFormat:@"%.2f", [slider doubleValue]]];
    }
  for (NSString *key in _patchFilterValues)
    [patch setObject:[_patchFilterValues objectForKey:key] forKey:key];
  [patch setObject:[_realtimeDSP internalSynthEffectsForVoice:voice] forKey:@"effects"];
  if (_applyingNamedPatch)
    {
      id name = [[_patchPresetPopUp selectedItem] representedObject];
      if ([name isKindOfClass:[NSString class]])
        [patch setObject:name forKey:@"name"];
    }
  else
    [_patchPresetPopUp selectItemAtIndex:0];
  [(ScorePatchEnvelopeView *)_patchEnvelopeView setPatch:patch];
  [_realtimeDSP useInternalSynthesizer];
  NSError *error = nil;
  if (![_realtimeDSP configureInternalSynthPatch:patch forVoice:voice error:&error])
    {
      [[NSDocumentController sharedDocumentController] presentError:error];
      return;
    }
  ScorePartDefinition *part = [self selectedStructuredPartCreatingIfNeeded:YES];
  if (!part)
    return;
  [self registerUndoSnapshotWithName:@"Edit Synth Patch"];
  NSMutableDictionary *parameters = [NSMutableDictionary
    dictionaryWithDictionary:[[part instrument] parameters] ?: [NSDictionary dictionary]];
  NSMutableDictionary *patches = [NSMutableDictionary
    dictionaryWithDictionary:[parameters objectForKey:@"internalSynthPatches"]
                               ?: [NSDictionary dictionary]];
  NSDictionary *normalized = [_realtimeDSP internalSynthPatchForVoice:voice];
  [patches setObject:normalized forKey:[NSString stringWithFormat:@"%ld", (long)voice]];
  [parameters setObject:patches forKey:@"internalSynthPatches"];
  if (voice == 1)
    [parameters setObject:normalized forKey:@"internalSynthPatch"];
  [[part instrument] setParameters:parameters];
  [[part instrument] setBackendIdentifier:@"scoremaker-internal-synth"];
  _audioUnitPartTrack = -1;
  _useRealtimeDSP = YES;
  [self updateChangeCount:NSChangeDone];
  [self commitUndoBaseline];
  [self rebuildInstrumentPopUpSelectingCurrentSound];
}

- (void)patchVoiceChanged:(id)sender
{
  (void)sender;
  if (_instrumentVoicePopUp)
    [_instrumentVoicePopUp selectItemAtIndex:[_patchVoicePopUp indexOfSelectedItem]];
  [self loadPatchEditorControls];
  [self rebuildInstrumentPopUpSelectingCurrentSound];
}

- (void)patchPresetChanged:(id)sender
{
  (void)sender;
  id name = [[_patchPresetPopUp selectedItem] representedObject];
  if (![name isKindOfClass:[NSString class]])
    return;
  NSDictionary *patch = [[self availableInternalSynthPatchLibrary] objectForKey:name];
  if (![patch isKindOfClass:[NSDictionary class]])
    return;
  NSInteger voice = [self selectedPatchVoice];
  NSError *error = nil;
  if (![_realtimeDSP configureInternalSynthPatch:patch forVoice:voice error:&error])
    {
      [[NSDocumentController sharedDocumentController] presentError:error];
      return;
    }
  [_patchWaveformPopUp selectItemWithTitle:[patch objectForKey:@"waveform"]];
  for (NSString *key in _patchControls)
    [[_patchControls objectForKey:key] setDoubleValue:[[patch objectForKey:key] doubleValue]];
  for (NSString *key in _patchFilterValues)
    [_patchFilterValues setObject:[patch objectForKey:key]
                                  ?: [[ScoreRealtimeDSP defaultInternalSynthPatch] objectForKey:key]
                           forKey:key];
  _applyingNamedPatch = YES;
  [self patchControlChanged:nil];
  _applyingNamedPatch = NO;
}

- (void)saveInternalSynthPatchPreset:(id)sender
{
  (void)sender;
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"Save Internal Synth Patch"];
  [alert setInformativeText:@"Saved patches are available to every ScoreMaker score."];
  [alert addButtonWithTitle:@"Save"];
  [alert addButtonWithTitle:@"Cancel"];
  NSView *accessory = [[[NSView alloc] initWithFrame:NSMakeRect (0, 0, 360, 92)] autorelease];
  NSTextField *name = [[[NSTextField alloc] initWithFrame:NSMakeRect (0, 66, 360, 24)] autorelease];
  [name setPlaceholderString:@"Patch name"];
  [accessory addSubview:name];
  NSPopUpButton *category = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (0, 34, 170, 26)
                                                         pullsDown:NO] autorelease];
  [category addItemsWithTitles:@[ @"Lead", @"Bass", @"Pad", @"Pluck", @"Keys", @"Effects",
                                   @"Uncategorized" ]];
  [accessory addSubview:category];
  NSTextField *description = [[[NSTextField alloc] initWithFrame:NSMakeRect (0, 2, 360, 24)] autorelease];
  [description setPlaceholderString:@"Short sound description"];
  [accessory addSubview:description];
  [alert setAccessoryView:accessory];
  if ([alert runModal] != NSAlertFirstButtonReturn)
    return;
  NSString *trimmed = [[name stringValue]
    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (![trimmed length])
    return;
  NSMutableDictionary *patch = [NSMutableDictionary
    dictionaryWithDictionary:[self patchForPart:[self selectedStructuredPartCreatingIfNeeded:YES]
                                             voice:[self selectedPatchVoice]]];
  [patch setObject:trimmed forKey:@"name"];
  [patch setObject:[category titleOfSelectedItem] forKey:@"category"];
  [patch setObject:[description stringValue] ?: @"" forKey:@"description"];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *presets = [NSMutableDictionary
    dictionaryWithDictionary:[defaults dictionaryForKey:ScoreMakerInternalPatchPresetsKey]
                               ?: [NSDictionary dictionary]];
  [presets setObject:patch forKey:trimmed];
  [defaults setObject:presets forKey:ScoreMakerInternalPatchPresetsKey];
  if (_patchBrowserWindow)
    [self refreshPatchBrowser:nil];
  [self reloadPatchPresetPopUpSelectingName:trimmed];
  _applyingNamedPatch = YES;
  [self patchControlChanged:nil];
  _applyingNamedPatch = NO;
}

- (void)loadInternalSynthPatchPreset:(id)sender
{
  (void)sender;
  NSDictionary *presets = [self availableInternalSynthPatchLibrary];
  NSArray *names = [[presets allKeys] sortedArrayUsingSelector:@selector (localizedCaseInsensitiveCompare:)];
  if (![names count])
    {
      NSBeep ();
      return;
    }
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:@"Load Internal Synth Patch"];
  [alert setInformativeText:@"Choose a saved patch for the selected score voice."];
  [alert addButtonWithTitle:@"Load"];
  [alert addButtonWithTitle:@"Cancel"];
  NSPopUpButton *choices = [[[NSPopUpButton alloc] initWithFrame:NSMakeRect (0, 0, 320, 26)
                                                        pullsDown:NO] autorelease];
  [choices addItemsWithTitles:names];
  [alert setAccessoryView:choices];
  if ([alert runModal] != NSAlertFirstButtonReturn)
    return;
  NSString *selectedName = [choices titleOfSelectedItem];
  [self reloadPatchPresetPopUpSelectingName:selectedName];
  [self patchPresetChanged:_patchPresetPopUp];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
  return tableView == _patchBrowserTable ? (NSInteger)[_patchBrowserRows count] : 0;
}

- (id)tableView:(NSTableView *)tableView
  objectValueForTableColumn:(NSTableColumn *)tableColumn
                     row:(NSInteger)row
{
  if (tableView != _patchBrowserTable || row < 0 || row >= (NSInteger)[_patchBrowserRows count])
    return @"";
  return [[_patchBrowserRows objectAtIndex:(NSUInteger)row]
    objectForKey:[[tableColumn identifier] description]] ?: @"";
}

- (void)refreshPatchBrowser:(id)sender
{
  (void)sender;
  NSDictionary *presets = [self availableInternalSynthPatchLibrary];
  NSString *filter = [_patchBrowserCategoryPopUp titleOfSelectedItem] ?: @"All Categories";
  NSMutableArray *rows = [NSMutableArray array];
  for (NSString *name in presets)
    {
      NSDictionary *patch = [presets objectForKey:name];
      NSString *category = [patch objectForKey:@"category"] ?: @"Uncategorized";
      if (![filter isEqualToString:@"All Categories"] && ![category isEqualToString:filter])
        continue;
      [rows addObject:@{ @"name" : name,
                         @"category" : category,
                         @"description" : [patch objectForKey:@"description"] ?: @"",
                         @"patch" : patch }];
    }
  [rows sortUsingComparator:^NSComparisonResult (NSDictionary *left, NSDictionary *right) {
    NSComparisonResult categoryResult = [[left objectForKey:@"category"]
      localizedCaseInsensitiveCompare:[right objectForKey:@"category"]];
    return categoryResult == NSOrderedSame
             ? [[left objectForKey:@"name"] localizedCaseInsensitiveCompare:[right objectForKey:@"name"]]
             : categoryResult;
  }];
  [_patchBrowserRows release];
  _patchBrowserRows = [rows copy];
  [_patchBrowserTable reloadData];
  if ([_patchBrowserRows count])
    [_patchBrowserTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                    byExtendingSelection:NO];
}

- (void)showInternalSynthPatchBrowser:(id)sender
{
  (void)sender;
  if (!_patchBrowserWindow)
    {
      _patchBrowserWindow = [[NSWindow alloc]
        initWithContentRect:NSMakeRect (0, 0, 720, 430)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                             | NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
      [_patchBrowserWindow setReleasedWhenClosed:NO];
      [_patchBrowserWindow setTitle:@"ScoreMaker Patch Browser"];
      NSView *content = [_patchBrowserWindow contentView];
      NSTextField *heading = [[[NSTextField alloc] initWithFrame:NSMakeRect (18, 390, 330, 26)] autorelease];
      [heading setEditable:NO];
      [heading setBordered:NO];
      [heading setDrawsBackground:NO];
      [heading setFont:[NSFont boldSystemFontOfSize:18.0]];
      [heading setStringValue:@"Choose a Sound"];
      [content addSubview:heading];
      _patchBrowserCategoryPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect (500, 388, 200, 28)
                                                               pullsDown:NO];
      [_patchBrowserCategoryPopUp addItemsWithTitles:@[ @"All Categories", @"Lead", @"Bass", @"Pad",
                                                           @"Pluck", @"Keys", @"Effects", @"Uncategorized" ]];
      [_patchBrowserCategoryPopUp setTarget:self];
      [_patchBrowserCategoryPopUp setAction:@selector (refreshPatchBrowser:)];
      [content addSubview:_patchBrowserCategoryPopUp];

      _patchBrowserTable = [[NSTableView alloc] initWithFrame:NSMakeRect (0, 0, 680, 320)];
      for (NSDictionary *specification in @[
             @{ @"id" : @"name", @"title" : @"Patch", @"width" : @180 },
             @{ @"id" : @"category", @"title" : @"Category", @"width" : @110 },
             @{ @"id" : @"description", @"title" : @"Description", @"width" : @360 }
           ])
        {
          NSTableColumn *column = [[[NSTableColumn alloc]
            initWithIdentifier:[specification objectForKey:@"id"]] autorelease];
          [[column headerCell] setStringValue:[specification objectForKey:@"title"]];
          [column setWidth:[[specification objectForKey:@"width"] doubleValue]];
          [_patchBrowserTable addTableColumn:column];
        }
      [_patchBrowserTable setDataSource:self];
      [_patchBrowserTable setDelegate:self];
      [_patchBrowserTable setUsesAlternatingRowBackgroundColors:YES];
      [_patchBrowserTable setDoubleAction:@selector (usePatchBrowserSelection:)];
      [_patchBrowserTable setTarget:self];
      NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect (18, 62, 684, 316)] autorelease];
      [scroll setHasVerticalScroller:YES];
      [scroll setHasHorizontalScroller:NO];
      [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [scroll setDocumentView:_patchBrowserTable];
      [content addSubview:scroll];

      NSButton *audition = [[[NSButton alloc] initWithFrame:NSMakeRect (430, 18, 126, 32)] autorelease];
      [audition setTitle:@"Audition Phrase"];
      [audition setTarget:self];
      [audition setAction:@selector (auditionPatchBrowserSelection:)];
      [content addSubview:audition];
      NSButton *use = [[[NSButton alloc] initWithFrame:NSMakeRect (570, 18, 132, 32)] autorelease];
      [use setTitle:@"Use Patch"];
      [use setTarget:self];
      [use setAction:@selector (usePatchBrowserSelection:)];
      [content addSubview:use];
      NSTextField *voice = [[[NSTextField alloc] initWithFrame:NSMakeRect (18, 24, 380, 22)] autorelease];
      [voice setEditable:NO];
      [voice setBordered:NO];
      [voice setDrawsBackground:NO];
      [voice setTextColor:[NSColor secondaryLabelColor]];
      [voice setStringValue:@"Audition and assignment use the patch editor’s selected score voice."];
      [content addSubview:voice];
      [_patchBrowserWindow center];
    }
  [self refreshPatchBrowser:nil];
  [_patchBrowserWindow makeKeyAndOrderFront:self];
}

- (void)auditionPatchBrowserSelection:(id)sender
{
  (void)sender;
  NSInteger row = [_patchBrowserTable selectedRow];
  if (row < 0 || row >= (NSInteger)[_patchBrowserRows count])
    return;
  NSDictionary *patch = [[_patchBrowserRows objectAtIndex:(NSUInteger)row] objectForKey:@"patch"];
  NSInteger voice = [self selectedPatchVoice];
  [_realtimeDSP useInternalSynthesizer];
  NSError *error = nil;
  if (![_realtimeDSP configureInternalSynthPatch:patch forVoice:voice error:&error])
    {
      [[NSDocumentController sharedDocumentController] presentError:error];
      return;
    }
  NSArray *events = @[
    @{ @"time" : @0.0, @"pitch" : @60, @"voice" : @(voice), @"velocity" : @92, @"on" : @YES },
    @{ @"time" : @0.18, @"pitch" : @60, @"voice" : @(voice), @"velocity" : @0, @"on" : @NO },
    @{ @"time" : @0.20, @"pitch" : @64, @"voice" : @(voice), @"velocity" : @106, @"on" : @YES },
    @{ @"time" : @0.38, @"pitch" : @64, @"voice" : @(voice), @"velocity" : @0, @"on" : @NO },
    @{ @"time" : @0.40, @"pitch" : @67, @"voice" : @(voice), @"velocity" : @118, @"on" : @YES },
    @{ @"time" : @0.72, @"pitch" : @67, @"voice" : @(voice), @"velocity" : @0, @"on" : @NO }
  ];
  _useRealtimeDSP = YES;
  if (![_realtimeDSP scheduleEvents:events error:&error])
    [[NSDocumentController sharedDocumentController] presentError:error];
  else
    [NSTimer scheduledTimerWithTimeInterval:1.25
                                     target:self
                                   selector:@selector (restorePatchAfterBrowserAudition:)
                                   userInfo:nil
                                    repeats:NO];
}

- (void)restorePatchAfterBrowserAudition:(NSTimer *)timer
{
  (void)timer;
  ScorePartDefinition *part = [self selectedStructuredPartCreatingIfNeeded:NO];
  if (part)
    [self configureVoicePatchesForPart:part];
}

- (void)usePatchBrowserSelection:(id)sender
{
  (void)sender;
  NSInteger row = [_patchBrowserTable selectedRow];
  if (row < 0 || row >= (NSInteger)[_patchBrowserRows count])
    return;
  NSString *name = [[_patchBrowserRows objectAtIndex:(NSUInteger)row] objectForKey:@"name"];
  [self reloadPatchPresetPopUpSelectingName:name];
  [self patchPresetChanged:_patchPresetPopUp];
}

- (void)editInternalSynthPatchEffects:(id)sender
{
  (void)sender;
  NSInteger voice = [self selectedPatchVoice];
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
  for (NSDictionary *effect in [_realtimeDSP internalSynthEffectsForVoice:voice])
    [existing setObject:effect forKey:[effect objectForKey:@"type"] ?: @""];
  NSView *accessory = [[[NSView alloc] initWithFrame:NSMakeRect (0, 0, 500, 230)] autorelease];
  NSMutableArray *controls = [NSMutableArray array];
  for (NSUInteger index = 0; index < [specifications count]; index++)
    {
      NSDictionary *specification = [specifications objectAtIndex:index];
      NSDictionary *effect = [existing objectForKey:[specification objectForKey:@"type"]];
      CGFloat y = 190.0 - index * 42.0;
      NSButton *enabled = [[[NSButton alloc] initWithFrame:NSMakeRect (0, y, 135, 24)] autorelease];
      [enabled setButtonType:ScoreMakerSwitchButton];
      [enabled setTitle:[specification objectForKey:@"name"]];
      [enabled setState:effect ? NSControlStateValueOn : NSControlStateValueOff];
      [accessory addSubview:enabled];
      NSSlider *value = [[[NSSlider alloc] initWithFrame:NSMakeRect (140, y, 350, 24)] autorelease];
      [value setMinValue:[[specification objectForKey:@"minimum"] doubleValue]];
      [value setMaxValue:[[specification objectForKey:@"maximum"] doubleValue]];
      NSNumber *saved = [effect objectForKey:[specification objectForKey:@"key"]];
      [value setDoubleValue:saved ? [saved doubleValue]
                                  : [[specification objectForKey:@"default"] doubleValue]];
      [accessory addSubview:value];
      [controls addObject:@{ @"enabled" : enabled, @"value" : value,
                             @"specification" : specification }];
    }
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:[NSString stringWithFormat:@"Patch Effects — Voice %ld", (long)voice]];
  [alert setInformativeText:@"These effects belong to this patch and are included in globally saved patches."];
  [alert setAccessoryView:accessory];
  [alert addButtonWithTitle:@"Apply"];
  [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] != NSAlertFirstButtonReturn)
    return;
  NSMutableArray *effects = [NSMutableArray array];
  for (NSDictionary *control in controls)
    {
      if ([[control objectForKey:@"enabled"] state] != NSControlStateValueOn)
        continue;
      NSDictionary *specification = [control objectForKey:@"specification"];
      NSString *type = [specification objectForKey:@"type"];
      NSMutableDictionary *effect = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        type, @"type", [NSNumber numberWithDouble:[[control objectForKey:@"value"] doubleValue]],
        [specification objectForKey:@"key"], nil];
      if ([type isEqualToString:@"compressor"])
        [effect setObject:@4.0 forKey:@"ratio"];
      else if ([type isEqualToString:@"delay"])
        {
          [effect setObject:@0.3 forKey:@"time"];
          [effect setObject:@0.35 forKey:@"feedback"];
        }
      else if ([type isEqualToString:@"reverb"])
        [effect setObject:@0.35 forKey:@"roomSize"];
      [effects addObject:effect];
    }
  NSError *error = nil;
  if (![_realtimeDSP configureInternalSynthEffects:effects forVoice:voice error:&error])
    {
      [[NSDocumentController sharedDocumentController] presentError:error];
      return;
    }
  [self patchControlChanged:nil];
}

- (void)editInternalSynthFilterEnvelope:(id)sender
{
  (void)sender;
  NSArray *specifications = @[
    @{ @"key" : @"filterCutoff", @"name" : @"Cutoff Hz", @"min" : @20.0, @"max" : @12000.0 },
    @{ @"key" : @"filterResonance", @"name" : @"Resonance", @"min" : @0.0, @"max" : @0.95 },
    @{ @"key" : @"filterAttack", @"name" : @"Attack", @"min" : @0.0, @"max" : @5.0 },
    @{ @"key" : @"filterDecay", @"name" : @"Decay", @"min" : @0.0, @"max" : @5.0 },
    @{ @"key" : @"filterSustain", @"name" : @"Sustain", @"min" : @0.0, @"max" : @1.0 },
    @{ @"key" : @"filterRelease", @"name" : @"Release", @"min" : @0.0, @"max" : @8.0 },
    @{ @"key" : @"filterEnvelopeAmount", @"name" : @"Env Amount st", @"min" : @-48.0, @"max" : @96.0 },
    @{ @"key" : @"velocityToAmplitude", @"name" : @"Velocity → Amp", @"min" : @0.0, @"max" : @1.0 },
    @{ @"key" : @"velocityToFilter", @"name" : @"Velocity → Filter st", @"min" : @-48.0, @"max" : @48.0 }
  ];
  NSView *accessory = [[[NSView alloc] initWithFrame:NSMakeRect (0, 0, 520, 475)] autorelease];
  NSMutableDictionary *controls = [NSMutableDictionary dictionary];
  NSMutableDictionary *valueLabels = [NSMutableDictionary dictionary];
  NSTextField *graphHeading = [[[NSTextField alloc] initWithFrame:NSMakeRect (0, 449, 520, 22)] autorelease];
  [graphHeading setEditable:NO];
  [graphHeading setBordered:NO];
  [graphHeading setDrawsBackground:NO];
  [graphHeading setFont:[NSFont boldSystemFontOfSize:13.0]];
  [graphHeading setStringValue:@"Filter Envelope Shape"];
  [accessory addSubview:graphHeading];
  ScoreFilterEnvelopeView *graph = [[[ScoreFilterEnvelopeView alloc]
    initWithFrame:NSMakeRect (0, 350, 520, 94)] autorelease];
  [accessory addSubview:graph];
  for (NSUInteger index = 0; index < [specifications count]; index++)
    {
      NSDictionary *specification = [specifications objectAtIndex:index];
      CGFloat y = 320.0 - index * 37.0;
      NSTextField *label = [[[NSTextField alloc] initWithFrame:NSMakeRect (0, y, 145, 22)] autorelease];
      [label setEditable:NO];
      [label setBordered:NO];
      [label setDrawsBackground:NO];
      [label setStringValue:[specification objectForKey:@"name"]];
      [accessory addSubview:label];
      NSSlider *slider = [[[NSSlider alloc] initWithFrame:NSMakeRect (145, y, 315, 24)] autorelease];
      [slider setMinValue:[[specification objectForKey:@"min"] doubleValue]];
      [slider setMaxValue:[[specification objectForKey:@"max"] doubleValue]];
      [slider setDoubleValue:[[_patchFilterValues objectForKey:[specification objectForKey:@"key"]]
                               doubleValue]];
      [slider setContinuous:YES];
      [slider setTarget:graph];
      [slider setAction:@selector (controlChanged:)];
      [accessory addSubview:slider];
      NSTextField *value = [[[NSTextField alloc] initWithFrame:NSMakeRect (462, y, 56, 22)] autorelease];
      [value setEditable:NO];
      [value setBordered:NO];
      [value setDrawsBackground:NO];
      [value setAlignment:NSTextAlignmentRight];
      [value setStringValue:[NSString stringWithFormat:@"%.2f", [slider doubleValue]]];
      [accessory addSubview:value];
      [controls setObject:slider forKey:[specification objectForKey:@"key"]];
      [valueLabels setObject:value forKey:[specification objectForKey:@"key"]];
    }
  [graph setControls:controls valueLabels:valueLabels];
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setMessageText:[NSString stringWithFormat:@"Filter Envelope — Voice %ld",
                                                   (long)[self selectedPatchVoice]]];
  [alert setInformativeText:@"The filter envelope is independent of the amplitude envelope. Velocity can modulate loudness and cutoff separately."];
  [alert setAccessoryView:accessory];
  [alert addButtonWithTitle:@"Apply"];
  [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] != NSAlertFirstButtonReturn)
    return;
  for (NSString *key in controls)
    [_patchFilterValues setObject:[NSNumber numberWithDouble:[[controls objectForKey:key] doubleValue]]
                           forKey:key];
  [self patchControlChanged:nil];
}

- (void)resetInternalSynthPatch:(id)sender
{
  (void)sender;
  NSDictionary *defaults = [ScoreRealtimeDSP defaultInternalSynthPatch];
  [_patchWaveformPopUp selectItemWithTitle:[defaults objectForKey:@"waveform"]];
  for (NSString *key in _patchControls)
    [[_patchControls objectForKey:key] setDoubleValue:[[defaults objectForKey:key] doubleValue]];
  for (NSString *key in _patchFilterValues)
    [_patchFilterValues setObject:[defaults objectForKey:key] forKey:key];
  [_realtimeDSP configureInternalSynthEffects:[NSArray array]
                                     forVoice:[self selectedPatchVoice]
                                        error:NULL];
  [self patchControlChanged:nil];
}

- (void)previewInternalSynthPatch:(id)sender
{
  (void)sender;
  [self stopAudition];
  [_realtimeDSP useInternalSynthesizer];
  _useRealtimeDSP = YES;
  NSError *error = nil;
  if (![_realtimeDSP startWithError:&error])
    {
      [[NSDocumentController sharedDocumentController] presentError:error];
      return;
    }
  NSInteger voice = [self selectedPatchVoice];
  [_realtimeDSP noteOn:60 voice:voice velocity:104];
  _realtimeDSPPitch = 60;
  _realtimeDSPVoice = voice;
  _auditionResetTimer = [[NSTimer scheduledTimerWithTimeInterval:0.75
                                                          target:self
                                                        selector:@selector (finishAudition:)
                                                        userInfo:nil
                                                         repeats:NO] retain];
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
            NSMutableDictionary *parameters = [NSMutableDictionary
              dictionaryWithDictionary:[[part instrument] parameters]
                                       ?: [NSDictionary dictionary]];
            NSDictionary *patch = [parameters objectForKey:@"internalSynthPatch"]
                                    ?: [ScoreRealtimeDSP defaultInternalSynthPatch];
            [parameters setObject:patch forKey:@"internalSynthPatch"];
            [[part instrument] setBackendIdentifier:@"scoremaker-internal-synth"];
            [[part instrument] setParameters:parameters];
            [self configureVoicePatchesForPart:part];
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
                   [self rebuildInstrumentPopUpSelectingCurrentSound];
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
      [enabled setButtonType:ScoreMakerSwitchButton];
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
      if ([[[effectPart instrument] backendIdentifier]
            isEqualToString:@"scoremaker-internal-synth"])
        {
          [self configureVoicePatchesForPart:effectPart];
          _useRealtimeDSP = YES;
        }
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
        @"on" : [NSNumber numberWithBool:![event noteOff]],
        @"voice" : [NSNumber numberWithInteger:[note voice]]
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
  if (_routingMatrixWindow && [_routingMatrixWindow isVisible])
    [self refreshRoutingMatrix];
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
          ScoreNote *enteredNote =
            [self appendMIDINotePitch:data1
                             velocity:data2
                                track:destinationTrack
                            startTick:_midiStepStartTick
                        durationTicks:[self durationTicksForNoteValueDenominator:
                                              [self denominatorForSelectedNoteValue]]];
          [_midiHeldStepNotes addObject:key];
          if (enteredNote)
            [_midiHeldStepScoreNotes setObject:enteredNote forKey:key];
          [[[self scoreDocument] notes] sortUsingSelector:@selector (compareScoreNote:)];
          [self updateChangeCount:NSChangeDone];
          [self updateScoreSourceMIDIInputHighlight];
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
      [_midiHeldStepScoreNotes removeObjectForKey:key];
      [self updateScoreSourceMIDIInputHighlight];
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
      [_midiHeldStepScoreNotes removeAllObjects];
      [self updateScoreSourceMIDIInputHighlight];
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
  [_midiHeldStepScoreNotes removeAllObjects];
  [self updateScoreSourceMIDIInputHighlight];
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

- (NSString *)generatedScoreSourceWithError:(NSError **)error
{
  NSData *data = [ScorefileParser dataForDocument:[self scoreDocument] error:error];
  if (!data)
    return nil;
  return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

- (void)refreshScoreSourceEditorFromScoreIfClean
{
  if (!_scoreSourceTextView || _scoreSourceEditorDirty)
    return;
  NSError *error = nil;
  NSString *source = [self generatedScoreSourceWithError:&error];
  if (!source)
    {
      [_scoreSourceStatusLabel setStringValue:[NSString
        stringWithFormat:@"Could not refresh source: %@", [error localizedDescription]]];
      return;
    }
  [self clearScoreSourcePlaybackHighlight];
  [self clearScoreSourceErrorHighlight];
  _updatingScoreSourceEditor = YES;
  [_scoreSourceTextView setString:source];
  _updatingScoreSourceEditor = NO;
  [_scoreSourceStatusLabel setStringValue:@"Source updated from the current score."];
  [self updateScoreSourceSyntaxHighlighting];
  [self resetScoreSourceRangeCache];
}

- (void)positionScoreSourceEditorBesideDocument
{
  [self positionAuxiliaryWindowBesideDocument:_scoreSourceEditorWindow];
}

- (void)positionAuxiliaryWindowBesideDocument:(NSWindow *)auxiliaryWindow
{
  NSWindow *documentWindow = [self window];
  if (!documentWindow || !auxiliaryWindow)
    return;
  NSWindow *oldParent = [auxiliaryWindow parentWindow];
  if (oldParent && oldParent != documentWindow)
    [oldParent removeChildWindow:auxiliaryWindow];
  NSRect documentFrame = [documentWindow frame];
  NSRect auxiliaryFrame = [auxiliaryWindow frame];
  auxiliaryFrame.origin.x = NSMaxX (documentFrame) + 10.0;
  auxiliaryFrame.origin.y = NSMaxY (documentFrame) - auxiliaryFrame.size.height;
  [auxiliaryWindow setFrame:auxiliaryFrame display:NO];
  if ([auxiliaryWindow parentWindow] != documentWindow)
    [documentWindow addChildWindow:auxiliaryWindow ordered:NSWindowAbove];
}

- (void)arrangeScoreAuxiliaryWindows
{
  BOOL sourceVisible = _scoreSourceEditorWindow && [_scoreSourceEditorWindow isVisible];
  BOOL patchVisible = _patchEditorWindow && [_patchEditorWindow isVisible];
  if (!sourceVisible && !patchVisible)
    return;
  if (sourceVisible)
    [self positionAuxiliaryWindowBesideDocument:_scoreSourceEditorWindow];
  if (patchVisible)
    {
      [self positionAuxiliaryWindowBesideDocument:_patchEditorWindow];
      if (sourceVisible)
        {
          NSRect sourceFrame = [_scoreSourceEditorWindow frame];
          NSRect patchFrame = [_patchEditorWindow frame];
          patchFrame.origin.x = sourceFrame.origin.x;
          patchFrame.origin.y = NSMinY (sourceFrame) - 10.0 - patchFrame.size.height;
          [_patchEditorWindow setFrame:patchFrame display:NO];
        }
    }
}

- (void)showScoreSourceEditor:(id)sender
{
  (void)sender;
  if (!_scoreSourceEditorWindow)
    {
      NSRect frame = NSMakeRect (160.0, 140.0, 820.0, 650.0);
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
      NSUInteger style = ScoreMakerWindowTitled | ScoreMakerWindowClosable | ScoreMakerWindowMiniaturizable
                         | ScoreMakerWindowResizable;
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
      _scoreSourceEditorWindow = [[NSWindow alloc] initWithContentRect:frame
                                                             styleMask:style
                                                               backing:NSBackingStoreBuffered
                                                                 defer:NO];
      [_scoreSourceEditorWindow setReleasedWhenClosed:NO];
      [_scoreSourceEditorWindow setTitle:[NSString
        stringWithFormat:@"Score Source — %@", [self displayName]]];

      NSView *content = [_scoreSourceEditorWindow contentView];
      NSRect bounds = [content bounds];
      _scoreSourceStatusLabel = [[NSTextField alloc]
        initWithFrame:NSMakeRect (14.0, bounds.size.height - 34.0,
                                  bounds.size.width - 28.0, 20.0)];
      [_scoreSourceStatusLabel setEditable:NO];
      [_scoreSourceStatusLabel setSelectable:NO];
      [_scoreSourceStatusLabel setBezeled:NO];
      [_scoreSourceStatusLabel setDrawsBackground:NO];
      [_scoreSourceStatusLabel setFont:[NSFont systemFontOfSize:11.0]];
      [_scoreSourceStatusLabel setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
      [content addSubview:_scoreSourceStatusLabel];

      NSScrollView *sourceScroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect (14.0, 54.0, bounds.size.width - 28.0,
                                  bounds.size.height - 96.0)] autorelease];
      [sourceScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
      [sourceScroll setHasVerticalScroller:YES];
      [sourceScroll setHasHorizontalScroller:YES];
      [sourceScroll setBorderType:NSBezelBorder];
      _scoreSourceTextView = [[NSTextView alloc] initWithFrame:[[sourceScroll contentView] bounds]];
      [_scoreSourceTextView setMinSize:NSMakeSize (0.0, 0.0)];
      [_scoreSourceTextView setMaxSize:NSMakeSize (FLT_MAX, FLT_MAX)];
      [_scoreSourceTextView setVerticallyResizable:YES];
      [_scoreSourceTextView setHorizontallyResizable:YES];
      [[_scoreSourceTextView textContainer] setContainerSize:NSMakeSize (FLT_MAX, FLT_MAX)];
      [[_scoreSourceTextView textContainer] setWidthTracksTextView:NO];
      [_scoreSourceTextView setRichText:NO];
      [_scoreSourceTextView setAllowsUndo:YES];
      [_scoreSourceTextView setFont:[NSFont userFixedPitchFontOfSize:13.0]];
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector (scoreSourceTextDidChange:)
                                                   name:NSTextDidChangeNotification
                                                 object:_scoreSourceTextView];
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector (scoreSourceSelectionDidChange:)
                                                   name:NSTextViewDidChangeSelectionNotification
                                                 object:_scoreSourceTextView];
      [sourceScroll setDocumentView:_scoreSourceTextView];
      [content addSubview:sourceScroll];

      NSButton *revertButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect (14.0, 14.0, 170.0, 30.0)] autorelease];
      [revertButton setTitle:@"Regenerate from Score"];
      [revertButton setTarget:self];
      [revertButton setAction:@selector (revertScoreSource:)];
      [revertButton setAutoresizingMask:NSViewMaxXMargin | NSViewMaxYMargin];
      [content addSubview:revertButton];

      NSButton *applyButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect (bounds.size.width - 114.0, 14.0, 100.0, 30.0)] autorelease];
      [applyButton setTitle:@"Apply"];
      [applyButton setTarget:self];
      [applyButton setAction:@selector (applyScoreSource:)];
      [applyButton setKeyEquivalent:@"\r"];
      [applyButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
      [content addSubview:applyButton];
    }

  if (!_scoreSourceEditorDirty)
    {
      NSError *error = nil;
      NSString *source = _scoreSourceIsAuthoritative ? _scoreSourceText
                                                     : [self generatedScoreSourceWithError:&error];
      if (!source)
        {
          [self presentError:error];
          return;
        }
      _updatingScoreSourceEditor = YES;
      [_scoreSourceTextView setString:source];
      _updatingScoreSourceEditor = NO;
      [_scoreSourceStatusLabel setStringValue:@"Source matches the current score."];
      [self updateScoreSourceSyntaxHighlighting];
      [self resetScoreSourceRangeCache];
    }
  [self positionScoreSourceEditorBesideDocument];
  [_scoreSourceEditorWindow makeKeyAndOrderFront:self];
  [self arrangeScoreAuxiliaryWindows];
}

- (void)scoreSourceTextDidChange:(NSNotification *)notification
{
  (void)notification;
  if (_updatingScoreSourceEditor)
    return;
  [self clearScoreSourceErrorHighlight];
  _scoreSourceEditorDirty = YES;
  [self clearScoreSourcePlaybackHighlight];
  [self resetScoreSourceRangeCache];
  [_scoreSourceStatusLabel
    setStringValue:@"Edited source has not been applied to the score."];
  [self updateScoreSourceSyntaxHighlighting];
}

- (void)clearScoreSourceErrorHighlight
{
  if (_scoreSourceTextView && _scoreSourceErrorRange)
    {
      NSRange range = [_scoreSourceErrorRange rangeValue];
      NSUInteger length = [[_scoreSourceTextView string] length];
      if (range.location < length)
        {
          range.length = MIN (range.length, length - range.location);
          NSLayoutManager *layout = [_scoreSourceTextView layoutManager];
          [layout removeTemporaryAttribute:NSBackgroundColorAttributeName
                         forCharacterRange:range];
          [layout removeTemporaryAttribute:NSUnderlineStyleAttributeName
                         forCharacterRange:range];
          [layout removeTemporaryAttribute:NSUnderlineColorAttributeName
                         forCharacterRange:range];
        }
    }
  [_scoreSourceErrorRange release];
  _scoreSourceErrorRange = nil;
}

- (void)showScoreSourceError:(NSError *)error
{
  [self clearScoreSourceErrorHighlight];
  NSValue *value = [[error userInfo] objectForKey:ScorefileErrorRangeKey];
  if (!value)
    return;
  NSRange range = [value rangeValue];
  NSUInteger length = [[_scoreSourceTextView string] length];
  if (range.location >= length)
    return;
  range.length = MAX ((NSUInteger)1, MIN (range.length, length - range.location));
  _scoreSourceErrorRange = [[NSValue valueWithRange:range] retain];
  NSLayoutManager *layout = [_scoreSourceTextView layoutManager];
  [layout addTemporaryAttribute:NSBackgroundColorAttributeName
                         value:[[NSColor redColor] colorWithAlphaComponent:0.16]
             forCharacterRange:range];
  [layout addTemporaryAttribute:NSUnderlineStyleAttributeName
                         value:[NSNumber numberWithInteger:NSUnderlineStyleSingle]
             forCharacterRange:range];
  [layout addTemporaryAttribute:NSUnderlineColorAttributeName
                         value:[NSColor redColor]
             forCharacterRange:range];
  [_scoreSourceTextView scrollRangeToVisible:range];
}

static NSString *
ScoreSourceNoteIdentity (ScoreNote *note, ScoreDocument *document)
{
  double ticksPerQuarter = MAX ((double)1.0, (double)[document ticksPerQuarter]);
  long long startMicrobeats = llround ((double)[note startTick] * 1000000.0 / ticksPerQuarter);
  long long durationMicrobeats
    = llround ((double)[note durationTicks] * 1000000.0 / ticksPerQuarter);
  return [NSString stringWithFormat:@"%ld:%lld:%lld:%ld:%ld:%d", (long)[note track],
                                   startMicrobeats, durationMicrobeats, (long)[note pitch],
                                   (long)[note voice],
                                   [note isRest] ? 1 : 0];
}

- (void)resetScoreSourceRangeCache
{
  [_scoreSourceNoteRangeCache release];
  _scoreSourceNoteRangeCache = [[NSMutableDictionary alloc] init];
  [_scoreSourceRangeMappings release];
  _scoreSourceRangeMappings = nil;
  [_scoreSourcePlaybackSignature release];
  _scoreSourcePlaybackSignature = nil;
  [_scoreSourceActivePlaybackNotes release];
  _scoreSourceActivePlaybackNotes = [[NSMutableSet alloc] init];
  _scoreSourcePlaybackNoteIndex = 0;
  _scoreSourceLastPlaybackTick = NSNotFound;
  if (_scoreSourceEditorDirty || !_scoreSourceTextView)
    return;

  NSArray *parsedRanges = nil;
  NSString *title = [[[[self fileURL] path] lastPathComponent] stringByDeletingPathExtension];
  ScoreDocument *parsed = [ScorefileParser parseString:[_scoreSourceTextView string]
                                        suggestedTitle:title
                                      noteSourceRanges:&parsedRanges
                                                 error:NULL];
  if (!parsed)
    return;
  NSMutableDictionary *availableNotes = [NSMutableDictionary dictionary];
  for (ScoreNote *note in [[self scoreDocument] notes])
    {
      NSString *identity = ScoreSourceNoteIdentity (note, [self scoreDocument]);
      NSMutableArray *notes = [availableNotes objectForKey:identity];
      if (!notes)
        {
          notes = [NSMutableArray array];
          [availableNotes setObject:notes forKey:identity];
        }
      [notes addObject:note];
    }
  NSMutableArray *mappings = [NSMutableArray array];
  for (NSDictionary *entry in parsedRanges)
    {
      ScoreNote *parsedNote = [entry objectForKey:@"note"];
      NSString *identity = ScoreSourceNoteIdentity (parsedNote, parsed);
      NSMutableArray *notes = [availableNotes objectForKey:identity];
      if (![notes count])
        continue;
      ScoreNote *documentNote = [[[notes objectAtIndex:0] retain] autorelease];
      [notes removeObjectAtIndex:0];
      NSRange sourceRange = [[entry objectForKey:@"range"] rangeValue];
      NSValue *range = [NSValue valueWithRange:
        ScoreMakerSourceLineRangeForRange ([_scoreSourceTextView string], sourceRange)];
      NSDictionary *mapping = [NSDictionary dictionaryWithObjectsAndKeys:
        documentNote, @"note", range, @"range", nil];
      [mappings addObject:mapping];
      if (![_scoreSourceNoteRangeCache objectForKey:identity])
        [_scoreSourceNoteRangeCache setObject:range forKey:identity];
    }
  _scoreSourceRangeMappings = [mappings copy];
}

- (NSValue *)sourceRangeForScoreNote:(ScoreNote *)target
{
  if (!target || !_scoreSourceTextView)
    return nil;
  if (!_scoreSourceNoteRangeCache)
    [self resetScoreSourceRangeCache];
  NSString *targetIdentity = ScoreSourceNoteIdentity (target, [self scoreDocument]);
  return [_scoreSourceNoteRangeCache objectForKey:targetIdentity];
}

#if !defined(__APPLE__)
- (void)setScoreSourceSelectedRange:(NSRange)range
                     selectionColor:(NSColor *)color
        preservingHorizontalScroll:(BOOL)preserveHorizontalScroll
{
  if (!_scoreSourceTextView)
    return;

  NSClipView *clipView = nil;
  NSView *superview = [_scoreSourceTextView superview];
  if (preserveHorizontalScroll && [superview isKindOfClass:[NSClipView class]])
    clipView = (NSClipView *)superview;

  NSColor *selectionBackground = color ?: [NSColor selectedTextBackgroundColor];
  NSColor *selectionForeground = [NSColor selectedTextColor] ?: [NSColor textColor];
  [_scoreSourceTextView
    setSelectedTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
                                selectionBackground, NSBackgroundColorAttributeName,
                                selectionForeground, NSForegroundColorAttributeName, nil]];

  NSPoint originalOrigin = clipView ? [clipView bounds].origin : NSZeroPoint;
  [_scoreSourceTextView setSelectedRange:range];
  [_scoreSourceTextView scrollRangeToVisible:
    ScoreMakerSourceRangeWithLookahead ([_scoreSourceTextView string], range, 4)];

  if (clipView)
    {
      NSPoint adjustedOrigin = [clipView bounds].origin;
      adjustedOrigin.x = originalOrigin.x;
      [clipView scrollToPoint:adjustedOrigin];
      if ([[clipView superview] respondsToSelector:@selector (reflectScrolledClipView:)])
        [(NSScrollView *)[clipView superview] reflectScrolledClipView:clipView];
    }
}

- (void)scrollScoreSourceRangesToVisible:(NSArray *)ranges
              preservingHorizontalScroll:(BOOL)preserveHorizontalScroll
{
  if (!_scoreSourceTextView || ![ranges count])
    return;

  NSClipView *clipView = nil;
  NSView *superview = [_scoreSourceTextView superview];
  if (preserveHorizontalScroll && [superview isKindOfClass:[NSClipView class]])
    clipView = (NSClipView *)superview;

  NSPoint originalOrigin = clipView ? [clipView bounds].origin : NSZeroPoint;
  NSRange coveredRange = ScoreMakerSourceRangeCoveringRanges (ranges);
  NSRange scrollRange = ScoreMakerSourceRangeWithLookahead ([_scoreSourceTextView string],
                                                            coveredRange, 4);
  [_scoreSourceTextView scrollRangeToVisible:scrollRange];

  if (clipView)
    {
      NSPoint adjustedOrigin = [clipView bounds].origin;
      adjustedOrigin.x = originalOrigin.x;
      [clipView scrollToPoint:adjustedOrigin];
      if ([[clipView superview] respondsToSelector:@selector (reflectScrolledClipView:)])
        [(NSScrollView *)[clipView superview] reflectScrolledClipView:clipView];
    }
}
#endif

- (void)clearScoreSourcePlaybackHighlight
{
  if (_scoreSourceTextView)
    {
      NSLayoutManager *layout = [_scoreSourceTextView layoutManager];
      for (NSValue *value in _scoreSourcePlaybackRanges)
        [layout removeTemporaryAttribute:NSBackgroundColorAttributeName
                       forCharacterRange:[value rangeValue]];
#if !defined(__APPLE__)
      [_scoreSourceTextView
        setSelectedTextAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSColor selectedTextBackgroundColor],
                                    NSBackgroundColorAttributeName,
                                    [NSColor selectedTextColor], NSForegroundColorAttributeName,
                                    nil]];
#endif
    }
  [_scoreSourcePlaybackRanges release];
  _scoreSourcePlaybackRanges = nil;
  [_scoreSourcePlaybackSignature release];
  _scoreSourcePlaybackSignature = nil;
}

- (void)updateScoreSourcePlaybackHighlightAtTick:(NSUInteger)tick
{
  if (!_scoreSourceEditorWindow || ![_scoreSourceEditorWindow isVisible] ||
      _scoreSourceEditorDirty)
    return;
  if (!_scoreSourceActivePlaybackNotes || _scoreSourceLastPlaybackTick == NSNotFound ||
      tick < _scoreSourceLastPlaybackTick)
    {
      [_scoreSourceActivePlaybackNotes release];
      _scoreSourceActivePlaybackNotes = [[NSMutableSet alloc] init];
      _scoreSourcePlaybackNoteIndex = 0;
    }
  NSArray *notes = [[self scoreDocument] notes];
  while (_scoreSourcePlaybackNoteIndex < [notes count])
    {
      ScoreNote *note = [notes objectAtIndex:_scoreSourcePlaybackNoteIndex];
      if ([note startTick] > tick)
        break;
      if (![note isRest] && [note startTick] + [note durationTicks] > tick)
        [_scoreSourceActivePlaybackNotes addObject:note];
      _scoreSourcePlaybackNoteIndex++;
    }
  NSArray *previouslyActive = [[_scoreSourceActivePlaybackNotes allObjects] copy];
  for (ScoreNote *note in previouslyActive)
    if ([note startTick] + [note durationTicks] <= tick)
      [_scoreSourceActivePlaybackNotes removeObject:note];
  [previouslyActive release];
  _scoreSourceLastPlaybackTick = tick;

  NSArray *active =
    [[_scoreSourceActivePlaybackNotes allObjects] sortedArrayUsingSelector:@selector (compareScoreNote:)];
  NSMutableArray *identities = [NSMutableArray array];
  for (ScoreNote *note in active)
    [identities addObject:ScoreSourceNoteIdentity (note, [self scoreDocument])];
  [identities sortUsingSelector:@selector (compare:)];
  NSString *signature = [identities componentsJoinedByString:@"|"];
  if ([_scoreSourcePlaybackSignature isEqualToString:signature])
    return;
  [self clearScoreSourcePlaybackHighlight];
  _scoreSourcePlaybackSignature = [signature copy];
  if (![active count])
    return;
  NSMutableArray *ranges = [NSMutableArray array];
#if !defined(__APPLE__)
  NSColor *selectedPlaybackColor = nil;
#endif
  NSLayoutManager *layout = [_scoreSourceTextView layoutManager];
  for (ScoreNote *note in active)
    {
      NSValue *value = [self sourceRangeForScoreNote:note];
      if (value && ![ranges containsObject:value])
        {
          [ranges addObject:value];
          NSColor *color = [ScoreVoiceColor ([note voice], NO) colorWithAlphaComponent:0.34];
#if !defined(__APPLE__)
          if (!selectedPlaybackColor)
            selectedPlaybackColor = color;
#endif
          [layout addTemporaryAttribute:NSBackgroundColorAttributeName
                                 value:color
                     forCharacterRange:[value rangeValue]];
        }
    }
  if (![ranges count])
    return;
  _scoreSourcePlaybackRanges = [ranges copy];
#if defined(__APPLE__)
  [_scoreSourceTextView scrollRangeToVisible:[[ranges objectAtIndex:0] rangeValue]];
#else
  _updatingScoreSourceEditor = YES;
  [self setScoreSourceSelectedRange:[[ranges objectAtIndex:0] rangeValue]
                     selectionColor:selectedPlaybackColor
        preservingHorizontalScroll:YES];
  [self scrollScoreSourceRangesToVisible:ranges
              preservingHorizontalScroll:YES];
  _updatingScoreSourceEditor = NO;
#endif
}

- (void)updateScoreSourceMIDIInputHighlight
{
  [self clearScoreSourcePlaybackHighlight];
  if (!_scoreSourceEditorWindow || ![_scoreSourceEditorWindow isVisible]
      || _scoreSourceEditorDirty || ![_midiHeldStepScoreNotes count])
    return;

  NSArray *active = [_midiHeldStepScoreNotes allValues];
  NSMutableArray *ranges = [NSMutableArray array];
  NSLayoutManager *layout = [_scoreSourceTextView layoutManager];
  for (ScoreNote *note in active)
    {
      NSValue *value = [self sourceRangeForScoreNote:note];
      if (value && ![ranges containsObject:value])
        {
          [ranges addObject:value];
          NSColor *color = [ScoreVoiceColor ([note voice], NO) colorWithAlphaComponent:0.42];
          [layout addTemporaryAttribute:NSBackgroundColorAttributeName
                                 value:color
                     forCharacterRange:[value rangeValue]];
        }
    }
  if (![ranges count])
    return;
  _scoreSourcePlaybackRanges = [ranges copy];
  _scoreSourcePlaybackSignature = [@"midi-input" copy];
  [_scoreSourceTextView scrollRangeToVisible:[[ranges objectAtIndex:0] rangeValue]];
}

- (ScoreNote *)scoreNoteForSourceLocation:(NSUInteger)location
{
  if (!_scoreSourceRangeMappings && !_scoreSourceEditorDirty)
    [self resetScoreSourceRangeCache];
  for (NSDictionary *mapping in _scoreSourceRangeMappings)
    {
      NSRange range = [[mapping objectForKey:@"range"] rangeValue];
      if (NSLocationInRange (location, range))
        return [mapping objectForKey:@"note"];
    }
  return nil;
}

- (void)scoreSourceSelectionDidChange:(NSNotification *)notification
{
  (void)notification;
  if (_updatingScoreSourceEditor)
    return;
  NSRange selection = [_scoreSourceTextView selectedRange];
  ScoreNote *note = [self scoreNoteForSourceLocation:selection.location];
  [[self scoreView] selectNote:note scrollToVisible:(note != nil)];
}

- (void)updateScoreSourceSyntaxHighlighting
{
  if (!_scoreSourceTextView || _updatingScoreSourceEditor)
    return;
  NSTextStorage *storage = [_scoreSourceTextView textStorage];
  NSString *source = [storage string];
  NSRange whole = NSMakeRange (0, [source length]);
  _updatingScoreSourceEditor = YES;
  [storage beginEditing];
  [storage setAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
                            [NSFont userFixedPitchFontOfSize:13.0], NSFontAttributeName,
                            [NSColor textColor], NSForegroundColorAttributeName, nil]
                   range:whole];
  NSArray *rules = [NSArray arrayWithObjects:
    [NSArray arrayWithObjects:@"/\\*[\\s\\S]*?\\*/", [NSColor grayColor], nil],
    [NSArray arrayWithObjects:@"\"(?:\\\\.|[^\"\\\\])*\"", [NSColor colorWithCalibratedRed:0.72 green:0.20 blue:0.16 alpha:1.0], nil],
    [NSArray arrayWithObjects:@"\\b(?:info|string|var|part|BEGIN|END|t|tempo|timeSignature|program|keyNum|freq|noteOn|noteOff|noteUpdate)\\b", [NSColor colorWithCalibratedRed:0.22 green:0.28 blue:0.78 alpha:1.0], nil],
    [NSArray arrayWithObjects:@"\\b(?:[a-gA-G](?:s|f|#|b)?-?[0-9]+k?)\\b", [NSColor colorWithCalibratedRed:0.10 green:0.50 blue:0.28 alpha:1.0], nil], nil];
  for (NSArray *rule in rules)
    {
      NSRegularExpression *expression = [NSRegularExpression
        regularExpressionWithPattern:[rule objectAtIndex:0]
                             options:NSRegularExpressionCaseInsensitive
                               error:NULL];
      for (NSTextCheckingResult *match in
           [expression matchesInString:source options:0 range:whole])
        [storage addAttribute:NSForegroundColorAttributeName
                        value:[rule objectAtIndex:1]
                        range:[match range]];
    }
  [storage endEditing];
  _updatingScoreSourceEditor = NO;
}

- (void)applyScoreSource:(id)sender
{
  (void)sender;
  [self clearScoreSourceErrorHighlight];
  NSString *source = [_scoreSourceTextView string];
  NSError *error = nil;
  NSString *suggestedTitle = [[[self fileURL] path] lastPathComponent];
  suggestedTitle = [suggestedTitle stringByDeletingPathExtension];
  ScoreDocument *parsed = [ScorefileParser parseString:source
                                        suggestedTitle:suggestedTitle
                                                 error:&error];
  if (!parsed)
    {
      [self showScoreSourceError:error];
      NSNumber *line = [[error userInfo] objectForKey:ScorefileErrorLineKey];
      NSNumber *column = [[error userInfo] objectForKey:ScorefileErrorColumnKey];
      NSString *location = line ? [NSString stringWithFormat:@" at line %@, column %@",
                                    line, column ?: [NSNumber numberWithInteger:1]] : @"";
      [_scoreSourceStatusLabel setStringValue:[NSString
        stringWithFormat:@"Cannot apply%@ — %@", location, [error localizedDescription]]];
      NSBeep ();
      return;
    }

  [self registerUndoSnapshotWithName:@"Edit Score Source"];
  _applyingScoreSource = YES;
  [parsed copyMIDIRoutingAssignmentsFromDocument:[self scoreDocument]];
  [self setScoreDocument:parsed];
  [[self scoreView] reloadDocument];
  [self refreshInspector];
  [self restoreAudioUnitInstrument];
  [self updateChangeCount:NSChangeDone];
  _applyingScoreSource = NO;
  [_scoreSourceText release];
  _scoreSourceText = [source copy];
  _scoreSourceIsAuthoritative = YES;
  _scoreSourceEditorDirty = NO;
  [self clearScoreSourceErrorHighlight];
  [self resetScoreSourceRangeCache];
  [_scoreSourceStatusLabel setStringValue:[NSString
    stringWithFormat:@"Applied successfully — %lu notes.",
                     (unsigned long)[[parsed notes] count]]];
  [self commitUndoBaseline];
}

- (void)revertScoreSource:(id)sender
{
  (void)sender;
  [self clearScoreSourceErrorHighlight];
  NSError *error = nil;
  NSString *source = [self generatedScoreSourceWithError:&error];
  if (!source)
    {
      [self presentError:error];
      return;
    }
  _updatingScoreSourceEditor = YES;
  [_scoreSourceTextView setString:source];
  _updatingScoreSourceEditor = NO;
  _scoreSourceEditorDirty = NO;
  [self resetScoreSourceRangeCache];
  [_scoreSourceStatusLabel setStringValue:@"Regenerated from the current score."];
  [self updateScoreSourceSyntaxHighlighting];
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
  if ([extension isEqualToString:@"score"])
    {
      NSString *source = [NSString stringWithContentsOfFile:path
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL];
      if (!source)
        source = [NSString stringWithContentsOfFile:path
                                           encoding:NSISOLatin1StringEncoding
                                              error:NULL];
      [_scoreSourceText release];
      _scoreSourceText = [source copy];
      _scoreSourceIsAuthoritative = (_scoreSourceText != nil);
      _scoreSourceEditorDirty = NO;
    }
  [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:url];
  return YES;
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName
{
  return [self readFromURL:url ofType:typeName error:NULL];
}

- (BOOL)readFromFile:(NSString *)fileName ofType:(NSString *)typeName
{
  return [self readFromURL:[NSURL fileURLWithPath:fileName] ofType:typeName error:NULL];
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
  if (_scoreSourceIsAuthoritative && [_scoreSourceText length])
    return [_scoreSourceText dataUsingEncoding:NSUTF8StringEncoding];
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
      data = (_scoreSourceIsAuthoritative && [_scoreSourceText length])
               ? [_scoreSourceText dataUsingEncoding:NSUTF8StringEncoding]
               : [ScorefileParser dataForDocument:document error:error];
    }
  if (!data)
    return NO;
  return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName
{
  return [self writeToURL:url ofType:typeName error:NULL];
}

- (BOOL)writeToFile:(NSString *)fileName ofType:(NSString *)typeName
{
  return [self writeToURL:[NSURL fileURLWithPath:fileName] ofType:typeName error:NULL];
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
