/* Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 * ScoreMaker is distributed under the GNU LGPL version 2.1 or later.
 */
#import <Foundation/Foundation.h>

@interface ScoreRealtimeDSP : NSObject
- (BOOL)startWithError:(NSError **)error;
- (void)stop;
- (BOOL)isRunning;
- (void)noteOn:(NSInteger)pitch velocity:(NSUInteger)velocity;
- (void)noteOff:(NSInteger)pitch;
- (BOOL)renderPitches:(NSArray *)pitches
             duration:(NSTimeInterval)duration
                toURL:(NSURL *)url
                error:(NSError **)error;
@end
