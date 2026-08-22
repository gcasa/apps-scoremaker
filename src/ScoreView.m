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
#import "PlaybackMonitorView.h"
#import "MusicPlatformModel.h"
#import <math.h>

static CGFloat const PaperInset = 18.0;
static CGFloat const PageGap = 24.0;
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
static CGFloat const MeasureLeadingNoteHorizontalInset = 15.0;
static CGFloat const MinimumMeasureWidth = 140.0;
static CGFloat const PlaybackCartoucheVerticalInset = 17.0;
static CGFloat const PlaybackCartoucheDamageInset = 20.0;
NSString *const ScoreViewDidEditScoreNotification = @"ScoreViewDidEditScoreNotification";
NSString *const ScoreViewSelectionDidChangeNotification
  = @"ScoreViewSelectionDidChangeNotification";
NSString *const ScorePalettePasteboardType = @"com.scoremaker.palette-item";
static NSArray *ScoreCopiedNotes = nil;

static NSInteger
ScoreViewModulo12 (NSInteger value) { return ((value % 12) + 12) % 12; }

static NSInteger
ScoreViewTonicPitchClass (NSInteger fifths, NSString *mode)
{
  return ScoreViewModulo12 (([mode isEqualToString:@"minor"] ? 9 : 0) + 7 * fifths);
}

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

- (CGFloat)pageWidth
{
  return (_document && [_document pageLayout])
           ? [[_document pageLayout] paperWidth] + 2.0 * PaperInset : 980.0;
}
- (CGFloat)leftMargin
{
  return (_document && [_document pageLayout]) ? [[_document pageLayout] marginLeft] : 48.0;
}
- (CGFloat)rightMargin
{
  return (_document && [_document pageLayout]) ? [[_document pageLayout] marginRight] : 48.0;
}
- (CGFloat)topMargin
{
  return (_document && [_document pageLayout]) ? [[_document pageLayout] marginTop] : 48.0;
}
- (CGFloat)bottomMargin
{
  return (_document && [_document pageLayout]) ? [[_document pageLayout] marginBottom] : 48.0;
}
- (CGFloat)partSpacing
{
  return PartStaffSpacing;
}
- (CGFloat)systemSpacingAdjustment
{
  CGFloat spacing = (_document && [_document pageLayout])
                      ? [[_document pageLayout] systemSpacing] : 24.0;
  return spacing - 24.0;
}
- (CGFloat)staffScale
{
  return (_document && [_document pageLayout]) ? [[_document pageLayout] staffScale] : 1.0;
}

- (BOOL)isTrebleStaffForNote:(ScoreNote *)note
{
  if ([note staffAssignment] == 1)
    return YES;
  if ([note staffAssignment] == 2)
    return NO;
  return [self displayedPitchForNote:note] >= 60;
}
- (CGFloat)musicWidth
{
  /* Keep line breaking in lockstep with drawSystemAtY:.  The clef/key/time
     preamble reserves 100 points after the part label, and the staff ends 18
     points before the available right edge.  Using the wider paper-content
     estimate here caused dense generated scores to be packed past the useful
     right margin and visually run off the page. */
  CGFloat staffLeft = [self leftMargin] + PartLabelWidth;
  CGFloat staffRight = [self pageWidth] - PaperInset * 2.0 - [self rightMargin];
  CGFloat musicLeft = staffLeft + 100.0;
  CGFloat musicRight = staffRight - 18.0;
  return MAX (240.0, musicRight - musicLeft);
}

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame:frame];
  if (self)
    {
      _separateParts = YES;
      _writtenPitch = YES;
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

- (NSInteger)configuredInstrumentTranspositionForTrack:(NSInteger)track
{
  if (track < 0) return 0;
  for (ScorePartDefinition *part in [_document parts])
    if ([part legacyTrack] == track)
      {
        NSInteger transposition = [[part instrument] transposition];
        if (transposition != 0) return transposition;
        NSString *name = [[part name] lowercaseString];
        if ([name rangeOfString:@"baritone sax"].location != NSNotFound) return -21;
        if ([name rangeOfString:@"tenor sax"].location != NSNotFound
            || [name rangeOfString:@"bass clarinet"].location != NSNotFound) return -14;
        if ([name rangeOfString:@"alto sax"].location != NSNotFound) return -9;
        if ([name rangeOfString:@"english horn"].location != NSNotFound
            || [name rangeOfString:@"horn"].location != NSNotFound) return -7;
        if ([name rangeOfString:@"clarinet"].location != NSNotFound
            || [name rangeOfString:@"trumpet"].location != NSNotFound) return -2;
        if ([name rangeOfString:@"piccolo"].location != NSNotFound) return 12;
        if ([name rangeOfString:@"double bass"].location != NSNotFound) return -12;
        return 0;
      }
  return 0;
}

- (NSInteger)instrumentTranspositionForTrack:(NSInteger)track
{
  return _writtenPitch ? [self configuredInstrumentTranspositionForTrack:track] : 0;
}

- (NSString *)transpositionLabelForTrack:(NSInteger)track
{
  switch ([self configuredInstrumentTranspositionForTrack:track])
    {
    case -2: case -14: return @"in B♭";
    case -9: case -21: return @"in E♭";
    case -7: return @"in F";
    case 12: return @"sounds 8va";
    case -12: return @"sounds 8vb";
    default:
      {
        NSInteger value = [self configuredInstrumentTranspositionForTrack:track];
        return value == 0 ? nil
          : [NSString stringWithFormat:@"sounds %+ld semitones", (long)value];
      }
    }
}

- (NSString *)displayNameForTrack:(NSInteger)track compact:(BOOL)compact
{
  NSString *name = [_document nameForTrack:track];
  if (![name length]) name = [NSString stringWithFormat:@"Part %ld", (long)(track + 1)];
  NSString *transposition = [self transpositionLabelForTrack:track];
  if (![transposition length]) return name;
  return compact ? [NSString stringWithFormat:@"%@ (%@)", name, transposition]
                 : [NSString stringWithFormat:@"%@\n%@", name, transposition];
}

- (NSInteger)displayedPitchForNote:(ScoreNote *)note
{
  return [note pitch] - [self instrumentTranspositionForTrack:[note track]];
}

- (NSInteger)displayedFifthsForMeasure:(ScoreMeasure *)measure track:(NSInteger)track
{
  NSInteger transposition = [self instrumentTranspositionForTrack:track];
  if (!measure || transposition == 0) return measure ? [measure keySignatureFifths] : 0;
  NSInteger target = ScoreViewModulo12 (
    ScoreViewTonicPitchClass ([measure keySignatureFifths], [measure keyMode]) - transposition);
  NSInteger best = 0, bestWeight = NSIntegerMax;
  for (NSInteger fifths = -7; fifths <= 7; fifths++)
    if (ScoreViewTonicPitchClass (fifths, [measure keyMode]) == target
        && labs (fifths) < bestWeight)
      { best = fifths; bestWeight = labs (fifths); }
  return best;
}

- (BOOL)writtenPitch { return _writtenPitch; }
- (void)setWrittenPitch:(BOOL)writtenPitch
{
  if (_writtenPitch == writtenPitch) return;
  _writtenPitch = writtenPitch;
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
      _loopEndNote = nil;
      [_engravingLayout release];
      _engravingLayout = nil;
      [self reloadDocument];
    }
}

