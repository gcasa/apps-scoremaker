#import "ScoreModel.h"

@implementation ScoreNote

- (NSInteger)pitch
{
    return _pitch;
}

- (void)setPitch:(NSInteger)pitch
{
    _pitch = pitch;
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

- (NSComparisonResult)compareScoreNote:(ScoreNote *)other
{
    if (_startTick < [other startTick]) return NSOrderedAscending;
    if (_startTick > [other startTick]) return NSOrderedDescending;
    if (_pitch > [other pitch]) return NSOrderedAscending;
    if (_pitch < [other pitch]) return NSOrderedDescending;
    return NSOrderedSame;
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
        _partNames = [[NSMutableDictionary alloc] init];
        _annotationText = [@"" retain];
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
    [_notes release];
    [_partNames release];
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

@end
