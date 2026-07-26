#import "ScoreMakerDocument.h"
#import "MidiParser.h"
#import "ScorefileParser.h"
#import <float.h>
#import <math.h>
#import <AVFoundation/AVFoundation.h>

@interface AVMIDIPlayer (ScoreMakerPlaybackStatus)
- (BOOL)isPlaying;
- (NSError *)error;
@end

static CGFloat const InspectorWidth = 280.0;
static CGFloat const InspectorPadding = 18.0;

@class ScoreMakerDocument;

@interface ScorePaletteItemView : NSView
{
    ScoreMakerDocument *_document;
    NSString *_item;
    NSString *_label;
    NSUInteger _denominator;
}
- (id)initWithFrame:(NSRect)frame document:(ScoreMakerDocument *)document item:(NSString *)item label:(NSString *)label denominator:(NSUInteger)denominator;
@end

@interface ScoreMakerDocument (Palette)
- (NSString *)palettePayloadForItem:(NSString *)item denominator:(NSUInteger)denominator;
@end

@implementation ScorePaletteItemView

- (id)initWithFrame:(NSRect)frame document:(ScoreMakerDocument *)document item:(NSString *)item label:(NSString *)label denominator:(NSUInteger)denominator
{
    self = [super initWithFrame:frame];
    if (self) {
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
    NSRectFill(bounds);
    [[NSColor colorWithCalibratedWhite:0.7 alpha:1.0] setStroke];
    NSFrameRect(bounds);

    [[NSColor blackColor] setStroke];
    [[NSColor blackColor] setFill];
    CGFloat x = 22.0;
    CGFloat y = 20.0;
    if ([_item isEqualToString:@"rest"]) {
        if (_denominator == 1) {
            NSRectFill(NSMakeRect(x - 8.0, y - 1.0, 16.0, 5.0));
        } else if (_denominator == 2) {
            NSRectFill(NSMakeRect(x - 8.0, y - 6.0, 16.0, 5.0));
        } else {
            [self drawRestGlyphAtX:x y:y denominator:_denominator];
        }
    } else {
        BOOL filled = (_denominator >= 4);
        NSBezierPath *head = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(x - 6.0, y - 4.0, 12.0, 8.0)];
        filled ? [head fill] : [head stroke];
        if (_denominator > 1) {
            [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 6.0, y)
                                      toPoint:NSMakePoint(x + 6.0, y - 18.0)];
            [self drawFlagsFromX:x + 6.0 stemEnd:y - 18.0 denominator:_denominator];
        }
    }

    NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSFont systemFontOfSize:12.0], NSFontAttributeName,
                           [NSColor blackColor], NSForegroundColorAttributeName,
                           nil];
    [_label drawAtPoint:NSMakePoint(44.0, 12.0) withAttributes:attrs];
}

- (NSImage *)dragImage
{
    NSImage *image = [[[NSImage alloc] initWithSize:NSMakeSize(54.0, 42.0)] autorelease];
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                     pixelsWide:54
                                                                     pixelsHigh:42
                                                                  bitsPerSample:8
                                                                samplesPerPixel:4
                                                                       hasAlpha:YES
                                                                       isPlanar:NO
                                                                 colorSpaceName:NSCalibratedRGBColorSpace
                                                                    bytesPerRow:0
                                                                   bitsPerPixel:0] autorelease];
    if (!rep) {
        return image;
    }

    memset([rep bitmapData], 0, (size_t)[rep bytesPerRow] * (size_t)[rep pixelsHigh]);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
    [[NSColor blackColor] setStroke];
    [[NSColor blackColor] setFill];
    if ([_item isEqualToString:@"rest"]) {
        if (_denominator == 2) {
            NSRectFill(NSMakeRect(18.0, 14.0, 18.0, 6.0));
        } else {
            NSRectFill(NSMakeRect(18.0, 20.0, 18.0, 6.0));
        }
    } else {
        NSBezierPath *head = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(20.0, 20.0, 12.0, 8.0)];
        if (_denominator >= 4) {
            [head fill];
        } else {
            [head stroke];
        }
        if (_denominator > 1) {
            [NSBezierPath strokeLineFromPoint:NSMakePoint(32.0, 24.0)
                                      toPoint:NSMakePoint(32.0, 5.0)];
        }
    }
    [NSGraphicsContext restoreGraphicsState];
    [image addRepresentation:rep];
    return image;
}

- (void)drawFlagsFromX:(CGFloat)x stemEnd:(CGFloat)stemEnd denominator:(NSUInteger)denominator
{
    NSUInteger flags = 0;
    for (NSUInteger value = denominator; value > 4; value /= 2) {
        flags++;
    }
    for (NSUInteger i = 0; i < flags; i++) {
        CGFloat y = stemEnd + (CGFloat)i * 6.0;
        NSBezierPath *flag = [NSBezierPath bezierPath];
        [flag moveToPoint:NSMakePoint(x, y)];
        [flag curveToPoint:NSMakePoint(x + 12.0, y + 9.0)
             controlPoint1:NSMakePoint(x + 10.0, y + 1.0)
             controlPoint2:NSMakePoint(x + 12.0, y + 7.0)];
        [flag stroke];
    }
}

