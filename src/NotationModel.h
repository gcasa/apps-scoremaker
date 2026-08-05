#import <Foundation/Foundation.h>
#import "ScoreModel.h"

typedef NS_ENUM(NSInteger, ScoreNotationKind) {
    ScoreNotationNote,
    ScoreNotationRest,
    ScoreNotationAccidental,
    ScoreNotationSlur,
    ScoreNotationTie,
    ScoreNotationTuplet,
    ScoreNotationDynamic,
    ScoreNotationArticulation,
    ScoreNotationKeySignature,
    ScoreNotationRepeat
};

/* A normalized semantic element. Importers and editors may continue using the
 * compatibility fields on ScoreNote/ScoreMeasure; all downstream consumers
 * should use this representation instead of interpreting those fields again. */
@interface ScoreNotationElement : NSObject
{
    ScoreNotationKind _kind;
    NSUInteger _startTick;
    NSUInteger _endTick;
    NSInteger _track;
    NSInteger _notationVoice;
    NSString *_value;
    id _source;
}
@property(nonatomic) ScoreNotationKind kind;
@property(nonatomic) NSUInteger startTick;
@property(nonatomic) NSUInteger endTick;
@property(nonatomic) NSInteger track;
@property(nonatomic) NSInteger notationVoice;
@property(nonatomic, copy) NSString *value;
@property(nonatomic, assign) id source;
@end

@interface ScoreNotationModel : NSObject
+ (NSArray *)elementsForDocument:(ScoreDocument *)document;
@end
