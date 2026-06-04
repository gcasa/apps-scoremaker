#import <Foundation/Foundation.h>
#import "ScoreModel.h"

@interface ScorefileParser : NSObject
+ (ScoreDocument *)parseFileAtPath:(NSString *)path error:(NSError **)error;
+ (NSData *)dataForDocument:(ScoreDocument *)document error:(NSError **)error;
+ (BOOL)writeDocument:(ScoreDocument *)document toFileAtPath:(NSString *)path error:(NSError **)error;
@end
