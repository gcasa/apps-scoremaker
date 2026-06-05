#import <Foundation/Foundation.h>

@interface ScoreNote : NSObject
{
    NSInteger _pitch;
    NSInteger _channel;
    NSInteger _track;
    NSUInteger _startTick;
    NSUInteger _durationTicks;
    BOOL _rest;
    NSInteger _accidental;
}
- (NSInteger)pitch;
- (void)setPitch:(NSInteger)pitch;
- (NSInteger)channel;
- (void)setChannel:(NSInteger)channel;
- (NSInteger)track;
- (void)setTrack:(NSInteger)track;
- (NSUInteger)startTick;
- (void)setStartTick:(NSUInteger)startTick;
- (NSUInteger)durationTicks;
- (void)setDurationTicks:(NSUInteger)durationTicks;
- (BOOL)isRest;
- (void)setRest:(BOOL)rest;
- (NSInteger)accidental;
- (void)setAccidental:(NSInteger)accidental;
- (NSComparisonResult)compareScoreNote:(ScoreNote *)other;
@end

@interface ScoreDocument : NSObject
{
    NSString *_title;
    NSMutableArray *_notes;
    NSMutableDictionary *_partNames;
    NSString *_annotationText;
    NSUInteger _ticksPerQuarter;
    NSUInteger _tempoMicrosecondsPerQuarter;
    NSUInteger _timeSignatureNumerator;
    NSUInteger _timeSignatureDenominator;
    NSUInteger _totalTicks;
}
- (NSString *)title;
- (void)setTitle:(NSString *)title;
- (NSMutableArray *)notes;
- (void)setNotes:(NSMutableArray *)notes;
- (NSMutableDictionary *)partNames;
- (void)setPartNames:(NSMutableDictionary *)partNames;
- (NSString *)annotationText;
- (void)setAnnotationText:(NSString *)annotationText;
- (NSUInteger)ticksPerQuarter;
- (void)setTicksPerQuarter:(NSUInteger)ticksPerQuarter;
- (NSUInteger)tempoMicrosecondsPerQuarter;
- (void)setTempoMicrosecondsPerQuarter:(NSUInteger)tempoMicrosecondsPerQuarter;
- (NSUInteger)timeSignatureNumerator;
- (void)setTimeSignatureNumerator:(NSUInteger)timeSignatureNumerator;
- (NSUInteger)timeSignatureDenominator;
- (void)setTimeSignatureDenominator:(NSUInteger)timeSignatureDenominator;
- (NSUInteger)totalTicks;
- (void)setTotalTicks:(NSUInteger)totalTicks;
- (NSString *)nameForTrack:(NSInteger)track;
- (void)setName:(NSString *)name forTrack:(NSInteger)track;
@end
