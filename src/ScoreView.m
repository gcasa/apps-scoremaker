#import "ScoreView.h"
#import <math.h>

static CGFloat const PageWidth = 980.0;
static CGFloat const Margin = 48.0;
static CGFloat const PartLabelWidth = 82.0;
static CGFloat const SystemHeight = 210.0;
static CGFloat const StaffGap = 82.0;
static CGFloat const LineSpacing = 10.0;
static CGFloat const TicksPerSystemQuarters = 16.0;
static CGFloat const ClefImageWidth = 20.0;
static CGFloat const ClefImageHeight = 60.0;
static CGFloat const FirstSystemOffset = 54.0;
NSString * const ScoreViewDidEditScoreNotification = @"ScoreViewDidEditScoreNotification";
NSString * const ScorePalettePasteboardType = @"com.scoremaker.palette-item";

@implementation ScoreView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self registerForDraggedTypes:[NSArray arrayWithObject:ScorePalettePasteboardType]];
    }
    return self;
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
    if (_document != document) {
        [_document release];
        _document = [document retain];
        _selectedNote = nil;
        [self reloadDocument];
    }
}

- (ScoreNote *)selectedNote
{
    return _selectedNote;
}

- (void)dealloc
{
    [_document release];
    [super dealloc];
}

- (void)updateFrameForDocument
{
    NSUInteger ticksPerSystem = [self ticksPerSystem];
    NSUInteger systems = 1;
    if (_document && ticksPerSystem > 0) {
        systems = MAX((NSUInteger)1, ([_document totalTicks] / ticksPerSystem) + 1);
    }
    CGFloat height = Margin + (CGFloat)systems * SystemHeight + Margin;
    [self setFrameSize:NSMakeSize(PageWidth, height)];
}

- (void)reloadDocument
{
    [self updateFrameForDocument];
    [self setNeedsDisplay:YES];
}

- (NSUInteger)ticksPerSystem
{
    NSUInteger tpq = _document ? [_document ticksPerQuarter] : 480;
    return (NSUInteger)(TicksPerSystemQuarters * (CGFloat)tpq);
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    BOOL drawingToScreen = [[NSGraphicsContext currentContext] isDrawingToScreen];
    NSColor *backgroundColor = drawingToScreen ? [NSColor colorWithCalibratedWhite:0.96 alpha:1.0] : [NSColor whiteColor];
    [backgroundColor setFill];
    NSRectFill([self bounds]);

    if (drawingToScreen) {
        NSRect page = NSMakeRect(18.0, 18.0, PageWidth - 36.0, [self bounds].size.height - 36.0);
        [[NSColor whiteColor] setFill];
        NSRectFill(page);
        [[NSColor colorWithCalibratedWhite:0.82 alpha:1.0] setStroke];
        NSFrameRect(page);
    }

    if (!_document) {
        [self drawCenteredMessage:@"Open a MIDI or score file to display sheet music."];
        return;
    }

    [self drawTitle];
    NSUInteger ticksPerSystem = [self ticksPerSystem];
    NSUInteger systemCount = MAX((NSUInteger)1, ([_document totalTicks] / ticksPerSystem) + 1);
    for (NSUInteger system = 0; system < systemCount; system++) {
        CGFloat y = Margin + FirstSystemOffset + (CGFloat)system * SystemHeight;
        [self drawSystemAtY:y systemIndex:system ticksPerSystem:ticksPerSystem];
    }
}

- (void)drawCenteredMessage:(NSString *)message
{
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSFont systemFontOfSize:18.0], NSFontAttributeName,
                           [NSColor colorWithCalibratedWhite:0.3 alpha:1.0], NSForegroundColorAttributeName,
                           nil];
    NSSize size = [message sizeWithAttributes:attrs];
    NSRect bounds = [self bounds];
    [message drawAtPoint:NSMakePoint((bounds.size.width - size.width) / 2.0,
                                     (bounds.size.height - size.height) / 2.0)
          withAttributes:attrs];
}

- (void)drawTitle
{
    NSDictionary *titleAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
                                [NSFont boldSystemFontOfSize:24.0], NSFontAttributeName,
                                [NSColor blackColor], NSForegroundColorAttributeName,
                                nil];
    NSString *title = [_document title] ? [_document title] : @"Untitled";
    [title drawAtPoint:NSMakePoint(Margin, Margin - 18.0) withAttributes:titleAttrs];
}

