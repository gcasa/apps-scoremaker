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

#import "ScoreView.h"
#import <math.h>

static CGFloat const PageWidth = 980.0;
static CGFloat const PaperInset = 18.0;
static CGFloat const BasePaperHeight = 1222.0;
static CGFloat const PageGap = 24.0;
static CGFloat const Margin = 48.0;
static CGFloat const PartLabelWidth = 82.0;
static CGFloat const SinglePartSystemHeight = 210.0;
static CGFloat const StaffGap = 82.0;
static CGFloat const PartStaffSpacing = 34.0;
static CGFloat const LineSpacing = 10.0;
static CGFloat const ClefImageWidth = 20.0;
static CGFloat const ClefImageHeight = 60.0;
static CGFloat const FirstSystemOffset = 54.0;
static CGFloat const PaletteDragNoteHeadXOffset = 26.0;
static CGFloat const PaletteDragNoteHeadYOffset = 25.0;
static CGFloat const ChordSnapDistance = 9.0;
static CGFloat const NoteHorizontalInset = 6.0;
static CGFloat const MinimumMeasureWidth = 140.0;
static CGFloat const EngravingMusicWidth = 684.0;
static CGFloat const SystemsPageHeight = 1050.0;
NSString *const ScoreViewDidEditScoreNotification = @"ScoreViewDidEditScoreNotification";
NSString *const ScoreViewSelectionDidChangeNotification
  = @"ScoreViewSelectionDidChangeNotification";
NSString *const ScorePalettePasteboardType = @"com.scoremaker.palette-item";

static BOOL
ScoreRectCollides (NSRect rect, NSArray *occupied)
{
  NSRect padded = NSInsetRect (rect, -2.0, -2.0);
  for (NSValue *value in occupied)
    if (NSIntersectsRect (padded, [value rectValue]))
      return YES;
  return NO;
}

static NSRect
ScorePlaceRect (NSRect desired, NSMutableArray *occupied, CGFloat step)
{
  NSRect placed = desired;
  NSUInteger attempts = 0;
  while (ScoreRectCollides (placed, occupied) && attempts++ < 12)
    placed.origin.y += step;
  [occupied addObject:[NSValue valueWithRect:placed]];
  return placed;
}

@implementation ScoreView

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self)
    {
      _separateParts = YES;
      [self registerForDraggedTypes:[NSArray arrayWithObject:ScorePalettePasteboardType]];
    }
  return self;
}

- (BOOL)separateParts
{
  return _separateParts;
}
- (void)setSeparateParts:(BOOL)separate
{
  if (_separateParts == separate)
    return;
  _separateParts = separate;
  [self reloadDocument];
}

- (NSNumber *)publicationTrack
{
  return _publicationTrack;
}
- (void)setPublicationTrack:(NSNumber *)track
{
  if (_publicationTrack == track || [_publicationTrack isEqual:track])
    return;
  [_publicationTrack release];
  _publicationTrack = [track retain];
  [self reloadDocument];
}

- (ScoreDocument *)document
{
  return _document;
}

- (BOOL)isFlipped
{
  return YES;
}

- (void)setDocument:(ScoreDocument *)document
{
  if (_document != document)
    {
      [_document release];
      _document = [document retain];
      _selectedNote = nil;
      [_engravingLayout release];
      _engravingLayout = nil;
      [self reloadDocument];
    }
}

- (ScoreNote *)selectedNote
{
  return _selectedNote;
}

- (void)setPlaybackTick:(NSUInteger)tick
{
  NSUInteger previousTick = _playbackTick;
  BOOL wasShowingPlayback = _showPlayback;
  _playbackTick = tick;
  _showPlayback = YES;

  /* Playback changes only the note highlights.  Invalidating the whole
   * document here made long scores re-render at 30 frames per second. */
  if (wasShowingPlayback)
    {
      NSUInteger previousSystem = 0;
      NSArray *layouts = [self systemLayouts];
      for (NSUInteger index = 0; index < [layouts count]; index++)
        {
          ScoreEngravingSystem *layout = [layouts objectAtIndex:index];
          if (previousTick >= [layout startTick] && previousTick < [layout endTick])
            {
              previousSystem = index;
              break;
            }
        }
      [self setNeedsDisplayInRect:NSInsetRect (
                                     NSMakeRect (0.0, [self yForSystem:previousSystem],
                                                 NSWidth ([self bounds]), [self systemHeight]),
                                     0.0, -12.0)];
    }

  NSUInteger currentSystem = 0;
  NSArray *layouts = [self systemLayouts];
  for (NSUInteger index = 0; index < [layouts count]; index++)
    {
      ScoreEngravingSystem *layout = [layouts objectAtIndex:index];
      if (tick >= [layout startTick] && tick < [layout endTick])
        {
          currentSystem = index;
          break;
        }
    }
  [self setNeedsDisplayInRect:NSInsetRect (
                                 NSMakeRect (0.0, [self yForSystem:currentSystem],
                                             NSWidth ([self bounds]), [self systemHeight]),
                                 0.0, -12.0)];
}

- (void)clearPlayback
{
  if (_showPlayback)
    {
      _showPlayback = NO;
      NSUInteger system = 0;
      NSArray *layouts = [self systemLayouts];
      for (NSUInteger index = 0; index < [layouts count]; index++)
        {
          ScoreEngravingSystem *layout = [layouts objectAtIndex:index];
          if (_playbackTick >= [layout startTick] && _playbackTick < [layout endTick])
            {
              system = index;
              break;
            }
        }
      [self setNeedsDisplayInRect:NSInsetRect (
                                     NSMakeRect (0.0, [self yForSystem:system],
                                                 NSWidth ([self bounds]), [self systemHeight]),
                                     0.0, -12.0)];
    }
}

- (void)scrollPlaybackTickToVisible:(NSUInteger)tick
{
  NSUInteger system = 0;
  NSArray *layouts = [self systemLayouts];
  for (NSUInteger index = 0; index < [layouts count]; index++)
    {
      ScoreEngravingSystem *layout = [layouts objectAtIndex:index];
      if (tick >= [layout startTick] && tick < [layout endTick])
        {
          system = index;
          break;
        }
    }
  CGFloat systemY = [self yForSystem:system];
  NSRect visible = [self visibleRect];
  NSRect target = NSMakeRect (NSMinX (visible), systemY - 28.0, 1.0, [self systemHeight] + 56.0);
  if (NSMinY (target) < NSMinY (visible) || NSMaxY (target) > NSMaxY (visible))
    {
      [self scrollRectToVisible:target];
    }
}

- (void)dealloc
{
  [_document release];
  [_engravingLayout release];
  [_publicationTrack release];
  [super dealloc];
}

- (void)updateFrameForDocument
{
  NSUInteger pages = [self pageCount];
  CGFloat height
    = 2.0 * PaperInset + (CGFloat)pages * [self paperHeight] + (CGFloat)(pages - 1) * PageGap;
  [self setFrameSize:NSMakeSize (PageWidth, height)];
}

- (void)reloadDocument
{
  [_engravingLayout release];
  _engravingLayout = nil;
  [self updateFrameForDocument];
  [self setNeedsDisplay:YES];
}

- (NSArray *)systemLayouts
{
  if (_engravingLayout)
    return [_engravingLayout systems];
  if (!_document)
    return [NSArray array];
  ScoreDocument *layoutDocument = _document;
  if (_publicationTrack)
    {
      layoutDocument = [[_document copy] autorelease];
      NSMutableArray *notes = [NSMutableArray array];
      for (ScoreNote *note in [_document notes])
        if ([note track] == [_publicationTrack integerValue])
          [notes addObject:note];
      [layoutDocument setNotes:notes];
    }
  ScoreEngraver *engraver = [[[ScoreEngraver alloc] init] autorelease];
  _engravingLayout = [[engraver layoutDocument:layoutDocument
                                    musicWidth:EngravingMusicWidth
                           minimumMeasureWidth:MinimumMeasureWidth] retain];
  return [_engravingLayout systems];
}

- (NSUInteger)systemCount
{
  return MAX ((NSUInteger)1, [[self systemLayouts] count]);
}

- (NSUInteger)pageCount
{
  NSUInteger perPage = [self systemsPerPage];
  return MAX ((NSUInteger)1, ([self systemCount] + perPage - 1) / perPage);
}

- (NSArray *)scoreTracks
{
  if (_publicationTrack)
    return [NSArray arrayWithObject:_publicationTrack];
  NSMutableSet *trackSet = [NSMutableSet setWithArray:[[_document partNames] allKeys]];
  for (ScoreNote *note in [_document notes])
    [trackSet addObject:[NSNumber numberWithInteger:[note track]]];
  if ([trackSet count] == 0)
    [trackSet addObject:@0];
  return [[trackSet allObjects] sortedArrayUsingSelector:@selector (compare:)];
}

- (CGFloat)partGrandStaffHeight
{
  return StaffGap + 4.0 * LineSpacing;
}

- (CGFloat)systemHeight
{
  NSUInteger parts = _separateParts ? MAX ((NSUInteger)1, [[self scoreTracks] count]) : 1;
  return [self partGrandStaffHeight] * parts + PartStaffSpacing * (parts - 1)
         + (SinglePartSystemHeight - [self partGrandStaffHeight]);
}

- (NSUInteger)systemsPerPage
{
  return MAX ((NSUInteger)1, (NSUInteger)floor (SystemsPageHeight / [self systemHeight]));
}

- (CGFloat)paperHeight
{
  /* Keep unusually large ensembles on the paper instead of clipping staves. */
  return MAX (BasePaperHeight, Margin + FirstSystemOffset + [self systemHeight] + Margin);
}

- (CGFloat)pageOriginY:(NSUInteger)page
{
  return PaperInset + (CGFloat)page * ([self paperHeight] + PageGap);
}

- (CGFloat)yForSystem:(NSUInteger)system
{
  NSUInteger perPage = [self systemsPerPage];
  NSUInteger page = system / perPage;
  NSUInteger systemOnPage = system % perPage;
  return [self pageOriginY:page] + Margin + FirstSystemOffset
         + (CGFloat)systemOnPage * [self systemHeight];
}

