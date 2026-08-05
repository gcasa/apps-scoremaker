#import "PlaybackMonitorView.h"
#import <math.h>

static BOOL IsBlackKey(NSInteger pitch)
{
    NSInteger pitchClass = pitch % 12;
    return pitchClass == 1 || pitchClass == 3 || pitchClass == 6 ||
           pitchClass == 8 || pitchClass == 10;
}

@implementation PlaybackMonitorView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        _inputPitch = -1;
        _liveNotes = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)setDocument:(ScoreDocument *)document
{
    if (_document != document) {
        [_document release];
        _document = [document retain];
    }
    _inputPitch = -1;
    [self setNeedsDisplay:YES];
}

- (void)setTarget:(id)target { _target = target; }
- (void)setAction:(SEL)action { _action = action; }
- (NSInteger)inputPitch { return _inputPitch; }
- (void)setInputPitch:(NSInteger)pitch
{
    _inputPitch = pitch;
    [self setNeedsDisplay:YES];
}
- (void)resetInputPitch
{
    if (_inputPitch != -1) {
        _inputPitch = -1;
        [self setNeedsDisplay:YES];
    }
}

- (void)liveNoteOn:(NSInteger)pitch voice:(NSInteger)voice velocity:(NSUInteger)velocity
{
    [_liveNotes setObject:[NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInteger:MAX((NSInteger)1, voice)], @"voice",
        [NSNumber numberWithUnsignedInteger:MIN((NSUInteger)127, velocity)], @"velocity", nil]
                   forKey:[NSNumber numberWithInteger:pitch]];
    [self setNeedsDisplay:YES];
}

- (void)liveNoteOff:(NSInteger)pitch
{
    [_liveNotes removeObjectForKey:[NSNumber numberWithInteger:pitch]];
    [self setNeedsDisplay:YES];
}

- (void)clearLiveNotes
{
    [_liveNotes removeAllObjects];
    [self setNeedsDisplay:YES];
}

- (void)setPlaybackTick:(NSUInteger)tick
{
    _playbackTick = tick;
    _showPlayback = YES;
    [self setNeedsDisplay:YES];
}

- (void)clearPlayback
{
    _showPlayback = NO;
    _inputPitch = -1;
    [self setNeedsDisplay:YES];
}

- (NSArray *)activeNotes
{
    if (!_document || !_showPlayback) return [NSArray array];
    NSMutableArray *notes = [NSMutableArray array];
    for (ScoreNote *note in [_document notes]) {
        if (![note isRest] && [note startTick] <= _playbackTick &&
            _playbackTick < [note startTick] + [note durationTicks]) {
            [notes addObject:note];
        }
    }
    return notes;
}