- (ScoreNote *)selectedNote
{
  return _selectedNote;
}

- (NSArray *)selectedNotes
{
  if (!_selectedNote || ![[_document notes] containsObject:_selectedNote])
    return [NSArray array];
  if (![self hasLoopSelection])
    return [NSArray arrayWithObject:_selectedNote];
  NSUInteger start = [self loopStartTick], end = [self loopEndTick];
  NSMutableArray *selection = [NSMutableArray array];
  for (ScoreNote *note in [_document notes])
    if ([note startTick] < end && [note startTick] + [note durationTicks] > start)
      [selection addObject:note];
  return selection;
}

- (void)selectNote:(ScoreNote *)note scrollToVisible:(BOOL)scroll
{
  if (note && ![[_document notes] containsObject:note])
    return;
  _selectedNote = note;
  _loopEndNote = nil;
  [self setNeedsDisplay:YES];
  if (scroll && note)
    [self scrollPlaybackTickToVisible:[note startTick]];
  [[NSNotificationCenter defaultCenter] postNotificationName:ScoreViewSelectionDidChangeNotification
                                                      object:self];
}

- (BOOL)hasLoopSelection
{
  return _selectedNote && _loopEndNote && _selectedNote != _loopEndNote
         && [[_document notes] containsObject:_selectedNote]
         && [[_document notes] containsObject:_loopEndNote];
}

- (NSUInteger)loopStartTick
{
  if (![self hasLoopSelection])
    return 0;
  return MIN ([_selectedNote startTick], [_loopEndNote startTick]);
}

- (NSUInteger)loopEndTick
{
  if (![self hasLoopSelection])
    return 0;
  ScoreNote *later = [_selectedNote startTick] > [_loopEndNote startTick] ? _selectedNote
                                                                         : _loopEndNote;
  return [later startTick] + MAX ((NSUInteger)1, [later durationTicks]);
}

- (void)setPlaybackTick:(NSUInteger)tick
{
  NSUInteger previousTick = _playbackTick;
  BOOL wasShowingPlayback = _showPlayback;
  _playbackTick = tick;
  _showPlayback = YES;

  /* Playback changes only the active system's cartouche and note highlights.
   * Invalidating the whole document here made long scores re-render at
   * 30 frames per second. */
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
                                     0.0, -PlaybackCartoucheDamageInset)];
    }

  NSUInteger currentSystem = 0;
  NSArray *layouts = [self systemLayouts];
  NSMutableIndexSet *damagedSystems = [NSMutableIndexSet indexSet];
  for (NSUInteger index = 0; index < [layouts count]; index++)
    {
      ScoreEngravingSystem *layout = [layouts objectAtIndex:index];
      if (tick >= [layout startTick] && tick < [layout endTick])
        {
          currentSystem = index;
          break;
        }
    }
  [damagedSystems addIndex:currentSystem];

  /* A note may be engraved in more than one system.  When its active state
   * changes, repaint every system containing it; otherwise the glow drawn in
   * an earlier system survives after the playhead has moved on. */
  if (wasShowingPlayback)
    for (ScoreNote *note in [_document notes])
      {
        if ([note isRest])
          continue;
        NSUInteger noteEnd = [note startTick] + [note durationTicks];
        BOOL wasPlaying = [note startTick] <= previousTick && previousTick < noteEnd;
        BOOL isPlaying = [note startTick] <= tick && tick < noteEnd;
        if (wasPlaying == isPlaying)
          continue;
        for (NSUInteger index = 0; index < [layouts count]; index++)
          {
            ScoreEngravingSystem *layout = [layouts objectAtIndex:index];
            if ([note startTick] < [layout endTick] && noteEnd > [layout startTick])
              [damagedSystems addIndex:index];
          }
      }
  NSUInteger damagedSystem = [damagedSystems firstIndex];
  while (damagedSystem != NSNotFound)
    {
      [self setNeedsDisplayInRect:NSInsetRect (
                                     NSMakeRect (0.0, [self yForSystem:damagedSystem],
                                                 NSWidth ([self bounds]), [self systemHeight]),
                                     0.0, -PlaybackCartoucheDamageInset)];
      damagedSystem = [damagedSystems indexGreaterThanIndex:damagedSystem];
    }
}

- (void)clearPlayback
{
  if (_showPlayback)
    {
      _showPlayback = NO;
      NSArray *layouts = [self systemLayouts];
      NSMutableIndexSet *damagedSystems = [NSMutableIndexSet indexSet];
      for (NSUInteger index = 0; index < [layouts count]; index++)
        {
          ScoreEngravingSystem *layout = [layouts objectAtIndex:index];
          if (_playbackTick >= [layout startTick] && _playbackTick < [layout endTick])
            {
              [damagedSystems addIndex:index];
              break;
            }
        }
      for (ScoreNote *note in [_document notes])
        {
          NSUInteger noteEnd = [note startTick] + [note durationTicks];
          if ([note isRest] || [note startTick] > _playbackTick || _playbackTick >= noteEnd)
            continue;
          for (NSUInteger index = 0; index < [layouts count]; index++)
            {
              ScoreEngravingSystem *layout = [layouts objectAtIndex:index];
              if ([note startTick] < [layout endTick] && noteEnd > [layout startTick])
                [damagedSystems addIndex:index];
            }
        }
      NSUInteger system = [damagedSystems firstIndex];
      while (system != NSNotFound)
        {
          [self setNeedsDisplayInRect:NSInsetRect (
                                         NSMakeRect (0.0, [self yForSystem:system],
                                                     NSWidth ([self bounds]), [self systemHeight]),
                                         0.0, -PlaybackCartoucheDamageInset)];
          system = [damagedSystems indexGreaterThanIndex:system];
        }
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
  [_displayedAccidentals release];
  [_publicationTrack release];
  [super dealloc];
}

- (void)updateFrameForDocument
{
  NSUInteger pages = [self pageCount];
  CGFloat height
    = 2.0 * PaperInset + (CGFloat)pages * [self paperHeight] + (CGFloat)(pages - 1) * PageGap;
  [self setFrameSize:NSMakeSize ([self pageWidth], height)];
}

- (void)reloadDocument
{
  [_engravingLayout release];
  _engravingLayout = nil;
  [_displayedAccidentals release];
  _displayedAccidentals = [ScoreDisplayedAccidentalMapForDocument (_document) copy];
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
                                    musicWidth:[self musicWidth]
                           minimumMeasureWidth:MinimumMeasureWidth] retain];
  return [_engravingLayout systems];
}

- (NSUInteger)systemCount
{
  return MAX ((NSUInteger)1, [[self systemLayouts] count]);
}

- (NSUInteger)pageCount
{
  NSUInteger count = [self systemCount];
  return count ? [self pageForSystem:count - 1] + 1 : 1;
}

- (NSUInteger)pageForSystem:(NSUInteger)targetSystem
{
  return ScorePageIndexForSystem ([self systemLayouts], targetSystem, [self systemsPerPage]);
}