- (void)drawRestGlyphAtX:(CGFloat)x y:(CGFloat)y denominator:(NSUInteger)denominator
{
    NSUInteger flags = 0;
    for (NSUInteger value = denominator; value > 4; value /= 2) {
        flags++;
    }
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:NSMakePoint(x - 4.0, y - 14.0)];
    [path curveToPoint:NSMakePoint(x + 5.0, y + 4.0)
         controlPoint1:NSMakePoint(x + 8.0, y - 9.0)
         controlPoint2:NSMakePoint(x - 8.0, y - 2.0)];
    [path setLineWidth:2.0];
    [path stroke];
    for (NSUInteger i = 1; i < flags; i++) {
        CGFloat offset = (CGFloat)i * 6.0;
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x + 1.0, y - 8.0 + offset)
                                  toPoint:NSMakePoint(x + 9.0, y - 3.0 + offset)];
    }
}

- (void)mouseDragged:(NSEvent *)event
{
    NSString *payload = [_document palettePayloadForItem:_item denominator:_denominator];
    if ([payload length] == 0) {
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSDragPboard];
    [pasteboard declareTypes:[NSArray arrayWithObject:ScorePalettePasteboardType] owner:nil];
    [pasteboard setString:payload forType:ScorePalettePasteboardType];
    [self dragImage:[self dragImage]
                 at:NSMakePoint(4.0, 4.0)
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

- (id)init
{
    self = [super init];
    if (self) {
        ScoreDocument *document = [[[ScoreDocument alloc] init] autorelease];
        [document setTitle:@"Untitled"];
        [self setScoreDocument:document];
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

- (NSView *)inspectorView
{
    return _inspectorView;
}

- (void)setInspectorView:(NSView *)inspectorView
{
    if (_inspectorView != inspectorView) {
        [_inspectorView release];
        _inspectorView = [inspectorView retain];
    }
}

- (ScoreDocument *)scoreDocument
{
    return _scoreDocument;
}

- (void)setScoreDocument:(ScoreDocument *)document
{
    if (_scoreDocument != document) {
        [_scoreDocument release];
        _scoreDocument = [document retain];
    }
    [[self scoreView] setDocument:_scoreDocument];
    if ([self window]) {
        [[self window] setTitle:[self displayName]];
    }
    [self refreshInspector];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopCurrentPlayback];
    [_scoreDocument release];
    [_scrollView release];
    [_scoreView release];
    [_inspectorView release];
    [_tempoField release];
    [_timeNumeratorField release];
    [_timeDenominatorField release];
    [_notePitchField release];
    [_noteStartField release];
    [_noteDurationField release];
    [_noteTrackField release];
    [_noteTypePopUp release];
    [_noteValuePopUp release];
    [_addNoteButton release];
    [_playButton release];
    [_stopButton release];
    [_annotationTextView release];
    [_playbackTask release];
    [_playbackFilePath release];
    [super dealloc];
}

- (void)close
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopCurrentPlayback];
    [super close];
}

- (void)makeWindowControllers
{
    NSRect frame = NSMakeRect(100.0, 100.0, 1240.0, 760.0);
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
    [[self window] setReleasedWhenClosed:NO];
    [[self window] setTitle:[self displayName]];

    [self setScoreView:[[[ScoreView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 980.0, 760.0)] autorelease]];
    [[self scoreView] setDocument:[self scoreDocument]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(scoreViewDidEditScore:)
                                                 name:ScoreViewDidEditScoreNotification
                                               object:[self scoreView]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(scoreViewSelectionDidChange:)
                                                 name:ScoreViewSelectionDidChangeNotification
                                               object:[self scoreView]];
    NSRect contentBounds = [[[self window] contentView] bounds];
    NSRect scoreFrame = contentBounds;
    scoreFrame.size.width = MAX((CGFloat)300.0, scoreFrame.size.width - InspectorWidth);
    NSRect inspectorFrame = NSMakeRect(NSMaxX(scoreFrame), 0.0, InspectorWidth, contentBounds.size.height);

    [self setScrollView:[[[NSScrollView alloc] initWithFrame:scoreFrame] autorelease]];
    [[self scrollView] setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [[self scrollView] setHasVerticalScroller:YES];
    [[self scrollView] setHasHorizontalScroller:YES];
    [[self scrollView] setDocumentView:[self scoreView]];

    [[[self window] contentView] addSubview:[self scrollView]];
    [self buildInspectorWithFrame:inspectorFrame];
    [[[self window] contentView] addSubview:[self inspectorView]];
    [self refreshInspector];
    [self setWindowController:[[[NSWindowController alloc] initWithWindow:[self window]] autorelease]];
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
    [field setAction:@selector(scoreMetadataDidChange:)];
    [field setDelegate:self];
    return field;
}

- (void)buildInspectorWithFrame:(NSRect)frame
{
    [self setInspectorView:[[[NSView alloc] initWithFrame:frame] autorelease]];
    [[self inspectorView] setAutoresizingMask:NSViewMinXMargin | NSViewHeightSizable];

    NSTextField *title = [self labelWithString:@"Score" frame:NSMakeRect(InspectorPadding, frame.size.height - 36.0, 220.0, 20.0)];
    [title setFont:[NSFont boldSystemFontOfSize:15.0]];
    [title setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:title];

    _playButton = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - InspectorPadding - 176.0, frame.size.height - 42.0, 82.0, 28.0)];
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
    [_playButton setAction:@selector(playScore:)];
    [_playButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [[self inspectorView] addSubview:_playButton];

    _stopButton = [[NSButton alloc] initWithFrame:NSMakeRect(frame.size.width - InspectorPadding - 86.0, frame.size.height - 42.0, 86.0, 28.0)];
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
    [_stopButton setAction:@selector(stopPlayback:)];
    [_stopButton setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [[self inspectorView] addSubview:_stopButton];

    NSTextField *tempoLabel = [self labelWithString:@"Tempo (BPM)" frame:NSMakeRect(InspectorPadding, frame.size.height - 76.0, 120.0, 18.0)];
    [tempoLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:tempoLabel];
    _tempoField = [[self metadataFieldWithFrame:NSMakeRect(InspectorPadding, frame.size.height - 104.0, 92.0, 24.0)] retain];
    [_tempoField setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:_tempoField];

    NSTextField *timeLabel = [self labelWithString:@"Timing" frame:NSMakeRect(InspectorPadding, frame.size.height - 144.0, 120.0, 18.0)];
    [timeLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:timeLabel];
    _timeNumeratorField = [[self metadataFieldWithFrame:NSMakeRect(InspectorPadding, frame.size.height - 172.0, 48.0, 24.0)] retain];
    [_timeNumeratorField setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:_timeNumeratorField];
    NSTextField *slash = [self labelWithString:@"/" frame:NSMakeRect(InspectorPadding + 56.0, frame.size.height - 170.0, 10.0, 18.0)];
    [slash setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:slash];
    _timeDenominatorField = [[self metadataFieldWithFrame:NSMakeRect(InspectorPadding + 70.0, frame.size.height - 172.0, 48.0, 24.0)] retain];
    [_timeDenominatorField setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:_timeDenominatorField];

    NSTextField *addNoteLabel = [self labelWithString:@"Add Note" frame:NSMakeRect(InspectorPadding, frame.size.height - 214.0, 120.0, 18.0)];
    [addNoteLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:addNoteLabel];

    NSTextField *typeLabel = [self labelWithString:@"Type" frame:NSMakeRect(InspectorPadding, frame.size.height - 242.0, 48.0, 18.0)];
    [typeLabel setFont:[NSFont systemFontOfSize:11.0]];
    [typeLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:typeLabel];
    _noteTypePopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(InspectorPadding, frame.size.height - 270.0, 70.0, 26.0) pullsDown:NO];
    [_noteTypePopUp addItemWithTitle:@"Note"];
    [_noteTypePopUp addItemWithTitle:@"Rest"];
    [_noteTypePopUp setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:_noteTypePopUp];

    NSTextField *valueLabel = [self labelWithString:@"Value" frame:NSMakeRect(InspectorPadding + 82.0, frame.size.height - 242.0, 48.0, 18.0)];
    [valueLabel setFont:[NSFont systemFontOfSize:11.0]];
    [valueLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:valueLabel];
    _noteValuePopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(InspectorPadding + 82.0, frame.size.height - 270.0, 74.0, 26.0) pullsDown:NO];
    [_noteValuePopUp addItemWithTitle:@"Whole"];
    [_noteValuePopUp addItemWithTitle:@"Half"];
    [_noteValuePopUp addItemWithTitle:@"1/4"];
    [_noteValuePopUp addItemWithTitle:@"1/8"];
    [_noteValuePopUp addItemWithTitle:@"1/16"];
    [_noteValuePopUp addItemWithTitle:@"1/32"];
    [_noteValuePopUp setTarget:self];
    [_noteValuePopUp setAction:@selector(noteValueDidChange:)];
    [_noteValuePopUp setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:_noteValuePopUp];

    NSTextField *pitchLabel = [self labelWithString:@"Pitch" frame:NSMakeRect(InspectorPadding + 168.0, frame.size.height - 242.0, 48.0, 18.0)];
    [pitchLabel setFont:[NSFont systemFontOfSize:11.0]];
    [pitchLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:pitchLabel];
    _notePitchField = [[self metadataFieldWithFrame:NSMakeRect(InspectorPadding + 168.0, frame.size.height - 270.0, 66.0, 24.0)] retain];
    [_notePitchField setStringValue:@"C4"];
    [_notePitchField setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:_notePitchField];

    NSTextField *startLabel = [self labelWithString:@"Start" frame:NSMakeRect(InspectorPadding, frame.size.height - 304.0, 48.0, 18.0)];
    [startLabel setFont:[NSFont systemFontOfSize:11.0]];
    [startLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:startLabel];
    _noteStartField = [[self metadataFieldWithFrame:NSMakeRect(InspectorPadding, frame.size.height - 332.0, 58.0, 24.0)] retain];
    [_noteStartField setStringValue:@"0"];
    [_noteStartField setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:_noteStartField];

    NSTextField *durationLabel = [self labelWithString:@"Beats" frame:NSMakeRect(InspectorPadding + 70.0, frame.size.height - 304.0, 48.0, 18.0)];
    [durationLabel setFont:[NSFont systemFontOfSize:11.0]];
    [durationLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:durationLabel];
    _noteDurationField = [[self metadataFieldWithFrame:NSMakeRect(InspectorPadding + 70.0, frame.size.height - 332.0, 58.0, 24.0)] retain];
    [_noteDurationField setStringValue:@"1"];
    [_noteDurationField setEditable:NO];
    [_noteDurationField setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:_noteDurationField];

    NSTextField *trackLabel = [self labelWithString:@"Track" frame:NSMakeRect(InspectorPadding + 140.0, frame.size.height - 304.0, 48.0, 18.0)];
    [trackLabel setFont:[NSFont systemFontOfSize:11.0]];
    [trackLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:trackLabel];
    _noteTrackField = [[self metadataFieldWithFrame:NSMakeRect(InspectorPadding + 140.0, frame.size.height - 332.0, 50.0, 24.0)] retain];
    [_noteTrackField setStringValue:@"1"];
    [_noteTrackField setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:_noteTrackField];

    _addNoteButton = [[NSButton alloc] initWithFrame:NSMakeRect(InspectorPadding + 198.0, frame.size.height - 332.0, 64.0, 26.0)];
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
    [_addNoteButton setAction:@selector(addNote:)];
    [_addNoteButton setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:_addNoteButton];

    NSTextField *paletteLabel = [self labelWithString:@"Palette" frame:NSMakeRect(InspectorPadding, frame.size.height - 376.0, 120.0, 18.0)];
    [paletteLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:paletteLabel];

    NSArray *denominators = [NSArray arrayWithObjects:
                             [NSNumber numberWithUnsignedInteger:1],
                             [NSNumber numberWithUnsignedInteger:2],
                             [NSNumber numberWithUnsignedInteger:4],
                             [NSNumber numberWithUnsignedInteger:8],
                             [NSNumber numberWithUnsignedInteger:16],
                             [NSNumber numberWithUnsignedInteger:32],
                             nil];
    for (NSUInteger i = 0; i < [denominators count]; i++) {
        NSUInteger denominator = [[denominators objectAtIndex:i] unsignedIntegerValue];
        NSString *valueLabel = denominator == 1 ? @"Whole" : (denominator == 2 ? @"Half" : [NSString stringWithFormat:@"1/%lu", (unsigned long)denominator]);
        NSString *noteLabel = [NSString stringWithFormat:@"%@ Note", valueLabel];
        ScorePaletteItemView *notePalette = [[[ScorePaletteItemView alloc] initWithFrame:NSMakeRect(InspectorPadding, frame.size.height - 402.0 - (CGFloat)i * 34.0, 110.0, 30.0)
                                                                                document:self
                                                                                    item:@"note"
                                                                                   label:noteLabel
                                                                             denominator:denominator] autorelease];
        [notePalette setAutoresizingMask:NSViewMinYMargin];
        [[self inspectorView] addSubview:notePalette];

        NSString *restLabel = [NSString stringWithFormat:@"%@ Rest", valueLabel];
        ScorePaletteItemView *restPalette = [[[ScorePaletteItemView alloc] initWithFrame:NSMakeRect(InspectorPadding + 122.0, frame.size.height - 402.0 - (CGFloat)i * 34.0, 110.0, 30.0)
                                                                                document:self
                                                                                    item:@"rest"
                                                                                   label:restLabel
                                                                             denominator:denominator] autorelease];
        [restPalette setAutoresizingMask:NSViewMinYMargin];
        [[self inspectorView] addSubview:restPalette];
    }

    NSTextField *notesLabel = [self labelWithString:@"Score Notes" frame:NSMakeRect(InspectorPadding, frame.size.height - 624.0, 120.0, 18.0)];
    [notesLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:notesLabel];

    NSScrollView *notesScroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(InspectorPadding, InspectorPadding, frame.size.width - 2.0 * InspectorPadding, frame.size.height - 658.0)] autorelease];
    [notesScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [notesScroll setHasVerticalScroller:YES];
    [notesScroll setBorderType:NSBezelBorder];

    _annotationTextView = [[NSTextView alloc] initWithFrame:[[notesScroll contentView] bounds]];
    [_annotationTextView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_annotationTextView setMinSize:NSMakeSize(0.0, 0.0)];
    [_annotationTextView setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [_annotationTextView setVerticallyResizable:YES];
    [_annotationTextView setHorizontallyResizable:NO];
    [[_annotationTextView textContainer] setContainerSize:NSMakeSize([notesScroll contentSize].width, FLT_MAX)];
    [[_annotationTextView textContainer] setWidthTracksTextView:YES];
    [_annotationTextView setFont:[NSFont systemFontOfSize:12.0]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(annotationTextDidChange:)
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
    [_timeNumeratorField setEnabled:hasDocument];
    [_timeDenominatorField setEnabled:hasDocument];
    [_notePitchField setEnabled:hasDocument];
    [_noteStartField setEnabled:hasDocument];
    [_noteDurationField setEnabled:hasDocument];
    [_noteTrackField setEnabled:hasDocument];
    [_noteTypePopUp setEnabled:hasDocument];
    [_noteValuePopUp setEnabled:hasDocument];
    [_addNoteButton setEnabled:hasDocument];
    [_playButton setEnabled:hasDocument];
    [_stopButton setEnabled:hasDocument];
    [_annotationTextView setEditable:hasDocument];

    if (!hasDocument) {
        [_tempoField setStringValue:@""];
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
    [_timeNumeratorField setIntegerValue:(NSInteger)[document timeSignatureNumerator]];
    [_timeDenominatorField setIntegerValue:(NSInteger)[document timeSignatureDenominator]];
    [_noteDurationField setDoubleValue:[self beatsForNoteValueDenominator:[self denominatorForSelectedNoteValue]]];

    ScoreNote *selectedNote = [[self scoreView] selectedNote];
    if (selectedNote) {
        NSUInteger ticksPerQuarter = MAX((NSUInteger)1, [document ticksPerQuarter]);
        double durationBeats = (double)[selectedNote durationTicks] / (double)ticksPerQuarter;
        [_noteTypePopUp selectItemWithTitle:[selectedNote isRest] ? @"Rest" : @"Note"];
        if (![selectedNote isRest]) {
            static NSString *pitchNames[] = {
                @"C", @"C#", @"D", @"D#", @"E", @"F",
                @"F#", @"G", @"G#", @"A", @"A#", @"B"
            };
            NSInteger pitch = [selectedNote pitch];
            NSInteger accidental = [selectedNote accidental];
            NSInteger naturalPitch = pitch - accidental;
            NSInteger pitchClass = naturalPitch % 12;
            if (pitchClass < 0) pitchClass += 12;
            NSString *name = pitchNames[pitchClass];
            if (accidental > 0) {
                name = [name stringByAppendingString:@"#"];
            } else if (accidental < 0) {
                name = [name stringByAppendingString:@"b"];
            }
            NSInteger octave = naturalPitch / 12 - 1;
            [_notePitchField setStringValue:[NSString stringWithFormat:@"%@%ld", name, (long)octave]];
        }
        [_noteStartField setDoubleValue:(double)[selectedNote startTick] / (double)ticksPerQuarter];
        [_noteDurationField setDoubleValue:durationBeats];
        [_noteTrackField setIntegerValue:[selectedNote track] + 1];

        NSArray *valueTitles = [NSArray arrayWithObjects:@"Whole", @"Half", @"1/4", @"1/8", @"1/16", @"1/32", nil];
        double valueBeats[] = { 4.0, 2.0, 1.0, 0.5, 0.25, 0.125 };
        NSUInteger closestIndex = 0;
        double closestDifference = DBL_MAX;
        for (NSUInteger i = 0; i < [valueTitles count]; i++) {
            double difference = fabs(durationBeats - valueBeats[i]);
            if (difference < closestDifference) {
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

- (BOOL)isSupportedTimeSignatureDenominator:(NSUInteger)denominator
{
    switch (denominator) {
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
    if (!document) {
        return;
    }

    NSInteger bpm = [_tempoField integerValue];
    if (bpm < 1) bpm = 1;
    if (bpm > 400) bpm = 400;
    [document setTempoMicrosecondsPerQuarter:(NSUInteger)(60000000.0 / (double)bpm)];

    NSInteger numerator = [_timeNumeratorField integerValue];
    NSInteger denominator = [_timeDenominatorField integerValue];
    if (numerator < 1) numerator = 1;
    if (numerator > 64) numerator = 64;
    if (![self isSupportedTimeSignatureDenominator:(NSUInteger)denominator]) {
        denominator = 4;
    }
    [document setTimeSignatureNumerator:(NSUInteger)numerator];
    [document setTimeSignatureDenominator:(NSUInteger)denominator];

    if (markChange) {
        [self updateChangeCount:NSChangeDone];
    }
    [self refreshInspector];
    [[self scoreView] setNeedsDisplay:YES];
}

- (void)scoreMetadataDidChange:(id)sender
{
    (void)sender;
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
    if (_updatingInspector) {
        return;
    }
    ScoreDocument *document = [self scoreDocument];
    if (!document) {
        return;
    }

    [document setAnnotationText:[_annotationTextView string]];
    [self updateChangeCount:NSChangeDone];
}

- (void)scoreViewDidEditScore:(NSNotification *)notification
{
    (void)notification;
    [[self scoreView] reloadDocument];
    [self updateChangeCount:NSChangeDone];
    [self refreshInspector];
}

- (void)scoreViewSelectionDidChange:(NSNotification *)notification
{
    (void)notification;
    [self refreshInspector];
}

- (void)noteValueDidChange:(id)sender
{
    (void)sender;
    [_noteDurationField setDoubleValue:[self beatsForNoteValueDenominator:[self denominatorForSelectedNoteValue]]];
}

- (NSUInteger)denominatorForSelectedNoteValue
{
    NSString *title = [_noteValuePopUp titleOfSelectedItem];
    if ([title isEqualToString:@"Whole"]) {
        return 1;
    }
    if ([title isEqualToString:@"Half"]) {
        return 2;
    }
    NSRange slash = [title rangeOfString:@"/"];
    if (slash.location != NSNotFound && slash.location + 1 < [title length]) {
        NSInteger denominator = [[title substringFromIndex:slash.location + 1] integerValue];
        if (denominator > 0) {
            return (NSUInteger)denominator;
        }
    }
    return 4;
}

- (double)beatsForNoteValueDenominator:(NSUInteger)denominator
{
    if (denominator == 0) {
        denominator = 4;
    }
    return 4.0 / (double)denominator;
}

- (NSUInteger)durationTicksForNoteValueDenominator:(NSUInteger)denominator
{
    ScoreDocument *document = [self scoreDocument];
    if (!document) {
        return 1;
    }
    return MAX((NSUInteger)1, (NSUInteger)llround([self beatsForNoteValueDenominator:denominator] * (double)[document ticksPerQuarter]));
}

- (NSString *)palettePayloadForItem:(NSString *)item denominator:(NSUInteger)denominator
{
    ScoreDocument *document = [self scoreDocument];
    if (!document) {
        return nil;
    }

    NSInteger trackNumber = [_noteTrackField integerValue];
    if (trackNumber < 1) trackNumber = 1;

    NSUInteger durationTicks = [self durationTicksForNoteValueDenominator:denominator];
    NSInteger pitch = -1;
    return [NSString stringWithFormat:@"%@:%ld:%lu:%ld",
            item,
            (long)pitch,
            (unsigned long)durationTicks,
            (long)(trackNumber - 1)];
}

- (void)stopCurrentPlayback
{
    [_playbackTimer invalidate];
    [_playbackTimer release];
    _playbackTimer = nil;
    [[self scoreView] clearPlayback];
    [_playbackSound stop];
    [_playbackSound release];
    _playbackSound = nil;
    [(AVMIDIPlayer *)_midiPlayer stop];
    [_midiPlayer release];
    _midiPlayer = nil;
    if (_playbackTask) {
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:NSTaskDidTerminateNotification
                                                      object:_playbackTask];
        if ([_playbackTask isRunning]) {
            [_playbackTask terminate];
        }
        [_playbackTask release];
        _playbackTask = nil;
    }
    if (_playbackFilePath) {
        [[NSFileManager defaultManager] removeFileAtPath:_playbackFilePath handler:nil];
        [_playbackFilePath release];
        _playbackFilePath = nil;
    }
}

- (void)updatePlaybackHighlight:(NSTimer *)timer
{
    (void)timer;
    ScoreDocument *document = [self scoreDocument];
    if (!document) {
        [self stopCurrentPlayback];
        return;
    }

    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - _playbackStartTime;
    double secondsPerQuarter = (double)[document tempoMicrosecondsPerQuarter] / 1000000.0;
    if (secondsPerQuarter <= 0.0) secondsPerQuarter = 0.5;
    NSUInteger tick = (NSUInteger)floor((elapsed / secondsPerQuarter) * (double)[document ticksPerQuarter]);

    if (tick >= [document totalTicks]) {
        [_playbackTimer invalidate];
        [_playbackTimer release];
        _playbackTimer = nil;
        [[self scoreView] clearPlayback];
        return;
    }

    [[self scoreView] setPlaybackTick:tick];
    [[self scoreView] scrollPlaybackTickToVisible:tick];
}

- (void)startPlaybackHighlight
{
    _playbackStartTime = [NSDate timeIntervalSinceReferenceDate];
    [[self scoreView] setPlaybackTick:0];
    [[self scoreView] scrollPlaybackTickToVisible:0];
    _playbackTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0 / 30.0
                                                      target:self
                                                    selector:@selector(updatePlaybackHighlight:)
                                                    userInfo:nil
                                                     repeats:YES] retain];
}

- (void)stopPlayback:(id)sender
{
    (void)sender;
    [self stopCurrentPlayback];
}

#if !defined(__APPLE__)
- (NSString *)availableMIDIPlaybackTool
{
    NSArray *candidates = [NSArray arrayWithObjects:@"/usr/bin/timidity",
                           @"/usr/local/bin/timidity",
                           @"/bin/timidity",
                           nil];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSEnumerator *enumerator = [candidates objectEnumerator];
    NSString *path = nil;
    while ((path = [enumerator nextObject]) != nil) {
        if ([fileManager isExecutableFileAtPath:path]) {
            return path;
        }
    }
    return nil;
}

- (void)externalPlaybackTaskDidTerminate:(NSNotification *)notification
{
    if ([notification object] != _playbackTask) {
        return;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSTaskDidTerminateNotification
                                                  object:_playbackTask];
    [_playbackTask release];
    _playbackTask = nil;
    if (_playbackFilePath) {
        [[NSFileManager defaultManager] removeFileAtPath:_playbackFilePath handler:nil];
        [_playbackFilePath release];
        _playbackFilePath = nil;
    }
}

- (BOOL)playMIDIDataWithExternalPlayer:(NSData *)midiData error:(NSError **)error
{
    NSString *toolPath = [self availableMIDIPlaybackTool];
    if (!toolPath) {
        if (error) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"No MIDI playback tool was found. Install TiMidity++ or use the macOS build for direct system MIDI playback."
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:@"ScoreMakerPlayback"
                                         code:3
                                     userInfo:userInfo];
        }
        return NO;
    }

    NSString *fileName = [NSString stringWithFormat:@"ScoreMaker-%d-%f.mid", getpid(), [NSDate timeIntervalSinceReferenceDate]];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    if (![midiData writeToFile:path atomically:YES]) {
        if (error) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"The generated MIDI could not be written to a temporary playback file."
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:@"ScoreMakerPlayback"
                                         code:4
                                     userInfo:userInfo];
        }
        return NO;
    }

    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:toolPath];
    [task setArguments:[NSArray arrayWithObjects:@"-idq", path, nil]];

    NS_DURING
        [task launch];
    NS_HANDLER
        [[NSFileManager defaultManager] removeFileAtPath:path handler:nil];
        if (error) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"The MIDI playback tool could not be launched: %@", [localException reason]]
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:@"ScoreMakerPlayback"
                                         code:5
                                     userInfo:userInfo];
        }
        return NO;
    NS_ENDHANDLER

    _playbackTask = [task retain];
    _playbackFilePath = [path retain];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(externalPlaybackTaskDidTerminate:)
                                                 name:NSTaskDidTerminateNotification
                                               object:_playbackTask];
    return YES;
}
#endif

