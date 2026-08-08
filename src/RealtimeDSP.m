/* Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 * ScoreMaker is distributed under the GNU LGPL version 2.1 or later.
 */
#import "RealtimeDSP.h"
#import "MusicEngine.h"
#import "MusicPlatformModel.h"
#import <math.h>
#import <stdatomic.h>
#if defined(__APPLE__)
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AudioToolbox/AUCocoaUIView.h>
#import <CoreAudioKit/CoreAudioKit.h>
#endif

#define SCORE_DSP_VOICES 64
#define SCORE_DSP_EVENTS 1024
#define SCORE_AUDIO_UNIT_TIMEOUT 12.0
static NSString *const ScoreAudioUnitBlacklistDefaultsKey = @"ScoreAudioUnitBlacklist";
static NSString *const ScoreAudioUnitFailureDefaultsKey = @"ScoreAudioUnitFailures";
typedef struct
{
  int pitch;
  float velocity;
  BOOL on;
  uint64_t sampleFrame;
} ScoreDSPEvent;
typedef struct
{
  int pitch;
  double phase;
  double lfoPhase;
  uint64_t ageFrames;
  float envelopeLevel;
  float releaseRate;
  float velocity;
  int envelopeStage;
  BOOL active;
  BOOL releasing;
} ScoreDSPVoice;

typedef struct
{
  int waveform;
  float attack;
  float decay;
  float sustain;
  float release;
  float lfoRate;
  float lfoDepth;
  float lfoDelay;
} ScoreDSPPatch;
typedef struct
{
  ScoreDSPVoice voices[SCORE_DSP_VOICES];
  ScoreDSPEvent events[SCORE_DSP_EVENTS];
  atomic_uint readIndex;
  atomic_uint writeIndex;
  double sampleRate;
  ScoreDSPEvent *scheduledEvents;
  NSUInteger scheduledEventCount;
  NSUInteger scheduledEventIndex;
  uint64_t renderedFrames;
  float gain;
  float lowpassCoefficient;
  float lowpassLeft;
  float lowpassRight;
  float compressorThreshold;
  float compressorRatio;
  float delayMix;
  float delayFeedback;
  NSUInteger delayFrames;
  NSUInteger delayIndex;
  float *delayLeft;
  float *delayRight;
  NSUInteger delayCapacity;
  float reverbMix;
  float reverbFeedback;
  NSUInteger reverbFrames;
  NSUInteger reverbIndex;
  float *reverbLeft;
  float *reverbRight;
  NSUInteger reverbCapacity;
  _Atomic(int) patchWaveform;
  _Atomic(float) patchAttack;
  _Atomic(float) patchDecay;
  _Atomic(float) patchSustain;
  _Atomic(float) patchRelease;
  _Atomic(float) patchLFORate;
  _Atomic(float) patchLFODepth;
  _Atomic(float) patchLFODelay;
} ScoreDSPState;

static ScoreDSPPatch
ScoreDSPLoadPatch (ScoreDSPState *state)
{
  return (ScoreDSPPatch){ atomic_load_explicit (&state->patchWaveform, memory_order_acquire),
                          atomic_load_explicit (&state->patchAttack, memory_order_acquire),
                          atomic_load_explicit (&state->patchDecay, memory_order_acquire),
                          atomic_load_explicit (&state->patchSustain, memory_order_acquire),
                          atomic_load_explicit (&state->patchRelease, memory_order_acquire),
                          atomic_load_explicit (&state->patchLFORate, memory_order_acquire),
                          atomic_load_explicit (&state->patchLFODepth, memory_order_acquire),
                          atomic_load_explicit (&state->patchLFODelay, memory_order_acquire) };
}

static void
ScoreDSPStorePatch (ScoreDSPState *state, ScoreDSPPatch patch)
{
  atomic_store_explicit (&state->patchWaveform, patch.waveform, memory_order_release);
  atomic_store_explicit (&state->patchAttack, patch.attack, memory_order_release);
  atomic_store_explicit (&state->patchDecay, patch.decay, memory_order_release);
  atomic_store_explicit (&state->patchSustain, patch.sustain, memory_order_release);
  atomic_store_explicit (&state->patchRelease, patch.release, memory_order_release);
  atomic_store_explicit (&state->patchLFORate, patch.lfoRate, memory_order_release);
  atomic_store_explicit (&state->patchLFODepth, patch.lfoDepth, memory_order_release);
  atomic_store_explicit (&state->patchLFODelay, patch.lfoDelay, memory_order_release);
}

static float
ScoreDSPPatchFloat (NSDictionary *patch, NSDictionary *defaults, NSString *key)
{
  NSNumber *value = [patch objectForKey:key] ?: [defaults objectForKey:key];
  return [value floatValue];
}

static void
ScoreDSPInitializeEffects (ScoreDSPState *state, double sampleRate)
{
  state->sampleRate = sampleRate;
  state->gain = 1.0f;
  state->compressorThreshold = 1.0f;
  state->compressorRatio = 1.0f;
  state->delayCapacity = (NSUInteger)ceil (sampleRate * 2.0);
  state->reverbCapacity = (NSUInteger)ceil (sampleRate * 0.75);
  state->delayLeft = calloc (state->delayCapacity, sizeof (float));
  state->delayRight = calloc (state->delayCapacity, sizeof (float));
  state->reverbLeft = calloc (state->reverbCapacity, sizeof (float));
  state->reverbRight = calloc (state->reverbCapacity, sizeof (float));
  atomic_init (&state->patchWaveform, 0);
  atomic_init (&state->patchAttack, 0.01f);
  atomic_init (&state->patchDecay, 0.12f);
  atomic_init (&state->patchSustain, 0.78f);
  atomic_init (&state->patchRelease, 0.28f);
  atomic_init (&state->patchLFORate, 5.0f);
  atomic_init (&state->patchLFODepth, 0.0f);
  atomic_init (&state->patchLFODelay, 0.0f);
  ScoreDSPStorePatch (state, (ScoreDSPPatch){ 0, 0.01f, 0.12f, 0.78f, 0.28f, 5.0f, 0.0f,
                                              0.0f });
}

static void
ScoreDSPDisposeEffects (ScoreDSPState *state)
{
  free (state->delayLeft);
  free (state->delayRight);
  free (state->reverbLeft);
  free (state->reverbRight);
  state->delayLeft = NULL;
  state->delayRight = NULL;
  state->reverbLeft = NULL;
  state->reverbRight = NULL;
}

static float
ScoreDSPCompress (float sample, float threshold, float ratio)
{
  float magnitude = fabsf (sample);
  if (magnitude <= threshold || ratio <= 1.0f)
    return sample;
  float compressed = threshold + (magnitude - threshold) / ratio;
  return copysignf (compressed, sample);
}