- (NSUInteger)positionOnPageForSystem:(NSUInteger)targetSystem
{
  return ScorePositionOnPageForSystem ([self systemLayouts], targetSystem,
                                       [self systemsPerPage]);
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
  NSMutableArray *ordered = [NSMutableArray array];
  for (ScorePartDefinition *part in [_document parts])
    {
      NSNumber *track = [NSNumber numberWithInteger:[part legacyTrack]];
      [trackSet removeObject:track];
      if ([part visible]) [ordered addObject:track];
    }
  [ordered addObjectsFromArray:[[trackSet allObjects] sortedArrayUsingSelector:@selector (compare:)]];
  if ([ordered count] == 0)
    [ordered addObject:@0];
  return ordered;
}

- (CGFloat)partGrandStaffHeight
{
  return StaffGap + 4.0 * LineSpacing;
}

- (CGFloat)systemHeight
{
  NSUInteger parts = _separateParts ? MAX ((NSUInteger)1, [[self scoreTracks] count]) : 1;
  CGFloat base = [self partGrandStaffHeight] * parts + [self partSpacing] * (parts - 1)
                 + (SinglePartSystemHeight - [self partGrandStaffHeight])
                 + [self systemSpacingAdjustment];
  return base * [self staffScale];
}

- (NSUInteger)systemsPerPage
{
  CGFloat available = [self paperHeight] - [self topMargin] - [self bottomMargin]
                      - FirstSystemOffset;
  return MAX ((NSUInteger)1, (NSUInteger)floor (available / [self systemHeight]));
}

- (CGFloat)paperHeight
{
  /* Keep unusually large ensembles on the paper instead of clipping staves. */
  CGFloat requested = (_document && [_document pageLayout])
                        ? [[_document pageLayout] paperHeight] : 1222.0;
  return MAX (requested, [self topMargin] + FirstSystemOffset + [self systemHeight]
                         + [self bottomMargin]);
}

- (CGFloat)pageOriginY:(NSUInteger)page
{
  return PaperInset + (CGFloat)page * ([self paperHeight] + PageGap);
}

- (CGFloat)yForSystem:(NSUInteger)system
{
  NSUInteger page = [self pageForSystem:system];
  NSUInteger systemOnPage = [self positionOnPageForSystem:system];
  return [self pageOriginY:page] + [self topMargin] + FirstSystemOffset
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
  return NSMakeRect (PaperInset, [self pageOriginY:pageIndex], [self pageWidth] - 2.0 * PaperInset,
                     [self paperHeight]);
}

- (NSSize)printedPageContentSize
{
  return NSMakeSize ([self pageWidth] - 2.0 * PaperInset, [self paperHeight]);
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
                                     [self pageWidth] - 2.0 * PaperInset, [self paperHeight]);
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
                                     [self pageWidth] - 2.0 * PaperInset, [self paperHeight]);
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
          for (NSUInteger system = 0; system < systemCount; system++)
            {
              if ([self pageForSystem:system] == page)
                [self drawSystemAtY:[self yForSystem:system] systemIndex:system];
            }
          [NSGraphicsContext restoreGraphicsState];
        }
      return;
    }

  for (NSUInteger page = 0; page < [self pageCount]; page++)
    {
      CGFloat originY = [self pageOriginY:page];
      NSRect paper = NSMakeRect (PaperInset, originY, [self pageWidth] - 2.0 * PaperInset,
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
  ScorePageLayout *layout = [_document pageLayout];
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
  CGFloat pageWidth = [self pageWidth];
  CGFloat leftMargin = [self leftMargin], rightMargin = [self rightMargin];
  CGFloat topMargin = [self topMargin];
  NSRect titleRect = NSMakeRect (leftMargin + 90.0, pageOriginY + topMargin - 28.0,
                                 pageWidth - leftMargin - rightMargin - 180.0, 40.0);
  [title drawInRect:titleRect withAttributes:titleAttrs];
  if (_publicationTrack)
    {
      NSString *partName = [self displayNameForTrack:[_publicationTrack integerValue] compact:YES];
      NSDictionary *partAttrs = [NSDictionary
        dictionaryWithObjectsAndKeys:[NSFont boldSystemFontOfSize:14.0], NSFontAttributeName,
                                     [NSColor blackColor], NSForegroundColorAttributeName, centered,
                                     NSParagraphStyleAttributeName, nil];
      [partName drawInRect:NSMakeRect (leftMargin + 90.0, pageOriginY + topMargin + 8.0,
                                       pageWidth - leftMargin - rightMargin - 180.0, 22.0)
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
    = NSMakeRect (pageWidth - rightMargin - 54.0, pageOriginY + topMargin - 24.0, 54.0, 20.0);
  if (![[_document pageLayout] showPageNumbers])
    pageNumber = @"";
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
        = NSMakeRect (pageWidth / 2.0, pageOriginY + topMargin + 10.0,
                      pageWidth / 2.0 - rightMargin, 24.0);
      [composer drawInRect:composerRect withAttributes:composerAttrs];
    }
  if (page > 0 && [layout showHeaders] && [[layout headerText] length])
    {
      NSDictionary *runningAttrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:11.0],
        NSForegroundColorAttributeName : [NSColor darkGrayColor]
      };
      [[layout headerText]
        drawInRect:NSMakeRect (leftMargin, pageOriginY + 12.0,
                               pageWidth - leftMargin - rightMargin, 18.0)
        withAttributes:runningAttrs];
    }
  if ([[layout footerText] length])
    {
      NSMutableParagraphStyle *footerStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
      [footerStyle setAlignment:NSTextAlignmentCenter];
      NSDictionary *footerAttrs = @{
        NSFontAttributeName : [NSFont systemFontOfSize:10.0],
        NSForegroundColorAttributeName : [NSColor darkGrayColor],
        NSParagraphStyleAttributeName : footerStyle
      };
      [[layout footerText]
        drawInRect:NSMakeRect (leftMargin,
                               pageOriginY + [self paperHeight] - [self bottomMargin] + 14.0,
                               pageWidth - leftMargin - rightMargin, 16.0)
        withAttributes:footerAttrs];
    }
}

- (void)drawPlaybackCartoucheAtY:(CGFloat)y
                     systemStart:(NSUInteger)systemStart
                       systemEnd:(NSUInteger)systemEnd
                            left:(CGFloat)left
                           right:(CGFloat)right
{
  if (!_showPlayback || _playbackTick < systemStart || _playbackTick >= systemEnd
      || ![[NSGraphicsContext currentContext] isDrawingToScreen])
    return;

  CGFloat x = [self xForTick:_playbackTick
                       start:systemStart
                         end:systemEnd
                        left:left
                       right:right];
  NSUInteger parts = _separateParts ? MAX ((NSUInteger)1, [[self scoreTracks] count]) : 1;
  CGFloat partStride = [self partGrandStaffHeight] + [self partSpacing];
  CGFloat top = y - PlaybackCartoucheVerticalInset;
  CGFloat bottom = y + (CGFloat)(parts - 1) * partStride + [self partGrandStaffHeight]
                   + PlaybackCartoucheVerticalInset;
  NSRect rect = NSMakeRect (x - 13.0, top, 26.0, bottom - top);
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:7.0 yRadius:7.0];

  [[NSColor colorWithCalibratedRed:0.12 green:0.48 blue:0.95 alpha:0.18] setFill];
  [path fill];
  [[NSColor colorWithCalibratedRed:0.08 green:0.38 blue:0.88 alpha:0.55] setStroke];
  [path setLineWidth:1.5];
  [path stroke];
}