- (void)drawKeyboardInRect:(NSRect)rect activeNotes:(NSArray *)activeNotes
{
    NSMutableSet *activePitches = [NSMutableSet set];
    for (ScoreNote *note in activeNotes)
        [activePitches addObject:[NSNumber numberWithInteger:[note pitch]]];
    if (_inputPitch >= 21 && _inputPitch <= 108)
        [activePitches addObject:[NSNumber numberWithInteger:_inputPitch]];
    [activePitches addObjectsFromArray:[_liveNotes allKeys]];

    NSInteger firstPitch = 21; // A0
    NSInteger lastPitch = 108; // C8
    NSInteger whiteCount = 52;
    CGFloat whiteWidth = NSWidth(rect) / (CGFloat)whiteCount;
    CGFloat blackWidth = MAX((CGFloat)3.0, whiteWidth * 0.62);
    CGFloat blackHeight = NSHeight(rect) * 0.62;
    NSMutableDictionary *whitePositions = [NSMutableDictionary dictionary];
    NSInteger whiteIndex = 0;

    for (NSInteger pitch = firstPitch; pitch <= lastPitch; pitch++) {
        if (IsBlackKey(pitch)) continue;
        CGFloat x = NSMinX(rect) + (CGFloat)whiteIndex * whiteWidth;
        [whitePositions setObject:[NSNumber numberWithDouble:x]
                          forKey:[NSNumber numberWithInteger:pitch]];
        NSRect key = NSMakeRect(x, NSMinY(rect), whiteWidth, NSHeight(rect));
        BOOL active = [activePitches containsObject:[NSNumber numberWithInteger:pitch]];
        [(active ? [NSColor colorWithCalibratedRed:0.25 green:0.65 blue:1.0 alpha:1.0] : [NSColor whiteColor]) setFill];
        NSRectFill(key);
        if (pitch == 60) {
            NSMutableParagraphStyle *centered = [[[NSMutableParagraphStyle alloc] init] autorelease];
            [centered setAlignment:NSTextAlignmentCenter];
            NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSFont boldSystemFontOfSize:9.0], NSFontAttributeName,
                [NSColor blackColor], NSForegroundColorAttributeName,
                centered, NSParagraphStyleAttributeName, nil];
            [@"C" drawInRect:NSMakeRect(x, NSMaxY(key) - 15.0, whiteWidth, 12.0)
              withAttributes:attributes];
        }
        whiteIndex++;
    }

    [[NSColor colorWithCalibratedWhite:0.12 alpha:1.0] setFill];
    for (NSInteger boundary = 0; boundary <= whiteCount; boundary++) {
        CGFloat x = NSMinX(rect) + (CGFloat)boundary * whiteWidth;
        NSRectFill(NSMakeRect(floor(x), NSMinY(rect), 1.0, NSHeight(rect)));
    }
    NSFrameRect(rect);

    for (NSInteger pitch = firstPitch; pitch <= lastPitch; pitch++) {
        if (!IsBlackKey(pitch)) continue;
        NSInteger previous = pitch - 1;
        while (previous >= firstPitch && IsBlackKey(previous)) previous--;
        NSNumber *previousX = [whitePositions objectForKey:[NSNumber numberWithInteger:previous]];
        if (!previousX) continue;
        CGFloat x = [previousX doubleValue] + whiteWidth - blackWidth / 2.0;
        NSRect key = NSMakeRect(x, NSMinY(rect), blackWidth, blackHeight);
        BOOL active = [activePitches containsObject:[NSNumber numberWithInteger:pitch]];
        [(active ? [NSColor colorWithCalibratedRed:0.15 green:0.55 blue:1.0 alpha:1.0] : [NSColor colorWithCalibratedWhite:0.08 alpha:1.0]) setFill];
        NSRectFill(key);
        [[NSColor blackColor] setStroke];
        NSFrameRect(key);
    }
}

- (NSInteger)pitchAtPoint:(NSPoint)point inKeyboardRect:(NSRect)rect
{
    if (!NSPointInRect(point, rect)) return -1;
    NSInteger firstPitch = 21;
    NSInteger lastPitch = 108;
    CGFloat whiteWidth = NSWidth(rect) / 52.0;
    CGFloat blackWidth = MAX((CGFloat)3.0, whiteWidth * 0.62);
    CGFloat blackHeight = NSHeight(rect) * 0.62;
    NSInteger whiteIndex = 0;
    for (NSInteger pitch = firstPitch; pitch <= lastPitch; pitch++) {
        if (IsBlackKey(pitch)) continue;
        CGFloat whiteX = NSMinX(rect) + (CGFloat)whiteIndex * whiteWidth;
        NSInteger blackPitch = pitch + 1;
        if (blackPitch <= lastPitch && IsBlackKey(blackPitch)) {
            NSRect blackKey = NSMakeRect(whiteX + whiteWidth - blackWidth / 2.0,
                                         NSMinY(rect), blackWidth, blackHeight);
            if (NSPointInRect(point, blackKey)) return blackPitch;
        }
        whiteIndex++;
    }
    NSInteger requestedWhite = MIN((NSInteger)51, MAX((NSInteger)0,
        (NSInteger)floor((point.x - NSMinX(rect)) / whiteWidth)));
    whiteIndex = 0;
    for (NSInteger pitch = firstPitch; pitch <= lastPitch; pitch++) {
        if (IsBlackKey(pitch)) continue;
        if (whiteIndex++ == requestedWhite) return pitch;
    }
    return -1;
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    CGFloat split = floor(NSWidth([self bounds]) * 0.7);
    NSRect keyboard = NSMakeRect(12.0, 28.0, split - 24.0, NSHeight([self bounds]) - 38.0);
    NSInteger pitch = [self pitchAtPoint:point inKeyboardRect:keyboard];
    if (pitch < 0) {
        [super mouseDown:event];
        return;
    }
    [self setInputPitch:pitch];
    if (_action) [NSApp sendAction:_action to:_target from:self];
}