- (BOOL)knowsPageRange:(NSRangePointer)range
{
  if (range)
    *range = NSMakeRange (1, [self pageCount]);
  return YES;
}

- (NSRect)rectForPage:(NSInteger)page
{
  NSUInteger pageIndex = page > 0 ? (NSUInteger)page - 1 : 0;
  return NSMakeRect (PaperInset, [self pageOriginY:pageIndex], PageWidth - 2.0 * PaperInset,
                     [self paperHeight]);
}

- (NSSize)printedPageContentSize
{
  return NSMakeSize (PageWidth - 2.0 * PaperInset, [self paperHeight]);
}

- (void)drawRect:(NSRect)dirtyRect
{
  BOOL drawingToScreen = [[NSGraphicsContext currentContext] isDrawingToScreen];
  NSColor *backgroundColor
    = drawingToScreen ? [NSColor colorWithCalibratedWhite:0.78 alpha:1.0] : [NSColor whiteColor];
  [backgroundColor setFill];
  NSRectFill ([self bounds]);

  if (drawingToScreen)
    {
      for (NSUInteger page = 0; page < [self pageCount]; page++)
        {
          NSRect paper = NSMakeRect (PaperInset, [self pageOriginY:page],
                                     PageWidth - 2.0 * PaperInset, [self paperHeight]);
          if (!NSIntersectsRect (NSInsetRect (dirtyRect, -8.0, -8.0), paper))
            continue;
          [[NSColor colorWithCalibratedWhite:0.75 alpha:0.35] setFill];
          NSRectFill (NSOffsetRect (paper, 3.0, 4.0));
          [[NSColor whiteColor] setFill];
          NSRectFill (paper);
          [[NSColor colorWithCalibratedWhite:0.82 alpha:1.0] setStroke];
          NSFrameRect (paper);
        }
    }

  if (!_document)
    {
      [self drawCenteredMessage:@"Open a MIDI or score file to display sheet music."];
      return;
    }

  if (!drawingToScreen)
    {
      NSPrintInfo *printInfo = [[NSPrintOperation currentOperation] printInfo];
      NSRect imageableBounds
        = printInfo ? [printInfo imageablePageBounds] : NSMakeRect (0.0, 0.0, 540.0, 720.0);
      NSSize pageSize = [self printedPageContentSize];
      CGFloat widthScale = (NSWidth (imageableBounds) - 24.0) / MAX (pageSize.width, 1.0);
      CGFloat heightScale = (NSHeight (imageableBounds) - 24.0) / MAX (pageSize.height, 1.0);
      CGFloat printScale = MIN ((CGFloat)1.0, MIN (widthScale, heightScale));
      NSUInteger systemCount = [self systemCount];

      for (NSUInteger page = 0; page < [self pageCount]; page++)
        {
          NSRect paper = NSMakeRect (PaperInset, [self pageOriginY:page],
                                     PageWidth - 2.0 * PaperInset, [self paperHeight]);
          if (!NSIntersectsRect (dirtyRect, paper))
            continue;

          [NSGraphicsContext saveGraphicsState];
          NSRectClip (paper);
          CGFloat centerX = NSMidX (paper);
          CGFloat pageTop = NSMinY (paper);
          NSAffineTransform *fit = [NSAffineTransform transform];
          [fit translateXBy:centerX yBy:pageTop];
          [fit scaleBy:printScale];
          [fit translateXBy:-centerX yBy:-pageTop];
          [fit concat];

          [self drawHeaderForPage:page atOriginY:[self pageOriginY:page]];
          NSUInteger perPage = [self systemsPerPage];
          NSUInteger firstSystem = page * perPage;
          NSUInteger lastSystem = MIN (systemCount, firstSystem + perPage);
          for (NSUInteger system = firstSystem; system < lastSystem; system++)
            {
              [self drawSystemAtY:[self yForSystem:system] systemIndex:system];
            }
          [NSGraphicsContext restoreGraphicsState];
        }
      return;
    }

  for (NSUInteger page = 0; page < [self pageCount]; page++)
    {
      CGFloat originY = [self pageOriginY:page];
      NSRect paper = NSMakeRect (PaperInset, originY, PageWidth - 2.0 * PaperInset,
                                 [self paperHeight]);
      if (NSIntersectsRect (dirtyRect, paper))
        [self drawHeaderForPage:page atOriginY:originY];
    }
  NSUInteger systemCount = [self systemCount];
  for (NSUInteger system = 0; system < systemCount; system++)
    {
      CGFloat y = [self yForSystem:system];
      NSRect systemRect = NSInsetRect (
        NSMakeRect (0.0, y, NSWidth ([self bounds]), [self systemHeight]), 0.0, -12.0);
      if (!NSIntersectsRect (dirtyRect, systemRect))
        continue;
      [self drawSystemAtY:y systemIndex:system];
    }
}

- (void)drawCenteredMessage:(NSString *)message
{
  NSDictionary *attrs =
    [NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:18.0], NSFontAttributeName,
                                               [NSColor colorWithCalibratedWhite:0.3 alpha:1.0],
                                               NSForegroundColorAttributeName, nil];
  NSSize size = [message sizeWithAttributes:attrs];
  NSRect bounds = [self bounds];
  [message drawAtPoint:NSMakePoint ((bounds.size.width - size.width) / 2.0,
                                    (bounds.size.height - size.height) / 2.0)
        withAttributes:attrs];
}

- (void)drawHeaderForPage:(NSUInteger)page atOriginY:(CGFloat)pageOriginY
{
  CGFloat titleSize = page == 0 ? 30.0 : 18.0;
  NSFont *titleFont = [NSFont fontWithName:[_document titleFontName] size:titleSize];
  if (!titleFont)
    titleFont = [NSFont fontWithName:@"Times New Roman" size:titleSize];
  if (!titleFont)
    titleFont = [NSFont systemFontOfSize:titleSize];
  NSMutableParagraphStyle *centered = [[[NSMutableParagraphStyle alloc] init] autorelease];
  [centered setAlignment:NSTextAlignmentCenter];
  NSDictionary *titleAttrs =
    [NSDictionary dictionaryWithObjectsAndKeys:titleFont, NSFontAttributeName, [NSColor blackColor],
                                               NSForegroundColorAttributeName, centered,
                                               NSParagraphStyleAttributeName, nil];
  NSString *title = [_document title] ? [_document title] : @"Untitled";
  NSRect titleRect = NSMakeRect (Margin + 90.0, pageOriginY + Margin - 28.0,
                                 PageWidth - 2.0 * (Margin + 90.0), 40.0);
  [title drawInRect:titleRect withAttributes:titleAttrs];
  if (_publicationTrack)
    {
      NSString *partName = [_document nameForTrack:[_publicationTrack integerValue]];
      if (![partName length])
        partName =
          [NSString stringWithFormat:@"Part %ld", (long)([_publicationTrack integerValue] + 1)];
      NSDictionary *partAttrs = [NSDictionary
        dictionaryWithObjectsAndKeys:[NSFont boldSystemFontOfSize:14.0], NSFontAttributeName,
                                     [NSColor blackColor], NSForegroundColorAttributeName, centered,
                                     NSParagraphStyleAttributeName, nil];
      [partName drawInRect:NSMakeRect (Margin + 90.0, pageOriginY + Margin + 8.0,
                                       PageWidth - 2.0 * (Margin + 90.0), 22.0)
            withAttributes:partAttrs];
    }

  NSFont *pageNumberFont = [NSFont fontWithName:@"Times New Roman" size:12.0];
  if (!pageNumberFont)
    pageNumberFont = [NSFont systemFontOfSize:12.0];
  NSMutableParagraphStyle *rightAligned = [[[NSMutableParagraphStyle alloc] init] autorelease];
  [rightAligned setAlignment:NSTextAlignmentRight];
  NSDictionary *pageNumberAttrs =
    [NSDictionary dictionaryWithObjectsAndKeys:pageNumberFont, NSFontAttributeName,
                                               [NSColor blackColor], NSForegroundColorAttributeName,
                                               rightAligned, NSParagraphStyleAttributeName, nil];
  NSString *pageNumber = [NSString stringWithFormat:@"%lu", (unsigned long)(page + 1)];
  NSRect pageNumberRect
    = NSMakeRect (PageWidth - Margin - 54.0, pageOriginY + Margin - 24.0, 54.0, 20.0);
  [pageNumber drawInRect:pageNumberRect withAttributes:pageNumberAttrs];

  NSString *composer = [_document composer];
  if (page == 0 && [composer length] > 0)
    {
      NSFont *composerFont = [NSFont fontWithName:@"Times New Roman" size:15.0];
      if (!composerFont)
        composerFont = [NSFont systemFontOfSize:15.0];
      NSDictionary *composerAttrs = [NSDictionary
        dictionaryWithObjectsAndKeys:composerFont, NSFontAttributeName, [NSColor blackColor],
                                     NSForegroundColorAttributeName, rightAligned,
                                     NSParagraphStyleAttributeName, nil];
      NSRect composerRect
        = NSMakeRect (PageWidth / 2.0, pageOriginY + Margin + 10.0, PageWidth / 2.0 - Margin, 24.0);
      [composer drawInRect:composerRect withAttributes:composerAttrs];
    }
}