- (void)drawLoopSelectionAtY:(CGFloat)y
                 systemStart:(NSUInteger)systemStart
                   systemEnd:(NSUInteger)systemEnd
                        left:(CGFloat)left
                       right:(CGFloat)right
{
  if (![self hasLoopSelection] || ![[NSGraphicsContext currentContext] isDrawingToScreen])
    return;
  NSUInteger loopStart = [self loopStartTick], loopEnd = [self loopEndTick];
  if (loopEnd <= systemStart || loopStart >= systemEnd)
    return;

  NSUInteger visibleStart = MAX (loopStart, systemStart);
  NSUInteger visibleEnd = MIN (loopEnd, systemEnd);
  CGFloat x1 = [self xForTick:visibleStart
                        start:systemStart
                          end:systemEnd
                         left:left
                        right:right];
  CGFloat x2 = [self xForTick:visibleEnd
                        start:systemStart
                          end:systemEnd
                         left:left
                        right:right];
  NSUInteger parts = _separateParts ? MAX ((NSUInteger)1, [[self scoreTracks] count]) : 1;
  CGFloat partStride = [self partGrandStaffHeight] + [self partSpacing];
  CGFloat top = y - 11.0;
  CGFloat bottom = y + (CGFloat)(parts - 1) * partStride + [self partGrandStaffHeight] + 11.0;
  NSRect rect = NSMakeRect (x1, top, MAX ((CGFloat)8.0, x2 - x1), bottom - top);
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:5.0 yRadius:5.0];
  [[NSColor colorWithCalibratedRed:0.38 green:0.30 blue:0.88 alpha:0.09] setFill];
  [path fill];
  [[NSColor colorWithCalibratedRed:0.32 green:0.24 blue:0.78 alpha:0.28] setStroke];
  [path setLineWidth:1.0];
  [path stroke];
}

