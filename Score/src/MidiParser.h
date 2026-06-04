#import <Foundation/Foundation.h>
#import "ScoreModel.h"

@interface MidiParser : NSObject
+ (ScoreDocument *)parseFileAtPath:(NSString *)path error:(NSError **)error;
@end
