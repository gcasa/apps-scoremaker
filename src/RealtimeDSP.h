/* Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 * ScoreMaker is distributed under the GNU LGPL version 2.1 or later.
 */
#import <Foundation/Foundation.h>

@class NSViewController;

#if defined(__APPLE__)
typedef void (^ScoreAudioUnitLoadCompletion) (BOOL success, NSError *error);
#else
typedef id ScoreAudioUnitLoadCompletion;
#endif

@interface ScoreRealtimeDSP : NSObject
+ (NSArray *)availableAudioUnitInstruments;
- (BOOL)startWithError:(NSError **)error;
- (void)stop;
- (BOOL)isRunning;
- (void)useInternalSynthesizer;
- (void)loadAudioUnitInstrument:(NSDictionary *)description
                     completion:(ScoreAudioUnitLoadCompletion)completion;
- (NSDictionary *)audioUnitInstrumentDescription;
- (NSDictionary *)audioUnitFullState;
- (void)noteOn:(NSInteger)pitch velocity:(NSUInteger)velocity;
- (void)noteOff:(NSInteger)pitch;
- (void)allNotesOff;
- (BOOL)renderPitches:(NSArray *)pitches
             duration:(NSTimeInterval)duration
                toURL:(NSURL *)url
                error:(NSError **)error;
@end
