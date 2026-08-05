#import "ScoreModel.h"

@implementation ScoreNote

- (id)init
{
    self = [super init];
    if (self) {
        _voice = 1;
        _measureIndex = -1;
        _velocity = 64;
    }
    return self;
}

static NSInteger DefaultAccidentalForPitch(NSInteger pitch)
{
    NSInteger pitchClass = pitch % 12;
    if (pitchClass < 0) pitchClass += 12;
    switch (pitchClass) {
        case 1:
        case 6:
            return 1;
        case 3:
        case 8:
        case 10:
            return -1;
        default:
            return 0;
    }
}

- (NSInteger)pitch
{
    return _pitch;
}

- (void)setPitch:(NSInteger)pitch
{
    _pitch = pitch;
    _accidental = DefaultAccidentalForPitch(pitch);
}

- (NSInteger)channel
{
    return _channel;
}

- (void)setChannel:(NSInteger)channel
{
    _channel = channel;
}

- (NSInteger)track
{
    return _track;
}

- (void)setTrack:(NSInteger)track
{
    _track = track;
}

- (NSUInteger)startTick
{
    return _startTick;
}

- (void)setStartTick:(NSUInteger)startTick
{
    _startTick = startTick;
}

- (NSUInteger)durationTicks
{
    return _durationTicks;
}

- (void)setDurationTicks:(NSUInteger)durationTicks
{
    _durationTicks = durationTicks;
}

- (BOOL)isRest
{
    return _rest;
}

- (void)setRest:(BOOL)rest
{
    _rest = rest;
}

- (NSInteger)accidental
{
    return _accidental;
}

- (void)setAccidental:(NSInteger)accidental
{
    _accidental = MIN(MAX(accidental, (NSInteger)-1), (NSInteger)1);
}

- (BOOL)slurStart
{
    return _slurStart;
}

- (void)setSlurStart:(BOOL)slurStart
{
    _slurStart = slurStart;
}

- (BOOL)slurEnd
{
    return _slurEnd;
}

- (void)setSlurEnd:(BOOL)slurEnd
{
    _slurEnd = slurEnd;
}

- (BOOL)tieStart { return _tieStart; }
- (void)setTieStart:(BOOL)value { _tieStart = value; }
- (BOOL)tieEnd { return _tieEnd; }
- (void)setTieEnd:(BOOL)value { _tieEnd = value; }
- (NSUInteger)tupletActual { return _tupletActual; }
- (void)setTupletActual:(NSUInteger)value { _tupletActual = value; }
- (NSUInteger)tupletNormal { return _tupletNormal; }
- (void)setTupletNormal:(NSUInteger)value { _tupletNormal = value; }
- (NSString *)dynamic { return _dynamic; }
- (void)setDynamic:(NSString *)value { if (_dynamic != value) { [_dynamic release]; _dynamic = [value copy]; } }
- (NSString *)articulation { return _articulation; }
- (void)setArticulation:(NSString *)value { if (_articulation != value) { [_articulation release]; _articulation = [value copy]; } }

- (NSInteger)voice { return _voice; }
- (void)setVoice:(NSInteger)voice { _voice = MAX((NSInteger)1, voice); }
- (NSInteger)measureIndex { return _measureIndex; }
- (void)setMeasureIndex:(NSInteger)measureIndex { _measureIndex = MAX((NSInteger)-1, measureIndex); }
- (NSUInteger)velocity { return _velocity; }
- (void)setVelocity:(NSUInteger)velocity { _velocity = MIN((NSUInteger)127, velocity); }

- (NSComparisonResult)compareScoreNote:(ScoreNote *)other
{
    if (_startTick < [other startTick]) return NSOrderedAscending;
    if (_startTick > [other startTick]) return NSOrderedDescending;
    if (_voice < [other voice]) return NSOrderedAscending;
    if (_voice > [other voice]) return NSOrderedDescending;
    if (_rest && ![other isRest]) return NSOrderedDescending;
    if (!_rest && [other isRest]) return NSOrderedAscending;
    if (_pitch > [other pitch]) return NSOrderedAscending;
    if (_pitch < [other pitch]) return NSOrderedDescending;
    return NSOrderedSame;
}

