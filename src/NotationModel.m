#import "NotationModel.h"

@implementation ScoreNotationElement
@synthesize kind = _kind, startTick = _startTick, endTick = _endTick;
@synthesize track = _track, notationVoice = _notationVoice, value = _value, source = _source;
- (void)dealloc { [_value release]; [super dealloc]; }
@end

@implementation ScoreNotationModel
+ (ScoreNotationElement *)element:(ScoreNotationKind)kind start:(NSUInteger)start end:(NSUInteger)end
                            track:(NSInteger)track voice:(NSInteger)voice value:(NSString *)value source:(id)source
{
    ScoreNotationElement *element = [[[ScoreNotationElement alloc] init] autorelease];
    [element setKind:kind]; [element setStartTick:start]; [element setEndTick:end];
    [element setTrack:track]; [element setNotationVoice:voice]; [element setValue:value]; [element setSource:source];
    return element;
}

+ (NSArray *)elementsForDocument:(ScoreDocument *)document
{
    NSMutableArray *elements = [NSMutableArray array];
    for (ScoreMeasure *measure in [document measures]) {
        NSUInteger start = [measure startTick], end = start + [measure durationTicks];
        if ([measure keySignatureFifths] != 0)
            [elements addObject:[self element:ScoreNotationKeySignature start:start end:end track:-1 voice:0
                                         value:[NSString stringWithFormat:@"%ld", (long)[measure keySignatureFifths]] source:measure]];
        if ([measure repeatStart]) [elements addObject:[self element:ScoreNotationRepeat start:start end:start track:-1 voice:0 value:@"start" source:measure]];
        if ([measure repeatEnd]) [elements addObject:[self element:ScoreNotationRepeat start:end end:end track:-1 voice:0 value:@"end" source:measure]];
    }
    for (ScoreNote *note in [document notes]) {
        NSUInteger start = [note startTick], end = start + [note durationTicks];
        [elements addObject:[self element:[note isRest] ? ScoreNotationRest : ScoreNotationNote start:start end:end
                                     track:[note track] voice:[note voice] value:nil source:note]];
        if ([note accidental]) [elements addObject:[self element:ScoreNotationAccidental start:start end:start track:[note track] voice:[note voice]
                                                         value:[NSString stringWithFormat:@"%ld", (long)[note accidental]] source:note]];
        if ([note slurStart] || [note slurEnd]) [elements addObject:[self element:ScoreNotationSlur start:start end:end track:[note track] voice:[note voice] value:[note slurStart] ? @"start" : @"end" source:note]];
        if ([note tieStart] || [note tieEnd]) [elements addObject:[self element:ScoreNotationTie start:start end:end track:[note track] voice:[note voice] value:[note tieStart] ? @"start" : @"end" source:note]];
        if ([note tupletActual]) [elements addObject:[self element:ScoreNotationTuplet start:start end:end track:[note track] voice:[note voice]
                                                        value:[NSString stringWithFormat:@"%lu:%lu", (unsigned long)[note tupletActual], (unsigned long)[note tupletNormal]] source:note]];
        if ([[note dynamic] length]) [elements addObject:[self element:ScoreNotationDynamic start:start end:start track:[note track] voice:[note voice] value:[note dynamic] source:note]];
        if ([[note articulation] length]) [elements addObject:[self element:ScoreNotationArticulation start:start end:start track:[note track] voice:[note voice] value:[note articulation] source:note]];
    }
    return elements;
}
@end
