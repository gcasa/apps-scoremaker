/* Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 * ScoreMaker is distributed under the GNU LGPL version 2.1 or later.
 */
#import <Foundation/Foundation.h>

@class NSViewController;

#if defined(__APPLE__)
/** Completion block used when asynchronously loading an Audio Unit instrument. */
typedef void (^ScoreAudioUnitLoadCompletion) (BOOL success, NSError *error);
/** Completion block used when requesting an Audio Unit editor controller. */
typedef void (^ScoreAudioUnitViewCompletion) (NSViewController *controller, NSError *error);
#else
/** Opaque completion object on platforms without Objective-C blocks support. */
typedef id ScoreAudioUnitLoadCompletion;
/** Opaque editor-completion object on non-Apple platforms. */
typedef id ScoreAudioUnitViewCompletion;
#endif

/**
 * Provides real-time synthesis, Audio Unit hosting, effects, preset management,
 * event scheduling, and offline audio rendering.
 */
@interface ScoreRealtimeDSP : NSObject
/** Returns dictionaries describing installed Audio Unit music devices. */
+ (NSArray *)availableAudioUnitInstruments;
/** Returns a stable serialized identifier for an Audio Unit description. */
+ (NSString *)identifierForAudioUnitDescription:(NSDictionary *)description;
/** Returns whether the described Audio Unit has been disabled after failures. */
+ (BOOL)isAudioUnitBlacklisted:(NSDictionary *)description;
/** Adds or removes the described Audio Unit from the persistent blacklist. */
+ (void)setAudioUnit:(NSDictionary *)description blacklisted:(BOOL)blacklisted;
/** Returns stable identifiers for all blacklisted Audio Units. */
+ (NSArray *)blacklistedAudioUnitIdentifiers;
/** Removes every entry from the Audio Unit blacklist. */
+ (void)clearAudioUnitBlacklist;
/** Returns the most recently persisted Audio Unit compatibility results. */
+ (NSArray *)audioUnitCompatibilityReport;
/** Returns effect type identifiers accepted by the effects configuration API. */
+ (NSArray *)supportedEffectTypes;
/** Returns a complete, validated default internal-synth patch dictionary. */
+ (NSDictionary *)defaultInternalSynthPatch;
/** Returns the bundled factory patch dictionaries keyed by patch name. */
+ (NSDictionary *)factoryInternalSynthPatches;
/** Returns installed Audio Units suitable for replacing a missing description. */
+ (NSArray *)relinkCandidatesForAudioUnit:(NSDictionary *)description;
/** Returns names of user presets stored for the described Audio Unit. */
+ (NSArray *)userPresetsForAudioUnit:(NSDictionary *)description;
/** Removes a named user preset from the described Audio Unit. */
+ (BOOL)removeUserPreset:(NSString *)name
            forAudioUnit:(NSDictionary *)description
                   error:(NSError **)error;
/** Starts the audio engine and returns whether startup succeeded. */
- (BOOL)startWithError:(NSError **)error;
/** Stops rendering and releases active notes. */
- (void)stop;
/** Returns whether the audio engine is running. */
- (BOOL)isRunning;
/** Selects the built-in synthesizer as the active instrument. */
- (void)useInternalSynthesizer;
/** Asynchronously loads the Audio Unit described by <var>description</var>. */
- (void)loadAudioUnitInstrument:(NSDictionary *)description
                     completion:(ScoreAudioUnitLoadCompletion)completion;
/** Returns the active Audio Unit description, or <code>nil</code>. */
- (NSDictionary *)audioUnitInstrumentDescription;
/** Returns the active Audio Unit's opaque full-state dictionary. */
- (NSDictionary *)audioUnitFullState;
/** Returns metadata dictionaries for the active Audio Unit's parameters. */
- (NSArray *)audioUnitParameters;
/** Sets one Audio Unit parameter by address. */
- (BOOL)setAudioUnitParameter:(uint64_t)address value:(double)value error:(NSError **)error;
/** Asynchronously supplies the active Audio Unit's custom editor controller. */
- (void)requestAudioUnitViewController:(ScoreAudioUnitViewCompletion)completion;
/** Saves the active Audio Unit state as a named user preset. */
- (BOOL)saveUserPreset:(NSString *)name error:(NSError **)error;
/** Loads a named user preset into the active Audio Unit. */
- (BOOL)loadUserPreset:(NSString *)name error:(NSError **)error;
/** Validates and installs the shared effects-chain dictionaries. */
- (BOOL)configureEffects:(NSArray *)effects error:(NSError **)error;
/** Compiles compatible effect nodes from a synthesis graph. */
- (BOOL)configureEffectsFromGraph:(id)graph error:(NSError **)error;
/** Returns the installed shared effects configuration. */
- (NSArray *)effectConfiguration;
/** Returns the default-voice internal-synth patch. */
- (NSDictionary *)internalSynthPatch;
/** Validates and installs the default-voice internal-synth patch. */
- (BOOL)configureInternalSynthPatch:(NSDictionary *)patch error:(NSError **)error;
/** Returns the internal-synth patch assigned to <var>voice</var>. */
- (NSDictionary *)internalSynthPatchForVoice:(NSInteger)voice;
/** Validates and installs an internal-synth patch for one notation voice. */
- (BOOL)configureInternalSynthPatch:(NSDictionary *)patch
                           forVoice:(NSInteger)voice
                              error:(NSError **)error;
/** Returns the effects chain assigned to <var>voice</var>. */
- (NSArray *)internalSynthEffectsForVoice:(NSInteger)voice;
/** Validates and installs the effects chain assigned to <var>voice</var>. */
- (BOOL)configureInternalSynthEffects:(NSArray *)effects
                              forVoice:(NSInteger)voice
                                 error:(NSError **)error;
/** Starts a default-voice note immediately. */
- (void)noteOn:(NSInteger)pitch velocity:(NSUInteger)velocity;
/** Releases a default-voice note immediately. */
- (void)noteOff:(NSInteger)pitch;
/** Starts a note immediately using the patch assigned to <var>voice</var>. */
- (void)noteOn:(NSInteger)pitch voice:(NSInteger)voice velocity:(NSUInteger)velocity;
/** Releases a note in <var>voice</var> immediately. */
- (void)noteOff:(NSInteger)pitch voice:(NSInteger)voice;
/** Releases all sounding and scheduled notes. */
- (void)allNotesOff;
/** Replaces the pending real-time event timeline with <var>events</var>. */
- (BOOL)scheduleEvents:(NSArray *)events error:(NSError **)error;
/** Renders event dictionaries for <var>duration</var> seconds to <var>url</var>. */
- (BOOL)renderEvents:(NSArray *)events
            duration:(NSTimeInterval)duration
               toURL:(NSURL *)url
               error:(NSError **)error;
/** Renders an audition chord for <var>duration</var> seconds to <var>url</var>. */
- (BOOL)renderPitches:(NSArray *)pitches
             duration:(NSTimeInterval)duration
                toURL:(NSURL *)url
                error:(NSError **)error;
@end