- (void)drawSystemAtY:(CGFloat)y systemIndex:(NSUInteger)systemIndex
{
  CGFloat left = Margin + PartLabelWidth;
  CGFloat right = PageWidth - Margin;
  ScoreEngravingSystem *layout = [[self systemLayouts] objectAtIndex:systemIndex];
  NSUInteger startTick = [layout startTick];
  NSUInteger endTick = [layout endTick];

  CGFloat musicLeft = left + 100.0;
  CGFloat musicRight = right - 18.0;
  NSArray *tracks = _separateParts ? [self scoreTracks] : [NSArray arrayWithObject:@-1];
  CGFloat partStride = [self partGrandStaffHeight] + PartStaffSpacing;
  NSUInteger perPage = [self systemsPerPage];
  for (NSUInteger partIndex = 0; partIndex < [tracks count]; partIndex++)
    {
      NSInteger track = [[tracks objectAtIndex:partIndex] integerValue];
      CGFloat trebleTop = y + partIndex * partStride;
      CGFloat bassTop = trebleTop + StaffGap;
      [self drawPartNameForTrack:track
                               x:Margin - 10.0
                               y:trebleTop
                          height:[self partGrandStaffHeight]];
      [self drawStaffFromX:left toX:right topY:trebleTop];
      [self drawStaffFromX:left toX:right topY:bassTop];
      [self drawBraceAtX:left - 14.0 topY:trebleTop bottomY:bassTop + 4.0 * LineSpacing];
      [self
        drawClefNamed:@"treble_clef"
             fallback:@"G"
               inRect:NSMakeRect (left + 14.0, trebleTop - 10.0, ClefImageWidth, ClefImageHeight)];
      [self
        drawClefNamed:@"bass_clef"
             fallback:@"F"
               inRect:NSMakeRect (left + 16.0, bassTop - 10.0, ClefImageWidth, ClefImageHeight)];
      if (systemIndex == 0 && partIndex == 0)
        [self drawTempoMarkAtX:musicLeft y:trebleTop - 30.0];
      if (systemIndex % perPage == 0)
        [self drawTimeSignatureAtX:left + 58.0 trebleY:trebleTop bassY:bassTop];
      ScoreMeasure *openingMeasure = [_document measureContainingTick:startTick];
      if (openingMeasure && [openingMeasure keySignatureFifths] != 0)
        [self drawKeySignature:[openingMeasure keySignatureFifths]
                           atX:left + 39.0
                       trebleY:trebleTop
                         bassY:bassTop];
      [self drawMeasureLinesFromX:musicLeft
                              toX:musicRight
                             topY:trebleTop
                      systemStart:startTick
                        systemEnd:endTick];
      [self drawNotesFromX:musicLeft
                       toX:musicRight
                   trebleY:trebleTop
                     bassY:bassTop
               systemStart:startTick
                 systemEnd:endTick
                     track:track];
    }
}

- (void)drawKeySignature:(NSInteger)fifths
                     atX:(CGFloat)x
                 trebleY:(CGFloat)trebleY
                   bassY:(CGFloat)bassY
{
  NSString *symbol = fifths > 0 ? @"♯" : @"♭";
  NSInteger count = labs (fifths);
  NSInteger sharpSteps[] = { 0, 3, -1, 2, 5, 1, 4 };
  NSInteger flatSteps[] = { 4, 1, 5, 2, 6, 3, 7 };
  NSDictionary *attrs =
    [NSDictionary dictionaryWithObjectsAndKeys:([NSFont fontWithName:@"Times New Roman" size:18.0]
                                                  ?: [NSFont systemFontOfSize:16.0]),
                                               NSFontAttributeName, [NSColor blackColor],
                                               NSForegroundColorAttributeName, nil];
  for (NSInteger i = 0; i < count; i++)
    {
      NSInteger step = fifths > 0 ? sharpSteps[i] : flatSteps[i];
      [symbol drawAtPoint:NSMakePoint (x + i * 8.0, trebleY + step * 2.5 - 9.0)
           withAttributes:attrs];
      [symbol drawAtPoint:NSMakePoint (x + i * 8.0, bassY + step * 2.5 - 9.0) withAttributes:attrs];
    }
}

- (void)drawTempoMarkAtX:(CGFloat)x y:(CGFloat)y
{
  NSUInteger tempo = [_document tempoMicrosecondsPerQuarter];
  if (tempo == 0)
    {
      return;
    }

  NSUInteger beatsPerMinute = (NSUInteger)((60000000.0 / (double)tempo) + 0.5);
  NSDictionary *attrs = [NSDictionary
    dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:13.0], NSFontAttributeName,
                                 [NSColor blackColor], NSForegroundColorAttributeName, nil];

  CGFloat noteCenterY = y + 8.0;
  NSBezierPath *head =
    [NSBezierPath bezierPathWithOvalInRect:NSMakeRect (x, noteCenterY - 3.0, 8.0, 6.0)];
  NSAffineTransform *slant = [NSAffineTransform transform];
  [slant translateXBy:x + 4.0 yBy:noteCenterY];
  [slant rotateByDegrees:-18.0];
  [slant translateXBy:-(x + 4.0) yBy:-noteCenterY];
  [head transformUsingAffineTransform:slant];
  [[NSColor blackColor] setFill];
  [head fill];

  CGFloat stemX = x + 7.5;
  [NSBezierPath strokeLineFromPoint:NSMakePoint (stemX, noteCenterY)
                            toPoint:NSMakePoint (stemX, noteCenterY - 24.0)];

  NSString *tempoText = [NSString stringWithFormat:@"= %lu", (unsigned long)beatsPerMinute];
  [tempoText drawAtPoint:NSMakePoint (x + 17.0, y) withAttributes:attrs];
}

- (NSImage *)clefImageNamed:(NSString *)name
{
  static NSMutableDictionary *clefImageCache = nil;
  NSImage *cached = [clefImageCache objectForKey:name];
  if (cached)
    {
      return cached;
    }

  NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
  if (!path)
    {
      NSArray *candidateDirectories = [NSArray
        arrayWithObjects:[[NSFileManager defaultManager] currentDirectoryPath],
                         [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent], nil];
      NSEnumerator *directoryEnumerator = [candidateDirectories objectEnumerator];
      NSString *directory = nil;
      while ((directory = [directoryEnumerator nextObject]) != nil)
        {
          NSString *candidate =
            [[directory stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"Resources/%@.png", name]]
              stringByStandardizingPath];
          if ([[NSFileManager defaultManager] fileExistsAtPath:candidate])
            {
              path = candidate;
              break;
            }
        }
    }
  if (!path)
    {
      path = [[NSString stringWithFormat:@"Resources/%@.png", name] stringByStandardizingPath];
    }
  NSImage *image = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
  if (image)
    {
      if (!clefImageCache)
        {
          clefImageCache = [[NSMutableDictionary alloc] init];
        }
      [clefImageCache setObject:image forKey:name];
    }
  return image;
}

- (void)drawClefNamed:(NSString *)name fallback:(NSString *)fallback inRect:(NSRect)rect
{
  NSImage *image = [self clefImageNamed:name];
  if (image)
    {
      [NSGraphicsContext saveGraphicsState];
      NSAffineTransform *transform = [NSAffineTransform transform];
      [transform translateXBy:0.0 yBy:NSMaxY (rect)];
      [transform scaleXBy:1.0 yBy:-1.0];
      [transform concat];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
      [image drawInRect:NSMakeRect (rect.origin.x, 0.0, rect.size.width, rect.size.height)
               fromRect:NSZeroRect
              operation:NSCompositeSourceOver
               fraction:1.0];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
      [NSGraphicsContext restoreGraphicsState];
      return;
    }

  NSFont *clefFont = [NSFont fontWithName:@"Times New Roman" size:42.0];
  if (!clefFont)
    {
      clefFont = [NSFont boldSystemFontOfSize:38.0];
    }
  NSDictionary *clefAttrs =
    [NSDictionary dictionaryWithObjectsAndKeys:clefFont, NSFontAttributeName, [NSColor blackColor],
                                               NSForegroundColorAttributeName, nil];
  [fallback drawAtPoint:NSMakePoint (rect.origin.x - 4.0, rect.origin.y - 4.0)
         withAttributes:clefAttrs];
}

- (void)drawPartNameForTrack:(NSInteger)track x:(CGFloat)x y:(CGFloat)y height:(CGFloat)height
{
  NSString *name = nil;
  if (track < 0)
    {
      NSMutableArray *names = [NSMutableArray array];
      for (NSNumber *number in [self scoreTracks])
        {
          NSString *partName = [_document nameForTrack:[number integerValue]];
          [names addObject:[partName length]
                             ? partName
                             : [NSString
                                 stringWithFormat:@"Part %ld", (long)([number integerValue] + 1)]];
        }
      name = [names componentsJoinedByString:@"\n"];
    }
  else
    {
      name = [_document nameForTrack:track];
      if ([name length] == 0)
        name = [NSString stringWithFormat:@"Part %ld", (long)(track + 1)];
    }

  NSMutableParagraphStyle *style = [[[NSMutableParagraphStyle alloc] init] autorelease];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
  [style setAlignment:NSRightTextAlignment];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
  [style setLineBreakMode:NSLineBreakByWordWrapping];
  NSDictionary *attrs =
    [NSDictionary dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:10.0], NSFontAttributeName,
                                               [NSColor colorWithCalibratedWhite:0.2 alpha:1.0],
                                               NSForegroundColorAttributeName, style,
                                               NSParagraphStyleAttributeName, nil];
  NSRect rect = NSMakeRect (x, y + height / 2.0 - 26.0, PartLabelWidth, 52.0);
  [name drawInRect:rect withAttributes:attrs];
}

- (void)drawStaffFromX:(CGFloat)left toX:(CGFloat)right topY:(CGFloat)top
{
  [[NSColor blackColor] setStroke];
  for (NSUInteger i = 0; i < 5; i++)
    {
      CGFloat y = top + (CGFloat)i * LineSpacing;
      [NSBezierPath strokeLineFromPoint:NSMakePoint (left, y) toPoint:NSMakePoint (right, y)];
    }
}

- (void)drawBraceAtX:(CGFloat)x topY:(CGFloat)top bottomY:(CGFloat)bottom
{
  NSBezierPath *path = [NSBezierPath bezierPath];
  [path moveToPoint:NSMakePoint (x + 10.0, top)];
  [path curveToPoint:NSMakePoint (x + 10.0, bottom)
       controlPoint1:NSMakePoint (x - 10.0, top + 35.0)
       controlPoint2:NSMakePoint (x - 10.0, bottom - 35.0)];
  [path setLineWidth:2.0];
  [[NSColor blackColor] setStroke];
  [path stroke];
}