- (void)drawVoiceMetersInRect:(NSRect)rect activeNotes:(NSArray *)activeNotes
{
    NSMutableSet *voiceSet = [NSMutableSet set];
    for (ScoreNote *note in [_document notes])
        [voiceSet addObject:[NSNumber numberWithInteger:[note voice]]];
    for (NSDictionary *live in [_liveNotes allValues])
        [voiceSet addObject:[live objectForKey:@"voice"]];
    if ([voiceSet count] == 0) [voiceSet addObject:[NSNumber numberWithInteger:1]];
    NSArray *voices = [[voiceSet allObjects] sortedArrayUsingSelector:@selector(compare:)];
    CGFloat rowHeight = MIN((CGFloat)24.0, NSHeight(rect) / MAX((CGFloat)1.0, (CGFloat)[voices count]));
    NSDictionary *labelAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSFont systemFontOfSize:11.0], NSFontAttributeName,
        [NSColor controlTextColor], NSForegroundColorAttributeName, nil];
    for (NSUInteger index = 0; index < [voices count]; index++) {
        NSNumber *voice = [voices objectAtIndex:index];
        NSUInteger velocity = 0;
        for (ScoreNote *note in activeNotes)
            if ([note voice] == [voice integerValue]) velocity = MAX(velocity, [note velocity]);
        for (NSDictionary *live in [_liveNotes allValues])
            if ([[live objectForKey:@"voice"] integerValue] == [voice integerValue])
                velocity = MAX(velocity, [[live objectForKey:@"velocity"] unsignedIntegerValue]);
        CGFloat y = NSMinY(rect) + (CGFloat)index * rowHeight;
        NSString *label = [NSString stringWithFormat:@"Voice %@", voice];
        [label drawInRect:NSMakeRect(NSMinX(rect), y + 3.0, 58.0, rowHeight) withAttributes:labelAttributes];
        NSRect meter = NSMakeRect(NSMinX(rect) + 62.0, y + 4.0, MAX((CGFloat)1.0, NSWidth(rect) - 98.0), rowHeight - 8.0);
        [[NSColor colorWithCalibratedWhite:0.18 alpha:1.0] setFill];
        NSRectFill(meter);
        NSRect level = meter;
        level.size.width *= (CGFloat)velocity / 127.0;
        [[NSColor colorWithCalibratedRed:0.2 green:0.78 blue:0.35 alpha:1.0] setFill];
        NSRectFill(level);
        NSString *value = [NSString stringWithFormat:@"%lu", (unsigned long)velocity];
        [value drawInRect:NSMakeRect(NSMaxX(meter) + 5.0, y + 3.0, 30.0, rowHeight) withAttributes:labelAttributes];
    }
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill([self bounds]);
    [[NSColor grayColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, NSWidth([self bounds]), 1.0));

    NSDictionary *headingAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSFont boldSystemFontOfSize:11.0], NSFontAttributeName,
        [NSColor controlTextColor], NSForegroundColorAttributeName, nil];
    [@"Piano" drawAtPoint:NSMakePoint(12.0, 8.0) withAttributes:headingAttributes];
    CGFloat split = floor(NSWidth([self bounds]) * 0.7);
    [@"Voices / MIDI velocity" drawAtPoint:NSMakePoint(split + 14.0, 8.0) withAttributes:headingAttributes];
    NSArray *activeNotes = [self activeNotes];
    [self drawKeyboardInRect:NSMakeRect(12.0, 28.0, split - 24.0, NSHeight([self bounds]) - 38.0)
                 activeNotes:activeNotes];
    [self drawVoiceMetersInRect:NSMakeRect(split + 14.0, 28.0, NSWidth([self bounds]) - split - 26.0,
                                           NSHeight([self bounds]) - 38.0)
                    activeNotes:activeNotes];
}

- (void)dealloc
{
    [_document release];
    [_liveNotes release];
    [super dealloc];
}

@end
