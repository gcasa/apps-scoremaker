#import <Foundation/Foundation.h>

@interface ScoreNote : NSObject <NSCopying>
{
    NSInteger _pitch;
    NSInteger _channel;
    NSInteger _track;
    NSUInteger _startTick;
    NSUInteger _durationTicks;
    BOOL _rest;
    NSInteger _accidental;
    BOOL _slurStart;
    BOOL _slurEnd;
    NSInteger _voice;
    NSInteger _measureIndex;
    NSUInteger _velocity;
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
- (BOOL)slurStart;
- (void)setSlurStart:(BOOL)slurStart;
- (BOOL)slurEnd;
- (void)setSlurEnd:(BOOL)slurEnd;
- (NSInteger)voice;
- (void)setVoice:(NSInteger)voice;
- (NSInteger)measureIndex;
- (void)setMeasureIndex:(NSInteger)measureIndex;
- (NSUInteger)velocity;
- (void)setVelocity:(NSUInteger)velocity;
- (NSComparisonResult)compareScoreNote:(ScoreNote *)other;
@end

@interface ScoreMeasure : NSObject <NSCopying>
{
    NSInteger _number;
    NSUInteger _startTick;
    NSUInteger _durationTicks;
    NSUInteger _timeSignatureNumerator;
    NSUInteger _timeSignatureDenominator;
    BOOL _implicit;
}
- (NSInteger)number;
- (void)setNumber:(NSInteger)number;
- (NSUInteger)startTick;
- (void)setStartTick:(NSUInteger)startTick;
- (NSUInteger)durationTicks;
- (void)setDurationTicks:(NSUInteger)durationTicks;
- (NSUInteger)timeSignatureNumerator;
- (void)setTimeSignatureNumerator:(NSUInteger)value;
- (NSUInteger)timeSignatureDenominator;
- (void)setTimeSignatureDenominator:(NSUInteger)value;
- (BOOL)isImplicit;
- (void)setImplicit:(BOOL)implicit;
@end

@interface ScoreDocument : NSObject <NSCopying>
{
    NSString *_title;
    NSString *_titleFontName;
    NSString *_composer;
    NSMutableArray *_notes;
    NSMutableArray *_measures;
    NSMutableDictionary *_partNames;
    NSMutableDictionary *_trackPrograms;
    NSString *_annotationText;
    NSUInteger _ticksPerQuarter;
    NSUInteger _tempoMicrosecondsPerQuarter;
    NSUInteger _timeSignatureNumerator;
    NSUInteger _timeSignatureDenominator;
    NSUInteger _totalTicks;
}
- (NSString *)title;
- (void)setTitle:(NSString *)title;
- (NSString *)titleFontName;
- (void)setTitleFontName:(NSString *)fontName;
- (NSString *)composer;
- (void)setComposer:(NSString *)composer;
- (NSMutableArray *)notes;
- (void)setNotes:(NSMutableArray *)notes;
- (NSMutableArray *)measures;
- (void)setMeasures:(NSMutableArray *)measures;
- (void)buildDefaultMeasures;
- (ScoreMeasure *)measureContainingTick:(NSUInteger)tick;
- (ScoreMeasure *)ensureMeasureContainingTick:(NSUInteger)tick;
- (NSMutableDictionary *)partNames;
- (void)setPartNames:(NSMutableDictionary *)partNames;
- (NSMutableDictionary *)trackPrograms;
- (void)setTrackPrograms:(NSMutableDictionary *)trackPrograms;
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
- (NSNumber *)programForTrack:(NSInteger)track;
- (void)setProgram:(NSNumber *)program forTrack:(NSInteger)track;
@end