- (void)drawTimeSignatureAtX:(CGFloat)x trebleY:(CGFloat)trebleY bassY:(CGFloat)bassY
{
  NSDictionary *attrs = [NSDictionary
    dictionaryWithObjectsAndKeys:[NSFont boldSystemFontOfSize:22.0], NSFontAttributeName,
                                 [NSColor blackColor], NSForegroundColorAttributeName, nil];
  NSString *top =
    [NSString stringWithFormat:@"%lu", (unsigned long)[_document timeSignatureNumerator]];
  NSString *bottom =
    [NSString stringWithFormat:@"%lu", (unsigned long)[_document timeSignatureDenominator]];
  [top drawAtPoint:NSMakePoint (x, trebleY - 2.0) withAttributes:attrs];
  [bottom drawAtPoint:NSMakePoint (x, trebleY + 20.0) withAttributes:attrs];
  [top drawAtPoint:NSMakePoint (x, bassY - 2.0) withAttributes:attrs];
  [bottom drawAtPoint:NSMakePoint (x, bassY + 20.0) withAttributes:attrs];
}

- (void)drawMeasureLinesFromX:(CGFloat)left
                          toX:(CGFloat)right
                         topY:(CGFloat)top
                  systemStart:(NSUInteger)systemStart
                    systemEnd:(NSUInteger)systemEnd
{
  if ([[_document measures] count] == 0)
    [_document buildDefaultMeasures];
  for (ScoreMeasure *measure in [_document measures])
    {
      NSUInteger tick = [measure startTick];
      if (tick < systemStart || tick > systemEnd)
        continue;
      CGFloat x = [self xForTick:tick start:systemStart end:systemEnd left:left right:right];
      [NSBezierPath strokeLineFromPoint:NSMakePoint (x, top)
                                toPoint:NSMakePoint (x, top + StaffGap + 4.0 * LineSpacing)];
      CGFloat bottom = top + StaffGap + 4.0 * LineSpacing;
      if ([measure repeatStart] || [measure repeatEnd])
        {
          CGFloat thickX = x + ([measure repeatStart] ? 4.0 : -4.0);
          NSBezierPath *thick = [NSBezierPath bezierPath];
          [thick moveToPoint:NSMakePoint (thickX, top)];
          [thick lineToPoint:NSMakePoint (thickX, bottom)];
          [thick setLineWidth:3.0];
          [thick stroke];
          CGFloat dotX = x + ([measure repeatStart] ? 10.0 : -10.0);
          [[NSColor blackColor] setFill];
          for (CGFloat staffY = top; staffY <= top + StaffGap; staffY += StaffGap)
            for (NSInteger dot = 0; dot < 2; dot++)
              [[NSBezierPath
                bezierPathWithOvalInRect:NSMakeRect (dotX - 2.0, staffY + 14.0 + dot * 10.0, 4.0,
                                                     4.0)] fill];
        }
    }

  NSUInteger compositionEnd = [_document totalTicks];
  if (compositionEnd > systemStart && compositionEnd <= systemEnd)
    {
      CGFloat x = [self xForTick:compositionEnd
                           start:systemStart
                             end:systemEnd
                            left:left
                           right:right];
      CGFloat bottom = top + StaffGap + 4.0 * LineSpacing;

      NSBezierPath *thinLine = [NSBezierPath bezierPath];
      [thinLine moveToPoint:NSMakePoint (x - 5.0, top)];
      [thinLine lineToPoint:NSMakePoint (x - 5.0, bottom)];
      [thinLine setLineWidth:1.0];
      [thinLine stroke];

      NSBezierPath *thickLine = [NSBezierPath bezierPath];
      [thickLine moveToPoint:NSMakePoint (x, top)];
      [thickLine lineToPoint:NSMakePoint (x, bottom)];
      [thickLine setLineWidth:3.0];
      [thickLine stroke];
    }
}

- (void)drawNotesFromX:(CGFloat)left
                   toX:(CGFloat)right
               trebleY:(CGFloat)trebleY
                 bassY:(CGFloat)bassY
           systemStart:(NSUInteger)systemStart
             systemEnd:(NSUInteger)systemEnd
                 track:(NSInteger)track
{
  NSMutableArray *visibleNotes = [NSMutableArray array];
  NSEnumerator *noteEnumerator = [[_document notes] objectEnumerator];
  ScoreNote *note = nil;
  while ((note = [noteEnumerator nextObject]) != nil)
    {
      if (track >= 0 && [note track] != track)
        continue;
      if ([note startTick] >= systemEnd || [note startTick] + [note durationTicks] <= systemStart)
        {
          continue;
        }

      BOOL treble = [note pitch] >= 60;
      CGFloat staffTop = treble ? trebleY : bassY;
      CGFloat x = [note isRest] ? [self noteXForTick:[note startTick]
                                               start:systemStart
                                                 end:systemEnd
                                                left:left
                                               right:right]
                                : [self engravedXForNote:note
                                                   start:systemStart
                                                     end:systemEnd
                                                    left:left
                                                   right:right];
      CGFloat y = [note isRest] ? staffTop + 2.0 * LineSpacing
                                : [self yForNote:note treble:treble staffTop:staffTop];
      BOOL playing = _showPlayback && ![note isRest] && [note startTick] <= _playbackTick
                     && _playbackTick < [note startTick] + [note durationTicks];
      if (playing && [[NSGraphicsContext currentContext] isDrawingToScreen])
        {
          [self drawPlaybackHighlightAtX:x y:y];
        }
      if (note == _selectedNote && [[NSGraphicsContext currentContext] isDrawingToScreen])
        {
          [self drawSelectionAtX:x y:y];
        }
      if ([note isRest])
        {
          [self drawRestAtX:x y:y duration:[note durationTicks]];
        }
      else
        {
          [visibleNotes addObject:note];
        }
    }

  NSUInteger quarter = MAX ((NSUInteger)1, [_document ticksPerQuarter]);
  NSMutableDictionary *groupsByBeat = [NSMutableDictionary dictionary];
  noteEnumerator = [visibleNotes objectEnumerator];
  while ((note = [noteEnumerator nextObject]) != nil)
    {
      if ([note durationTicks] > quarter / 2)
        {
          continue;
        }
      BOOL treble = [note pitch] >= 60;
      NSUInteger beat = [note startTick] / quarter;
      NSString *key = [NSString stringWithFormat:@"%ld:%ld:%d:%lu", (long)[note track],
                                                 (long)[note voice], treble, (unsigned long)beat];
      NSMutableArray *group = [groupsByBeat objectForKey:key];
      if (!group)
        {
          group = [NSMutableArray array];
          [groupsByBeat setObject:group forKey:key];
        }
      [group addObject:note];
    }

  NSMutableSet *beamedNotes = [NSMutableSet set];
  NSMutableDictionary *beamEnds = [NSMutableDictionary dictionary];
  NSMutableDictionary *stemDirections = [NSMutableDictionary dictionary];
  NSMutableArray *beamGroups = [NSMutableArray array];
  NSEnumerator *groupEnumerator = [[groupsByBeat allValues] objectEnumerator];
  NSArray *group = nil;
  while ((group = [groupEnumerator nextObject]) != nil)
    {
      if ([group count] < 2)
        {
          continue;
        }
      ScoreNote *first = [group objectAtIndex:0];
      ScoreNote *last = [group lastObject];
      if ([first startTick] == [last startTick])
        {
          continue;
        }
      BOOL treble = [first pitch] >= 60;
      CGFloat staffTop = treble ? trebleY : bassY;
      CGFloat averageY = 0.0;
      NSEnumerator *beamNoteEnumerator = [group objectEnumerator];
      while ((note = [beamNoteEnumerator nextObject]) != nil)
        {
          averageY += [self yForNote:note treble:treble staffTop:staffTop];
        }
      averageY /= (CGFloat)[group count];
      BOOL stemsUp = averageY >= staffTop + 2.0 * LineSpacing;
      CGFloat firstY = [self yForNote:first treble:treble staffTop:staffTop];
      CGFloat lastY = [self yForNote:last treble:treble staffTop:staffTop];
      CGFloat firstBeamY = firstY + (stemsUp ? -34.0 : 34.0);
      CGFloat lastBeamY = lastY + (stemsUp ? -34.0 : 34.0);
      CGFloat delta = lastBeamY - firstBeamY;
      if (delta > 8.0)
        lastBeamY = firstBeamY + 8.0;
      if (delta < -8.0)
        lastBeamY = firstBeamY - 8.0;
      CGFloat firstX = [self engravedXForNote:first
                                        start:systemStart
                                          end:systemEnd
                                         left:left
                                        right:right];
      CGFloat lastX = [self engravedXForNote:last
                                       start:systemStart
                                         end:systemEnd
                                        left:left
                                       right:right];

      beamNoteEnumerator = [group objectEnumerator];
      while ((note = [beamNoteEnumerator nextObject]) != nil)
        {
          CGFloat x = [self engravedXForNote:note
                                       start:systemStart
                                         end:systemEnd
                                        left:left
                                       right:right];
          CGFloat fraction = lastX > firstX ? (x - firstX) / (lastX - firstX) : 0.0;
          CGFloat beamY = firstBeamY + fraction * (lastBeamY - firstBeamY);
          NSValue *noteKey = [NSValue valueWithPointer:note];
          [beamEnds setObject:[NSNumber numberWithDouble:beamY] forKey:noteKey];
          [stemDirections setObject:[NSNumber numberWithBool:stemsUp] forKey:noteKey];
          [beamedNotes addObject:note];
        }
      [beamGroups addObject:group];
    }

  noteEnumerator = [visibleNotes objectEnumerator];
  while ((note = [noteEnumerator nextObject]) != nil)
    {
      BOOL treble = [note pitch] >= 60;
      CGFloat staffTop = treble ? trebleY : bassY;
      CGFloat x = [self engravedXForNote:note
                                   start:systemStart
                                     end:systemEnd
                                    left:left
                                   right:right];
      CGFloat y = [self yForNote:note treble:treble staffTop:staffTop];
      NSValue *noteKey = [NSValue valueWithPointer:note];
      NSNumber *beamEnd = [beamEnds objectForKey:noteKey];
      BOOL stemsUp = beamEnd ? [[stemDirections objectForKey:noteKey] boolValue]
                             : (y >= staffTop + 2.0 * LineSpacing);
      CGFloat stemEnd = beamEnd ? [beamEnd doubleValue] : y + (stemsUp ? -34.0 : 34.0);
      [self drawNoteAtX:x
                      y:y
                   note:note
                 treble:treble
               staffTop:staffTop
                stemsUp:stemsUp
                stemEnd:stemEnd
               drawFlag:![beamedNotes containsObject:note]];
    }

  groupEnumerator = [beamGroups objectEnumerator];
  while ((group = [groupEnumerator nextObject]) != nil)
    {
      [self drawBeamsForNotes:group
                         left:left
                        right:right
                  systemStart:systemStart
                    systemEnd:systemEnd
                     beamEnds:beamEnds
               stemDirections:stemDirections];
    }

  [self drawSlursForNotes:visibleNotes
                     left:left
                    right:right
              systemStart:systemStart
                systemEnd:systemEnd
                  trebleY:trebleY
                    bassY:bassY];
  [self drawTiesAndNoteMarks:visibleNotes
                        left:left
                       right:right
                 systemStart:systemStart
                   systemEnd:systemEnd
                     trebleY:trebleY
                       bassY:bassY];
}

