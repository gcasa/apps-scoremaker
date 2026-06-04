#import <Foundation/Foundation.h>

@interface ScoreNote : NSObject
{
    NSInteger _pitch;
    NSInteger _channel;
    NSInteger _track;
    NSUInteger _startTick;
    NSUInteger _durationTicks;
}
@property NSInteger pitch;
@property NSInteger channel;
@property NSInteger track;
@property NSUInteger startTick;
@property NSUInteger durationTicks;
- (NSComparisonResult)compareScoreNote:(ScoreNote *)other;
@end

@interface ScoreDocument : NSObject
{
    NSString *_title;
    NSMutableArray *_notes;
    NSMutableDictionary *_partNames;
    NSUInteger _ticksPerQuarter;
    NSUInteger _tempoMicrosecondsPerQuarter;
    NSUInteger _timeSignatureNumerator;
    NSUInteger _timeSignatureDenominator;
    NSUInteger _totalTicks;
}
@property(retain) NSString *title;
@property(retain) NSMutableArray *notes;
@property(retain) NSMutableDictionary *partNames;
@property NSUInteger ticksPerQuarter;
@property NSUInteger tempoMicrosecondsPerQuarter;
@property NSUInteger timeSignatureNumerator;
@property NSUInteger timeSignatureDenominator;
@property NSUInteger totalTicks;
- (NSString *)nameForTrack:(NSInteger)track;
- (void)setName:(NSString *)name forTrack:(NSInteger)track;
@end
