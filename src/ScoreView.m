#import "ScoreView.h"

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

@implementation ScoreView

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
        [self reloadDocument];
    }
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
    [[NSColor colorWithCalibratedWhite:0.96 alpha:1.0] setFill];
    NSRectFill([self bounds]);

    NSRect page = NSMakeRect(18.0, 18.0, PageWidth - 36.0, [self bounds].size.height - 36.0);
    [[NSColor whiteColor] setFill];
    NSRectFill(page);
    [[NSColor colorWithCalibratedWhite:0.82 alpha:1.0] setStroke];
    NSFrameRect(page);

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
    NSEnumerator *noteEnumerator = [[_document notes] objectEnumerator];
    ScoreNote *note = nil;
    while ((note = [noteEnumerator nextObject]) != nil) {
        if ([note startTick] >= systemEnd || [note startTick] + [note durationTicks] <= systemStart) {
            continue;
        }

        BOOL treble = [note pitch] >= 60;
        CGFloat staffTop = treble ? trebleY : bassY;
        CGFloat x = [self xForTick:[note startTick] start:systemStart end:systemEnd left:left right:right];
        CGFloat y = [self yForPitch:[note pitch] treble:treble staffTop:staffTop];
        [self drawNoteAtX:x y:y pitch:[note pitch] treble:treble staffTop:staffTop duration:[note durationTicks]];
    }
}

- (CGFloat)xForTick:(NSUInteger)tick start:(NSUInteger)start end:(NSUInteger)end left:(CGFloat)left right:(CGFloat)right
{
    if (end <= start) return left;
    if (tick <= start) return left;
    if (tick >= end) return right;
    CGFloat t = (CGFloat)(tick - start) / (CGFloat)(end - start);
    return left + t * (right - left);
}

- (CGFloat)yForPitch:(NSInteger)pitch treble:(BOOL)treble staffTop:(CGFloat)staffTop
{
    NSInteger bottomLinePitch = treble ? 64 : 43;
    NSInteger steps = [self diatonicStepsFromPitch:bottomLinePitch toPitch:pitch];
    CGFloat bottomY = staffTop + 4.0 * LineSpacing;
    return bottomY - ((CGFloat)steps * LineSpacing / 2.0);
}

- (NSInteger)diatonicStepsFromPitch:(NSInteger)fromPitch toPitch:(NSInteger)toPitch
{
    NSInteger fromOctave = fromPitch / 12;
    NSInteger toOctave = toPitch / 12;
    NSInteger fromPc = fromPitch % 12;
    NSInteger toPc = toPitch % 12;
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

- (void)drawNoteAtX:(CGFloat)x
                  y:(CGFloat)y
              pitch:(NSInteger)pitch
             treble:(BOOL)treble
           staffTop:(CGFloat)staffTop
           duration:(NSUInteger)duration
{
    (void)pitch;
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

    CGFloat stemX = x + 5.5;
    CGFloat stemEnd = y - 34.0;
    if (y < staffTop + 2.0 * LineSpacing) {
        stemX = x - 5.5;
        stemEnd = y + 34.0;
    }
    [NSBezierPath strokeLineFromPoint:NSMakePoint(stemX, y) toPoint:NSMakePoint(stemX, stemEnd)];

    CGFloat bottom = staffTop + 4.0 * LineSpacing;
    CGFloat top = staffTop;
    for (CGFloat ledger = bottom + LineSpacing; ledger <= y + 1.0; ledger += LineSpacing) {
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x - 10.0, ledger) toPoint:NSMakePoint(x + 10.0, ledger)];
    }
    for (CGFloat ledger = top - LineSpacing; ledger >= y - 1.0; ledger -= LineSpacing) {
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x - 10.0, ledger) toPoint:NSMakePoint(x + 10.0, ledger)];
    }

    if (duration <= [_document ticksPerQuarter] / 2) {
        NSBezierPath *flag = [NSBezierPath bezierPath];
        [flag moveToPoint:NSMakePoint(stemX, stemEnd)];
        [flag curveToPoint:NSMakePoint(stemX + (stemEnd < y ? 14.0 : -14.0), stemEnd + (stemEnd < y ? 10.0 : -10.0))
             controlPoint1:NSMakePoint(stemX + 12.0, stemEnd + 2.0)
             controlPoint2:NSMakePoint(stemX + 14.0, stemEnd + 8.0)];
        [flag stroke];
    }
}

@end