- (void)drawSystemAtY:(CGFloat)y systemIndex:(NSUInteger)systemIndex
{
  CGFloat staffScale = [self staffScale];
  [NSGraphicsContext saveGraphicsState];
  if (fabs (staffScale - 1.0) > 0.001)
    {
      NSAffineTransform *transform = [NSAffineTransform transform];
      [transform translateXBy:0.0 yBy:y];
      [transform scaleXBy:1.0 yBy:staffScale];
      [transform translateXBy:0.0 yBy:-y];
      [transform concat];
    }
  CGFloat left = [self leftMargin] + PartLabelWidth;
  CGFloat right = [self pageWidth] - PaperInset * 2.0 - [self rightMargin];
  ScoreEngravingSystem *layout = [[self systemLayouts] objectAtIndex:systemIndex];
  NSUInteger startTick = [layout startTick];
  NSUInteger endTick = [layout endTick];

  ScoreMeasure *openingMeasure = [_document measureContainingTick:startTick];
  NSArray *tracks = _separateParts ? [self scoreTracks] : [NSArray arrayWithObject:@-1];
  NSInteger openingFifths = 0;
  for (NSNumber *trackNumber in tracks)
    {
      NSInteger candidate = [self displayedFifthsForMeasure:openingMeasure
                                                       track:[trackNumber integerValue]];
      if (labs (candidate) > labs (openingFifths)) openingFifths = candidate;
    }
  BOOL drawsOpeningTime = [self positionOnPageForSystem:systemIndex] == 0;
  CGFloat keySignatureX = left + 39.0;
  CGFloat keySignatureWidth = labs (openingFifths) * 8.0;
  CGFloat timeSignatureX = openingFifths ? keySignatureX + keySignatureWidth + 7.0 : left + 58.0;
  CGFloat musicLeft = MAX (left + 100.0,
                           drawsOpeningTime ? timeSignatureX + 38.0
                                            : keySignatureX + keySignatureWidth + 12.0);
  CGFloat musicRight = right - 18.0;
  CGFloat partStride = [self partGrandStaffHeight] + [self partSpacing];
  [self drawLoopSelectionAtY:y
                 systemStart:startTick
                   systemEnd:endTick
                        left:musicLeft
                       right:musicRight];
  [self drawPlaybackCartoucheAtY:y
                     systemStart:startTick
                       systemEnd:endTick
                            left:musicLeft
                           right:musicRight];
  for (NSUInteger partIndex = 0; partIndex < [tracks count]; partIndex++)
    {
      NSInteger track = [[tracks objectAtIndex:partIndex] integerValue];
      NSInteger partOpeningFifths = [self displayedFifthsForMeasure:openingMeasure track:track];
      CGFloat trebleTop = y + partIndex * partStride;
      CGFloat bassTop = trebleTop + StaffGap;
      [self drawPartNameForTrack:track
                               x:[self leftMargin] - 10.0
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
      if (drawsOpeningTime)
        [self drawTimeSignatureAtX:timeSignatureX trebleY:trebleTop bassY:bassTop];
      if (openingMeasure && partOpeningFifths != 0)
        [self drawKeySignature:partOpeningFifths
                           atX:keySignatureX
                       trebleY:trebleTop
                         bassY:bassTop];
      ScoreMeasure *previousMeasure = nil;
      for (ScoreMeasure *measure in [_document measures])
        {
          NSUInteger tick = [measure startTick];
          if (tick <= startTick) { previousMeasure = measure; continue; }
          if (tick >= endTick) break;
          NSInteger previousFifths = [self displayedFifthsForMeasure:previousMeasure track:track];
          NSInteger measureFifths = [self displayedFifthsForMeasure:measure track:track];
          if (previousMeasure &&
              (previousFifths != measureFifths ||
               ![[previousMeasure keyMode] isEqualToString:[measure keyMode]]))
            {
              CGFloat keyX = [self xForTick:tick start:startTick end:endTick
                                      left:musicLeft right:musicRight] + 7.0;
              [self drawKeySignatureCancellationFrom:previousFifths
                                                   to:measureFifths
                                                  atX:keyX trebleY:trebleTop bassY:bassTop];
            }
          previousMeasure = measure;
        }
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
  [NSGraphicsContext restoreGraphicsState];
}

- (void)drawKeyAccidentals:(NSInteger)fifths symbol:(NSString *)symbol
                       atX:(CGFloat)x trebleY:(CGFloat)trebleY bassY:(CGFloat)bassY
{
  NSInteger count = labs (fifths);
  NSInteger trebleSharpSteps[] = { 0, 3, -1, 2, 5, 1, 4 };
  NSInteger trebleFlatSteps[] = { 4, 1, 5, 2, 6, 3, 7 };
  NSInteger bassSharpSteps[] = { 2, 5, 1, 4, 7, 3, 6 };
  NSInteger bassFlatSteps[] = { -1, 3, 0, 4, 1, 5, 2 };
  NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
    ([NSFont fontWithName:@"Times New Roman" size:18.0] ?: [NSFont systemFontOfSize:16.0]),
    NSFontAttributeName, [NSColor blackColor], NSForegroundColorAttributeName, nil];
  for (NSInteger i = 0; i < count; i++)
    {
      NSInteger trebleStep = fifths > 0 ? trebleSharpSteps[i] : trebleFlatSteps[i];
      NSInteger bassStep = fifths > 0 ? bassSharpSteps[i] : bassFlatSteps[i];
      [symbol drawAtPoint:NSMakePoint (x + i * 8.0, trebleY + trebleStep * 2.5 - 9.0)
           withAttributes:attrs];
      [symbol drawAtPoint:NSMakePoint (x + i * 8.0, bassY + bassStep * 2.5 - 9.0)
           withAttributes:attrs];
    }
}

- (void)drawKeySignatureCancellationFrom:(NSInteger)oldFifths
                                       to:(NSInteger)newFifths
                                      atX:(CGFloat)x
                                  trebleY:(CGFloat)trebleY
                                    bassY:(CGFloat)bassY
{
  if (oldFifths)
    [self drawKeyAccidentals:oldFifths symbol:@"♮" atX:x trebleY:trebleY bassY:bassY];
  CGFloat newX = x + (oldFifths ? labs (oldFifths) * 8.0 + 4.0 : 0.0);
  if (newFifths)
    [self drawKeyAccidentals:newFifths symbol:(newFifths > 0 ? @"♯" : @"♭")
                         atX:newX trebleY:trebleY bassY:bassY];
}

- (void)drawKeySignature:(NSInteger)fifths
                     atX:(CGFloat)x
                 trebleY:(CGFloat)trebleY
                   bassY:(CGFloat)bassY
{
  [self drawKeyAccidentals:fifths symbol:(fifths > 0 ? @"♯" : @"♭")
                       atX:x trebleY:trebleY bassY:bassY];
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
          [names addObject:[self displayNameForTrack:[number integerValue] compact:YES]];
        }
      name = [names componentsJoinedByString:@"\n"];
    }
  else
    {
      name = [self displayNameForTrack:track compact:NO];
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
      if ([[measure rehearsalMark] length])
        {
          NSDictionary *attrs = @{ NSFontAttributeName : [NSFont boldSystemFontOfSize:12.0],
                                   NSForegroundColorAttributeName : [NSColor blackColor] };
          NSSize size = [[measure rehearsalMark] sizeWithAttributes:attrs];
          NSRect box = NSMakeRect (x + 4.0, top - 30.0, size.width + 12.0, size.height + 6.0);
          [[NSBezierPath bezierPathWithRoundedRect:box xRadius:2.0 yRadius:2.0] stroke];
          [[measure rehearsalMark] drawAtPoint:NSMakePoint (x + 10.0, top - 27.0)
                                 withAttributes:attrs];
        }
      if ([[measure endingText] length])
        {
          CGFloat endingY = top - 15.0;
          [NSBezierPath strokeLineFromPoint:NSMakePoint (x, endingY)
                                    toPoint:NSMakePoint (MIN (right, x + 90.0), endingY)];
          [NSBezierPath strokeLineFromPoint:NSMakePoint (x, endingY)
                                    toPoint:NSMakePoint (x, endingY + 12.0)];
          [[measure endingText] drawAtPoint:NSMakePoint (x + 5.0, endingY - 2.0)
                              withAttributes:@{ NSFontAttributeName : [NSFont systemFontOfSize:10.0],
                                                NSForegroundColorAttributeName : [NSColor blackColor] }];
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

      BOOL treble = [self isTrebleStaffForNote:note];
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
          [self drawPlaybackHighlightAtX:x y:y voice:[note voice]];
        }
      if ([[self selectedNotes] containsObject:note]
          && [[NSGraphicsContext currentContext] isDrawingToScreen])
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
      BOOL treble = [self isTrebleStaffForNote:note];
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

      /* The end notes establish the beam slope, but an interior note can be
       * much closer to that line.  Move the complete beam stack away from
       * the noteheads before fixing the stem ends.  Account for the outer
       * edge of secondary/tertiary beams, which is the edge nearest a head.
       */
      CGFloat beamAdjustment = 0.0;
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
          CGFloat noteY = [self yForNote:note treble:treble staffTop:staffTop];
          NSUInteger beamCount = MIN ((NSUInteger)3,
                                      [self flagCountForDuration:[note durationTicks]]);
          CGFloat beamInset = beamCount > 1 ? 4.0 * (1.8 + (CGFloat)beamCount) : 4.0;
          CGFloat clearance = 6.0;
          if (stemsUp)
            beamAdjustment = MIN (beamAdjustment, noteY - clearance - beamInset - beamY);
          else
            beamAdjustment = MAX (beamAdjustment, noteY + clearance + beamInset - beamY);
        }
      firstBeamY += beamAdjustment;
      lastBeamY += beamAdjustment;

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
      BOOL treble = [self isTrebleStaffForNote:note];
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
      BOOL treble = [self isTrebleStaffForNote:note];
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
      BOOL treble = [self isTrebleStaffForNote:note];
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
      if ([[note ornament] length])
        {
          NSString *mark = [[note ornament] isEqualToString:@"trill-mark"] ? @"tr" : @"∿";
          NSFont *font = [NSFont fontWithName:@"Times New Roman Italic" size:12.0];
          if (!font) font = [NSFont systemFontOfSize:12.0];
          NSDictionary *attrs = @{ NSFontAttributeName : font,
                                   NSForegroundColorAttributeName : [NSColor blackColor] };
          NSSize size = [mark sizeWithAttributes:attrs];
          NSRect rect = ScorePlaceRect (NSMakeRect (x - size.width / 2.0, y - 38.0,
                                                    size.width, size.height), occupied, -12.0);
          [mark drawAtPoint:rect.origin withAttributes:attrs];
        }
      if ([[note lyric] length])
        {
          NSDictionary *lyricAttrs = @{ NSFontAttributeName : [NSFont systemFontOfSize:11.0],
                                        NSForegroundColorAttributeName : [NSColor blackColor] };
          NSSize size = [[note lyric] sizeWithAttributes:lyricAttrs];
          NSRect rect = ScorePlaceRect (NSMakeRect (x - size.width / 2.0, staff + 66.0,
                                                    size.width, size.height), occupied, 13.0);
          [[note lyric] drawAtPoint:rect.origin withAttributes:lyricAttrs];
        }
      if ([[note directionText] length])
        {
          NSFont *textFont = [NSFont fontWithName:@"Times New Roman Italic" size:11.0];
          if (!textFont) textFont = [NSFont systemFontOfSize:11.0];
          NSDictionary *textAttrs = @{ NSFontAttributeName : textFont,
                                       NSForegroundColorAttributeName : [NSColor blackColor] };
          [[note directionText] drawAtPoint:NSMakePoint (x - 4.0, staff - 34.0)
                              withAttributes:textAttrs];
        }
      ScoreNote *spanEnd = nil;
      if ([[note hairpinStart] length] || [note pedalStart] || [note octaveShiftStart])
        for (NSUInteger j = i + 1; j < [notes count]; j++)
          {
            ScoreNote *candidate = [notes objectAtIndex:j];
            if ([candidate track] != [note track] || [candidate voice] != [note voice]) continue;
            if (([[note hairpinStart] length] && [candidate hairpinEnd])
                || ([note pedalStart] && [candidate pedalEnd])
                || ([note octaveShiftStart] && [candidate octaveShiftEnd]))
              { spanEnd = candidate; break; }
          }
      CGFloat spanEndX = spanEnd ? [self engravedXForNote:spanEnd start:systemStart end:systemEnd
                                                         left:left right:right]
                                 : MIN (right, x + 72.0);
      if ([[note hairpinStart] length])
        {
          CGFloat lineY = staff + 64.0, opening = 7.0;
          BOOL crescendo = [[note hairpinStart] isEqualToString:@"crescendo"];
          CGFloat leftOpen = crescendo ? 0.0 : opening, rightOpen = crescendo ? opening : 0.0;
          [NSBezierPath strokeLineFromPoint:NSMakePoint (x, lineY - leftOpen)
                                    toPoint:NSMakePoint (spanEndX, lineY - rightOpen)];
          [NSBezierPath strokeLineFromPoint:NSMakePoint (x, lineY + leftOpen)
                                    toPoint:NSMakePoint (spanEndX, lineY + rightOpen)];
        }
      if ([note pedalStart])
        {
          CGFloat lineY = staff + 84.0;
          [@"Ped." drawAtPoint:NSMakePoint (x, lineY - 8.0) withAttributes:small];
          [NSBezierPath strokeLineFromPoint:NSMakePoint (x + 26.0, lineY)
                                    toPoint:NSMakePoint (spanEndX, lineY)];
          [NSBezierPath strokeLineFromPoint:NSMakePoint (spanEndX, lineY)
                                    toPoint:NSMakePoint (spanEndX, lineY - 7.0)];
        }
      if ([note octaveShiftStart])
        {
          CGFloat lineY = staff - 42.0;
          NSString *label = [note octaveShiftStart] > 0 ? @"8va" : @"8vb";
          [label drawAtPoint:NSMakePoint (x, lineY - 8.0) withAttributes:small];
          NSBezierPath *line = [NSBezierPath bezierPath];
          [line setLineDash:(CGFloat[]){ 4.0, 3.0 } count:2 phase:0.0];
          [line moveToPoint:NSMakePoint (x + 24.0, lineY)];
          [line lineToPoint:NSMakePoint (spanEndX, lineY)];
          [line stroke];
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
      CGFloat endStaff = [self displayedPitchForNote:endNote] >= 60 ? trebleY : bassY;
      CGFloat endY = [self yForNote:endNote
                              treble:([self displayedPitchForNote:endNote] >= 60)
                            staffTop:endStaff];
      NSBezierPath *tie = [NSBezierPath bezierPath];
      [tie moveToPoint:NSMakePoint (x + 5.0, y + 5.0)];
      [tie curveToPoint:NSMakePoint (endX - 5.0, endY + 5.0)
          controlPoint1:NSMakePoint (x + (endX - x) * .3, y + 14.0)
          controlPoint2:NSMakePoint (x + (endX - x) * .7, endY + 14.0)];
      [tie stroke];
    }
}