static void
ScoreDSPApplyEffects (ScoreDSPState *state, float *left, float *right)
{
  float l = *left * state->gain;
  float r = *right * state->gain;
  if (state->lowpassCoefficient > 0.0f)
    {
      state->lowpassLeft += state->lowpassCoefficient * (l - state->lowpassLeft);
      state->lowpassRight += state->lowpassCoefficient * (r - state->lowpassRight);
      l = state->lowpassLeft;
      r = state->lowpassRight;
    }
  l = ScoreDSPCompress (l, state->compressorThreshold, state->compressorRatio);
  r = ScoreDSPCompress (r, state->compressorThreshold, state->compressorRatio);
  if (state->delayFrames && state->delayLeft)
    {
      float delayedLeft = state->delayLeft[state->delayIndex];
      float delayedRight = state->delayRight[state->delayIndex];
      state->delayLeft[state->delayIndex] = l + delayedLeft * state->delayFeedback;
      state->delayRight[state->delayIndex] = r + delayedRight * state->delayFeedback;
      l = l * (1.0f - state->delayMix) + delayedLeft * state->delayMix;
      r = r * (1.0f - state->delayMix) + delayedRight * state->delayMix;
      state->delayIndex = (state->delayIndex + 1) % state->delayFrames;
    }
  if (state->reverbFrames && state->reverbLeft)
    {
      NSUInteger rightIndex = (state->reverbIndex + state->reverbFrames / 7)
                              % state->reverbFrames;
      float wetLeft = state->reverbLeft[state->reverbIndex];
      float wetRight = state->reverbRight[rightIndex];
      state->reverbLeft[state->reverbIndex] = l + wetRight * state->reverbFeedback;
      state->reverbRight[rightIndex] = r + wetLeft * state->reverbFeedback;
      l = l * (1.0f - state->reverbMix) + wetLeft * state->reverbMix;
      r = r * (1.0f - state->reverbMix) + wetRight * state->reverbMix;
      state->reverbIndex = (state->reverbIndex + 1) % state->reverbFrames;
    }
  *left = tanhf (l);
  *right = tanhf (r);
}

static void
ScoreDSPPush (ScoreDSPState *s, int pitch, float velocity, BOOL on)
{
  unsigned write = atomic_load_explicit (&s->writeIndex, memory_order_relaxed);
  unsigned next = (write + 1) % SCORE_DSP_EVENTS;
  if (next == atomic_load_explicit (&s->readIndex, memory_order_acquire))
    return;
  s->events[write] = (ScoreDSPEvent){ pitch, velocity, on, 0 };
  atomic_store_explicit (&s->writeIndex, next, memory_order_release);
}
static void
ScoreDSPApplyEvent (ScoreDSPState *s, ScoreDSPEvent e)
{
  if (e.on)
    {
      ScoreDSPVoice *v = NULL;
      for (int i = 0; i < SCORE_DSP_VOICES; i++)
        if (!s->voices[i].active)
          {
            v = &s->voices[i];
            break;
          }
      if (!v)
        v = &s->voices[0];
      *v = (ScoreDSPVoice){ .pitch = e.pitch,
                            .phase = 0,
                            .lfoPhase = 0,
                            .ageFrames = 0,
                            .envelopeLevel = 0,
                            .releaseRate = 0,
                            .velocity = e.velocity,
                            .envelopeStage = 0,
                            .active = YES,
                            .releasing = NO };
    }
  else
    for (int i = 0; i < SCORE_DSP_VOICES; i++)
      if (s->voices[i].active && s->voices[i].pitch == e.pitch)
        s->voices[i].releasing = YES;
}
static void
ScoreDSPApplyImmediateEvents (ScoreDSPState *s)
{
  unsigned read = atomic_load_explicit (&s->readIndex, memory_order_relaxed);
  unsigned write = atomic_load_explicit (&s->writeIndex, memory_order_acquire);
  while (read != write)
    {
      ScoreDSPEvent e = s->events[read];
      read = (read + 1) % SCORE_DSP_EVENTS;
      ScoreDSPApplyEvent (s, e);
    }
  atomic_store_explicit (&s->readIndex, read, memory_order_release);
}
static void
ScoreDSPRender (ScoreDSPState *s, float *left, float *right, NSUInteger frames)
{
  ScoreDSPApplyImmediateEvents (s);
  ScoreDSPPatch patch = ScoreDSPLoadPatch (s);
  for (NSUInteger f = 0; f < frames; f++)
    {
      while (s->scheduledEventIndex < s->scheduledEventCount
             && s->scheduledEvents[s->scheduledEventIndex].sampleFrame <= s->renderedFrames)
        ScoreDSPApplyEvent (s, s->scheduledEvents[s->scheduledEventIndex++]);
      double mix = 0;
      for (int i = 0; i < SCORE_DSP_VOICES; i++)
        {
          ScoreDSPVoice *v = &s->voices[i];
          if (!v->active)
            continue;
          if (v->releasing)
            {
              if (v->releaseRate <= 0.0f)
                v->releaseRate = patch.release > 0.0001f
                                   ? v->envelopeLevel / (patch.release * (float)s->sampleRate)
                                   : v->envelopeLevel;
              v->envelopeLevel -= v->releaseRate;
              if (v->envelopeLevel <= 0.0001f)
                {
                  v->active = NO;
                  continue;
                }
            }
          else if (v->envelopeStage == 0)
            {
              v->envelopeLevel += patch.attack > 0.0001f
                                    ? 1.0f / (patch.attack * (float)s->sampleRate)
                                    : 1.0f;
              if (v->envelopeLevel >= 1.0f)
                {
                  v->envelopeLevel = 1.0f;
                  v->envelopeStage = 1;
                }
            }
          else if (v->envelopeStage == 1)
            {
              v->envelopeLevel -= patch.decay > 0.0001f
                                    ? (1.0f - patch.sustain)
                                        / (patch.decay * (float)s->sampleRate)
                                    : 1.0f;
              if (v->envelopeLevel <= patch.sustain)
                {
                  v->envelopeLevel = patch.sustain;
                  v->envelopeStage = 2;
                }
            }
          double hz = 440.0 * pow (2.0, (v->pitch - 69) / 12.0);
          if ((double)v->ageFrames / s->sampleRate >= patch.lfoDelay && patch.lfoDepth != 0.0f)
            hz *= pow (2.0, sin (v->lfoPhase) * patch.lfoDepth / 12.0);
          double oscillator = 0.0;
          switch (patch.waveform)
            {
            case 1:
              oscillator = (2.0 / M_PI) * asin (sin (v->phase));
              break;
            case 2:
              oscillator = v->phase / M_PI - 1.0;
              break;
            case 3:
              oscillator = v->phase < M_PI ? 1.0 : -1.0;
              break;
            default:
              oscillator = sin (v->phase);
              break;
            }
          mix += oscillator * v->envelopeLevel * v->velocity;
          v->phase += 2.0 * M_PI * hz / s->sampleRate;
          if (v->phase >= 2.0 * M_PI)
            v->phase -= 2.0 * M_PI;
          v->lfoPhase += 2.0 * M_PI * patch.lfoRate / s->sampleRate;
          if (v->lfoPhase >= 2.0 * M_PI)
            v->lfoPhase -= 2.0 * M_PI;
          v->ageFrames++;
        }
      float sample = (float)(mix * 0.22);
      left[f] = sample;
      right[f] = sample;
      ScoreDSPApplyEffects (s, &left[f], &right[f]);
      s->renderedFrames++;
    }
}