- (void)drawSystemAtY:(CGFloat)y systemIndex:(NSUInteger)systemIndex ticksPerSystem:(NSUInteger)ticksPerSystem
{
    CGFloat left = Margin + PartLabelWidth;
    CGFloat right = PageWidth - Margin;
    CGFloat trebleTop = y;
    CGFloat bassTop = y + StaffGap;
    NSUInteger startTick = systemIndex * ticksPerSystem;
    NSUInteger endTick = startTick + ticksPerSystem;

    [self drawPartNamesForSystemStart:startTick
                            systemEnd:endTick
                                    x:Margin - 10.0
                                    y:trebleTop
                               height:bassTop + 4.0 * LineSpacing - trebleTop];
    [self drawStaffFromX:left toX:right topY:trebleTop];
    [self drawStaffFromX:left toX:right topY:bassTop];
    [self drawBraceAtX:left - 14.0 topY:trebleTop bottomY:bassTop + 4.0 * LineSpacing];

    [self drawClefNamed:@"treble_clef" fallback:@"G" inRect:NSMakeRect(left + 14.0,
                                                                        trebleTop - 10.0,
                                                                        ClefImageWidth,
                                                                        ClefImageHeight)];
    [self drawClefNamed:@"bass_clef" fallback:@"F" inRect:NSMakeRect(left + 16.0,
                                                                      bassTop - 10.0,
                                                                      ClefImageWidth,
                                                                      ClefImageHeight)];

    CGFloat musicLeft = left + 100.0;
    CGFloat musicRight = right - 18.0;
    if (systemIndex == 0) {
        [self drawTempoMarkAtX:musicLeft y:trebleTop - 30.0];
        [self drawTimeSignatureAtX:left + 58.0 trebleY:trebleTop bassY:bassTop];
    }

    [self drawMeasureLinesFromX:musicLeft toX:musicRight topY:trebleTop systemStart:startTick systemEnd:endTick];
    [self drawNotesFromX:musicLeft toX:musicRight trebleY:trebleTop bassY:bassTop systemStart:startTick systemEnd:endTick];
}

- (void)drawTempoMarkAtX:(CGFloat)x y:(CGFloat)y
{
    NSUInteger tempo = [_document tempoMicrosecondsPerQuarter];
    if (tempo == 0) {
        return;
    }

    NSUInteger beatsPerMinute = (NSUInteger)((60000000.0 / (double)tempo) + 0.5);
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSFont systemFontOfSize:13.0], NSFontAttributeName,
                           [NSColor blackColor], NSForegroundColorAttributeName,
                           nil];

    CGFloat noteCenterY = y + 8.0;
    NSBezierPath *head = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x, noteCenterY - 3.0, 8.0, 6.0)];
    NSAffineTransform *slant = [NSAffineTransform transform];
    [slant translateXBy:x + 4.0 yBy:noteCenterY];
    [slant rotateByDegrees:-18.0];
    [slant translateXBy:-(x + 4.0) yBy:-noteCenterY];
    [head transformUsingAffineTransform:slant];
    [[NSColor blackColor] setFill];
    [head fill];

    CGFloat stemX = x + 7.5;
    [NSBezierPath strokeLineFromPoint:NSMakePoint(stemX, noteCenterY)
                              toPoint:NSMakePoint(stemX, noteCenterY - 24.0)];

    NSString *tempoText = [NSString stringWithFormat:@"= %lu", (unsigned long)beatsPerMinute];
    [tempoText drawAtPoint:NSMakePoint(x + 17.0, y) withAttributes:attrs];
}

- (NSImage *)clefImageNamed:(NSString *)name
{
    static NSMutableDictionary *clefImageCache = nil;
    NSImage *cached = [clefImageCache objectForKey:name];
    if (cached) {
        return cached;
    }

    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"png"];
    if (!path) {
        path = [[NSString stringWithFormat:@"Resources/%@.png", name] stringByStandardizingPath];
    }
    NSImage *image = [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
    if (image) {
        if (!clefImageCache) {
            clefImageCache = [[NSMutableDictionary alloc] init];
        }
        [clefImageCache setObject:image forKey:name];
    }
    return image;
}