- (BOOL)playMIDIDataDirectly:(NSData *)midiData error:(NSError **)error
{
#if !defined(__APPLE__)
    return [self playMIDIDataWithExternalPlayer:midiData error:error];
#else
    NSError *playerError = nil;
    AVMIDIPlayer *player = [[[AVMIDIPlayer alloc] initWithData:midiData soundBankURL:nil error:&playerError] autorelease];
    if (player) {
        [player prepareToPlay];
        [player play:nil];
        if ([player respondsToSelector:@selector(isPlaying)] && ![player isPlaying]) {
            if (error) {
                NSError *playbackError = [player respondsToSelector:@selector(error)] ? [player error] : nil;
                NSString *description = playbackError ? [playbackError localizedDescription] : @"The generated MIDI was loaded, but MIDI playback could not start.";
                NSDictionary *userInfo = [NSDictionary dictionaryWithObject:description
                                                                     forKey:NSLocalizedDescriptionKey];
                *error = [NSError errorWithDomain:@"ScoreMakerPlayback"
                                             code:2
                                         userInfo:userInfo];
            }
            return NO;
        }
        _midiPlayer = [player retain];
        return YES;
    }

    NSSound *sound = [[[NSSound alloc] initWithData:midiData] autorelease];
    if (!sound) {
        if (error) {
            NSString *description = @"The generated MIDI could not be loaded by the system MIDI player.";
            if (playerError) {
                description = [description stringByAppendingFormat:@" %@", [playerError localizedDescription]];
            }
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:description
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:@"ScoreMakerPlayback"
                                         code:1
                                     userInfo:userInfo];
        }
        return NO;
    }

    if (![sound play]) {
        if (error) {
            NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"The generated MIDI was loaded, but the system MIDI player could not start playback."
                                                                 forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:@"ScoreMakerPlayback"
                                         code:2
                                     userInfo:userInfo];
        }
        return NO;
    }

    _playbackSound = [sound retain];
    return YES;
