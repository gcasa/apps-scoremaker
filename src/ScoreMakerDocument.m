#import "ScoreMakerDocument.h"
#import "MidiParser.h"
#import "ScorefileParser.h"
#import <float.h>
#import <math.h>

static CGFloat const InspectorWidth = 280.0;
static CGFloat const InspectorPadding = 18.0;

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
    return _window;
}

- (void)setWindow:(NSWindow *)window
{
    if (_window != window) {
        [_window release];
        _window = [window retain];
    }
}

- (NSWindowController *)windowController
{
    return _windowController;
}

- (void)setWindowController:(NSWindowController *)windowController
{
    if (_windowController != windowController) {
        [_windowController release];
        _windowController = [windowController retain];
    }
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
    [_window release];
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
    [_addNoteButton release];
    [_annotationTextView release];
    [_windowController release];
    [super dealloc];
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
    [[self window] setTitle:[self displayName]];

    [self setScoreView:[[[ScoreView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 980.0, 760.0)] autorelease]];
    [[self scoreView] setDocument:[self scoreDocument]];
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

    NSTextField *pitchLabel = [self labelWithString:@"Pitch" frame:NSMakeRect(InspectorPadding, frame.size.height - 242.0, 48.0, 18.0)];
    [pitchLabel setFont:[NSFont systemFontOfSize:11.0]];
    [pitchLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:pitchLabel];
    _notePitchField = [[self metadataFieldWithFrame:NSMakeRect(InspectorPadding, frame.size.height - 270.0, 66.0, 24.0)] retain];
    [_notePitchField setStringValue:@"C4"];
    [_notePitchField setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:_notePitchField];

    NSTextField *startLabel = [self labelWithString:@"Start" frame:NSMakeRect(InspectorPadding + 78.0, frame.size.height - 242.0, 48.0, 18.0)];
    [startLabel setFont:[NSFont systemFontOfSize:11.0]];
    [startLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:startLabel];
    _noteStartField = [[self metadataFieldWithFrame:NSMakeRect(InspectorPadding + 78.0, frame.size.height - 270.0, 58.0, 24.0)] retain];
    [_noteStartField setStringValue:@"0"];
    [_noteStartField setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:_noteStartField];

    NSTextField *durationLabel = [self labelWithString:@"Beats" frame:NSMakeRect(InspectorPadding + 148.0, frame.size.height - 242.0, 48.0, 18.0)];
    [durationLabel setFont:[NSFont systemFontOfSize:11.0]];
    [durationLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:durationLabel];
    _noteDurationField = [[self metadataFieldWithFrame:NSMakeRect(InspectorPadding + 148.0, frame.size.height - 270.0, 58.0, 24.0)] retain];
    [_noteDurationField setStringValue:@"1"];
    [_noteDurationField setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:_noteDurationField];

    NSTextField *trackLabel = [self labelWithString:@"Track" frame:NSMakeRect(InspectorPadding, frame.size.height - 304.0, 48.0, 18.0)];
    [trackLabel setFont:[NSFont systemFontOfSize:11.0]];
    [trackLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:trackLabel];
    _noteTrackField = [[self metadataFieldWithFrame:NSMakeRect(InspectorPadding, frame.size.height - 332.0, 66.0, 24.0)] retain];
    [_noteTrackField setStringValue:@"1"];
    [_noteTrackField setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:_noteTrackField];

    _addNoteButton = [[NSButton alloc] initWithFrame:NSMakeRect(InspectorPadding + 78.0, frame.size.height - 332.0, 128.0, 26.0)];
    [_addNoteButton setTitle:@"Add Note"];
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

    NSTextField *notesLabel = [self labelWithString:@"Score Notes" frame:NSMakeRect(InspectorPadding, frame.size.height - 376.0, 120.0, 18.0)];
    [notesLabel setAutoresizingMask:NSViewMinYMargin];
    [[self inspectorView] addSubview:notesLabel];

    NSScrollView *notesScroll = [[[NSScrollView alloc] initWithFrame:NSMakeRect(InspectorPadding, InspectorPadding, frame.size.width - 2.0 * InspectorPadding, frame.size.height - 410.0)] autorelease];
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
    [_addNoteButton setEnabled:hasDocument];
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

- (void)addNote:(id)sender
{
    (void)sender;
    ScoreDocument *document = [self scoreDocument];
    if (!document) {
        return;
    }

    NSInteger pitch = 0;
    if (![self pitchString:[_notePitchField stringValue] toMidiPitch:&pitch]) {
        NSAlert *alert = [[[NSAlert alloc] init] autorelease];
        [alert setMessageText:@"The note pitch is not valid"];
        [alert setInformativeText:@"Use a MIDI pitch from 0 to 127 or a pitch name like C4, F#3, or Bb5."];
        [alert runModal];
        return;
    }

    double startBeats = [_noteStartField doubleValue];
    double durationBeats = [_noteDurationField doubleValue];
    NSInteger trackNumber = [_noteTrackField integerValue];
    if (startBeats < 0.0) startBeats = 0.0;
    if (durationBeats <= 0.0) durationBeats = 1.0;
    if (trackNumber < 1) trackNumber = 1;

    NSUInteger startTick = (NSUInteger)llround(startBeats * (double)[document ticksPerQuarter]);
    NSUInteger durationTicks = MAX((NSUInteger)1, (NSUInteger)llround(durationBeats * (double)[document ticksPerQuarter]));
    ScoreNote *note = [[[ScoreNote alloc] init] autorelease];
    [note setPitch:pitch];
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