- (void)drawClefNamed:(NSString *)name fallback:(NSString *)fallback inRect:(NSRect)rect
{
    NSImage *image = [self clefImageNamed:name];
    if (image) {
        [NSGraphicsContext saveGraphicsState];
        NSAffineTransform *transform = [NSAffineTransform transform];
        [transform translateXBy:0.0 yBy:NSMaxY(rect)];
        [transform scaleXBy:1.0 yBy:-1.0];
        [transform concat];
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
        [image drawInRect:NSMakeRect(rect.origin.x, 0.0, rect.size.width, rect.size.height)
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
    if (!clefFont) {
        clefFont = [NSFont boldSystemFontOfSize:38.0];
    }
    NSDictionary *clefAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
                               clefFont, NSFontAttributeName,
                               [NSColor blackColor], NSForegroundColorAttributeName,
                               nil];
    [fallback drawAtPoint:NSMakePoint(rect.origin.x - 4.0, rect.origin.y - 4.0) withAttributes:clefAttrs];
}

- (void)drawPartNamesForSystemStart:(NSUInteger)systemStart
                           systemEnd:(NSUInteger)systemEnd
                                   x:(CGFloat)x
                                   y:(CGFloat)y
                              height:(CGFloat)height
{
    NSMutableArray *tracks = [NSMutableArray array];
    NSEnumerator *noteEnumerator = [[_document notes] objectEnumerator];
    ScoreNote *note = nil;
    while ((note = [noteEnumerator nextObject]) != nil) {
        if ([note startTick] >= systemEnd || [note startTick] + [note durationTicks] <= systemStart) {
            continue;
        }
        NSNumber *track = [NSNumber numberWithInteger:[note track]];
        if (![tracks containsObject:track]) {
            [tracks addObject:track];
        }
    }
    if ([tracks count] == 0) {
        return;
    }
    [tracks sortUsingSelector:@selector(compare:)];

    NSMutableArray *names = [NSMutableArray array];
    NSEnumerator *trackEnumerator = [tracks objectEnumerator];
    NSNumber *track = nil;
    while ((track = [trackEnumerator nextObject]) != nil) {
        NSString *name = [_document nameForTrack:[track integerValue]];
        if ([name length] == 0) {
            name = [NSString stringWithFormat:@"Part %ld", (long)([track integerValue] + 1)];
        }
        [names addObject:name];
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
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSFont systemFontOfSize:10.0], NSFontAttributeName,
                           [NSColor colorWithCalibratedWhite:0.2 alpha:1.0], NSForegroundColorAttributeName,
                           style, NSParagraphStyleAttributeName,
                           nil];
    NSString *label = [names componentsJoinedByString:@"\n"];
    NSRect rect = NSMakeRect(x, y + height / 2.0 - 26.0, PartLabelWidth, 52.0);
    [label drawInRect:rect withAttributes:attrs];
}

- (void)drawStaffFromX:(CGFloat)left toX:(CGFloat)right topY:(CGFloat)top
{
    [[NSColor blackColor] setStroke];
    for (NSUInteger i = 0; i < 5; i++) {
        CGFloat y = top + (CGFloat)i * LineSpacing;
        [NSBezierPath strokeLineFromPoint:NSMakePoint(left, y) toPoint:NSMakePoint(right, y)];
    }
}

- (void)drawBraceAtX:(CGFloat)x topY:(CGFloat)top bottomY:(CGFloat)bottom
{
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(x + 10.0, top)];
    [path curveToPoint:NSMakePoint(x + 10.0, bottom)
         controlPoint1:NSMakePoint(x - 10.0, top + 35.0)
         controlPoint2:NSMakePoint(x - 10.0, bottom - 35.0)];
    [path setLineWidth:2.0];
    [[NSColor blackColor] setStroke];
    [path stroke];
}

- (void)drawTimeSignatureAtX:(CGFloat)x trebleY:(CGFloat)trebleY bassY:(CGFloat)bassY
{
    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSFont boldSystemFontOfSize:22.0], NSFontAttributeName,
                           [NSColor blackColor], NSForegroundColorAttributeName,
                           nil];
    NSString *top = [NSString stringWithFormat:@"%lu", (unsigned long)[_document timeSignatureNumerator]];
    NSString *bottom = [NSString stringWithFormat:@"%lu", (unsigned long)[_document timeSignatureDenominator]];
    [top drawAtPoint:NSMakePoint(x, trebleY - 2.0) withAttributes:attrs];
    [bottom drawAtPoint:NSMakePoint(x, trebleY + 20.0) withAttributes:attrs];
    [top drawAtPoint:NSMakePoint(x, bassY - 2.0) withAttributes:attrs];
    [bottom drawAtPoint:NSMakePoint(x, bassY + 20.0) withAttributes:attrs];
}

- (void)drawMeasureLinesFromX:(CGFloat)left
                          toX:(CGFloat)right
                         topY:(CGFloat)top
                  systemStart:(NSUInteger)systemStart
                    systemEnd:(NSUInteger)systemEnd
{
    NSUInteger beatsPerMeasure = [_document timeSignatureNumerator];
    NSUInteger beatUnit = [_document timeSignatureDenominator];
    NSUInteger ticksPerMeasure = ([_document ticksPerQuarter] * 4 * beatsPerMeasure) / MAX((NSUInteger)1, beatUnit);
    if (ticksPerMeasure == 0) ticksPerMeasure = [_document ticksPerQuarter] * 4;

    NSUInteger firstMeasure = ((systemStart + ticksPerMeasure - 1) / ticksPerMeasure) * ticksPerMeasure;
    for (NSUInteger tick = firstMeasure; tick <= systemEnd; tick += ticksPerMeasure) {
        CGFloat x = [self xForTick:tick start:systemStart end:systemEnd left:left right:right];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x, top)
                                  toPoint:NSMakePoint(x, top + StaffGap + 4.0 * LineSpacing)];
        if (tick + ticksPerMeasure <= tick) break;
    }
}