- (id)copyWithZone:(NSZone *)zone
{
    ScoreNote *copy = [[ScoreNote allocWithZone:zone] init];
    [copy setPitch:_pitch]; [copy setAccidental:_accidental]; [copy setChannel:_channel];
    [copy setTrack:_track]; [copy setStartTick:_startTick]; [copy setDurationTicks:_durationTicks];
    [copy setRest:_rest]; [copy setSlurStart:_slurStart]; [copy setSlurEnd:_slurEnd];
    [copy setTieStart:_tieStart]; [copy setTieEnd:_tieEnd];
    [copy setTupletActual:_tupletActual]; [copy setTupletNormal:_tupletNormal];
    [copy setDynamic:_dynamic]; [copy setArticulation:_articulation];
    [copy setVoice:_voice]; [copy setMeasureIndex:_measureIndex]; [copy setVelocity:_velocity];
    return copy;
}

- (void)dealloc
{
    [_dynamic release];
    [_articulation release];
    [super dealloc];
}

@end

@implementation ScoreMeasure
- (NSInteger)number { return _number; }
- (void)setNumber:(NSInteger)number { _number = number; }
- (NSUInteger)startTick { return _startTick; }
- (void)setStartTick:(NSUInteger)startTick { _startTick = startTick; }
- (NSUInteger)durationTicks { return _durationTicks; }
- (void)setDurationTicks:(NSUInteger)durationTicks { _durationTicks = durationTicks; }
- (NSUInteger)timeSignatureNumerator { return _timeSignatureNumerator; }
- (void)setTimeSignatureNumerator:(NSUInteger)value { _timeSignatureNumerator = MAX((NSUInteger)1, value); }
- (NSUInteger)timeSignatureDenominator { return _timeSignatureDenominator; }
- (void)setTimeSignatureDenominator:(NSUInteger)value { _timeSignatureDenominator = MAX((NSUInteger)1, value); }
- (BOOL)isImplicit { return _implicit; }
- (void)setImplicit:(BOOL)implicit { _implicit = implicit; }
- (NSInteger)keySignatureFifths { return _keySignatureFifths; }
- (void)setKeySignatureFifths:(NSInteger)value { _keySignatureFifths = MIN(MAX(value, (NSInteger)-7), (NSInteger)7); }
- (BOOL)repeatStart { return _repeatStart; }
- (void)setRepeatStart:(BOOL)value { _repeatStart = value; }
- (BOOL)repeatEnd { return _repeatEnd; }
- (void)setRepeatEnd:(BOOL)value { _repeatEnd = value; }
- (id)copyWithZone:(NSZone *)zone
{
    ScoreMeasure *copy = [[ScoreMeasure allocWithZone:zone] init];
    [copy setNumber:_number]; [copy setStartTick:_startTick]; [copy setDurationTicks:_durationTicks];
    [copy setTimeSignatureNumerator:_timeSignatureNumerator];
    [copy setTimeSignatureDenominator:_timeSignatureDenominator]; [copy setImplicit:_implicit];
    [copy setKeySignatureFifths:_keySignatureFifths];
    [copy setRepeatStart:_repeatStart]; [copy setRepeatEnd:_repeatEnd];
    return copy;
}
@end

@implementation ScoreDocument

- (NSString *)title
{
    return _title;
}

- (void)setTitle:(NSString *)title
{
    if (_title != title) {
        [_title release];
        _title = [title retain];
    }
}

- (NSString *)titleFontName
{
    return _titleFontName;
}

- (void)setTitleFontName:(NSString *)fontName
{
    if (_titleFontName != fontName) {
        [_titleFontName release];
        _titleFontName = [fontName copy];
    }
}

- (NSString *)composer
{
    return _composer;
}

- (void)setComposer:(NSString *)composer
{
    if (_composer != composer) {
        [_composer release];
        _composer = [composer copy];
    }
}

- (NSMutableArray *)notes
{
    return _notes;
}

- (void)setNotes:(NSMutableArray *)notes
{
    if (_notes != notes) {
        [_notes release];
        _notes = [notes retain];
    }
}

- (NSMutableArray *)measures { return _measures; }