- (void)drawTiesAndNoteMarks:(NSArray *)notes
                        left:(CGFloat)left
                       right:(CGFloat)right
                 systemStart:(NSUInteger)systemStart
                   systemEnd:(NSUInteger)systemEnd
                     trebleY:(CGFloat)trebleY
                       bassY:(CGFloat)bassY
{
  NSDictionary *small = [NSDictionary
    dictionaryWithObjectsAndKeys:[NSFont systemFontOfSize:11.0], NSFontAttributeName,
                                 [NSColor blackColor], NSForegroundColorAttributeName, nil];
  NSMutableArray *occupied = [NSMutableArray array];
  for (ScoreNote *note in notes)
    {
      if ([note isRest])
        continue;
      BOOL treble = [note pitch] >= 60;
      CGFloat staff = treble ? trebleY : bassY;
      CGFloat x = [self engravedXForNote:note
                                   start:systemStart
                                     end:systemEnd
                                    left:left
                                   right:right];
      CGFloat y = [self yForNote:note treble:treble staffTop:staff];
      [occupied addObject:[NSValue valueWithRect:NSMakeRect (x - 7.0, y - 6.0, 14.0, 12.0)]];
    }
  for (NSUInteger i = 0; i < [notes count]; i++)
    {
      ScoreNote *note = [notes objectAtIndex:i];
      BOOL treble = [note pitch] >= 60;
      CGFloat staff = treble ? trebleY : bassY;
      CGFloat x = [self engravedXForNote:note
                                   start:systemStart
                                     end:systemEnd
                                    left:left
                                   right:right];
      CGFloat y = [self yForNote:note treble:treble staffTop:staff];
      if ([[note dynamic] length])
        {
          NSSize size = [[note dynamic] sizeWithAttributes:small];
          NSRect rect = ScorePlaceRect (
            NSMakeRect (x - size.width / 2.0, staff + 48.0, size.width, size.height), occupied,
            13.0);
          [[note dynamic] drawAtPoint:rect.origin withAttributes:small];
        }
      if ([[note articulation] length])
        {
          NSString *mark = [[note articulation] isEqualToString:@"staccato"]
                             ? @"•"
                             : ([[note articulation] isEqualToString:@"tenuto"] ? @"—" : @">");
          NSSize size = [mark sizeWithAttributes:small];
          NSRect rect = ScorePlaceRect (
            NSMakeRect (x - size.width / 2.0, y - 22.0, size.width, size.height), occupied, -12.0);
          [mark drawAtPoint:rect.origin withAttributes:small];
        }
      if ([note tupletActual] > 0)
        {
          NSString *number = [NSString stringWithFormat:@"%lu", (unsigned long)[note tupletActual]];
          NSSize size = [number sizeWithAttributes:small];
          NSRect rect = ScorePlaceRect (
            NSMakeRect (x - size.width / 2.0, y - 40.0, size.width, size.height), occupied, -12.0);
          [number drawAtPoint:rect.origin withAttributes:small];
        }
      if (![note tieStart])
        continue;
      ScoreNote *endNote = nil;
      for (NSUInteger j = i + 1; j < [notes count]; j++)
        {
          ScoreNote *candidate = [notes objectAtIndex:j];
          if ([candidate tieEnd] && [candidate pitch] == [note pitch] &&
              [candidate track] == [note track] && [candidate voice] == [note voice])
            {
              endNote = candidate;
              break;
            }
        }
      if (!endNote)
        continue;
      CGFloat endX = [self engravedXForNote:endNote
                                      start:systemStart
                                        end:systemEnd
                                       left:left
                                      right:right];
      CGFloat endStaff = [endNote pitch] >= 60 ? trebleY : bassY;
      CGFloat endY = [self yForNote:endNote treble:([endNote pitch] >= 60) staffTop:endStaff];
      NSBezierPath *tie = [NSBezierPath bezierPath];
      [tie moveToPoint:NSMakePoint (x + 5.0, y + 5.0)];
      [tie curveToPoint:NSMakePoint (endX - 5.0, endY + 5.0)
          controlPoint1:NSMakePoint (x + (endX - x) * .3, y + 14.0)
          controlPoint2:NSMakePoint (x + (endX - x) * .7, endY + 14.0)];
      [tie stroke];
    }
}

- (void)drawPlaybackHighlightAtX:(CGFloat)x y:(CGFloat)y
{
  NSRect glowRect = NSMakeRect (x - 12.0, y - 10.0, 24.0, 20.0);
  NSColor *glow = [NSColor colorWithCalibratedRed:1.0 green:0.72 blue:0.12 alpha:0.55];
  [glow setFill];
  [[NSBezierPath bezierPathWithOvalInRect:glowRect] fill];
}

- (void)drawSelectionAtX:(CGFloat)x y:(CGFloat)y
{
  NSRect rect = NSMakeRect (x - 15.0, y - 17.0, 30.0, 34.0);
  [[NSColor selectedControlColor] setStroke];
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:4.0 yRadius:4.0];
  [path setLineWidth:2.0];
  [path stroke];
}

- (CGFloat)xForTick:(NSUInteger)tick
              start:(NSUInteger)start
                end:(NSUInteger)end
               left:(CGFloat)left
              right:(CGFloat)right
{
  if (end <= start)
    return left;
  if (tick <= start)
    return left;
  if (tick >= end)
    return right;
  ScoreEngravingSystem *matching = nil;
  for (ScoreEngravingSystem *layout in [self systemLayouts])
    {
      if ([layout startTick] == start && [layout endTick] == end)
        {
          matching = layout;
          break;
        }
    }
  if (matching)
    return left + [matching fractionForTick:tick] * (right - left);
  return left + (CGFloat)(tick - start) / (CGFloat)(end - start) * (right - left);
}

- (CGFloat)noteXForTick:(NSUInteger)tick
                  start:(NSUInteger)start
                    end:(NSUInteger)end
                   left:(CGFloat)left
                  right:(CGFloat)right
{
  return MIN (right - 2.0,
              [self xForTick:tick start:start end:end left:left right:right] + NoteHorizontalInset);
}

- (CGFloat)chordOffsetForNote:(ScoreNote *)note
{
  if ([note isRest])
    return 0.0;
  NSMutableArray *chord = [NSMutableArray array];
  BOOL treble = [note pitch] >= 60;
  for (ScoreNote *candidate in [_document notes])
    {
      if ([candidate isRest] || [candidate startTick] != [note startTick] ||
          [candidate track] != [note track] || [candidate voice] != [note voice]
          || (([candidate pitch] >= 60) != treble))
        continue;
      [chord addObject:candidate];
    }
  [chord sortUsingSelector:@selector (compareScoreNote:)];
  NSUInteger index = [chord indexOfObjectIdenticalTo:note];
  CGFloat offset = 0.0;
  if (index != NSNotFound && index + 1 < [chord count])
    {
      ScoreNote *lower = [chord objectAtIndex:index + 1];
      NSInteger lowerSteps = [self diatonicStepsFromPitch:0
                                                  toPitch:[lower pitch]
                                               accidental:[lower accidental]];
      NSInteger noteSteps = [self diatonicStepsFromPitch:0
                                                 toPitch:[note pitch]
                                              accidental:[note accidental]];
      if (noteSteps - lowerSteps <= 1)
        offset = (index % 2 == 0) ? 6.5 : 0.0;
    }
  NSInteger noteSteps = [self diatonicStepsFromPitch:0
                                             toPitch:[note pitch]
                                          accidental:[note accidental]];
  for (ScoreNote *candidate in [_document notes])
    if (candidate != note && ![candidate isRest] && [candidate startTick] == [note startTick] &&
        [candidate track] == [note track] && [candidate voice] != [note voice]
        && (([candidate pitch] >= 60) == treble))
      {
        NSInteger candidateSteps = [self diatonicStepsFromPitch:0
                                                        toPitch:[candidate pitch]
                                                     accidental:[candidate accidental]];
        if (labs (candidateSteps - noteSteps) <= 1)
          {
            offset += ([note voice] % 2) ? 6.5 : -6.5;
            break;
          }
      }
  return offset;
}

- (CGFloat)engravedXForNote:(ScoreNote *)note
                      start:(NSUInteger)start
                        end:(NSUInteger)end
                       left:(CGFloat)left
                      right:(CGFloat)right
{
  CGFloat base = [self noteXForTick:[note startTick] start:start end:end left:left right:right];
  return MIN (right - 1.0, MAX (left + 1.0, base + [self chordOffsetForNote:note]));
}

- (CGFloat)accidentalColumnOffsetForNote:(ScoreNote *)note
{
  if ([note accidental] == 0)
    return 0.0;
  NSMutableArray *accidentals = [NSMutableArray array];
  BOOL treble = [note pitch] >= 60;
  for (ScoreNote *candidate in [_document notes])
    {
      if ([candidate isRest] || [candidate accidental] == 0 ||
          [candidate startTick] != [note startTick] || [candidate track] != [note track]
          || (([candidate pitch] >= 60) != treble))
        continue;
      [accidentals addObject:candidate];
    }
  [accidentals sortUsingSelector:@selector (compareScoreNote:)];
  NSUInteger index = [accidentals indexOfObjectIdenticalTo:note];
  if (index == NSNotFound)
    return 0.0;
  /* Stagger close accidentals into columns; distant symbols can reuse a column. */
  NSUInteger column = 0;
  for (NSUInteger i = 0; i < index; i++)
    {
      ScoreNote *other = [accidentals objectAtIndex:i];
      if (labs ([other pitch] - [note pitch]) < 6)
        column++;
    }
  return (CGFloat)column * 9.0;
}

