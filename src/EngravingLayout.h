#import <AppKit/AppKit.h>
#import "NotationModel.h"

@interface ScoreEngravingSystem : NSObject
{
    NSUInteger _startTick, _endTick, _firstMeasureIndex, _lastMeasureIndex;
    NSArray *_ticks, *_fractions;
}
@property(nonatomic) NSUInteger startTick;
@property(nonatomic) NSUInteger endTick;
@property(nonatomic) NSUInteger firstMeasureIndex;
@property(nonatomic) NSUInteger lastMeasureIndex;
@property(nonatomic, copy) NSArray *ticks;
@property(nonatomic, copy) NSArray *fractions;
- (CGFloat)fractionForTick:(NSUInteger)tick;
@end

@interface ScoreEngravingLayout : NSObject
{
    NSArray *_systems, *_notationElements;
}
@property(nonatomic, copy) NSArray *systems;
@property(nonatomic, copy) NSArray *notationElements;
- (ScoreEngravingSystem *)systemContainingTick:(NSUInteger)tick;
@end

@interface ScoreEngraver : NSObject
- (ScoreEngravingLayout *)layoutDocument:(ScoreDocument *)document
                              musicWidth:(CGFloat)musicWidth
                     minimumMeasureWidth:(CGFloat)minimumMeasureWidth;
@end