- (void)setMeasures:(NSMutableArray *)measures
{
    if (_measures != measures) {
        [_measures release];
        _measures = [measures retain];
    }
}

- (void)buildDefaultMeasures
{
    [_measures removeAllObjects];
    NSUInteger duration = (_ticksPerQuarter * 4 * _timeSignatureNumerator) /
                          MAX((NSUInteger)1, _timeSignatureDenominator);
    if (duration == 0) duration = MAX((NSUInteger)1, _ticksPerQuarter * 4);
    NSUInteger count = MAX((NSUInteger)1, (_totalTicks + duration - 1) / duration);
    for (NSUInteger index = 0; index < count; index++) {
        ScoreMeasure *measure = [[[ScoreMeasure alloc] init] autorelease];
        [measure setNumber:(NSInteger)index + 1];
        [measure setStartTick:index * duration];
        [measure setDurationTicks:duration];
        [measure setTimeSignatureNumerator:_timeSignatureNumerator];
        [measure setTimeSignatureDenominator:_timeSignatureDenominator];
        [_measures addObject:measure];
    }
    for (ScoreNote *note in _notes) {
        ScoreMeasure *measure = [self measureContainingTick:[note startTick]];
        [note setMeasureIndex:measure ? (NSInteger)[_measures indexOfObjectIdenticalTo:measure] : -1];
    }
}

- (ScoreMeasure *)measureContainingTick:(NSUInteger)tick
{
    for (ScoreMeasure *measure in _measures) {
        NSUInteger end = [measure startTick] + [measure durationTicks];
        if (tick >= [measure startTick] && tick < end) return measure;
    }
    return nil;
}

- (ScoreMeasure *)ensureMeasureContainingTick:(NSUInteger)tick
{
    ScoreMeasure *existing = [self measureContainingTick:tick];
    if (existing) return existing;
    if ([_measures count] == 0) [self buildDefaultMeasures];
    existing = [self measureContainingTick:tick];
    while (!existing) {
        ScoreMeasure *previous = [_measures lastObject];
        NSUInteger start = previous ? [previous startTick] + [previous durationTicks] : 0;
        NSUInteger beats = previous ? [previous timeSignatureNumerator] : _timeSignatureNumerator;
        NSUInteger beatType = previous ? [previous timeSignatureDenominator] : _timeSignatureDenominator;
        NSUInteger duration = (_ticksPerQuarter * 4 * beats) / MAX((NSUInteger)1, beatType);
        if (duration == 0) duration = MAX((NSUInteger)1, _ticksPerQuarter * 4);
        ScoreMeasure *measure = [[[ScoreMeasure alloc] init] autorelease];
        [measure setNumber:previous ? [previous number] + 1 : 1];
        [measure setStartTick:start];
        [measure setDurationTicks:duration];
        [measure setTimeSignatureNumerator:beats];
        [measure setTimeSignatureDenominator:beatType];
        [_measures addObject:measure];
        if (tick >= start && tick < start + duration) existing = measure;
    }
    return existing;
}

- (NSMutableDictionary *)partNames
{
    return _partNames;
}

- (void)setPartNames:(NSMutableDictionary *)partNames
{
    if (_partNames != partNames) {
        [_partNames release];
        _partNames = [partNames retain];
    }
}

- (NSMutableDictionary *)trackPrograms
{
    return _trackPrograms;
}

- (void)setTrackPrograms:(NSMutableDictionary *)trackPrograms
{
    if (_trackPrograms != trackPrograms) {
        [_trackPrograms release];
        _trackPrograms = [trackPrograms retain];
    }
}

- (NSString *)annotationText
{
    return _annotationText;
}

- (void)setAnnotationText:(NSString *)annotationText
{
    if (_annotationText != annotationText) {
        [_annotationText release];
        _annotationText = [annotationText retain];
    }
}

- (NSUInteger)ticksPerQuarter
{
    return _ticksPerQuarter;
}

- (void)setTicksPerQuarter:(NSUInteger)ticksPerQuarter
{
    _ticksPerQuarter = ticksPerQuarter;
}

- (NSUInteger)tempoMicrosecondsPerQuarter
{
    return _tempoMicrosecondsPerQuarter;
}