- (void)drawSlursForNotes:(NSArray *)notes
                     left:(CGFloat)left
                    right:(CGFloat)right
              systemStart:(NSUInteger)systemStart
                systemEnd:(NSUInteger)systemEnd
                  trebleY:(CGFloat)trebleY
                    bassY:(CGFloat)bassY
{
  for (NSUInteger i = 0; i < [notes count]; i++)
    {
      ScoreNote *startNote = [notes objectAtIndex:i];
      if (![startNote slurStart] || [startNote isRest])
        continue;

      ScoreNote *endNote = nil;
      for (NSUInteger j = i + 1; j < [notes count]; j++)
        {
          ScoreNote *candidate = [notes objectAtIndex:j];
          if ([candidate slurEnd] && [candidate track] == [startNote track] &&
              [candidate startTick] > [startNote startTick])
            {
              endNote = candidate;
              break;
            }
        }
      if (!endNote || [endNote startTick] >= systemEnd)
        continue;

      BOOL treble = [startNote pitch] >= 60;
      CGFloat startStaff = treble ? trebleY : bassY;
      CGFloat endStaff = [endNote pitch] >= 60 ? trebleY : bassY;
      CGFloat startX = [self engravedXForNote:startNote
                                        start:systemStart
                                          end:systemEnd
                                         left:left
                                        right:right];
      CGFloat endX = [self engravedXForNote:endNote
                                      start:systemStart
                                        end:systemEnd
                                       left:left
                                      right:right];
      CGFloat startY = [self yForNote:startNote treble:treble staffTop:startStaff] + 11.0;
      CGFloat endY =
        [self yForNote:endNote treble:([endNote pitch] >= 60) staffTop:endStaff] + 11.0;
      CGFloat bow = MAX (12.0, MIN (28.0, (endX - startX) * 0.18));
      NSBezierPath *slur = [NSBezierPath bezierPath];
      [slur moveToPoint:NSMakePoint (startX, startY)];
      [slur curveToPoint:NSMakePoint (endX, endY)
           controlPoint1:NSMakePoint (startX + (endX - startX) * 0.3, startY + bow)
           controlPoint2:NSMakePoint (startX + (endX - startX) * 0.7, endY + bow)];
      [[NSColor blackColor] setStroke];
      [slur setLineWidth:1.5];
      [slur stroke];
    }
}

- (CGFloat)yForNote:(ScoreNote *)note treble:(BOOL)treble staffTop:(CGFloat)staffTop
{
  NSInteger bottomLinePitch = treble ? 64 : 43;
  NSInteger steps = [self diatonicStepsFromPitch:bottomLinePitch
                                         toPitch:[note pitch]
                                      accidental:[note accidental]];
  CGFloat bottomY = staffTop + 4.0 * LineSpacing;
  return bottomY - ((CGFloat)steps * LineSpacing / 2.0);
}

- (NSInteger)diatonicStepsFromPitch:(NSInteger)fromPitch
                            toPitch:(NSInteger)toPitch
                         accidental:(NSInteger)accidental
{
  NSInteger fromOctave = fromPitch / 12;
  NSInteger spelledPitch = toPitch - accidental;
  NSInteger toOctave = spelledPitch / 12;
  NSInteger fromPc = fromPitch % 12;
  NSInteger toPc = spelledPitch % 12;
  if (toPc < 0)
    toPc += 12;
  return (toOctave - fromOctave) * 7 + [self scaleDegreeForPitchClass:toPc] -
         [self scaleDegreeForPitchClass:fromPc];
}

- (NSInteger)scaleDegreeForPitchClass:(NSInteger)pitchClass
{
  switch (pitchClass)
    {
    case 0:
    case 1:
      return 0;
    case 2:
    case 3:
      return 1;
    case 4:
      return 2;
    case 5:
    case 6:
      return 3;
    case 7:
    case 8:
      return 4;
    case 9:
    case 10:
      return 5;
    default:
      return 6;
    }
}

- (NSInteger)pitchClassForScaleDegree:(NSInteger)degree
{
  NSInteger normalized = degree % 7;
  if (normalized < 0)
    normalized += 7;
  switch (normalized)
    {
    case 0:
      return 0;
    case 1:
      return 2;
    case 2:
      return 4;
    case 3:
      return 5;
    case 4:
      return 7;
    case 5:
      return 9;
    default:
      return 11;
    }
}

- (NSInteger)pitchForY:(CGFloat)y treble:(BOOL)treble staffTop:(CGFloat)staffTop
{
  NSInteger bottomLinePitch = treble ? 64 : 43;
  CGFloat bottomY = staffTop + 4.0 * LineSpacing;
  NSInteger steps = (NSInteger)llround ((bottomY - y) / (LineSpacing / 2.0));
  NSInteger bottomOctave = bottomLinePitch / 12;
  NSInteger bottomDegree = [self scaleDegreeForPitchClass:(bottomLinePitch % 12)];
  NSInteger absoluteDegree = bottomOctave * 7 + bottomDegree + steps;
  NSInteger octave = absoluteDegree / 7;
  NSInteger degree = absoluteDegree % 7;
  if (degree < 0)
    {
      degree += 7;
      octave--;
    }
  NSInteger pitch = octave * 12 + [self pitchClassForScaleDegree:degree];
  if (pitch < 0)
    pitch = 0;
  if (pitch > 127)
    pitch = 127;
  return pitch;
}

- (void)drawRestAtX:(CGFloat)x y:(CGFloat)y duration:(NSUInteger)duration
{
  [[NSColor blackColor] setStroke];
  [[NSColor blackColor] setFill];
  CGFloat quarter = [_document ticksPerQuarter];
  if (duration >= quarter * 4)
    {
      NSRect rect = NSMakeRect (x - 8.0, y - 1.0, 16.0, 5.0);
      NSRectFill (rect);
      return;
    }
  if (duration >= quarter * 2)
    {
      NSRect rect = NSMakeRect (x - 8.0, y - 6.0, 16.0, 5.0);
      NSRectFill (rect);
      return;
    }
  if (duration >= quarter)
    {
      NSRect rect = NSMakeRect (x - 1.0, y - 12.0, 3.0, 24.0);
      NSRectFill (rect);
      [NSBezierPath strokeLineFromPoint:NSMakePoint (x - 5.0, y - 12.0)
                                toPoint:NSMakePoint (x + 6.0, y - 2.0)];
      [NSBezierPath strokeLineFromPoint:NSMakePoint (x - 5.0, y - 2.0)
                                toPoint:NSMakePoint (x + 6.0, y + 8.0)];
      return;
    }
  NSBezierPath *path = [NSBezierPath bezierPath];
  [path moveToPoint:NSMakePoint (x - 5.0, y - 14.0)];
  [path curveToPoint:NSMakePoint (x + 4.0, y + 2.0)
       controlPoint1:NSMakePoint (x + 8.0, y - 9.0)
       controlPoint2:NSMakePoint (x - 8.0, y - 2.0)];
  [path curveToPoint:NSMakePoint (x - 3.0, y + 15.0)
       controlPoint1:NSMakePoint (x + 12.0, y + 7.0)
       controlPoint2:NSMakePoint (x - 7.0, y + 8.0)];
  [path setLineWidth:2.0];
  [path stroke];
  NSUInteger flags = [self flagCountForDuration:duration];
  for (NSUInteger i = 1; i < flags; i++)
    {
      CGFloat offset = (CGFloat)i * 6.0;
      [NSBezierPath strokeLineFromPoint:NSMakePoint (x + 1.0, y - 8.0 + offset)
                                toPoint:NSMakePoint (x + 10.0, y - 2.0 + offset)];
    }
}

- (NSUInteger)flagCountForDuration:(NSUInteger)duration
{
  NSUInteger quarter = MAX ((NSUInteger)1, [_document ticksPerQuarter]);
  if (duration >= quarter)
    {
      return 0;
    }
  NSUInteger flags = 1;
  NSUInteger threshold = quarter / 2;
  while (threshold > 1 && duration <= threshold / 2)
    {
      flags++;
      threshold /= 2;
    }
  return flags;
}

- (BOOL)scoreLayoutForPoint:(NSPoint)point
                systemStart:(NSUInteger *)systemStart
                  systemEnd:(NSUInteger *)systemEnd
                       left:(CGFloat *)left
                      right:(CGFloat *)right
                   staffTop:(CGFloat *)staffTop
                     treble:(BOOL *)treble
                      track:(NSInteger *)track
{
  if (!_document)
    {
      return NO;
    }
  NSUInteger systemCount = [self systemCount];
  CGFloat staffLeft = Margin + PartLabelWidth + 100.0;
  CGFloat staffRight = PageWidth - Margin - 18.0;
  NSArray *tracks = _separateParts ? [self scoreTracks] : [NSArray arrayWithObject:@-1];
  CGFloat partStride = [self partGrandStaffHeight] + PartStaffSpacing;
  for (NSUInteger system = 0; system < systemCount; system++)
    {
      CGFloat y = [self yForSystem:system];
      for (NSUInteger partIndex = 0; partIndex < [tracks count]; partIndex++)
        {
          CGFloat trebleTop = y + partIndex * partStride;
          CGFloat bassTop = trebleTop + StaffGap;
          BOOL isTreble = NO;
          CGFloat top = 0.0;
          if (point.y >= trebleTop - 30.0 && point.y <= trebleTop + 4.0 * LineSpacing + 21.0)
            {
              isTreble = YES;
              top = trebleTop;
            }
          else if (point.y >= bassTop - 21.0 && point.y <= bassTop + 4.0 * LineSpacing + 30.0)
            {
              isTreble = NO;
              top = bassTop;
            }
          else
            continue;
          if (point.x < staffLeft - 20.0 || point.x > staffRight + 20.0)
            continue;
          ScoreEngravingSystem *layout = [[self systemLayouts] objectAtIndex:system];
          if (systemStart)
            *systemStart = [layout startTick];
          if (systemEnd)
            *systemEnd = [layout endTick];
          if (left)
            *left = staffLeft;
          if (right)
            *right = staffRight;
          if (staffTop)
            *staffTop = top;
          if (treble)
            *treble = isTreble;
          NSInteger hitTrack = [[tracks objectAtIndex:partIndex] integerValue];
          if (track && hitTrack >= 0)
            *track = hitTrack;
          return YES;
        }
    }
  return NO;
}

