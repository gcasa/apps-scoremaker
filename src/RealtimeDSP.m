/* Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 * ScoreMaker is distributed under the GNU LGPL version 2.1 or later.
 */
#import "RealtimeDSP.h"
#import <math.h>
#import <stdatomic.h>
#if defined(__APPLE__)
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#endif

#define SCORE_DSP_VOICES 64
#define SCORE_DSP_EVENTS 1024
typedef struct
{
  int pitch;
  float velocity;
  BOOL on;
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
} ScoreDSPState;

static void
ScoreDSPPush (ScoreDSPState *s, int pitch, float velocity, BOOL on)
{
  unsigned write = atomic_load_explicit (&s->writeIndex, memory_order_relaxed);
  unsigned next = (write + 1) % SCORE_DSP_EVENTS;
  if (next == atomic_load_explicit (&s->readIndex, memory_order_acquire))
    return;
  s->events[write] = (ScoreDSPEvent){ pitch, velocity, on };
  atomic_store_explicit (&s->writeIndex, next, memory_order_release);
}
static void
ScoreDSPApplyEvents (ScoreDSPState *s)
{
  unsigned read = atomic_load_explicit (&s->readIndex, memory_order_relaxed);
  unsigned write = atomic_load_explicit (&s->writeIndex, memory_order_acquire);
  while (read != write)
    {
      ScoreDSPEvent e = s->events[read];
      read = (read + 1) % SCORE_DSP_EVENTS;
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
  atomic_store_explicit (&s->readIndex, read, memory_order_release);
}
static void
ScoreDSPRender (ScoreDSPState *s, float *left, float *right, NSUInteger frames)
{
  ScoreDSPApplyEvents (s);
  for (NSUInteger f = 0; f < frames; f++)
    {
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
    }
}

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
                      @"manufacturerCode", nil]];
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
  AudioComponentDescription component
    = { [[description objectForKey:@"type"] unsignedIntValue],
        [[description objectForKey:@"subtype"] unsignedIntValue],
        [[description objectForKey:@"manufacturerCode"] unsignedIntValue],
        0,
        0 };
  NSDictionary *savedDescription = [description copy];
  [AVAudioUnit
    instantiateWithComponentDescription:component
                                options:kAudioComponentInstantiation_LoadOutOfProcess
                      completionHandler:^(AVAudioUnit *unit, NSError *error) {
                        dispatch_async (dispatch_get_main_queue (), ^{
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
- (void)stop
{
#if defined(__APPLE__)
  [_engine stop];
  [_source release];
  _source = nil;
  [_engine release];
  _engine = nil;
#endif
  _running = NO;
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
- (BOOL)renderPitches:(NSArray *)pitches
             duration:(NSTimeInterval)duration
                toURL:(NSURL *)url
                error:(NSError **)error
{
  return NO;
}
- (void)dealloc
{
  [self stop];
#if defined(__APPLE__)
  [_instrument release];
  [_instrumentDescription release];
#endif
  free (_dsp);
  [super dealloc];
}
@end
