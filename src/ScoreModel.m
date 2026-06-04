#import "ScoreModel.h"

@implementation ScoreNote
@synthesize pitch = _pitch;
@synthesize channel = _channel;
@synthesize track = _track;
@synthesize startTick = _startTick;
@synthesize durationTicks = _durationTicks;

- (NSComparisonResult)compareScoreNote:(ScoreNote *)other
{
    if (_startTick < other.startTick) return NSOrderedAscending;
    if (_startTick > other.startTick) return NSOrderedDescending;
    if (_pitch > other.pitch) return NSOrderedAscending;
    if (_pitch < other.pitch) return NSOrderedDescending;
    return NSOrderedSame;
}

@end

@implementation ScoreDocument
@synthesize title = _title;
@synthesize notes = _notes;
@synthesize partNames = _partNames;
@synthesize ticksPerQuarter = _ticksPerQuarter;
@synthesize tempoMicrosecondsPerQuarter = _tempoMicrosecondsPerQuarter;
@synthesize timeSignatureNumerator = _timeSignatureNumerator;
@synthesize timeSignatureDenominator = _timeSignatureDenominator;
@synthesize totalTicks = _totalTicks;

- (id)init
{
    self = [super init];
    if (self) {
        _notes = [[NSMutableArray alloc] init];
        _partNames = [[NSMutableDictionary alloc] init];
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
