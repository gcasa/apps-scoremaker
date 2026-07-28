#import <Foundation/Foundation.h>
#import "ScoreModel.h"

@interface MusicXMLParser : NSObject
+ (ScoreDocument *)parseFileAtPath:(NSString *)path error:(NSError **)error;
+ (NSData *)dataForDocument:(ScoreDocument *)document error:(NSError **)error;
@end