- (void)drawPlaybackHighlightAtX:(CGFloat)x y:(CGFloat)y voice:(NSInteger)voice
{
  NSRect glowRect = NSMakeRect (x - 12.0, y - 10.0, 24.0, 20.0);
  NSColor *glow = [ScoreVoiceColor (voice, NO) colorWithAlphaComponent:0.55];
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
  CGFloat inset = NoteHorizontalInset;
  ScoreMeasure *measure = [_document measureContainingTick:tick];
  if (measure && tick == [measure startTick])
    {
      inset = MeasureLeadingNoteHorizontalInset;
      NSUInteger index = [[_document measures] indexOfObjectIdenticalTo:measure];
      if (index > 0 && index != NSNotFound)
        {
          ScoreMeasure *previous = [[_document measures] objectAtIndex:index - 1];
          if ([previous keySignatureFifths] != [measure keySignatureFifths] ||
              ![[previous keyMode] isEqualToString:[measure keyMode]])
            inset += 8.0 * (labs ([previous keySignatureFifths]) +
                            labs ([measure keySignatureFifths])) + 12.0;
        }
    }
  return MIN (right - 2.0,
              [self xForTick:tick start:start end:end left:left right:right] + inset);
}

- (CGFloat)chordOffsetForNote:(ScoreNote *)note
{
  if ([note isRest])
    return 0.0;
  NSMutableArray *chord = [NSMutableArray array];
  BOOL treble = [self isTrebleStaffForNote:note];
  for (ScoreNote *candidate in [_document notes])
    {
      if ([candidate isRest] || [candidate startTick] != [note startTick] ||
          [candidate track] != [note track] || [candidate voice] != [note voice]
          || (([self displayedPitchForNote:candidate] >= 60) != treble))
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
                                                 toPitch:[self displayedPitchForNote:note]
                                              accidental:[note accidental]];
      if (noteSteps - lowerSteps <= 1)
        offset = (index % 2 == 0) ? 6.5 : 0.0;
    }
  NSInteger noteSteps = [self diatonicStepsFromPitch:0
                                             toPitch:[self displayedPitchForNote:note]
                                          accidental:[note accidental]];
  for (ScoreNote *candidate in [_document notes])
    if (candidate != note && ![candidate isRest] && [candidate startTick] == [note startTick] &&
        [candidate track] == [note track] && [candidate voice] != [note voice]
        && (([self displayedPitchForNote:candidate] >= 60) == treble))
      {
        NSInteger candidateSteps = [self diatonicStepsFromPitch:0
                                                        toPitch:[self displayedPitchForNote:candidate]
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
  if ([[_displayedAccidentals objectForKey:[NSValue valueWithPointer:note]] integerValue]
        == NSIntegerMax)
    return 0.0;
  NSMutableArray *accidentals = [NSMutableArray array];
  BOOL treble = [self isTrebleStaffForNote:note];
  for (ScoreNote *candidate in [_document notes])
    {
      if ([candidate isRest] ||
          [[_displayedAccidentals objectForKey:[NSValue valueWithPointer:candidate]] integerValue]
            == NSIntegerMax ||
          [candidate startTick] != [note startTick] || [candidate track] != [note track]
          || (([self displayedPitchForNote:candidate] >= 60) != treble))
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
      if (labs ([self displayedPitchForNote:other] - [self displayedPitchForNote:note]) < 6)
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

      BOOL treble = [self displayedPitchForNote:startNote] >= 60;
      CGFloat startStaff = treble ? trebleY : bassY;
      CGFloat endStaff = [self displayedPitchForNote:endNote] >= 60 ? trebleY : bassY;
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
        [self yForNote:endNote treble:([self displayedPitchForNote:endNote] >= 60)
                 staffTop:endStaff] + 11.0;
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
                                         toPitch:[self displayedPitchForNote:note]
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
  CGFloat scale = [self staffScale];
  CGFloat bottomY = staffTop + 4.0 * LineSpacing * scale;
  NSInteger steps
    = (NSInteger)llround ((bottomY - y) / ((LineSpacing * scale) / 2.0));
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
  CGFloat staffLeft = [self leftMargin] + PartLabelWidth + 100.0;
  CGFloat staffRight = [self pageWidth] - PaperInset * 2.0 - [self rightMargin] - 18.0;
  NSArray *tracks = _separateParts ? [self scoreTracks] : [NSArray arrayWithObject:@-1];
  CGFloat partStride = [self partGrandStaffHeight] + [self partSpacing];
  CGFloat scale = [self staffScale];
  for (NSUInteger system = 0; system < systemCount; system++)
    {
      CGFloat y = [self yForSystem:system];
      for (NSUInteger partIndex = 0; partIndex < [tracks count]; partIndex++)
        {
          CGFloat baseTrebleTop = y + partIndex * partStride;
          CGFloat baseBassTop = baseTrebleTop + StaffGap;
          CGFloat trebleTop = y + (baseTrebleTop - y) * scale;
          CGFloat bassTop = y + (baseBassTop - y) * scale;
          BOOL isTreble = NO;
          CGFloat top = 0.0;
          if (point.y >= trebleTop - 30.0 * scale
              && point.y <= trebleTop + (4.0 * LineSpacing + 21.0) * scale)
            {
              isTreble = YES;
              top = trebleTop;
            }
          else if (point.y >= bassTop - 21.0 * scale
                   && point.y <= bassTop + (4.0 * LineSpacing + 30.0) * scale)
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
  CGFloat left = [self leftMargin] + PartLabelWidth + 100.0;
  CGFloat right = [self pageWidth] - PaperInset * 2.0 - [self rightMargin] - 18.0;
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
      CGFloat systemY = [self yForSystem:system];
      CGFloat scale = [self staffScale];
      NSUInteger partIndex
        = _separateParts
            ? [[self scoreTracks] indexOfObject:[NSNumber numberWithInteger:[note track]]]
            : 0;
      if (partIndex == NSNotFound)
        continue;
      CGFloat basePartTop
        = systemY + partIndex * ([self partGrandStaffHeight] + [self partSpacing]);
      BOOL treble = [self isTrebleStaffForNote:note];
      CGFloat baseStaffTop = treble ? basePartTop : basePartTop + StaffGap;
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
      CGFloat baseNoteY = [note isRest]
                            ? baseStaffTop + 2.0 * LineSpacing
                            : [self yForNote:note treble:treble staffTop:baseStaffTop];
      CGFloat noteY = systemY + (baseNoteY - systemY) * scale;
      NSRect hitRect = NSMakeRect (x - 14.0, noteY - 16.0 * scale, 28.0, 32.0 * scale);
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
  ScoreNote *clickedNote = [self noteAtPoint:point];
  if (([event modifierFlags] & NSEventModifierFlagShift) && _selectedNote && clickedNote)
    _loopEndNote = clickedNote;
  else
    {
      _selectedNote = clickedNote;
      _loopEndNote = nil;
    }
  _draggedNote = clickedNote;
  _dragChanged = NO;
  [[self window] makeFirstResponder:self];
  [self setNeedsDisplay:YES];
  [[NSNotificationCenter defaultCenter] postNotificationName:ScoreViewSelectionDidChangeNotification
                                                      object:self];
  if (clickedNote && [event clickCount] == 2)
    [NSApp sendAction:NSSelectorFromString (@"playFromSelection:") to:nil from:self];
}

- (void)mouseDragged:(NSEvent *)event
{
  if (!_draggedNote || ![[_document notes] containsObject:_draggedNote])
    return;
  NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
  NSUInteger systemStart = 0, systemEnd = 0;
  CGFloat left = 0, right = 0, staffTop = 0;
  BOOL treble = YES;
  NSInteger track = [_draggedNote track];
  if (![self scoreLayoutForPoint:point systemStart:&systemStart systemEnd:&systemEnd left:&left
                           right:&right staffTop:&staffTop treble:&treble track:&track])
    return;
  NSUInteger tick = [self tickForPoint:point systemStart:systemStart systemEnd:systemEnd
                                  left:left right:right];
  NSUInteger quantum = MAX ((NSUInteger)1, [_document ticksPerQuarter] / 4);
  tick = ((tick + quantum / 2) / quantum) * quantum;
  NSInteger pitch = [_draggedNote isRest] ? [_draggedNote pitch]
                                           : [self pitchForY:point.y treble:treble staffTop:staffTop];
  if (tick != [_draggedNote startTick] || pitch != [_draggedNote pitch]
      || track != [_draggedNote track])
    {
      [_draggedNote setStartTick:tick];
      [_draggedNote setPitch:pitch];
      [_draggedNote setTrack:MAX ((NSInteger)0, track)];
      _dragChanged = YES;
      [self reloadDocument];
    }
}

- (void)mouseUp:(NSEvent *)event
{
  (void)event;
  _draggedNote = nil;
  if (_dragChanged)
    {
      [[_document notes] sortUsingSelector:@selector (compareScoreNote:)];
      [self updateTotalTicksFromNotes];
      [[NSNotificationCenter defaultCenter] postNotificationName:ScoreViewDidEditScoreNotification
                                                          object:self];
    }
  _dragChanged = NO;
}

- (void)copy:(id)sender
{
  (void)sender;
  [ScoreCopiedNotes release];
  NSMutableArray *copies = [NSMutableArray array];
  for (ScoreNote *note in [self selectedNotes])
    [copies addObject:[[note copy] autorelease]];
  ScoreCopiedNotes = [copies copy];
}

- (void)cut:(id)sender
{
  [self copy:sender];
  NSArray *selection = [self selectedNotes];
  if (![selection count]) return;
  [[_document notes] removeObjectsInArray:selection];
  _selectedNote = nil;
  _loopEndNote = nil;
  [self updateTotalTicksFromNotes];
  [[NSNotificationCenter defaultCenter] postNotificationName:ScoreViewDidEditScoreNotification object:self];
}

- (void)paste:(id)sender
{
  (void)sender;
  if (![ScoreCopiedNotes count]) return;
  NSUInteger sourceStart = NSUIntegerMax;
  for (ScoreNote *note in ScoreCopiedNotes)
    sourceStart = MIN (sourceStart, [note startTick]);
  NSUInteger destination = _selectedNote ? [_selectedNote startTick] + [_selectedNote durationTicks]
                                         : [_document totalTicks];
  ScoreNote *first = nil;
  for (ScoreNote *source in ScoreCopiedNotes)
    {
      ScoreNote *note = [[source copy] autorelease];
      [note setStartTick:destination + [source startTick] - sourceStart];
      [[_document notes] addObject:note];
      if (!first) first = note;
    }
  [[_document notes] sortUsingSelector:@selector (compareScoreNote:)];
  _selectedNote = first;
  _loopEndNote = nil;
  [self updateTotalTicksFromNotes];
  [[NSNotificationCenter defaultCenter] postNotificationName:ScoreViewDidEditScoreNotification object:self];
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
      NSArray *selection = [self selectedNotes];
      if ([selection count])
        {
          [[_document notes] removeObjectsInArray:selection];
          _selectedNote = nil;
          _loopEndNote = nil;
          [self updateTotalTicksFromNotes];
          [[NSNotificationCenter defaultCenter]
            postNotificationName:ScoreViewDidEditScoreNotification
                          object:self];
          [self reloadDocument];
        }
      return;
    }
  if (_selectedNote && ([event keyCode] == 126 || [event keyCode] == 125
                        || [event keyCode] == 123 || [event keyCode] == 124))
    {
      NSInteger pitchDelta = [event keyCode] == 126 ? 1 : ([event keyCode] == 125 ? -1 : 0);
      NSInteger tickDelta = [event keyCode] == 124 ? 1 : ([event keyCode] == 123 ? -1 : 0);
      NSUInteger quantum = MAX ((NSUInteger)1, [_document ticksPerQuarter] / 4);
      for (ScoreNote *note in [self selectedNotes])
        {
          if (pitchDelta && ![note isRest])
            [note setPitch:MIN ((NSInteger)127, MAX ((NSInteger)0, [note pitch] + pitchDelta))];
          if (tickDelta)
            [note setStartTick:tickDelta > 0 ? [note startTick] + quantum
                                                : ([note startTick] >= quantum
                                                     ? [note startTick] - quantum : 0)];
        }
      [[_document notes] sortUsingSelector:@selector (compareScoreNote:)];
      [[NSNotificationCenter defaultCenter] postNotificationName:ScoreViewDidEditScoreNotification
                                                          object:self];
      return;
    }
  unichar lower = [[characters lowercaseString] length]
                    ? [[characters lowercaseString] characterAtIndex:0] : 0;
  if (lower >= 'a' && lower <= 'g'
      && !([event modifierFlags] & (NSEventModifierFlagCommand | NSEventModifierFlagControl)))
    {
      NSInteger pitchClasses[] = { 9, 11, 0, 2, 4, 5, 7 };
      NSInteger pitchClass = pitchClasses[lower - 'a'];
      NSInteger referencePitch = _selectedNote && ![_selectedNote isRest]
                                   ? [_selectedNote pitch] : 60;
      NSInteger octaveBase = (referencePitch / 12) * 12;
      NSInteger pitch = octaveBase + pitchClass;
      if (pitch - referencePitch > 6) pitch -= 12;
      if (referencePitch - pitch > 6) pitch += 12;
      ScoreNote *note = _selectedNote ? [[_selectedNote copy] autorelease]
                                      : [[[ScoreNote alloc] init] autorelease];
      [note setRest:NO];
      [note setPitch:MIN ((NSInteger)127, MAX ((NSInteger)0, pitch))];
      [note setStartTick:_selectedNote
                           ? [_selectedNote startTick] + [_selectedNote durationTicks]
                           : [_document totalTicks]];
      if (!_selectedNote)
        {
          [note setDurationTicks:MAX ((NSUInteger)1, [_document ticksPerQuarter])];
          [note setTrack:0];
          [note setVoice:1];
        }
      [[_document notes] addObject:note];
      [[_document notes] sortUsingSelector:@selector (compareScoreNote:)];
      _selectedNote = note;
      _loopEndNote = nil;
      [self updateTotalTicksFromNotes];
      [[NSNotificationCenter defaultCenter] postNotificationName:ScoreViewDidEditScoreNotification
                                                          object:self];
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
      [item isEqualToString:@"accent"] || [item isEqualToString:@"tenuto"] ||
      [item isEqualToString:@"grace"] || [item isEqualToString:@"cue"] ||
      [item isEqualToString:@"trill"] || [item isEqualToString:@"tremolo"] ||
      [item isEqualToString:@"crescendo"] || [item isEqualToString:@"diminuendo"] ||
      [item isEqualToString:@"pedal"] || [item isEqualToString:@"8va"] ||
      [item isEqualToString:@"8vb"])
    {
      ScoreNote *target = [self noteAtPoint:point];
      if (!target || [target isRest])
        return NO;

      if ([item isEqualToString:@"slur"] || [item isEqualToString:@"tie"]
          || [item isEqualToString:@"crescendo"] || [item isEqualToString:@"diminuendo"]
          || [item isEqualToString:@"pedal"] || [item isEqualToString:@"8va"]
          || [item isEqualToString:@"8vb"])
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
          else if ([item isEqualToString:@"tie"])
            {
              if ([_selectedNote pitch] != [target pitch])
                return NO;
              [_selectedNote setTieStart:YES];
              [target setTieEnd:YES];
            }
          else if ([item isEqualToString:@"crescendo"] || [item isEqualToString:@"diminuendo"])
            {
              [_selectedNote setHairpinStart:item];
              [target setHairpinEnd:YES];
            }
          else if ([item isEqualToString:@"pedal"])
            {
              [_selectedNote setPedalStart:YES];
              [target setPedalEnd:YES];
            }
          else
            {
              [_selectedNote setOctaveShiftStart:[item isEqualToString:@"8va"] ? 1 : -1];
              [target setOctaveShiftEnd:YES];
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
      else if ([item isEqualToString:@"grace"])
        [target setGrace:![target isGrace]];
      else if ([item isEqualToString:@"cue"])
        [target setCue:![target isCue]];
      else if ([item isEqualToString:@"trill"])
        [target setOrnament:@"trill-mark"];
      else if ([item isEqualToString:@"tremolo"])
        [target setTremoloStrokes:[target tremoloStrokes] ? 0 : 3];
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
  CGFloat noteScale = ([note isGrace] || [note isCue]) ? 0.72 : 1.0;
  NSRect oval = NSMakeRect (x - 5.5 * noteScale, y - 4.0 * noteScale,
                            11.0 * noteScale, 8.0 * noteScale);
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

  NSInteger accidental = [[_displayedAccidentals objectForKey:[NSValue valueWithPointer:note]]
    integerValue];
  if (accidental != NSIntegerMax)
    {
      NSString *symbol = accidental > 0 ? @"♯" : (accidental < 0 ? @"♭" : @"♮");
      NSFont *font = [NSFont fontWithName:@"Times New Roman" size:20.0 * noteScale];
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
  if ([note isGrace])
    [NSBezierPath strokeLineFromPoint:NSMakePoint (stemX - 4.0, (y + stemEnd) / 2.0 + 4.0)
                              toPoint:NSMakePoint (stemX + 7.0, (y + stemEnd) / 2.0 - 5.0)];
  for (NSUInteger stroke = 0; stroke < [note tremoloStrokes]; stroke++)
    {
      CGFloat center = y + (stemEnd - y) * 0.55 + (CGFloat)stroke * (stemsUp ? -5.0 : 5.0);
      NSBezierPath *tremolo = [NSBezierPath bezierPath];
      [tremolo moveToPoint:NSMakePoint (stemX - 6.0, center + 3.0)];
      [tremolo lineToPoint:NSMakePoint (stemX + 7.0, center - 3.0)];
      [tremolo setLineWidth:2.0];
      [tremolo stroke];
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