- (void)drawNotesFromX:(CGFloat)left
                   toX:(CGFloat)right
               trebleY:(CGFloat)trebleY
                 bassY:(CGFloat)bassY
           systemStart:(NSUInteger)systemStart
             systemEnd:(NSUInteger)systemEnd
{
    NSMutableArray *visibleNotes = [NSMutableArray array];
    NSEnumerator *noteEnumerator = [[_document notes] objectEnumerator];
    ScoreNote *note = nil;
    while ((note = [noteEnumerator nextObject]) != nil) {
        if ([note startTick] >= systemEnd || [note startTick] + [note durationTicks] <= systemStart) {
            continue;
        }

        BOOL treble = [note pitch] >= 60;
        CGFloat staffTop = treble ? trebleY : bassY;
        CGFloat x = [self xForTick:[note startTick] start:systemStart end:systemEnd left:left right:right];
        CGFloat y = [note isRest] ? staffTop + 2.0 * LineSpacing : [self yForNote:note treble:treble staffTop:staffTop];
        if (note == _selectedNote && [[NSGraphicsContext currentContext] isDrawingToScreen]) {
            [self drawSelectionAtX:x y:y];
        }
        if ([note isRest]) {
            [self drawRestAtX:x y:y duration:[note durationTicks]];
        } else {
            [visibleNotes addObject:note];
        }
    }

    NSUInteger quarter = MAX((NSUInteger)1, [_document ticksPerQuarter]);
    NSMutableDictionary *groupsByBeat = [NSMutableDictionary dictionary];
    noteEnumerator = [visibleNotes objectEnumerator];
    while ((note = [noteEnumerator nextObject]) != nil) {
        if ([note durationTicks] > quarter / 2) {
            continue;
        }
        BOOL treble = [note pitch] >= 60;
        NSUInteger beat = [note startTick] / quarter;
        NSString *key = [NSString stringWithFormat:@"%ld:%ld:%d:%lu",
                         (long)[note track],
                         (long)[note channel],
                         treble,
                         (unsigned long)beat];
        NSMutableArray *group = [groupsByBeat objectForKey:key];
        if (!group) {
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
    while ((group = [groupEnumerator nextObject]) != nil) {
        if ([group count] < 2) {
            continue;
        }
        ScoreNote *first = [group objectAtIndex:0];
        ScoreNote *last = [group lastObject];
        if ([first startTick] == [last startTick]) {
            continue;
        }
        BOOL treble = [first pitch] >= 60;
        CGFloat staffTop = treble ? trebleY : bassY;
        CGFloat averageY = 0.0;
        NSEnumerator *beamNoteEnumerator = [group objectEnumerator];
        while ((note = [beamNoteEnumerator nextObject]) != nil) {
            averageY += [self yForNote:note treble:treble staffTop:staffTop];
        }
        averageY /= (CGFloat)[group count];
        BOOL stemsUp = averageY >= staffTop + 2.0 * LineSpacing;
        CGFloat firstY = [self yForNote:first treble:treble staffTop:staffTop];
        CGFloat lastY = [self yForNote:last treble:treble staffTop:staffTop];
        CGFloat firstBeamY = firstY + (stemsUp ? -34.0 : 34.0);
        CGFloat lastBeamY = lastY + (stemsUp ? -34.0 : 34.0);
        CGFloat delta = lastBeamY - firstBeamY;
        if (delta > 8.0) lastBeamY = firstBeamY + 8.0;
        if (delta < -8.0) lastBeamY = firstBeamY - 8.0;
        CGFloat firstX = [self xForTick:[first startTick] start:systemStart end:systemEnd left:left right:right];
        CGFloat lastX = [self xForTick:[last startTick] start:systemStart end:systemEnd left:left right:right];

        beamNoteEnumerator = [group objectEnumerator];
        while ((note = [beamNoteEnumerator nextObject]) != nil) {
            CGFloat x = [self xForTick:[note startTick] start:systemStart end:systemEnd left:left right:right];
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
    while ((note = [noteEnumerator nextObject]) != nil) {
        BOOL treble = [note pitch] >= 60;
        CGFloat staffTop = treble ? trebleY : bassY;
        CGFloat x = [self xForTick:[note startTick] start:systemStart end:systemEnd left:left right:right];
        CGFloat y = [self yForNote:note treble:treble staffTop:staffTop];
        NSValue *noteKey = [NSValue valueWithPointer:note];
        NSNumber *beamEnd = [beamEnds objectForKey:noteKey];
        BOOL stemsUp = beamEnd ? [[stemDirections objectForKey:noteKey] boolValue] : (y >= staffTop + 2.0 * LineSpacing);
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
    while ((group = [groupEnumerator nextObject]) != nil) {
        [self drawBeamsForNotes:group
                          left:left
                         right:right
                   systemStart:systemStart
                     systemEnd:systemEnd
                      beamEnds:beamEnds
                stemDirections:stemDirections];
    }
}

- (void)drawSelectionAtX:(CGFloat)x y:(CGFloat)y
{
    NSRect rect = NSMakeRect(x - 15.0, y - 17.0, 30.0, 34.0);
    [[NSColor selectedControlColor] setStroke];
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:4.0 yRadius:4.0];
    [path setLineWidth:2.0];
    [path stroke];
}

- (CGFloat)xForTick:(NSUInteger)tick start:(NSUInteger)start end:(NSUInteger)end left:(CGFloat)left right:(CGFloat)right
{
    if (end <= start) return left;
    if (tick <= start) return left;
    if (tick >= end) return right;
    CGFloat t = (CGFloat)(tick - start) / (CGFloat)(end - start);
    return left + t * (right - left);
}

- (CGFloat)yForNote:(ScoreNote *)note treble:(BOOL)treble staffTop:(CGFloat)staffTop
{
    NSInteger bottomLinePitch = treble ? 64 : 43;
    NSInteger steps = [self diatonicStepsFromPitch:bottomLinePitch toPitch:[note pitch] accidental:[note accidental]];
    CGFloat bottomY = staffTop + 4.0 * LineSpacing;
    return bottomY - ((CGFloat)steps * LineSpacing / 2.0);
}

- (NSInteger)diatonicStepsFromPitch:(NSInteger)fromPitch toPitch:(NSInteger)toPitch accidental:(NSInteger)accidental
{
    NSInteger fromOctave = fromPitch / 12;
    NSInteger spelledPitch = toPitch - accidental;
    NSInteger toOctave = spelledPitch / 12;
    NSInteger fromPc = fromPitch % 12;
    NSInteger toPc = spelledPitch % 12;
    if (toPc < 0) toPc += 12;
    return (toOctave - fromOctave) * 7 + [self scaleDegreeForPitchClass:toPc] - [self scaleDegreeForPitchClass:fromPc];
}

- (NSInteger)scaleDegreeForPitchClass:(NSInteger)pitchClass
{
    switch (pitchClass) {
        case 0: case 1: return 0;
        case 2: case 3: return 1;
        case 4: return 2;
        case 5: case 6: return 3;
        case 7: case 8: return 4;
        case 9: case 10: return 5;
        default: return 6;
    }
}

- (NSInteger)pitchClassForScaleDegree:(NSInteger)degree
{
    NSInteger normalized = degree % 7;
    if (normalized < 0) normalized += 7;
    switch (normalized) {
        case 0: return 0;
        case 1: return 2;
        case 2: return 4;
        case 3: return 5;
        case 4: return 7;
        case 5: return 9;
        default: return 11;
    }
}

- (NSInteger)pitchForY:(CGFloat)y treble:(BOOL)treble staffTop:(CGFloat)staffTop
{
    NSInteger bottomLinePitch = treble ? 64 : 43;
    CGFloat bottomY = staffTop + 4.0 * LineSpacing;
    NSInteger steps = (NSInteger)llround((bottomY - y) / (LineSpacing / 2.0));
    NSInteger bottomOctave = bottomLinePitch / 12;
    NSInteger bottomDegree = [self scaleDegreeForPitchClass:(bottomLinePitch % 12)];
    NSInteger absoluteDegree = bottomOctave * 7 + bottomDegree + steps;
    NSInteger octave = absoluteDegree / 7;
    NSInteger degree = absoluteDegree % 7;
    if (degree < 0) {
        degree += 7;
        octave--;
    }
    NSInteger pitch = octave * 12 + [self pitchClassForScaleDegree:degree];
    if (pitch < 0) pitch = 0;
    if (pitch > 127) pitch = 127;
    return pitch;
}

- (void)drawRestAtX:(CGFloat)x y:(CGFloat)y duration:(NSUInteger)duration
{
    [[NSColor blackColor] setStroke];
    [[NSColor blackColor] setFill];
    CGFloat quarter = [_document ticksPerQuarter];
    if (duration >= quarter * 2) {
        NSRect rect = NSMakeRect(x - 8.0, y - 1.0, 16.0, 5.0);
        NSRectFill(rect);
        return;
    }
    if (duration >= quarter) {
        NSRect rect = NSMakeRect(x - 8.0, y - 6.0, 16.0, 5.0);
        NSRectFill(rect);
        return;
    }
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(x - 5.0, y - 14.0)];
    [path curveToPoint:NSMakePoint(x + 4.0, y + 2.0)
         controlPoint1:NSMakePoint(x + 8.0, y - 9.0)
         controlPoint2:NSMakePoint(x - 8.0, y - 2.0)];
    [path curveToPoint:NSMakePoint(x - 3.0, y + 15.0)
         controlPoint1:NSMakePoint(x + 12.0, y + 7.0)
         controlPoint2:NSMakePoint(x - 7.0, y + 8.0)];
    [path setLineWidth:2.0];
    [path stroke];
}

- (BOOL)scoreLayoutForPoint:(NSPoint)point
                systemStart:(NSUInteger *)systemStart
                  systemEnd:(NSUInteger *)systemEnd
                       left:(CGFloat *)left
                      right:(CGFloat *)right
                    staffTop:(CGFloat *)staffTop
                      treble:(BOOL *)treble
{
    if (!_document) {
        return NO;
    }
    NSUInteger ticksPerSystem = [self ticksPerSystem];
    NSUInteger systemCount = MAX((NSUInteger)1, ([_document totalTicks] / ticksPerSystem) + 1);
    CGFloat staffLeft = Margin + PartLabelWidth + 100.0;
    CGFloat staffRight = PageWidth - Margin - 18.0;
    for (NSUInteger system = 0; system < systemCount; system++) {
        CGFloat y = Margin + FirstSystemOffset + (CGFloat)system * SystemHeight;
        CGFloat trebleTop = y;
        CGFloat bassTop = y + StaffGap;
        BOOL isTreble = NO;
        CGFloat top = 0.0;
        if (point.y >= trebleTop - 30.0 && point.y <= trebleTop + 4.0 * LineSpacing + 30.0) {
            isTreble = YES;
            top = trebleTop;
        } else if (point.y >= bassTop - 30.0 && point.y <= bassTop + 4.0 * LineSpacing + 30.0) {
            isTreble = NO;
            top = bassTop;
        } else {
            continue;
        }
        if (point.x < staffLeft - 20.0 || point.x > staffRight + 20.0) {
            continue;
        }
        if (systemStart) *systemStart = system * ticksPerSystem;
        if (systemEnd) *systemEnd = (system + 1) * ticksPerSystem;
        if (left) *left = staffLeft;
        if (right) *right = staffRight;
        if (staffTop) *staffTop = top;
        if (treble) *treble = isTreble;
        return YES;
    }
    return NO;
}

- (NSUInteger)tickForPoint:(NSPoint)point systemStart:(NSUInteger)systemStart systemEnd:(NSUInteger)systemEnd left:(CGFloat)left right:(CGFloat)right
{
    CGFloat clampedX = MIN(MAX(point.x, left), right);
    CGFloat fraction = right > left ? (clampedX - left) / (right - left) : 0.0;
    NSUInteger tick = systemStart + (NSUInteger)llround(fraction * (CGFloat)(systemEnd - systemStart));
    NSUInteger quantum = MAX((NSUInteger)1, [_document ticksPerQuarter]);
    return ((tick + quantum / 2) / quantum) * quantum;
}

- (void)updateTotalTicksFromNotes
{
    NSUInteger totalTicks = 0;
    NSEnumerator *noteEnumerator = [[_document notes] objectEnumerator];
    ScoreNote *note = nil;
    while ((note = [noteEnumerator nextObject]) != nil) {
        NSUInteger endTick = [note startTick] + [note durationTicks];
        if (endTick > totalTicks) {
            totalTicks = endTick;
        }
    }
    [_document setTotalTicks:totalTicks];
}

- (BOOL)insertPaletteItem:(NSString *)item atPoint:(NSPoint)point pitch:(NSInteger)pitch durationTicks:(NSUInteger)durationTicks track:(NSInteger)track
{
    if (!_document) {
        return NO;
    }
    NSUInteger systemStart = 0;
    NSUInteger systemEnd = 0;
    CGFloat left = 0.0;
    CGFloat right = 0.0;
    CGFloat staffTop = 0.0;
    BOOL treble = YES;
    if (![self scoreLayoutForPoint:point systemStart:&systemStart systemEnd:&systemEnd left:&left right:&right staffTop:&staffTop treble:&treble]) {
        return NO;
    }

    BOOL rest = [item isEqualToString:@"rest"];
    ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
    [note setRest:rest];
    [note setPitch:rest ? (treble ? 72 : 48) : [self pitchForY:point.y treble:treble staffTop:staffTop]];
    if (!rest && pitch >= 0) {
        [note setPitch:pitch];
    }
    [note setChannel:0];
    [note setTrack:MAX((NSInteger)0, track)];
    [note setStartTick:[self tickForPoint:point systemStart:systemStart systemEnd:systemEnd left:left right:right]];
    [note setDurationTicks:MAX((NSUInteger)1, durationTicks)];
    [[_document notes] addObject:note];
    [[_document notes] sortUsingSelector:@selector(compareScoreNote:)];
    NSUInteger endTick = [note startTick] + [note durationTicks];
    if (endTick > [_document totalTicks]) {
        [_document setTotalTicks:endTick];
        [self updateFrameForDocument];
    }
    if (![_document nameForTrack:[note track]]) {
        [_document setName:[NSString stringWithFormat:@"Part %ld", (long)([note track] + 1)] forTrack:[note track]];
    }
    _selectedNote = note;
    [[NSNotificationCenter defaultCenter] postNotificationName:ScoreViewDidEditScoreNotification object:self];
    [self setNeedsDisplay:YES];
    return YES;
}

- (ScoreNote *)noteAtPoint:(NSPoint)point
{
    if (!_document) {
        return nil;
    }
    NSUInteger ticksPerSystem = [self ticksPerSystem];
    NSUInteger systemCount = MAX((NSUInteger)1, ([_document totalTicks] / ticksPerSystem) + 1);
    CGFloat left = Margin + PartLabelWidth + 100.0;
    CGFloat right = PageWidth - Margin - 18.0;
    ScoreNote *found = nil;
    NSEnumerator *noteEnumerator = [[_document notes] reverseObjectEnumerator];
    ScoreNote *note = nil;
    while ((note = [noteEnumerator nextObject]) != nil) {
        NSUInteger system = MIN(systemCount - 1, [note startTick] / ticksPerSystem);
        NSUInteger systemStart = system * ticksPerSystem;
        NSUInteger systemEnd = systemStart + ticksPerSystem;
        CGFloat y = Margin + FirstSystemOffset + (CGFloat)system * SystemHeight;
        BOOL treble = [note pitch] >= 60;
        CGFloat staffTop = treble ? y : y + StaffGap;
        CGFloat x = [self xForTick:[note startTick] start:systemStart end:systemEnd left:left right:right];
        CGFloat noteY = [note isRest] ? staffTop + 2.0 * LineSpacing : [self yForNote:note treble:treble staffTop:staffTop];
        NSRect hitRect = NSMakeRect(x - 14.0, noteY - 16.0, 28.0, 32.0);
        if (NSPointInRect(point, hitRect)) {
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
}

- (void)keyDown:(NSEvent *)event
{
    NSString *characters = [event charactersIgnoringModifiers];
    if ([characters length] > 0 &&
        ([characters characterAtIndex:0] == NSDeleteCharacter ||
         [characters characterAtIndex:0] == NSBackspaceCharacter)) {
        if (_selectedNote && [[_document notes] containsObject:_selectedNote]) {
            [[_document notes] removeObject:_selectedNote];
            _selectedNote = nil;
            [self updateTotalTicksFromNotes];
            [[NSNotificationCenter defaultCenter] postNotificationName:ScoreViewDidEditScoreNotification object:self];
            [self reloadDocument];
        }
        return;
    }
    [super keyDown:event];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    NSString *item = [[sender draggingPasteboard] stringForType:ScorePalettePasteboardType];
    if ([item length] == 0) {
        return NSDragOperationNone;
    }
    NSPoint point = [self convertPoint:[sender draggingLocation] fromView:nil];
    return [self scoreLayoutForPoint:point systemStart:NULL systemEnd:NULL left:NULL right:NULL staffTop:NULL treble:NULL] ? NSDragOperationCopy : NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
    return [self draggingEntered:sender];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSPasteboard *pasteboard = [sender draggingPasteboard];
    NSString *payload = [pasteboard stringForType:ScorePalettePasteboardType];
    if ([payload length] == 0) {
        return NO;
    }
    NSArray *parts = [payload componentsSeparatedByString:@":"];
    NSString *item = [parts count] > 0 ? [parts objectAtIndex:0] : @"note";
    NSInteger pitch = [parts count] > 1 ? [[parts objectAtIndex:1] integerValue] : -1;
    NSUInteger durationTicks = [parts count] > 2 ? (NSUInteger)[[parts objectAtIndex:2] integerValue] : [_document ticksPerQuarter];
    NSInteger track = [parts count] > 3 ? [[parts objectAtIndex:3] integerValue] : 0;
    NSPoint point = [self convertPoint:[sender draggingLocation] fromView:nil];
    return [self insertPaletteItem:item atPoint:point pitch:pitch durationTicks:durationTicks track:track];
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
    NSRect oval = NSMakeRect(x - 5.5, y - 4.0, 11.0, 8.0);
    NSBezierPath *head = [NSBezierPath bezierPathWithOvalInRect:oval];
    [[NSColor blackColor] setStroke];
    if (filled) {
        [[NSColor blackColor] setFill];
    } else {
        [[NSColor whiteColor] setFill];
    }
    [head fill];
    [head stroke];

    NSInteger accidental = [note accidental];
    if (accidental != 0) {
        NSString *symbol = accidental > 0 ? @"♯" : @"♭";
        NSFont *font = [NSFont fontWithName:@"Times New Roman" size:20.0];
        if (!font) font = [NSFont systemFontOfSize:17.0];
        NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                               font, NSFontAttributeName,
                               [NSColor blackColor], NSForegroundColorAttributeName,
                               nil];
        [symbol drawAtPoint:NSMakePoint(x - 20.0, y - 12.0) withAttributes:attrs];
    }

    CGFloat stemX = stemsUp ? x + 5.5 : x - 5.5;
    if (duration < [_document ticksPerQuarter] * 4) {
        [NSBezierPath strokeLineFromPoint:NSMakePoint(stemX, y) toPoint:NSMakePoint(stemX, stemEnd)];
    }

    CGFloat bottom = staffTop + 4.0 * LineSpacing;
    CGFloat top = staffTop;
    for (CGFloat ledger = bottom + LineSpacing; ledger <= y + 1.0; ledger += LineSpacing) {
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x - 10.0, ledger) toPoint:NSMakePoint(x + 10.0, ledger)];
    }
    for (CGFloat ledger = top - LineSpacing; ledger >= y - 1.0; ledger -= LineSpacing) {
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x - 10.0, ledger) toPoint:NSMakePoint(x + 10.0, ledger)];
    }

    if (drawFlag && duration <= [_document ticksPerQuarter] / 2) {
        NSBezierPath *flag = [NSBezierPath bezierPath];
        [flag moveToPoint:NSMakePoint(stemX, stemEnd)];
        CGFloat direction = stemsUp ? 1.0 : -1.0;
        [flag curveToPoint:NSMakePoint(stemX + direction * 14.0, stemEnd + (stemsUp ? 10.0 : -10.0))
             controlPoint1:NSMakePoint(stemX + direction * 12.0, stemEnd + (stemsUp ? 2.0 : -2.0))
             controlPoint2:NSMakePoint(stemX + direction * 14.0, stemEnd + (stemsUp ? 8.0 : -8.0))];
        [flag stroke];
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
    if ([notes count] < 2) return;
    ScoreNote *first = [notes objectAtIndex:0];
    ScoreNote *last = [notes lastObject];
    BOOL stemsUp = [[stemDirections objectForKey:[NSValue valueWithPointer:first]] boolValue];
    CGFloat firstX = [self xForTick:[first startTick] start:systemStart end:systemEnd left:left right:right] + (stemsUp ? 5.5 : -5.5);
    CGFloat lastX = [self xForTick:[last startTick] start:systemStart end:systemEnd left:left right:right] + (stemsUp ? 5.5 : -5.5);
    CGFloat firstY = [[beamEnds objectForKey:[NSValue valueWithPointer:first]] doubleValue];
    CGFloat lastY = [[beamEnds objectForKey:[NSValue valueWithPointer:last]] doubleValue];
    CGFloat thickness = stemsUp ? 4.0 : -4.0;

    [[NSColor blackColor] setFill];
    NSBezierPath *beam = [NSBezierPath bezierPath];
    [beam moveToPoint:NSMakePoint(firstX, firstY)];
    [beam lineToPoint:NSMakePoint(lastX, lastY)];
    [beam lineToPoint:NSMakePoint(lastX, lastY + thickness)];
    [beam lineToPoint:NSMakePoint(firstX, firstY + thickness)];
    [beam closePath];
    [beam fill];

    NSUInteger sixteenth = MAX((NSUInteger)1, [_document ticksPerQuarter] / 4);
    for (NSUInteger i = 0; i + 1 < [notes count]; i++) {
        ScoreNote *a = [notes objectAtIndex:i];
        ScoreNote *b = [notes objectAtIndex:i + 1];
        if ([a durationTicks] > sixteenth || [b durationTicks] > sixteenth) continue;
        CGFloat ax = [self xForTick:[a startTick] start:systemStart end:systemEnd left:left right:right] + (stemsUp ? 5.5 : -5.5);
        CGFloat bx = [self xForTick:[b startTick] start:systemStart end:systemEnd left:left right:right] + (stemsUp ? 5.5 : -5.5);
        CGFloat ay = [[beamEnds objectForKey:[NSValue valueWithPointer:a]] doubleValue] + thickness * 1.8;
        CGFloat by = [[beamEnds objectForKey:[NSValue valueWithPointer:b]] doubleValue] + thickness * 1.8;
        NSBezierPath *secondary = [NSBezierPath bezierPath];
        [secondary moveToPoint:NSMakePoint(ax, ay)];
        [secondary lineToPoint:NSMakePoint(bx, by)];
        [secondary lineToPoint:NSMakePoint(bx, by + thickness)];
        [secondary lineToPoint:NSMakePoint(ax, ay + thickness)];
        [secondary closePath];
        [secondary fill];
    }
}

@end
