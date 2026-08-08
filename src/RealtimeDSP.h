/* Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 * ScoreMaker is distributed under the GNU LGPL version 2.1 or later.
 */
#import <Foundation/Foundation.h>

@class NSViewController;

#if defined(__APPLE__)
typedef void (^ScoreAudioUnitLoadCompletion) (BOOL success, NSError *error);
typedef void (^ScoreAudioUnitViewCompletion) (NSViewController *controller, NSError *error);
#else
typedef id ScoreAudioUnitLoadCompletion;
typedef id ScoreAudioUnitViewCompletion;
#endif

@interface ScoreRealtimeDSP : NSObject
+ (NSArray *)availableAudioUnitInstruments;
+ (NSString *)identifierForAudioUnitDescription:(NSDictionary *)description;
+ (BOOL)isAudioUnitBlacklisted:(NSDictionary *)description;
+ (void)setAudioUnit:(NSDictionary *)description blacklisted:(BOOL)blacklisted;
+ (NSArray *)blacklistedAudioUnitIdentifiers;
+ (void)clearAudioUnitBlacklist;
+ (NSArray *)audioUnitCompatibilityReport;
+ (NSArray *)supportedEffectTypes;
+ (NSDictionary *)defaultInternalSynthPatch;
+ (NSArray *)relinkCandidatesForAudioUnit:(NSDictionary *)description;
+ (NSArray *)userPresetsForAudioUnit:(NSDictionary *)description;
+ (BOOL)removeUserPreset:(NSString *)name
            forAudioUnit:(NSDictionary *)description
                   error:(NSError **)error;
- (BOOL)startWithError:(NSError **)error;
- (void)stop;
- (BOOL)isRunning;
- (void)useInternalSynthesizer;
- (void)loadAudioUnitInstrument:(NSDictionary *)description
                     completion:(ScoreAudioUnitLoadCompletion)completion;
- (NSDictionary *)audioUnitInstrumentDescription;
- (NSDictionary *)audioUnitFullState;
- (NSArray *)audioUnitParameters;
- (BOOL)setAudioUnitParameter:(uint64_t)address value:(double)value error:(NSError **)error;
- (void)requestAudioUnitViewController:(ScoreAudioUnitViewCompletion)completion;
- (BOOL)saveUserPreset:(NSString *)name error:(NSError **)error;
- (BOOL)loadUserPreset:(NSString *)name error:(NSError **)error;
- (BOOL)configureEffects:(NSArray *)effects error:(NSError **)error;
- (BOOL)configureEffectsFromGraph:(id)graph error:(NSError **)error;
- (NSArray *)effectConfiguration;
- (NSDictionary *)internalSynthPatch;
- (BOOL)configureInternalSynthPatch:(NSDictionary *)patch error:(NSError **)error;
- (void)noteOn:(NSInteger)pitch velocity:(NSUInteger)velocity;
- (void)noteOff:(NSInteger)pitch;
- (void)allNotesOff;
- (BOOL)scheduleEvents:(NSArray *)events error:(NSError **)error;
- (BOOL)renderEvents:(NSArray *)events
            duration:(NSTimeInterval)duration
               toURL:(NSURL *)url
               error:(NSError **)error;
- (BOOL)renderPitches:(NSArray *)pitches
             duration:(NSTimeInterval)duration
                toURL:(NSURL *)url
                error:(NSError **)error;
@end
