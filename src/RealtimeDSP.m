/* Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 * ScoreMaker is distributed under the GNU LGPL version 2.1 or later.
 */
#import "RealtimeDSP.h"
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
  float level;
  float velocity;
  BOOL active;
  BOOL releasing;
} ScoreDSPVoice;
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
} ScoreDSPState;

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
      *v = (ScoreDSPVoice){ e.pitch, 0, 0, e.velocity, YES, NO };
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
          float target = v->releasing ? 0.0f : v->velocity;
          float rate = v->releasing ? 0.0008f : 0.0025f;
          v->level += (target - v->level) * rate;
          if (v->releasing && v->level < 0.0001f)
            {
              v->active = NO;
              continue;
            }
          double hz = 440.0 * pow (2.0, (v->pitch - 69) / 12.0);
          mix += sin (v->phase) * v->level;
          v->phase += 2.0 * M_PI * hz / s->sampleRate;
          if (v->phase >= 2.0 * M_PI)
            v->phase -= 2.0 * M_PI;
        }
      float sample = (float)tanh (mix * 0.22);
      left[f] = sample;
      right[f] = sample;
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
#endif
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
      _dsp->sampleRate = 48000;
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
      [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector (audioEngineConfigurationChanged:)
               name:AVAudioEngineConfigurationChangeNotification
             object:_engine];
      [_engine attachNode:_instrument];
      [_engine connect:_instrument to:[_engine mainMixerNode] format:nil];
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
  state.sampleRate = sampleRate;
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
          return NO;
        }
      framesRemaining -= count;
    }
  free (state.scheduledEvents);
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
  free (_dsp->scheduledEvents);
  free (_dsp);
  [super dealloc];
}
@end