- (NSUInteger)tickForPoint:(NSPoint)point
               systemStart:(NSUInteger)systemStart
                 systemEnd:(NSUInteger)systemEnd
                      left:(CGFloat)left
                     right:(CGFloat)right
{
  CGFloat clampedX = MIN (MAX (point.x, left), right);

  /*
   * If the notehead is dropped close to an existing onset, use precisely
   * the same tick. This makes building chords independent of small mouse
   * positioning differences and avoids adjacent quantization slots.
   */
  NSEnumerator *noteEnumerator = [[_document notes] objectEnumerator];
  ScoreNote *note = nil;
  while ((note = [noteEnumerator nextObject]) != nil)
    {
      if ([note startTick] < systemStart || [note startTick] >= systemEnd)
        {
          continue;
        }
      CGFloat noteX = [self noteXForTick:[note startTick]
                                   start:systemStart
                                     end:systemEnd
                                    left:left
                                   right:right];
      if (fabs (noteX - clampedX) <= ChordSnapDistance)
        {
          return [note startTick];
        }
    }

  CGFloat fraction = right > left ? (clampedX - left) / (right - left) : 0.0;
  NSUInteger tick
    = systemStart + (NSUInteger)llround (fraction * (CGFloat)(systemEnd - systemStart));
  for (ScoreEngravingSystem *layout in [self systemLayouts])
    {
      if ([layout startTick] != systemStart || [layout endTick] != systemEnd)
        continue;
      NSArray *ticks = [layout ticks];
      NSArray *fractions = [layout fractions];
      for (NSUInteger index = 0; index + 1 < [fractions count]; index++)
        {
          CGFloat fa = [[fractions objectAtIndex:index] doubleValue];
          CGFloat fb = [[fractions objectAtIndex:index + 1] doubleValue];
          if (fraction < fa || fraction > fb)
            continue;
          NSUInteger a = [[ticks objectAtIndex:index] unsignedIntegerValue];
          NSUInteger b = [[ticks objectAtIndex:index + 1] unsignedIntegerValue];
          CGFloat local = fb > fa ? (fraction - fa) / (fb - fa) : 0.0;
          tick = a + (NSUInteger)llround (local * (CGFloat)(b - a));
          break;
        }
      break;
    }
  NSUInteger quantum = MAX ((NSUInteger)1, [_document ticksPerQuarter] / 8);
  return ((tick + quantum / 2) / quantum) * quantum;
}

- (void)updateTotalTicksFromNotes
{
  NSUInteger totalTicks = 0;
  NSEnumerator *noteEnumerator = [[_document notes] objectEnumerator];
  ScoreNote *note = nil;
  while ((note = [noteEnumerator nextObject]) != nil)
    {
      NSUInteger endTick = [note startTick] + [note durationTicks];
      if (endTick > totalTicks)
        {
          totalTicks = endTick;
        }
    }
  [_document setTotalTicks:totalTicks];
}

- (BOOL)insertPaletteItem:(NSString *)item
                  atPoint:(NSPoint)point
                    pitch:(NSInteger)pitch
            durationTicks:(NSUInteger)durationTicks
                    track:(NSInteger)track
{
  if (!_document)
    {
      return NO;
    }
  NSUInteger systemStart = 0;
  NSUInteger systemEnd = 0;
  CGFloat left = 0.0;
  CGFloat right = 0.0;
  CGFloat staffTop = 0.0;
  BOOL treble = YES;
  NSInteger targetTrack = track;
  if (![self scoreLayoutForPoint:point
                     systemStart:&systemStart
                       systemEnd:&systemEnd
                            left:&left
                           right:&right
                        staffTop:&staffTop
                          treble:&treble
                           track:&targetTrack])
    {
      return NO;
    }

  BOOL rest = [item isEqualToString:@"rest"];
  ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
  [note setRest:rest];
  [note
    setPitch:rest ? (treble ? 72 : 48) : [self pitchForY:point.y treble:treble staffTop:staffTop]];
  if (!rest && pitch >= 0)
    {
      [note setPitch:pitch];
    }
  [note setChannel:MAX ((NSInteger)0, targetTrack) % 16];
  [note setTrack:MAX ((NSInteger)0, targetTrack)];
  [note setStartTick:[self tickForPoint:point
                            systemStart:systemStart
                              systemEnd:systemEnd
                                   left:left
                                  right:right]];
  [note setDurationTicks:MAX ((NSUInteger)1, durationTicks)];
  [[_document notes] addObject:note];
  [[_document notes] sortUsingSelector:@selector (compareScoreNote:)];
  NSUInteger endTick = [note startTick] + [note durationTicks];
  if (endTick > [_document totalTicks])
    {
      [_document setTotalTicks:endTick];
      [self updateFrameForDocument];
    }
  ScoreMeasure *measure = [_document ensureMeasureContainingTick:[note startTick]];
  [note setMeasureIndex:(NSInteger)[[_document measures] indexOfObjectIdenticalTo:measure]];
  if (![_document nameForTrack:[note track]])
    {
      [_document setName:[NSString stringWithFormat:@"Part %ld", (long)([note track] + 1)]
                forTrack:[note track]];
    }
  _selectedNote = note;
  [[NSNotificationCenter defaultCenter] postNotificationName:ScoreViewDidEditScoreNotification
                                                      object:self];
  [self setNeedsDisplay:YES];
  return YES;
}