#endif
}

- (void)playScore:(id)sender
{
    (void)sender;
    ScoreDocument *document = [self scoreDocument];
    if (!document) {
        return;
    }

    [self stopCurrentPlayback];

    [self syncInspectorMetadataMarkingChange:NO];
    NSError *error = nil;
    NSData *midiData = [MidiParser dataForDocument:document error:&error];
    if (!midiData) {
        [[NSDocumentController sharedDocumentController] presentError:error];
        return;
    }

    if (![self playMIDIDataDirectly:midiData error:&error]) {
        [[NSDocumentController sharedDocumentController] presentError:error];
        return;
    }
    [self startPlaybackHighlight];
}

- (BOOL)pitchString:(NSString *)string toMidiPitch:(NSInteger *)pitch
{
    NSString *trimmed = [[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([trimmed length] == 0) {
        return NO;
    }

    NSScanner *numberScanner = [NSScanner scannerWithString:trimmed];
    NSInteger numericPitch = 0;
    if ([numberScanner scanInteger:&numericPitch] && [numberScanner isAtEnd]) {
        if (numericPitch < 0 || numericPitch > 127) {
            return NO;
        }
        if (pitch) *pitch = numericPitch;
        return YES;
    }

    unichar letter = [trimmed characterAtIndex:0];
    NSInteger semitone = 0;
    switch (letter) {
        case 'c': semitone = 0; break;
        case 'd': semitone = 2; break;
        case 'e': semitone = 4; break;
        case 'f': semitone = 5; break;
        case 'g': semitone = 7; break;
        case 'a': semitone = 9; break;
        case 'b': semitone = 11; break;
        default: return NO;
    }

    NSUInteger index = 1;
    if (index < [trimmed length]) {
        unichar accidental = [trimmed characterAtIndex:index];
        if (accidental == '#' || accidental == 's') {
            semitone++;
            index++;
        } else if (accidental == 'b' || accidental == 'f') {
            semitone--;
            index++;
        }
    }

    if (index >= [trimmed length]) {
        return NO;
    }
    NSString *octaveString = [trimmed substringFromIndex:index];
    NSScanner *octaveScanner = [NSScanner scannerWithString:octaveString];
    NSInteger octave = 0;
    if (![octaveScanner scanInteger:&octave] || ![octaveScanner isAtEnd]) {
        return NO;
    }

    NSInteger midiPitch = (octave + 1) * 12 + semitone;
    if (midiPitch < 0 || midiPitch > 127) {
        return NO;
    }
    if (pitch) *pitch = midiPitch;
    return YES;
}

- (NSInteger)accidentalForPitchString:(NSString *)string
{
    NSString *trimmed = [[string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if ([trimmed length] < 2) {
        return 0;
    }
    unichar accidental = [trimmed characterAtIndex:1];
    if (accidental == '#' || accidental == 's') return 1;
    if (accidental == 'b' || accidental == 'f') return -1;
    return 0;
}

- (void)addNote:(id)sender
{
    (void)sender;
    ScoreDocument *document = [self scoreDocument];
    if (!document) {
        return;
    }

    BOOL rest = [[_noteTypePopUp titleOfSelectedItem] isEqualToString:@"Rest"];
    NSInteger pitch = 0;
    if (!rest && ![self pitchString:[_notePitchField stringValue] toMidiPitch:&pitch]) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"The note pitch is not valid"];
        [alert setInformativeText:@"Use a MIDI pitch from 0 to 127 or a pitch name like C4, F#3, or Bb5."];
        [alert runModal];
        return;
    }

    double startBeats = [_noteStartField doubleValue];
    NSUInteger denominator = [self denominatorForSelectedNoteValue];
    double durationBeats = [self beatsForNoteValueDenominator:denominator];
    NSInteger trackNumber = [_noteTrackField integerValue];
    if (startBeats < 0.0) startBeats = 0.0;
    if (trackNumber < 1) trackNumber = 1;

    NSUInteger startTick = (NSUInteger)llround(startBeats * (double)[document ticksPerQuarter]);
    NSUInteger durationTicks = [self durationTicksForNoteValueDenominator:denominator];
    ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
    [note setRest:rest];
    [note setPitch:rest ? 60 : pitch];
    if (!rest) {
        [note setAccidental:[self accidentalForPitchString:[_notePitchField stringValue]]];
    }
    [note setChannel:0];
    [note setTrack:trackNumber - 1];
    [note setStartTick:startTick];
    [note setDurationTicks:durationTicks];
    [[document notes] addObject:note];
    [[document notes] sortUsingSelector:@selector(compareScoreNote:)];

    NSUInteger noteEnd = startTick + durationTicks;
    if (noteEnd > [document totalTicks]) {
        [document setTotalTicks:noteEnd];
    }
    if (![document nameForTrack:trackNumber - 1]) {
        [document setName:[NSString stringWithFormat:@"Part %ld", (long)trackNumber] forTrack:trackNumber - 1];
    }

    [_noteStartField setDoubleValue:startBeats + durationBeats];
    [_noteDurationField setDoubleValue:durationBeats];
    [_noteTrackField setIntegerValue:trackNumber];
    [[self scoreView] reloadDocument];
    [self updateChangeCount:NSChangeDone];
    [self refreshInspector];
}

- (void)printDocument:(id)sender
{
    (void)sender;
    if (![self scoreView]) {
        return;
    }

    NSPrintInfo *printInfo = [[[self printInfo] copy] autorelease];
#if defined(__APPLE__)
    [printInfo setHorizontalPagination:NSPrintingPaginationModeFit];
    [printInfo setVerticalPagination:NSPrintingPaginationModeAutomatic];
#else
    [printInfo setHorizontalPagination:NSFitPagination];
    [printInfo setVerticalPagination:NSAutoPagination];
#endif
    [printInfo setHorizontallyCentered:YES];
    [printInfo setVerticallyCentered:NO];
    [printInfo setLeftMargin:24.0];
    [printInfo setRightMargin:24.0];
    [printInfo setTopMargin:24.0];
    [printInfo setBottomMargin:24.0];

    NSPrintOperation *operation = [NSPrintOperation printOperationWithView:[self scoreView] printInfo:printInfo];
    [operation setShowsPrintPanel:YES];
    [operation setShowsProgressPanel:YES];
    [operation runOperation];
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error
{
    (void)typeName;
    NSString *path = [url path];
    NSString *extension = [[path pathExtension] lowercaseString];
    ScoreDocument *document = nil;
    if ([extension isEqualToString:@"score"]) {
        document = [ScorefileParser parseFileAtPath:path error:error];
    } else {
        document = [MidiParser parseFileAtPath:path error:error];
    }
    if (!document) {
        return NO;
    }
    [document setTitle:[[path lastPathComponent] stringByDeletingPathExtension]];
    [self setScoreDocument:document];
    return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)error
{
    ScoreDocument *document = [self scoreDocument];
    if (!document) {
        if (error) {
            NSDictionary *info = [NSDictionary dictionaryWithObject:@"There is no score to save."
                                                             forKey:NSLocalizedDescriptionKey];
            *error = [NSError errorWithDomain:@"ScoreMakerDocument" code:1 userInfo:info];
        }
        return nil;
    }
    [self syncInspectorMetadataMarkingChange:NO];
    [document setAnnotationText:[_annotationTextView string]];

    NSString *lowerType = [typeName lowercaseString];
    if ([lowerType rangeOfString:@"midi"].location != NSNotFound) {
        return [MidiParser dataForDocument:document error:error];
    }
    return [ScorefileParser dataForDocument:document error:error];
}

- (NSArray *)writableTypesForSaveOperation:(NSSaveOperationType)saveOperation
{
    (void)saveOperation;
    return [NSArray arrayWithObjects:@"MusicKit Scorefile", @"MIDI File", nil];
}

- (NSString *)fileNameExtensionForType:(NSString *)typeName saveOperation:(NSSaveOperationType)saveOperation
{
    (void)saveOperation;
    if ([[typeName lowercaseString] rangeOfString:@"midi"].location != NSNotFound) {
        return @"mid";
    }
    return @"score";
}

- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel
{
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
    [savePanel setAllowedFileTypes:[NSArray arrayWithObjects:@"score", @"mid", @"midi", nil]];
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
    [savePanel setNameFieldStringValue:[[self displayName] stringByAppendingPathExtension:@"score"]];
    return [super prepareSavePanel:savePanel];
}

- (NSString *)displayName
{
    NSString *title = [[self scoreDocument] title];
    if ([title length] > 0) {
        return title;
    }
    NSString *name = [super displayName];
    if ([name length] > 0) {
        return [name stringByDeletingPathExtension];
    }
    return @"Untitled";
}

- (void)setFileURL:(NSURL *)absoluteURL
{
    [super setFileURL:absoluteURL];
    NSString *name = [[[absoluteURL path] lastPathComponent] stringByDeletingPathExtension];
    if ([name length] > 0) {
        [[self scoreDocument] setTitle:name];
        [[self scoreView] setNeedsDisplay:YES];
    }
}

@end