- (void)setTempoMicrosecondsPerQuarter:(NSUInteger)tempoMicrosecondsPerQuarter
{
    _tempoMicrosecondsPerQuarter = tempoMicrosecondsPerQuarter;
}

- (NSUInteger)timeSignatureNumerator
{
    return _timeSignatureNumerator;
}

- (void)setTimeSignatureNumerator:(NSUInteger)timeSignatureNumerator
{
    _timeSignatureNumerator = timeSignatureNumerator;
}

- (NSUInteger)timeSignatureDenominator
{
    return _timeSignatureDenominator;
}

- (void)setTimeSignatureDenominator:(NSUInteger)timeSignatureDenominator
{
    _timeSignatureDenominator = timeSignatureDenominator;
}

- (NSUInteger)totalTicks
{
    return _totalTicks;
}

- (void)setTotalTicks:(NSUInteger)totalTicks
{
    _totalTicks = totalTicks;
}

- (id)init
{
    self = [super init];
    if (self) {
        _notes = [[NSMutableArray alloc] init];
        _measures = [[NSMutableArray alloc] init];
        _partNames = [[NSMutableDictionary alloc] init];
        _trackPrograms = [[NSMutableDictionary alloc] init];
        _annotationText = [@"" retain];
        _titleFontName = [@"Times New Roman" copy];
        _ticksPerQuarter = 480;
        _tempoMicrosecondsPerQuarter = 500000;
        _timeSignatureNumerator = 4;
        _timeSignatureDenominator = 4;
        _totalTicks = 0;
    }
    return self;
}

- (void)dealloc
{
    [_title release];
    [_titleFontName release];
    [_composer release];
    [_notes release];
    [_measures release];
    [_partNames release];
    [_trackPrograms release];
    [_annotationText release];
    [super dealloc];
}

- (NSString *)nameForTrack:(NSInteger)track
{
    return [_partNames objectForKey:[NSNumber numberWithInteger:track]];
}

- (void)setName:(NSString *)name forTrack:(NSInteger)track
{
    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 0) {
        return;
    }
    [_partNames setObject:trimmed forKey:[NSNumber numberWithInteger:track]];
}

- (NSNumber *)programForTrack:(NSInteger)track
{
    return [_trackPrograms objectForKey:[NSNumber numberWithInteger:track]];
}

- (void)setProgram:(NSNumber *)program forTrack:(NSInteger)track
{
    NSNumber *trackNumber = [NSNumber numberWithInteger:track];
    if (!program) {
        [_trackPrograms removeObjectForKey:trackNumber];
        return;
    }

    NSInteger value = [program integerValue];
    if (value < 0 || value > 127) {
        [_trackPrograms removeObjectForKey:trackNumber];
        return;
    }
    [_trackPrograms setObject:[NSNumber numberWithInteger:value] forKey:trackNumber];
}

- (id)copyWithZone:(NSZone *)zone
{
    ScoreDocument *copy = [[ScoreDocument allocWithZone:zone] init];
    [copy setTitle:_title]; [copy setTitleFontName:_titleFontName]; [copy setComposer:_composer];
    [copy setAnnotationText:_annotationText]; [copy setTicksPerQuarter:_ticksPerQuarter];
    [copy setTempoMicrosecondsPerQuarter:_tempoMicrosecondsPerQuarter];
    [copy setTimeSignatureNumerator:_timeSignatureNumerator];
    [copy setTimeSignatureDenominator:_timeSignatureDenominator]; [copy setTotalTicks:_totalTicks];
    NSMutableArray *notes = [NSMutableArray arrayWithCapacity:[_notes count]];
    for (ScoreNote *note in _notes) [notes addObject:[[note copy] autorelease]];
    [copy setNotes:notes];
    NSMutableArray *measures = [NSMutableArray arrayWithCapacity:[_measures count]];
    for (ScoreMeasure *measure in _measures) [measures addObject:[[measure copy] autorelease]];
    [copy setMeasures:measures];
    [copy setPartNames:[[[NSMutableDictionary alloc] initWithDictionary:_partNames copyItems:YES] autorelease]];
    [copy setTrackPrograms:[[[NSMutableDictionary alloc] initWithDictionary:_trackPrograms copyItems:YES] autorelease]];
    return copy;
}

@end