- (ScoreNote *)noteAtPoint:(NSPoint)point
{
  if (!_document)
    {
      return nil;
    }
  NSUInteger systemCount = [self systemCount];
  CGFloat left = Margin + PartLabelWidth + 100.0;
  CGFloat right = PageWidth - Margin - 18.0;
  ScoreNote *found = nil;
  NSEnumerator *noteEnumerator = [[_document notes] reverseObjectEnumerator];
  ScoreNote *note = nil;
  while ((note = [noteEnumerator nextObject]) != nil)
    {
      NSUInteger system = 0;
      NSUInteger systemStart = 0;
      NSUInteger systemEnd = 0;
      for (NSUInteger index = 0; index < systemCount; index++)
        {
          ScoreEngravingSystem *layout = [[self systemLayouts] objectAtIndex:index];
          NSUInteger start = [layout startTick];
          NSUInteger end = [layout endTick];
          if ([note startTick] >= start && [note startTick] < end)
            {
              system = index;
              systemStart = start;
              systemEnd = end;
              break;
            }
        }
      CGFloat y = [self yForSystem:system];
      NSUInteger partIndex
        = _separateParts
            ? [[self scoreTracks] indexOfObject:[NSNumber numberWithInteger:[note track]]]
            : 0;
      if (partIndex == NSNotFound)
        continue;
      y += partIndex * ([self partGrandStaffHeight] + PartStaffSpacing);
      BOOL treble = [note pitch] >= 60;
      CGFloat staffTop = treble ? y : y + StaffGap;
      CGFloat x = [note isRest] ? [self noteXForTick:[note startTick]
                                               start:systemStart
                                                 end:systemEnd
                                                left:left
                                               right:right]
                                : [self engravedXForNote:note
                                                   start:systemStart
                                                     end:systemEnd
                                                    left:left
                                                   right:right];
      CGFloat noteY = [note isRest] ? staffTop + 2.0 * LineSpacing
                                    : [self yForNote:note treble:treble staffTop:staffTop];
      NSRect hitRect = NSMakeRect (x - 14.0, noteY - 16.0, 28.0, 32.0);
      if (NSPointInRect (point, hitRect))
        {
          found = note;
          break;
        }
    }
  return found;
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (void)mouseDown:(NSEvent *)event
{
  NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
  _selectedNote = [self noteAtPoint:point];
  [[self window] makeFirstResponder:self];
  [self setNeedsDisplay:YES];
  [[NSNotificationCenter defaultCenter] postNotificationName:ScoreViewSelectionDidChangeNotification
                                                      object:self];
}

- (void)keyDown:(NSEvent *)event
{
  NSString *characters = [event charactersIgnoringModifiers];
  unichar character = [characters length] > 0 ? [characters characterAtIndex:0] : 0;
  BOOL deleteKey
    = ([event keyCode] == 51 || [event keyCode] == 117 || character == NSDeleteCharacter
       || character == NSBackspaceCharacter || character == NSDeleteFunctionKey);
  if (deleteKey)
    {
      if (_selectedNote && [[_document notes] containsObject:_selectedNote])
        {
          [[_document notes] removeObject:_selectedNote];
          _selectedNote = nil;
          [self updateTotalTicksFromNotes];
          [[NSNotificationCenter defaultCenter]
            postNotificationName:ScoreViewDidEditScoreNotification
                          object:self];
          [self reloadDocument];
        }
      return;
    }
  [super keyDown:event];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
  NSString *item = [[sender draggingPasteboard] stringForType:ScorePalettePasteboardType];
  if ([item length] == 0)
    {
      return NSDragOperationNone;
    }
  NSPoint point = [self convertPoint:[sender draggingLocation] fromView:nil];
  return [self scoreLayoutForPoint:point
                       systemStart:NULL
                         systemEnd:NULL
                              left:NULL
                             right:NULL
                          staffTop:NULL
                            treble:NULL
                             track:NULL]
           ? NSDragOperationCopy
           : NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender
{
  return [self draggingEntered:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
  NSPasteboard *pasteboard = [sender draggingPasteboard];
  NSString *payload = [pasteboard stringForType:ScorePalettePasteboardType];
  if ([payload length] == 0)
    {
      return NO;
    }
  NSArray *parts = [payload componentsSeparatedByString:@":"];
  NSString *item = [parts count] > 0 ? [parts objectAtIndex:0] : @"note";
  NSInteger pitch = [parts count] > 1 ? [[parts objectAtIndex:1] integerValue] : -1;
  NSUInteger durationTicks = [parts count] > 2 ? (NSUInteger)[[parts objectAtIndex:2] integerValue]
                                               : [_document ticksPerQuarter];
  NSInteger track = [parts count] > 3 ? [[parts objectAtIndex:3] integerValue] : 0;
  NSPoint point = [self convertPoint:[sender draggingLocation] fromView:nil];
  if (![item isEqualToString:@"rest"])
    {
      /*
       * NSDraggingInfo reports the drag image anchor, while the palette
       * image draws its notehead to the right of and above that anchor.
       * Use the visible notehead as the requested time and pitch.
       */
      point.x += PaletteDragNoteHeadXOffset;
      point.y -= PaletteDragNoteHeadYOffset;
    }

  if ([item isEqualToString:@"sharp"] || [item isEqualToString:@"flat"] ||
      [item isEqualToString:@"natural"] || [item isEqualToString:@"slur"] ||
      [item isEqualToString:@"tie"] || [item isEqualToString:@"triplet"] ||
      [item isEqualToString:@"mf"] || [item isEqualToString:@"staccato"] ||
      [item isEqualToString:@"accent"] || [item isEqualToString:@"tenuto"])
    {
      ScoreNote *target = [self noteAtPoint:point];
      if (!target || [target isRest])
        return NO;

      if ([item isEqualToString:@"slur"] || [item isEqualToString:@"tie"])
        {
          if (!_selectedNote || _selectedNote == target || [_selectedNote isRest] ||
              [_selectedNote startTick] >= [target startTick])
            {
              return NO;
            }
          if ([item isEqualToString:@"slur"])
            {
              [_selectedNote setSlurStart:YES];
              [target setSlurEnd:YES];
            }
          else
            {
              if ([_selectedNote pitch] != [target pitch])
                return NO;
              [_selectedNote setTieStart:YES];
              [target setTieEnd:YES];
            }
        }
      else if ([item isEqualToString:@"triplet"])
        {
          [target setTupletActual:3];
          [target setTupletNormal:2];
        }
      else if ([item isEqualToString:@"mf"])
        {
          [target setDynamic:@"mf"];
        }
      else if ([item isEqualToString:@"staccato"] || [item isEqualToString:@"accent"] ||
               [item isEqualToString:@"tenuto"])
        {
          [target setArticulation:item];
        }
      else
        {
          NSInteger basePitch = [target pitch] - [target accidental];
          NSInteger accidental =
            [item isEqualToString:@"sharp"] ? 1 : ([item isEqualToString:@"flat"] ? -1 : 0);
          [target setPitch:MIN (MAX (basePitch + accidental, (NSInteger)0), (NSInteger)127)];
          [target setAccidental:accidental];
        }
      _selectedNote = target;
      [[_document notes] sortUsingSelector:@selector (compareScoreNote:)];
      [[NSNotificationCenter defaultCenter] postNotificationName:ScoreViewDidEditScoreNotification
                                                          object:self];
      [self setNeedsDisplay:YES];
      return YES;
    }
  return [self insertPaletteItem:item
                         atPoint:point
                           pitch:pitch
                   durationTicks:durationTicks
                           track:track];
}

- (void)drawNoteAtX:(CGFloat)x
                  y:(CGFloat)y
               note:(ScoreNote *)note
             treble:(BOOL)treble
           staffTop:(CGFloat)staffTop
            stemsUp:(BOOL)stemsUp
            stemEnd:(CGFloat)stemEnd
           drawFlag:(BOOL)drawFlag
{
  (void)treble;
  NSUInteger duration = [note durationTicks];
  BOOL filled = duration < ([_document ticksPerQuarter] * 2);
  NSRect oval = NSMakeRect (x - 5.5, y - 4.0, 11.0, 8.0);
  NSBezierPath *head = [NSBezierPath bezierPathWithOvalInRect:oval];
  [[NSColor blackColor] setStroke];
  if (filled)
    {
      [[NSColor blackColor] setFill];
    }
  else
    {
      [[NSColor whiteColor] setFill];
    }
  [head fill];
  [head stroke];

  NSInteger accidental = [note accidental];
  if (accidental != 0)
    {
      NSString *symbol = accidental > 0 ? @"♯" : @"♭";
      NSFont *font = [NSFont fontWithName:@"Times New Roman" size:20.0];
      if (!font)
        font = [NSFont systemFontOfSize:17.0];
      NSDictionary *attrs =
        [NSDictionary dictionaryWithObjectsAndKeys:font, NSFontAttributeName, [NSColor blackColor],
                                                   NSForegroundColorAttributeName, nil];
      [symbol
           drawAtPoint:NSMakePoint (x - 20.0 - [self accidentalColumnOffsetForNote:note], y - 12.0)
        withAttributes:attrs];
    }

  CGFloat stemX = stemsUp ? x + 5.5 : x - 5.5;
  if (duration < [_document ticksPerQuarter] * 4)
    {
      [NSBezierPath strokeLineFromPoint:NSMakePoint (stemX, y)
                                toPoint:NSMakePoint (stemX, stemEnd)];
    }

  CGFloat bottom = staffTop + 4.0 * LineSpacing;
  CGFloat top = staffTop;
  for (CGFloat ledger = bottom + LineSpacing; ledger <= y + 1.0; ledger += LineSpacing)
    {
      [NSBezierPath strokeLineFromPoint:NSMakePoint (x - 10.0, ledger)
                                toPoint:NSMakePoint (x + 10.0, ledger)];
    }
  for (CGFloat ledger = top - LineSpacing; ledger >= y - 1.0; ledger -= LineSpacing)
    {
      [NSBezierPath strokeLineFromPoint:NSMakePoint (x - 10.0, ledger)
                                toPoint:NSMakePoint (x + 10.0, ledger)];
    }

  if (drawFlag && duration <= [_document ticksPerQuarter] / 2)
    {
      NSUInteger flags = [self flagCountForDuration:duration];
      CGFloat direction = stemsUp ? 1.0 : -1.0;
      for (NSUInteger i = 0; i < flags; i++)
        {
          CGFloat flagY = stemEnd + (stemsUp ? (CGFloat)i * 6.0 : -(CGFloat)i * 6.0);
          NSBezierPath *flag = [NSBezierPath bezierPath];
          [flag moveToPoint:NSMakePoint (stemX, flagY)];
          [flag
             curveToPoint:NSMakePoint (stemX + direction * 14.0, flagY + (stemsUp ? 10.0 : -10.0))
            controlPoint1:NSMakePoint (stemX + direction * 12.0, flagY + (stemsUp ? 2.0 : -2.0))
            controlPoint2:NSMakePoint (stemX + direction * 14.0, flagY + (stemsUp ? 8.0 : -8.0))];
          [flag stroke];
        }
    }
}

- (void)drawBeamsForNotes:(NSArray *)notes
                     left:(CGFloat)left
                    right:(CGFloat)right
              systemStart:(NSUInteger)systemStart
                systemEnd:(NSUInteger)systemEnd
                 beamEnds:(NSDictionary *)beamEnds
           stemDirections:(NSDictionary *)stemDirections
{
  if ([notes count] < 2)
    return;
  ScoreNote *first = [notes objectAtIndex:0];
  ScoreNote *last = [notes lastObject];
  BOOL stemsUp = [[stemDirections objectForKey:[NSValue valueWithPointer:first]] boolValue];
  CGFloat firstX = [self engravedXForNote:first
                                    start:systemStart
                                      end:systemEnd
                                     left:left
                                    right:right]
                   + (stemsUp ? 5.5 : -5.5);
  CGFloat lastX = [self engravedXForNote:last start:systemStart end:systemEnd left:left right:right]
                  + (stemsUp ? 5.5 : -5.5);
  CGFloat firstY = [[beamEnds objectForKey:[NSValue valueWithPointer:first]] doubleValue];
  CGFloat lastY = [[beamEnds objectForKey:[NSValue valueWithPointer:last]] doubleValue];
  CGFloat thickness = stemsUp ? 4.0 : -4.0;

  [[NSColor blackColor] setFill];
  NSBezierPath *beam = [NSBezierPath bezierPath];
  [beam moveToPoint:NSMakePoint (firstX, firstY)];
  [beam lineToPoint:NSMakePoint (lastX, lastY)];
  [beam lineToPoint:NSMakePoint (lastX, lastY + thickness)];
  [beam lineToPoint:NSMakePoint (firstX, firstY + thickness)];
  [beam closePath];
  [beam fill];

  for (NSUInteger beamIndex = 2; beamIndex <= 3; beamIndex++)
    {
      for (NSUInteger i = 0; i + 1 < [notes count]; i++)
        {
          ScoreNote *a = [notes objectAtIndex:i];
          ScoreNote *b = [notes objectAtIndex:i + 1];
          if ([self flagCountForDuration:[a durationTicks]] < beamIndex ||
              [self flagCountForDuration:[b durationTicks]] < beamIndex)
            {
              continue;
            }
          CGFloat ax = [self engravedXForNote:a
                                        start:systemStart
                                          end:systemEnd
                                         left:left
                                        right:right]
                       + (stemsUp ? 5.5 : -5.5);
          CGFloat bx = [self engravedXForNote:b
                                        start:systemStart
                                          end:systemEnd
                                         left:left
                                        right:right]
                       + (stemsUp ? 5.5 : -5.5);
          CGFloat ay = [[beamEnds objectForKey:[NSValue valueWithPointer:a]] doubleValue]
                       + thickness * (0.8 + (CGFloat)beamIndex);
          CGFloat by = [[beamEnds objectForKey:[NSValue valueWithPointer:b]] doubleValue]
                       + thickness * (0.8 + (CGFloat)beamIndex);
          NSBezierPath *extraBeam = [NSBezierPath bezierPath];
          [extraBeam moveToPoint:NSMakePoint (ax, ay)];
          [extraBeam lineToPoint:NSMakePoint (bx, by)];
          [extraBeam lineToPoint:NSMakePoint (bx, by + thickness)];
          [extraBeam lineToPoint:NSMakePoint (ax, ay + thickness)];
          [extraBeam closePath];
          [extraBeam fill];
        }
    }
}

@end