@interface ScoreRealtimeDSP ()
+ (NSURL *)presetDirectoryForAudioUnit:(NSDictionary *)description create:(BOOL)create;
+ (void)recordAudioUnitFailure:(NSDictionary *)description;
+ (void)clearAudioUnitFailures:(NSDictionary *)description;
- (void)audioEngineConfigurationChanged:(NSNotification *)notification;
- (NSViewController *)legacyAudioUnitViewController;
@end

@implementation ScoreRealtimeDSP
{
  ScoreDSPState *_dsp;
#if defined(__APPLE__)
  AVAudioEngine *_engine;
  AVAudioSourceNode *_source;
  AVAudioUnitMIDIInstrument *_instrument;
  NSDictionary *_instrumentDescription;
  NSMutableArray *_engineEffectNodes;
#endif
  NSArray *_effectConfiguration;
  NSDictionary *_internalSynthPatch;
  BOOL _running;
}
+ (NSArray *)availableAudioUnitInstruments
{
#if defined(__APPLE__)
  NSMutableArray *instruments = [NSMutableArray array];
  NSArray *components = [[AVAudioUnitComponentManager sharedAudioUnitComponentManager]
    componentsPassingTest:^BOOL (AVAudioUnitComponent *component, BOOL *stop) {
      (void)stop;
      return [component audioComponentDescription].componentType == kAudioUnitType_MusicDevice;
    }];
  for (AVAudioUnitComponent *component in components)
    {
      AudioComponentDescription description = [component audioComponentDescription];
      [instruments
        addObject:[NSDictionary
                    dictionaryWithObjectsAndKeys:
                      [component name], @"name", [component manufacturerName], @"manufacturer",
                      [NSNumber numberWithUnsignedInt:description.componentType], @"type",
                      [NSNumber numberWithUnsignedInt:description.componentSubType], @"subtype",
                      [NSNumber numberWithUnsignedInt:description.componentManufacturer],
                      @"manufacturerCode",
                      [NSNumber numberWithBool:[[component configurationDictionary]
                                                objectForKey:@"NSExtension"] != nil],
                      @"isV3", [NSNumber numberWithBool:[component hasCustomView]], @"hasCustomView",
                      [NSNumber numberWithBool:[component isSandboxSafe]], @"sandboxSafe",
                      [NSNumber numberWithBool:[component passesAUVal]], @"passesAUVal",
                      [component versionString] ?: @"", @"version", nil]];
    }
  return [instruments
    sortedArrayUsingComparator:^NSComparisonResult (NSDictionary *left, NSDictionary *right) {
      return
        [[left objectForKey:@"name"] localizedCaseInsensitiveCompare:[right objectForKey:@"name"]];
    }];
#else
  return [NSArray array];
#endif
}
+ (NSString *)identifierForAudioUnitDescription:(NSDictionary *)description
{
  return [NSString stringWithFormat:@"%08x-%08x-%08x",
                                    [[description objectForKey:@"type"] unsignedIntValue],
                                    [[description objectForKey:@"subtype"] unsignedIntValue],
                                    [[description objectForKey:@"manufacturerCode"] unsignedIntValue]];
}
+ (BOOL)isAudioUnitBlacklisted:(NSDictionary *)description
{
  NSArray *blacklist = [[NSUserDefaults standardUserDefaults]
    arrayForKey:ScoreAudioUnitBlacklistDefaultsKey];
  return [blacklist containsObject:[self identifierForAudioUnitDescription:description]];
}
+ (void)setAudioUnit:(NSDictionary *)description blacklisted:(BOOL)blacklisted
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableArray *items = [NSMutableArray
    arrayWithArray:[defaults arrayForKey:ScoreAudioUnitBlacklistDefaultsKey] ?: [NSArray array]];
  NSString *identifier = [self identifierForAudioUnitDescription:description];
  [items removeObject:identifier];
  if (blacklisted)
    [items addObject:identifier];
  [defaults setObject:items forKey:ScoreAudioUnitBlacklistDefaultsKey];
}
+ (NSArray *)blacklistedAudioUnitIdentifiers
{
  return [[NSUserDefaults standardUserDefaults] arrayForKey:ScoreAudioUnitBlacklistDefaultsKey]
         ?: [NSArray array];
}
+ (void)clearAudioUnitBlacklist
{
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:ScoreAudioUnitBlacklistDefaultsKey];
}
+ (NSArray *)audioUnitCompatibilityReport
{
  NSMutableArray *report = [NSMutableArray array];
  for (NSDictionary *description in [self availableAudioUnitInstruments])
    {
      NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:description];
      NSString *status = @"Ready";
      if ([self isAudioUnitBlacklisted:description])
        status = @"Blacklisted";
      else if (![[description objectForKey:@"passesAUVal"] boolValue])
        status = @"Failed Apple validation";
      else if (![[description objectForKey:@"sandboxSafe"] boolValue])
        status = @"Requires out-of-process isolation";
      [entry setObject:status forKey:@"status"];
      [entry setObject:[[description objectForKey:@"isV3"] boolValue] ? @"AUv3" : @"AUv2"
                forKey:@"format"];
      [report addObject:entry];
    }
  return report;
}
+ (NSArray *)supportedEffectTypes
{
  return @[
    @{ @"identifier" : @"gain", @"name" : @"Gain" },
    @{ @"identifier" : @"lowpass", @"name" : @"Low-Pass Filter" },
    @{ @"identifier" : @"compressor", @"name" : @"Compressor" },
    @{ @"identifier" : @"delay", @"name" : @"Delay" },
    @{ @"identifier" : @"reverb", @"name" : @"Reverb" }
  ];
}
+ (NSDictionary *)defaultInternalSynthPatch
{
  return @{ @"waveform" : @"Sine",
            @"attack" : @0.01,
            @"decay" : @0.12,
            @"sustain" : @0.78,
            @"release" : @0.28,
            @"lfoRate" : @5.0,
            @"lfoDepth" : @0.0,
            @"lfoDelay" : @0.0 };
}
+ (NSArray *)relinkCandidatesForAudioUnit:(NSDictionary *)description
{
  NSMutableArray *candidates = [NSMutableArray array];
  NSString *manufacturer = [description objectForKey:@"manufacturer"];
  NSString *name = [description objectForKey:@"name"];
  for (NSDictionary *candidate in [self availableAudioUnitInstruments])
    {
      NSInteger score = 0;
      if (manufacturer && [[candidate objectForKey:@"manufacturer"] isEqualToString:manufacturer])
        score += 2;
      if (name && [[candidate objectForKey:@"name"] localizedCaseInsensitiveCompare:name]
                    == NSOrderedSame)
        score += 4;
      if (score)
        {
          NSMutableDictionary *ranked = [NSMutableDictionary dictionaryWithDictionary:candidate];
          [ranked setObject:[NSNumber numberWithInteger:score] forKey:@"relinkScore"];
          [candidates addObject:ranked];
        }
    }
  [candidates sortUsingComparator:^NSComparisonResult (NSDictionary *left, NSDictionary *right) {
    return [[right objectForKey:@"relinkScore"] compare:[left objectForKey:@"relinkScore"]];
  }];
  return candidates;
}
+ (NSURL *)presetDirectoryForAudioUnit:(NSDictionary *)description create:(BOOL)create
{
  NSURL *base = [[[NSFileManager defaultManager]
    URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
  NSURL *directory = [[[base URLByAppendingPathComponent:@"ScoreMaker" isDirectory:YES]
    URLByAppendingPathComponent:@"Audio Unit Presets" isDirectory:YES]
    URLByAppendingPathComponent:[self identifierForAudioUnitDescription:description]
                    isDirectory:YES];
  if (create)
    [[NSFileManager defaultManager] createDirectoryAtURL:directory
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:NULL];
  return directory;
}
+ (NSArray *)userPresetsForAudioUnit:(NSDictionary *)description
{
  NSArray *files = [[NSFileManager defaultManager]
    contentsOfDirectoryAtURL:[self presetDirectoryForAudioUnit:description create:NO]
  includingPropertiesForKeys:nil
                     options:NSDirectoryEnumerationSkipsHiddenFiles
                       error:NULL];
  NSMutableArray *names = [NSMutableArray array];
  for (NSURL *url in files)
    if ([[url pathExtension] isEqualToString:@"aupreset"])
      [names addObject:[[url lastPathComponent] stringByDeletingPathExtension]];
  return [names sortedArrayUsingSelector:@selector (localizedCaseInsensitiveCompare:)];
}
+ (BOOL)removeUserPreset:(NSString *)name
            forAudioUnit:(NSDictionary *)description
                   error:(NSError **)error
{
  if (![name length])
    {
      if (error)
        *error = [NSError errorWithDomain:@"ScoreMakerDSP"
                                     code:10
                                 userInfo:@{
                                   NSLocalizedDescriptionKey : @"Select an Audio Unit preset to delete."
                                 }];
      return NO;
    }
  NSURL *url = [[self presetDirectoryForAudioUnit:description create:NO]
    URLByAppendingPathComponent:[[name lastPathComponent] stringByAppendingPathExtension:@"aupreset"]];
  return [[NSFileManager defaultManager] removeItemAtURL:url error:error];
}
+ (void)recordAudioUnitFailure:(NSDictionary *)description
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *failures = [NSMutableDictionary
    dictionaryWithDictionary:[defaults dictionaryForKey:ScoreAudioUnitFailureDefaultsKey]
                             ?: [NSDictionary dictionary]];
  NSString *identifier = [self identifierForAudioUnitDescription:description];
  NSUInteger count = [[failures objectForKey:identifier] unsignedIntegerValue] + 1;
  [failures setObject:[NSNumber numberWithUnsignedInteger:count] forKey:identifier];
  [defaults setObject:failures forKey:ScoreAudioUnitFailureDefaultsKey];
  if (count >= 3)
    [self setAudioUnit:description blacklisted:YES];
}
+ (void)clearAudioUnitFailures:(NSDictionary *)description
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *failures = [NSMutableDictionary
    dictionaryWithDictionary:[defaults dictionaryForKey:ScoreAudioUnitFailureDefaultsKey]
                             ?: [NSDictionary dictionary]];
  [failures removeObjectForKey:[self identifierForAudioUnitDescription:description]];
  [defaults setObject:failures forKey:ScoreAudioUnitFailureDefaultsKey];
}
- (id)init
{
  if ((self = [super init]))
    {
      _dsp = calloc (1, sizeof (*_dsp));
      ScoreDSPInitializeEffects (_dsp, 48000.0);
      _effectConfiguration = [[NSArray alloc] init];
      _internalSynthPatch = [[[self class] defaultInternalSynthPatch] copy];
    }
  return self;
}
- (BOOL)startWithError:(NSError **)error
{
#if defined(__APPLE__)
  if (_running)
    return YES;
  if (_instrument)
    {
      _engine = [[AVAudioEngine alloc] init];
      _engineEffectNodes = [[NSMutableArray alloc] init];
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector (audioEngineConfigurationChanged:)
               name:AVAudioEngineConfigurationChangeNotification
             object:_engine];
      [_engine attachNode:_instrument];
      AVAudioNode *previous = _instrument;
      for (NSDictionary *effect in _effectConfiguration)
        {
          if ([[effect objectForKey:@"bypass"] boolValue])
            continue;
          NSString *type = [effect objectForKey:@"type"];
          AVAudioUnitEffect *node = nil;
          if ([type isEqualToString:@"gain"])
            {
              AVAudioUnitEQ *equalizer = [[[AVAudioUnitEQ alloc] initWithNumberOfBands:0] autorelease];
              [equalizer setGlobalGain:[[effect objectForKey:@"decibels"] floatValue]];
              node = equalizer;
            }
          else if ([type isEqualToString:@"lowpass"])
            {
              AVAudioUnitEQ *equalizer = [[[AVAudioUnitEQ alloc] initWithNumberOfBands:1] autorelease];
              AVAudioUnitEQFilterParameters *band = [[equalizer bands] objectAtIndex:0];
              [band setFilterType:AVAudioUnitEQFilterTypeLowPass];
              [band setFrequency:MAX (20.0f, MIN (20000.0f,
                                                  [[effect objectForKey:@"cutoff"] floatValue]))];
              [band setBypass:NO];
              node = equalizer;
            }
          else if ([type isEqualToString:@"delay"])
            {
              AVAudioUnitDelay *delay = [[[AVAudioUnitDelay alloc] init] autorelease];
              [delay setDelayTime:MAX (0.0, MIN (2.0, [[effect objectForKey:@"time"] doubleValue]))];
              [delay setFeedback:MAX (0.0f, MIN (95.0f,
                                                 [[effect objectForKey:@"feedback"] floatValue]
                                                   * 100.0f))];
              [delay setWetDryMix:MAX (0.0f, MIN (100.0f,
                                                  [[effect objectForKey:@"mix"] floatValue]
                                                    * 100.0f))];
              node = delay;
            }
          else if ([type isEqualToString:@"reverb"])
            {
              AVAudioUnitReverb *reverb = [[[AVAudioUnitReverb alloc] init] autorelease];
              [reverb loadFactoryPreset:AVAudioUnitReverbPresetMediumHall];
              [reverb setWetDryMix:MAX (0.0f, MIN (100.0f,
                                                   [[effect objectForKey:@"mix"] floatValue]
                                                     * 100.0f))];
              node = reverb;
            }
          if (!node)
            continue;
          [_engineEffectNodes addObject:node];
          [_engine attachNode:node];
          [_engine connect:previous to:node format:nil];
          previous = node;
        }
      [_engine connect:previous to:[_engine mainMixerNode] format:nil];
      if (![_engine startAndReturnError:error])
        {
          [_engine release];
          _engine = nil;
          return NO;
        }
      _running = YES;
      return YES;
    }
  _engine = [[AVAudioEngine alloc] init];
  AVAudioFormat *format = [[[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000
                                                                          channels:2] autorelease];
  _dsp->sampleRate = [format sampleRate];
  ScoreDSPState *state = _dsp;
  _source = [[AVAudioSourceNode alloc]
    initWithFormat:format
       renderBlock:^OSStatus (BOOL *silence, const AudioTimeStamp *time, AVAudioFrameCount count,
                              AudioBufferList *buffers) {
         (void)time;
         (void)silence;
         float *l = buffers->mBuffers[0].mData;
         float *r = buffers->mNumberBuffers > 1 ? buffers->mBuffers[1].mData : l;
         ScoreDSPRender (state, l, r, count);
         return noErr;
       }];
  [_engine attachNode:_source];
  [_engine connect:_source to:[_engine mainMixerNode] format:format];
  if (![_engine startAndReturnError:error])
    return NO;
  _running = YES;
  return YES;
#else
  if (error)
    *error = [NSError
      errorWithDomain:@"ScoreMakerDSP"
                 code:1
             userInfo:@{ NSLocalizedDescriptionKey : @"No GNUstep audio backend is installed." }];
  return NO;
#endif
}
- (void)useInternalSynthesizer
{
#if defined(__APPLE__)
  [self stop];
  [_instrument release];
  _instrument = nil;
  [_instrumentDescription release];
  _instrumentDescription = nil;
#endif
}
- (void)loadAudioUnitInstrument:(NSDictionary *)description
                     completion:(ScoreAudioUnitLoadCompletion)completion
{
#if defined(__APPLE__)
  if ([[self class] isAudioUnitBlacklisted:description])
    {
      if (completion)
        completion (NO, [NSError errorWithDomain:@"ScoreMakerDSP"
                                             code:4
                                         userInfo:@{
                                           NSLocalizedDescriptionKey :
                                             @"This Audio Unit is blacklisted after repeated failures."
                                         }]);
      return;
    }
  AudioComponentDescription component
    = { [[description objectForKey:@"type"] unsignedIntValue],
        [[description objectForKey:@"subtype"] unsignedIntValue],
        [[description objectForKey:@"manufacturerCode"] unsignedIntValue],
        0,
        0 };
  NSDictionary *savedDescription = [description copy];
  __block BOOL completed = NO;
  dispatch_after (
    dispatch_time (DISPATCH_TIME_NOW, (int64_t)(SCORE_AUDIO_UNIT_TIMEOUT * NSEC_PER_SEC)),
    dispatch_get_main_queue (), ^{
      if (completed)
        return;
      completed = YES;
      [[self class] recordAudioUnitFailure:description];
      if (completion)
        completion (NO, [NSError errorWithDomain:@"ScoreMakerDSP"
                                             code:5
                                         userInfo:@{
                                           NSLocalizedDescriptionKey :
                                             @"Audio Unit validation timed out. It may be unstable or incompatible."
                                         }]);
    });
  [AVAudioUnit
    instantiateWithComponentDescription:component
                                options:kAudioComponentInstantiation_LoadOutOfProcess
                      completionHandler:^(AVAudioUnit *unit, NSError *error) {
                        dispatch_async (dispatch_get_main_queue (), ^{
                          if (completed)
                            {
                              [savedDescription release];
                              return;
                            }
                          completed = YES;
                          if (!unit || ![unit isKindOfClass:[AVAudioUnitMIDIInstrument class]])
                            {
                              NSError *loadError = error;
                              if (!loadError)
                                loadError = [NSError
                                  errorWithDomain:@"ScoreMakerDSP"
                                             code:2
                                         userInfo:@{
                                           NSLocalizedDescriptionKey :
                                             @"The selected Audio Unit is not a MIDI instrument."
                                         }];
                              [[self class] recordAudioUnitFailure:description];
                              [savedDescription release];
                              if (completion)
                                completion (NO, loadError);
                              return;
                            }
                          [self stop];
                          [_instrument release];
                          _instrument = [(AVAudioUnitMIDIInstrument *)unit retain];
                          [_instrumentDescription release];
                          _instrumentDescription = savedDescription;
                          NSDictionary *state = [description objectForKey:@"state"];
                          if (state)
                            [[_instrument AUAudioUnit] setFullState:state];
                          NSError *startError = nil;
                          BOOL success = [self startWithError:&startError];
                          if (success)
                            [[self class] clearAudioUnitFailures:description];
                          else
                            [[self class] recordAudioUnitFailure:description];
                          if (completion)
                            completion (success, startError);
                        });
                      }];
#else
  (void)description;
  (void)completion;
#endif
}
- (NSDictionary *)audioUnitInstrumentDescription
{
#if defined(__APPLE__)
  return _instrumentDescription;
#else
  return nil;
#endif
}
- (NSDictionary *)audioUnitFullState
{
#if defined(__APPLE__)
  return _instrument ? [[_instrument AUAudioUnit] fullState] : nil;
#else
  return nil;
#endif
}
- (NSArray *)audioUnitParameters
{
#if defined(__APPLE__)
  NSMutableArray *result = [NSMutableArray array];
  for (AUParameter *parameter in [[[_instrument AUAudioUnit] parameterTree] allParameters])
    [result addObject:@{
      @"address" : [NSNumber numberWithUnsignedLongLong:[parameter address]],
      @"name" : [parameter displayName] ?: [parameter identifier] ?: @"Parameter",
      @"identifier" : [parameter identifier] ?: @"",
      @"value" : [NSNumber numberWithFloat:[parameter value]],
      @"minimum" : [NSNumber numberWithFloat:[parameter minValue]],
      @"maximum" : [NSNumber numberWithFloat:[parameter maxValue]],
      @"unit" : [parameter unitName] ?: @""
    }];
  return result;
#else
  return [NSArray array];
#endif
}
- (BOOL)setAudioUnitParameter:(uint64_t)address value:(double)value error:(NSError **)error
{
#if defined(__APPLE__)
  AUParameter *parameter = [[[_instrument AUAudioUnit] parameterTree] parameterWithAddress:address];
  if (!parameter)
    {
      if (error)
        *error = [NSError errorWithDomain:@"ScoreMakerDSP"
                                     code:6
                                 userInfo:@{
                                   NSLocalizedDescriptionKey : @"The Audio Unit parameter is unavailable."
                                 }];
      return NO;
    }
  [parameter setValue:(AUValue)value originator:nil];
  return YES;
#else
  (void)address;
  (void)value;
  (void)error;
  return NO;
#endif
}
- (void)requestAudioUnitViewController:(ScoreAudioUnitViewCompletion)completion
{
#if defined(__APPLE__)
  if (!_instrument)
    {
      if (completion)
        completion (nil, [NSError errorWithDomain:@"ScoreMakerDSP"
                                              code:7
                                          userInfo:@{
                                            NSLocalizedDescriptionKey : @"No Audio Unit is loaded."
                                          }]);
      return;
    }
  [[_instrument AUAudioUnit]
    requestViewControllerWithCompletionHandler:^(NSViewController *controller) {
      dispatch_async (dispatch_get_main_queue (), ^{
        if (completion)
          completion (controller ?: [self legacyAudioUnitViewController], nil);
      });
    }];
#else
  (void)completion;
#endif
}
- (NSViewController *)legacyAudioUnitViewController
{
#if defined(__APPLE__)
  if (!_instrument)
    return nil;
  UInt32 size = 0;
  Boolean writable = false;
  AudioUnit audioUnit = [_instrument audioUnit];
  if (AudioUnitGetPropertyInfo (audioUnit, kAudioUnitProperty_CocoaUI,
                                kAudioUnitScope_Global, 0, &size, &writable) != noErr
      || size < sizeof (AudioUnitCocoaViewInfo))
    return nil;
  AudioUnitCocoaViewInfo *info = malloc (size);
  if (!info)
    return nil;
  if (AudioUnitGetProperty (audioUnit, kAudioUnitProperty_CocoaUI, kAudioUnitScope_Global, 0,
                            info, &size) != noErr)
    {
      free (info);
      return nil;
    }
  NSViewController *controller = nil;
  NSBundle *bundle = [NSBundle bundleWithURL:(NSURL *)info->mCocoaAUViewBundleLocation];
  UInt32 classCount = (size - sizeof (CFURLRef)) / sizeof (CFStringRef);
  if ([bundle load])
    for (UInt32 index = 0; index < classCount; index++)
      {
        Class factoryClass = NSClassFromString ((NSString *)info->mCocoaAUViewClass[index]);
        id factory = [[[factoryClass alloc] init] autorelease];
        if (![factory respondsToSelector:@selector (uiViewForAudioUnit:withSize:)])
          continue;
        NSView *view = [factory uiViewForAudioUnit:audioUnit withSize:NSMakeSize (640, 480)];
        if (view)
          {
            controller = [[[NSViewController alloc] init] autorelease];
            [controller setView:view];
            break;
          }
      }
  free (info);
  return controller;
#else
  return nil;
#endif
}
- (BOOL)saveUserPreset:(NSString *)name error:(NSError **)error
{
#if defined(__APPLE__)
  NSDictionary *state = [self audioUnitFullState];
  NSDictionary *description = [self audioUnitInstrumentDescription];
  if (!state || !description || ![name length])
    {
      if (error)
        *error = [NSError errorWithDomain:@"ScoreMakerDSP"
                                     code:8
                                 userInfo:@{
                                   NSLocalizedDescriptionKey : @"Enter a name for the Audio Unit preset."
                                 }];
      return NO;
    }
  NSDictionary *preset = @{ @"version" : @1, @"description" : description, @"state" : state };
  NSData *data = [NSPropertyListSerialization dataWithPropertyList:preset
                                                            format:NSPropertyListBinaryFormat_v1_0
                                                           options:0
                                                             error:error];
  if (!data)
    return NO;
  NSString *filename = [[[name lastPathComponent] stringByDeletingPathExtension]
    stringByAppendingPathExtension:@"aupreset"];
  NSURL *url = [[[self class] presetDirectoryForAudioUnit:description create:YES]
    URLByAppendingPathComponent:filename];
  return [data writeToURL:url options:NSDataWritingAtomic error:error];
#else
  (void)name;
  (void)error;
  return NO;
#endif
}
- (BOOL)loadUserPreset:(NSString *)name error:(NSError **)error
{
#if defined(__APPLE__)
  NSDictionary *description = [self audioUnitInstrumentDescription];
  if (!description || ![name length])
    {
      if (error)
        *error = [NSError errorWithDomain:@"ScoreMakerDSP"
                                     code:9
                                 userInfo:@{
                                   NSLocalizedDescriptionKey : @"Select an Audio Unit preset to load."
                                 }];
      return NO;
    }
  NSString *filename = [[[name lastPathComponent] stringByDeletingPathExtension]
    stringByAppendingPathExtension:@"aupreset"];
  NSURL *url = [[[self class] presetDirectoryForAudioUnit:description create:NO]
    URLByAppendingPathComponent:filename];
  NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
  if (!data)
    return NO;
  NSDictionary *preset = [NSPropertyListSerialization propertyListWithData:data
                                                                   options:NSPropertyListImmutable
                                                                    format:NULL
                                                                     error:error];
  NSDictionary *state = [preset objectForKey:@"state"];
  if (!state)
    return NO;
  [[_instrument AUAudioUnit] setFullState:state];
  return YES;
#else
  (void)name;
  (void)error;
  return NO;
#endif
}
- (BOOL)configureEffects:(NSArray *)effects error:(NSError **)error
{
  NSSet *supported = [NSSet setWithObjects:@"gain", @"lowpass", @"compressor", @"delay",
                                           @"reverb", nil];
  for (NSDictionary *effect in effects)
    if (![supported containsObject:[effect objectForKey:@"type"]])
      {
        if (error)
          *error = [NSError
            errorWithDomain:@"ScoreMakerDSP"
                       code:11
                   userInfo:@{
                     NSLocalizedDescriptionKey :
                       [NSString stringWithFormat:@"Unsupported effect type: %@",
                                                  [effect objectForKey:@"type"] ?: @"(missing)"]
                   }];
        return NO;
      }
  BOOL restart = _running;
  if (restart)
    [self stop];
  [_effectConfiguration release];
  _effectConfiguration = [[NSArray alloc] initWithArray:effects copyItems:YES];
  _dsp->gain = 1.0f;
  _dsp->lowpassCoefficient = 0.0f;
  _dsp->compressorThreshold = 1.0f;
  _dsp->compressorRatio = 1.0f;
  _dsp->delayFrames = 0;
  _dsp->delayMix = 0.0f;
  _dsp->delayFeedback = 0.0f;
  _dsp->reverbFrames = 0;
  _dsp->reverbMix = 0.0f;
  _dsp->reverbFeedback = 0.0f;
  for (NSDictionary *effect in effects)
    {
      if ([[effect objectForKey:@"bypass"] boolValue])
        continue;
      NSString *type = [effect objectForKey:@"type"];
      if ([type isEqualToString:@"gain"])
        _dsp->gain = powf (10.0f, [[effect objectForKey:@"decibels"] floatValue] / 20.0f);
      else if ([type isEqualToString:@"lowpass"])
        {
          float cutoff = MAX (20.0f, MIN (20000.0f,
                                          [[effect objectForKey:@"cutoff"] floatValue] ?: 12000.0f));
          _dsp->lowpassCoefficient = 1.0f - expf (-2.0f * (float)M_PI * cutoff
                                                  / (float)_dsp->sampleRate);
        }
      else if ([type isEqualToString:@"compressor"])
        {
          float thresholdDB = [[effect objectForKey:@"threshold"] floatValue];
          _dsp->compressorThreshold = powf (10.0f, thresholdDB / 20.0f);
          _dsp->compressorRatio = MAX (1.0f, [[effect objectForKey:@"ratio"] floatValue]);
        }
      else if ([type isEqualToString:@"delay"])
        {
          double seconds = MAX (0.001, MIN (2.0, [[effect objectForKey:@"time"] doubleValue]));
          _dsp->delayFrames = MIN (_dsp->delayCapacity,
                                  MAX ((NSUInteger)1,
                                       (NSUInteger)llround (seconds * _dsp->sampleRate)));
          _dsp->delayMix = MAX (0.0f, MIN (1.0f, [[effect objectForKey:@"mix"] floatValue]));
          _dsp->delayFeedback =
            MAX (0.0f, MIN (0.95f, [[effect objectForKey:@"feedback"] floatValue]));
        }
      else if ([type isEqualToString:@"reverb"])
        {
          double room = MAX (0.05, MIN (0.75, [[effect objectForKey:@"roomSize"] doubleValue]));
          _dsp->reverbFrames = MIN (_dsp->reverbCapacity,
                                   MAX ((NSUInteger)1,
                                        (NSUInteger)llround (room * _dsp->sampleRate)));
          _dsp->reverbMix = MAX (0.0f, MIN (1.0f, [[effect objectForKey:@"mix"] floatValue]));
          _dsp->reverbFeedback =
            MAX (0.0f, MIN (0.92f, 0.45f + (float)room * 0.55f));
        }
    }
  memset (_dsp->delayLeft, 0, _dsp->delayCapacity * sizeof (float));
  memset (_dsp->delayRight, 0, _dsp->delayCapacity * sizeof (float));
  memset (_dsp->reverbLeft, 0, _dsp->reverbCapacity * sizeof (float));
  memset (_dsp->reverbRight, 0, _dsp->reverbCapacity * sizeof (float));
  _dsp->delayIndex = 0;
  _dsp->reverbIndex = 0;
  if (restart && ![self startWithError:error])
    return NO;
  return YES;
}
- (BOOL)configureEffectsFromGraph:(ScoreSynthesisGraph *)graph error:(NSError **)error
{
  NSArray *order = [ScoreSynthesisCompiler processingOrderForGraph:graph error:error];
  if (!order)
    return NO;
  NSMutableArray *effects = [NSMutableArray array];
  for (ScoreSynthesisNode *node in order)
    if ([[[self class] supportedEffectTypes]
          indexOfObjectPassingTest:^BOOL (NSDictionary *item, NSUInteger index, BOOL *stop) {
            (void)index;
            (void)stop;
            return [[item objectForKey:@"identifier"] isEqualToString:[node typeIdentifier]];
          }] != NSNotFound)
      {
        NSMutableDictionary *effect =
          [NSMutableDictionary dictionaryWithDictionary:[node parameters]];
        [effect setObject:[node typeIdentifier] forKey:@"type"];
        [effect setObject:[node identifier] forKey:@"nodeIdentifier"];
        [effects addObject:effect];
      }
  return [self configureEffects:effects error:error];
}
- (NSArray *)effectConfiguration
{
  return _effectConfiguration;
}
- (NSDictionary *)internalSynthPatch
{
  return _internalSynthPatch;
}
- (BOOL)configureInternalSynthPatch:(NSDictionary *)patch error:(NSError **)error
{
  NSDictionary *defaults = [[self class] defaultInternalSynthPatch];
  NSString *waveform = [patch objectForKey:@"waveform"] ?: [defaults objectForKey:@"waveform"];
  NSArray *waveforms = @[ @"Sine", @"Triangle", @"Saw", @"Square" ];
  NSUInteger waveformIndex = [waveforms indexOfObject:waveform];
  if (waveformIndex == NSNotFound)
    {
      if (error)
        *error = [NSError errorWithDomain:@"ScoreMakerDSP"
                                     code:12
                                 userInfo:@{
                                   NSLocalizedDescriptionKey : @"The oscillator waveform is invalid."
                                 }];
      return NO;
    }
  float attack = MAX (0.0f, MIN (10.0f, ScoreDSPPatchFloat (patch, defaults, @"attack")));
  float decay = MAX (0.0f, MIN (10.0f, ScoreDSPPatchFloat (patch, defaults, @"decay")));
  float sustain = MAX (0.0f, MIN (1.0f, ScoreDSPPatchFloat (patch, defaults, @"sustain")));
  float release = MAX (0.0f, MIN (20.0f, ScoreDSPPatchFloat (patch, defaults, @"release")));
  float lfoRate = MAX (0.01f, MIN (40.0f, ScoreDSPPatchFloat (patch, defaults, @"lfoRate")));
  float lfoDepth = MAX (0.0f, MIN (12.0f, ScoreDSPPatchFloat (patch, defaults, @"lfoDepth")));
  float lfoDelay = MAX (0.0f, MIN (10.0f, ScoreDSPPatchFloat (patch, defaults, @"lfoDelay")));
  NSDictionary *normalized = @{ @"waveform" : waveform,
                                @"attack" : [NSNumber numberWithFloat:attack],
                                @"decay" : [NSNumber numberWithFloat:decay],
                                @"sustain" : [NSNumber numberWithFloat:sustain],
                                @"release" : [NSNumber numberWithFloat:release],
                                @"lfoRate" : [NSNumber numberWithFloat:lfoRate],
                                @"lfoDepth" : [NSNumber numberWithFloat:lfoDepth],
                                @"lfoDelay" : [NSNumber numberWithFloat:lfoDelay] };
  [_internalSynthPatch release];
  _internalSynthPatch = [normalized copy];
  ScoreDSPStorePatch (_dsp, (ScoreDSPPatch){ (int)waveformIndex, attack, decay, sustain, release,
                                             lfoRate, lfoDepth, lfoDelay });
  return YES;
}
- (void)stop
{
#if defined(__APPLE__)
  if (_engine)
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVAudioEngineConfigurationChangeNotification
                                                  object:_engine];
  [_engine stop];
  [_source release];
  _source = nil;
  [_engineEffectNodes release];
  _engineEffectNodes = nil;
  [_engine release];
  _engine = nil;
#endif
  _running = NO;
}
- (void)audioEngineConfigurationChanged:(NSNotification *)notification
{
#if defined(__APPLE__)
  (void)notification;
  if (!_instrument)
    return;
  AVAudioEngine *observedEngine = _engine;
  dispatch_after (dispatch_time (DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                  dispatch_get_main_queue (), ^{
    if (_engine != observedEngine || [_engine isRunning])
      return;
    NSError *restartError = nil;
    if ([_engine startAndReturnError:&restartError])
      return;
    NSDictionary *failedDescription = [[_instrumentDescription retain] autorelease];
    [[self class] recordAudioUnitFailure:failedDescription];
    [self useInternalSynthesizer];
    [self startWithError:NULL];
  });
#else
  (void)notification;
#endif
}
- (BOOL)isRunning
{
  return _running;
}
- (void)noteOn:(NSInteger)pitch velocity:(NSUInteger)velocity
{
#if defined(__APPLE__)
  if (_instrument)
    {
      [_instrument sendMIDIEvent:0x90 data1:(UInt8)pitch data2:(UInt8)MIN (127, velocity)];
      return;
    }
#endif
  ScoreDSPPush (_dsp, (int)pitch, (float)MIN ((NSUInteger)127, velocity) / 127.0f, YES);
}
- (void)noteOff:(NSInteger)pitch
{
#if defined(__APPLE__)
  if (_instrument)
    {
      [_instrument sendMIDIEvent:0x80 data1:(UInt8)pitch data2:0];
      return;
    }
#endif
  ScoreDSPPush (_dsp, (int)pitch, 0, NO);
}
- (void)allNotesOff
{
  for (NSInteger pitch = 0; pitch < 128; pitch++)
    [self noteOff:pitch];
}
- (BOOL)scheduleEvents:(NSArray *)events error:(NSError **)error
{
#if defined(__APPLE__)
  [self stop];
  free (_dsp->scheduledEvents);
  _dsp->scheduledEvents = NULL;
  _dsp->scheduledEventCount = [events count];
  _dsp->scheduledEventIndex = 0;
  _dsp->renderedFrames = 0;
  memset (_dsp->voices, 0, sizeof (_dsp->voices));
  if ([events count])
    _dsp->scheduledEvents = calloc ([events count], sizeof (ScoreDSPEvent));
  for (NSUInteger index = 0; index < [events count]; index++)
    {
      NSDictionary *item = [events objectAtIndex:index];
      _dsp->scheduledEvents[index] = (ScoreDSPEvent){
        [[item objectForKey:@"pitch"] intValue],
        [[item objectForKey:@"velocity"] floatValue] / 127.0f,
        [[item objectForKey:@"on"] boolValue],
        (uint64_t)llround ([[item objectForKey:@"time"] doubleValue] * _dsp->sampleRate)
      };
    }
  if (![self startWithError:error])
    return NO;
  if (_instrument)
    {
      AUScheduleMIDIEventBlock schedule = [[_instrument AUAudioUnit] scheduleMIDIEventBlock];
      if (!schedule)
        {
          if (error)
            *error =
              [NSError errorWithDomain:@"ScoreMakerDSP"
                                  code:3
                              userInfo:@{
                                NSLocalizedDescriptionKey :
                                  @"The Audio Unit does not expose timestamped MIDI scheduling."
                              }];
          return NO;
        }
      for (NSUInteger index = 0; index < _dsp->scheduledEventCount; index++)
        {
          ScoreDSPEvent event = _dsp->scheduledEvents[index];
          uint8_t midi[3] = { event.on ? 0x90 : 0x80, (uint8_t)event.pitch,
                              event.on ? (uint8_t)lrintf (event.velocity * 127.0f) : 0 };
          schedule ((AUEventSampleTime)event.sampleFrame, 0, 3, midi);
        }
    }
  return YES;
#else
  (void)events;
  if (error)
    *error =
      [NSError errorWithDomain:@"ScoreMakerDSP"
                          code:1
                      userInfo:@{ NSLocalizedDescriptionKey : @"DSP scheduling is unavailable." }];
  return NO;
#endif
}
- (BOOL)renderEvents:(NSArray *)events
            duration:(NSTimeInterval)duration
               toURL:(NSURL *)url
               error:(NSError **)error
{
#if defined(__APPLE__)
  const double sampleRate = 48000.0;
  AVAudioFormat *format = [[[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate
                                                                          channels:2] autorelease];
  NSMutableDictionary *fileSettings =
    [NSMutableDictionary dictionaryWithDictionary:[format settings]];
  [fileSettings removeObjectForKey:AVLinearPCMIsNonInterleavedKey];
  AVAudioFile *file = [[[AVAudioFile alloc] initForWriting:url settings:fileSettings
                                                     error:error] autorelease];
  if (!file)
    return NO;
  ScoreDSPState state = { 0 };
  ScoreDSPInitializeEffects (&state, sampleRate);
  ScoreDSPStorePatch (&state, ScoreDSPLoadPatch (_dsp));
  state.gain = _dsp->gain;
  state.lowpassCoefficient = _dsp->lowpassCoefficient;
  state.compressorThreshold = _dsp->compressorThreshold;
  state.compressorRatio = _dsp->compressorRatio;
  state.delayFrames = _dsp->delayFrames;
  state.delayMix = _dsp->delayMix;
  state.delayFeedback = _dsp->delayFeedback;
  state.reverbFrames = _dsp->reverbFrames;
  state.reverbMix = _dsp->reverbMix;
  state.reverbFeedback = _dsp->reverbFeedback;
  state.scheduledEventCount = [events count];
  state.scheduledEvents = calloc (MAX ((NSUInteger)1, [events count]), sizeof (ScoreDSPEvent));
  for (NSUInteger index = 0; index < [events count]; index++)
    {
      NSDictionary *item = [events objectAtIndex:index];
      state.scheduledEvents[index] = (ScoreDSPEvent){
        [[item objectForKey:@"pitch"] intValue],
        [[item objectForKey:@"velocity"] floatValue] / 127.0f,
        [[item objectForKey:@"on"] boolValue],
        (uint64_t)llround ([[item objectForKey:@"time"] doubleValue] * sampleRate)
      };
    }
  uint64_t framesRemaining = (uint64_t)ceil (MAX (0.0, duration) * sampleRate);
  while (framesRemaining)
    {
      AVAudioFrameCount count = (AVAudioFrameCount)MIN ((uint64_t)4096, framesRemaining);
      AVAudioPCMBuffer *buffer = [[[AVAudioPCMBuffer alloc] initWithPCMFormat:format
                                                                frameCapacity:count] autorelease];
      [buffer setFrameLength:count];
      ScoreDSPRender (&state, [buffer floatChannelData][0], [buffer floatChannelData][1], count);
      if (![file writeFromBuffer:buffer error:error])
        {
          free (state.scheduledEvents);
          ScoreDSPDisposeEffects (&state);
          return NO;
        }
      framesRemaining -= count;
    }
  free (state.scheduledEvents);
  ScoreDSPDisposeEffects (&state);
  return YES;
#else
  (void)events;
  (void)duration;
  (void)url;
  if (error)
    *error = [NSError
      errorWithDomain:@"ScoreMakerDSP"
                 code:1
             userInfo:@{ NSLocalizedDescriptionKey : @"Offline rendering is unavailable." }];
  return NO;
#endif
}
- (BOOL)renderPitches:(NSArray *)pitches
             duration:(NSTimeInterval)duration
                toURL:(NSURL *)url
                error:(NSError **)error
{
  NSMutableArray *events = [NSMutableArray array];
  for (NSNumber *pitch in pitches)
    {
      [events addObject:@{ @"time" : @0, @"pitch" : pitch, @"velocity" : @96, @"on" : @YES }];
      [events addObject:@{
        @"time" : [NSNumber numberWithDouble:duration],
        @"pitch" : pitch,
        @"velocity" : @0,
        @"on" : @NO
      }];
    }
  return [self renderEvents:events duration:duration + 0.5 toURL:url error:error];
}
- (void)dealloc
{
  [self stop];
#if defined(__APPLE__)
  [_instrument release];
  [_instrumentDescription release];
#endif
  [_effectConfiguration release];
  [_internalSynthPatch release];
  free (_dsp->scheduledEvents);
  ScoreDSPDisposeEffects (_dsp);
  free (_dsp);
  [super dealloc];
}
@end
