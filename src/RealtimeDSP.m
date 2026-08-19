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
#define SCORE_DSP_EVENTS 4096
#define SCORE_DSP_PATCHES 16
#define SCORE_AUDIO_UNIT_TIMEOUT 12.0
static NSString *const ScoreAudioUnitBlacklistDefaultsKey = @"ScoreAudioUnitBlacklist";
static NSString *const ScoreAudioUnitFailureDefaultsKey = @"ScoreAudioUnitFailures";
typedef struct
{
  int pitch;
  double frequency;
  int track;
  int notationVoice;
  float velocity;
  float pan;
  BOOL on;
  uint64_t sampleFrame;
} ScoreDSPEvent;
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
  float filterCutoff;
  float filterResonance;
  float filterAttack;
  float filterDecay;
  float filterSustain;
  float filterRelease;
  float filterEnvelopeAmount;
  float velocityToAmplitude;
  float velocityToFilter;
} ScoreDSPPatch;
typedef struct
{
  int pitch;
  double frequency;
  int track;
  int notationVoice;
  double phase;
  double lfoPhase;
  uint64_t ageFrames;
  float envelopeLevel;
  float releaseRate;
  float filterEnvelopeLevel;
  float filterReleaseRate;
  float filterLow;
  float filterBand;
  float velocity;
  float pan;
  int envelopeStage;
  int filterEnvelopeStage;
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
  _Atomic(int) patchWaveform[SCORE_DSP_PATCHES];
  _Atomic(float) patchAttack[SCORE_DSP_PATCHES];
  _Atomic(float) patchDecay[SCORE_DSP_PATCHES];
  _Atomic(float) patchSustain[SCORE_DSP_PATCHES];
  _Atomic(float) patchRelease[SCORE_DSP_PATCHES];
  _Atomic(float) patchLFORate[SCORE_DSP_PATCHES];
  _Atomic(float) patchLFODepth[SCORE_DSP_PATCHES];
  _Atomic(float) patchLFODelay[SCORE_DSP_PATCHES];
  _Atomic(float) patchFilterCutoff[SCORE_DSP_PATCHES];
  _Atomic(float) patchFilterResonance[SCORE_DSP_PATCHES];
  _Atomic(float) patchFilterAttack[SCORE_DSP_PATCHES];
  _Atomic(float) patchFilterDecay[SCORE_DSP_PATCHES];
  _Atomic(float) patchFilterSustain[SCORE_DSP_PATCHES];
  _Atomic(float) patchFilterRelease[SCORE_DSP_PATCHES];
  _Atomic(float) patchFilterEnvelopeAmount[SCORE_DSP_PATCHES];
  _Atomic(float) patchVelocityToAmplitude[SCORE_DSP_PATCHES];
  _Atomic(float) patchVelocityToFilter[SCORE_DSP_PATCHES];
  float voiceGain[SCORE_DSP_PATCHES];
  float voiceLowpassCoefficient[SCORE_DSP_PATCHES];
  float voiceLowpassLeft[SCORE_DSP_PATCHES];
  float voiceLowpassRight[SCORE_DSP_PATCHES];
  float voiceCompressorThreshold[SCORE_DSP_PATCHES];
  float voiceCompressorRatio[SCORE_DSP_PATCHES];
  float voiceDelayMix[SCORE_DSP_PATCHES];
  float voiceDelayFeedback[SCORE_DSP_PATCHES];
  NSUInteger voiceDelayFrames[SCORE_DSP_PATCHES];
  NSUInteger voiceDelayIndex[SCORE_DSP_PATCHES];
  float *voiceDelayLeft[SCORE_DSP_PATCHES];
  float *voiceDelayRight[SCORE_DSP_PATCHES];
  float voiceReverbMix[SCORE_DSP_PATCHES];
  float voiceReverbFeedback[SCORE_DSP_PATCHES];
  NSUInteger voiceReverbFrames[SCORE_DSP_PATCHES];
  NSUInteger voiceReverbIndex[SCORE_DSP_PATCHES];
  float *voiceReverbLeft[SCORE_DSP_PATCHES];
  float *voiceReverbRight[SCORE_DSP_PATCHES];
} ScoreDSPState;

static ScoreDSPPatch
ScoreDSPLoadPatch (ScoreDSPState *state, NSInteger voice)
{
  NSUInteger index = (NSUInteger)MAX (1, MIN (SCORE_DSP_PATCHES, voice)) - 1;
  return (ScoreDSPPatch){ atomic_load_explicit (&state->patchWaveform[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchAttack[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchDecay[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchSustain[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchRelease[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchLFORate[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchLFODepth[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchLFODelay[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchFilterCutoff[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchFilterResonance[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchFilterAttack[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchFilterDecay[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchFilterSustain[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchFilterRelease[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchFilterEnvelopeAmount[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchVelocityToAmplitude[index], memory_order_acquire),
                          atomic_load_explicit (&state->patchVelocityToFilter[index], memory_order_acquire) };
}

static void
ScoreDSPStorePatch (ScoreDSPState *state, NSInteger voice, ScoreDSPPatch patch)
{
  NSUInteger index = (NSUInteger)MAX (1, MIN (SCORE_DSP_PATCHES, voice)) - 1;
  atomic_store_explicit (&state->patchWaveform[index], patch.waveform, memory_order_release);
  atomic_store_explicit (&state->patchAttack[index], patch.attack, memory_order_release);
  atomic_store_explicit (&state->patchDecay[index], patch.decay, memory_order_release);
  atomic_store_explicit (&state->patchSustain[index], patch.sustain, memory_order_release);
  atomic_store_explicit (&state->patchRelease[index], patch.release, memory_order_release);
  atomic_store_explicit (&state->patchLFORate[index], patch.lfoRate, memory_order_release);
  atomic_store_explicit (&state->patchLFODepth[index], patch.lfoDepth, memory_order_release);
  atomic_store_explicit (&state->patchLFODelay[index], patch.lfoDelay, memory_order_release);
  atomic_store_explicit (&state->patchFilterCutoff[index], patch.filterCutoff, memory_order_release);
  atomic_store_explicit (&state->patchFilterResonance[index], patch.filterResonance, memory_order_release);
  atomic_store_explicit (&state->patchFilterAttack[index], patch.filterAttack, memory_order_release);
  atomic_store_explicit (&state->patchFilterDecay[index], patch.filterDecay, memory_order_release);
  atomic_store_explicit (&state->patchFilterSustain[index], patch.filterSustain, memory_order_release);
  atomic_store_explicit (&state->patchFilterRelease[index], patch.filterRelease, memory_order_release);
  atomic_store_explicit (&state->patchFilterEnvelopeAmount[index], patch.filterEnvelopeAmount, memory_order_release);
  atomic_store_explicit (&state->patchVelocityToAmplitude[index], patch.velocityToAmplitude, memory_order_release);
  atomic_store_explicit (&state->patchVelocityToFilter[index], patch.velocityToFilter, memory_order_release);
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
  for (NSInteger voice = 1; voice <= SCORE_DSP_PATCHES; voice++)
    {
      NSUInteger index = (NSUInteger)voice - 1;
      atomic_init (&state->patchWaveform[index], 0);
      atomic_init (&state->patchAttack[index], 0.01f);
      atomic_init (&state->patchDecay[index], 0.12f);
      atomic_init (&state->patchSustain[index], 0.78f);
      atomic_init (&state->patchRelease[index], 0.28f);
      atomic_init (&state->patchLFORate[index], 5.0f);
      atomic_init (&state->patchLFODepth[index], 0.0f);
      atomic_init (&state->patchLFODelay[index], 0.0f);
      atomic_init (&state->patchFilterCutoff[index], 12000.0f);
      atomic_init (&state->patchFilterResonance[index], 0.0f);
      atomic_init (&state->patchFilterAttack[index], 0.01f);
      atomic_init (&state->patchFilterDecay[index], 0.15f);
      atomic_init (&state->patchFilterSustain[index], 0.0f);
      atomic_init (&state->patchFilterRelease[index], 0.25f);
      atomic_init (&state->patchFilterEnvelopeAmount[index], 0.0f);
      atomic_init (&state->patchVelocityToAmplitude[index], 1.0f);
      atomic_init (&state->patchVelocityToFilter[index], 0.0f);
      state->voiceGain[index] = 1.0f;
      state->voiceCompressorThreshold[index] = 1.0f;
      state->voiceCompressorRatio[index] = 1.0f;
      state->voiceDelayLeft[index] = calloc (state->delayCapacity, sizeof (float));
      state->voiceDelayRight[index] = calloc (state->delayCapacity, sizeof (float));
      state->voiceReverbLeft[index] = calloc (state->reverbCapacity, sizeof (float));
      state->voiceReverbRight[index] = calloc (state->reverbCapacity, sizeof (float));
    }
}

static void
ScoreDSPDisposeEffects (ScoreDSPState *state)
{
  free (state->delayLeft);
  free (state->delayRight);
  free (state->reverbLeft);
  free (state->reverbRight);
  for (NSUInteger index = 0; index < SCORE_DSP_PATCHES; index++)
    {
      free (state->voiceDelayLeft[index]);
      free (state->voiceDelayRight[index]);
      free (state->voiceReverbLeft[index]);
      free (state->voiceReverbRight[index]);
    }
  state->delayLeft = NULL;
  state->delayRight = NULL;
  state->reverbLeft = NULL;
  state->reverbRight = NULL;
}

static float ScoreDSPCompress (float sample, float threshold, float ratio);

static void
ScoreDSPApplyVoiceEffects (ScoreDSPState *state, NSUInteger index, float *left, float *right)
{
  float l = *left * state->voiceGain[index];
  float r = *right * state->voiceGain[index];
  float coefficient = state->voiceLowpassCoefficient[index];
  if (coefficient > 0.0f)
    {
      state->voiceLowpassLeft[index] += coefficient * (l - state->voiceLowpassLeft[index]);
      state->voiceLowpassRight[index] += coefficient * (r - state->voiceLowpassRight[index]);
      l = state->voiceLowpassLeft[index];
      r = state->voiceLowpassRight[index];
    }
  l = ScoreDSPCompress (l, state->voiceCompressorThreshold[index],
                        state->voiceCompressorRatio[index]);
  r = ScoreDSPCompress (r, state->voiceCompressorThreshold[index],
                        state->voiceCompressorRatio[index]);
  NSUInteger delayFrames = state->voiceDelayFrames[index];
  if (delayFrames && state->voiceDelayLeft[index])
    {
      NSUInteger position = state->voiceDelayIndex[index];
      float dl = state->voiceDelayLeft[index][position];
      float dr = state->voiceDelayRight[index][position];
      state->voiceDelayLeft[index][position] = l + dl * state->voiceDelayFeedback[index];
      state->voiceDelayRight[index][position] = r + dr * state->voiceDelayFeedback[index];
      l = l * (1.0f - state->voiceDelayMix[index]) + dl * state->voiceDelayMix[index];
      r = r * (1.0f - state->voiceDelayMix[index]) + dr * state->voiceDelayMix[index];
      state->voiceDelayIndex[index] = (position + 1) % delayFrames;
    }
  NSUInteger reverbFrames = state->voiceReverbFrames[index];
  if (reverbFrames && state->voiceReverbLeft[index])
    {
      NSUInteger position = state->voiceReverbIndex[index];
      NSUInteger rightPosition = (position + reverbFrames / 7) % reverbFrames;
      float wetLeft = state->voiceReverbLeft[index][position];
      float wetRight = state->voiceReverbRight[index][rightPosition];
      state->voiceReverbLeft[index][position] = l + wetRight * state->voiceReverbFeedback[index];
      state->voiceReverbRight[index][rightPosition] = r + wetLeft * state->voiceReverbFeedback[index];
      l = l * (1.0f - state->voiceReverbMix[index]) + wetLeft * state->voiceReverbMix[index];
      r = r * (1.0f - state->voiceReverbMix[index]) + wetRight * state->voiceReverbMix[index];
      state->voiceReverbIndex[index] = (position + 1) % reverbFrames;
    }
  *left = l;
  *right = r;
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
ScoreDSPPush (ScoreDSPState *s, int pitch, int notationVoice, float velocity, BOOL on)
{
  unsigned write = atomic_load_explicit (&s->writeIndex, memory_order_relaxed);
  unsigned next = (write + 1) % SCORE_DSP_EVENTS;
  if (next == atomic_load_explicit (&s->readIndex, memory_order_acquire))
    return;
  s->events[write] = (ScoreDSPEvent){ pitch, 0.0, 0, notationVoice, velocity, 0.0f, on, 0 };
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
                            .frequency = e.frequency,
                            .track = e.track,
                            .notationVoice = e.notationVoice,
                            .phase = 0,
                            .lfoPhase = 0,
                            .ageFrames = 0,
                            .envelopeLevel = 0,
                            .releaseRate = 0,
                            .velocity = e.velocity,
                            .pan = e.pan,
                            .envelopeStage = 0,
                            .active = YES,
                            .releasing = NO };
    }
  else
    for (int i = 0; i < SCORE_DSP_VOICES; i++)
      if (s->voices[i].active && s->voices[i].pitch == e.pitch
          && s->voices[i].track == e.track
          && s->voices[i].notationVoice == e.notationVoice
          && (e.frequency <= 0.0 || fabs (s->voices[i].frequency - e.frequency) < 0.000001))
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
  ScoreDSPPatch patches[SCORE_DSP_PATCHES];
  for (NSInteger voice = 1; voice <= SCORE_DSP_PATCHES; voice++)
    patches[voice - 1] = ScoreDSPLoadPatch (s, voice);
  for (NSUInteger f = 0; f < frames; f++)
    {
      while (s->scheduledEventIndex < s->scheduledEventCount
             && s->scheduledEvents[s->scheduledEventIndex].sampleFrame <= s->renderedFrames)
        ScoreDSPApplyEvent (s, s->scheduledEvents[s->scheduledEventIndex++]);
      double voiceLeftMix[SCORE_DSP_PATCHES] = { 0 };
      double voiceRightMix[SCORE_DSP_PATCHES] = { 0 };
      for (int i = 0; i < SCORE_DSP_VOICES; i++)
        {
          ScoreDSPVoice *v = &s->voices[i];
          if (!v->active)
            continue;
          NSUInteger patchIndex = (NSUInteger)MAX (1, MIN (SCORE_DSP_PATCHES, v->notationVoice)) - 1;
          ScoreDSPPatch patch = patches[patchIndex];
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
          if (v->releasing)
            {
              if (v->filterReleaseRate <= 0.0f)
                v->filterReleaseRate = patch.filterRelease > 0.0001f
                                          ? v->filterEnvelopeLevel
                                              / (patch.filterRelease * (float)s->sampleRate)
                                          : v->filterEnvelopeLevel;
              v->filterEnvelopeLevel = MAX (0.0f, v->filterEnvelopeLevel - v->filterReleaseRate);
            }
          else if (v->filterEnvelopeStage == 0)
            {
              v->filterEnvelopeLevel += patch.filterAttack > 0.0001f
                                           ? 1.0f / (patch.filterAttack * (float)s->sampleRate)
                                           : 1.0f;
              if (v->filterEnvelopeLevel >= 1.0f)
                {
                  v->filterEnvelopeLevel = 1.0f;
                  v->filterEnvelopeStage = 1;
                }
            }
          else if (v->filterEnvelopeStage == 1)
            {
              v->filterEnvelopeLevel -= patch.filterDecay > 0.0001f
                                           ? (1.0f - patch.filterSustain)
                                               / (patch.filterDecay * (float)s->sampleRate)
                                           : 1.0f;
              if (v->filterEnvelopeLevel <= patch.filterSustain)
                {
                  v->filterEnvelopeLevel = patch.filterSustain;
                  v->filterEnvelopeStage = 2;
                }
            }
          double hz = v->frequency > 0.0
                        ? v->frequency
                        : 440.0 * pow (2.0, (v->pitch - 69) / 12.0);
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
          float velocityGain = (1.0f - patch.velocityToAmplitude)
                               + patch.velocityToAmplitude * v->velocity;
          float cutoffSemitones = patch.filterEnvelopeAmount * v->filterEnvelopeLevel
                                  + patch.velocityToFilter * v->velocity;
          float filtered = (float)oscillator;
          if (patch.filterCutoff < 12000.0f || patch.filterResonance > 0.0f
              || patch.filterEnvelopeAmount != 0.0f || patch.velocityToFilter != 0.0f)
            {
              float cutoff = patch.filterCutoff * powf (2.0f, cutoffSemitones / 12.0f);
              cutoff = MAX (20.0f, MIN ((float)s->sampleRate * 0.20f, cutoff));
              float coefficient = MIN (0.9f, 2.0f * sinf ((float)M_PI * cutoff / (float)s->sampleRate));
              float damping = 2.0f - 1.85f * patch.filterResonance;
              v->filterLow += coefficient * v->filterBand;
              float high = filtered - v->filterLow - damping * v->filterBand;
              v->filterBand += coefficient * high;
              filtered = v->filterLow;
            }
          double sample = filtered * v->envelopeLevel * velocityGain;
          float pan = MAX (-1.0f, MIN (1.0f, v->pan));
          voiceLeftMix[patchIndex] += sample * sqrt ((1.0 - pan) * 0.5);
          voiceRightMix[patchIndex] += sample * sqrt ((1.0 + pan) * 0.5);
          v->phase += 2.0 * M_PI * hz / s->sampleRate;
          if (v->phase >= 2.0 * M_PI)
            v->phase -= 2.0 * M_PI;
          v->lfoPhase += 2.0 * M_PI * patch.lfoRate / s->sampleRate;
          if (v->lfoPhase >= 2.0 * M_PI)
            v->lfoPhase -= 2.0 * M_PI;
          v->ageFrames++;
        }
      float mixedLeft = 0.0f;
      float mixedRight = 0.0f;
      for (NSUInteger patchIndex = 0; patchIndex < SCORE_DSP_PATCHES; patchIndex++)
        {
          float voiceLeft = (float)(voiceLeftMix[patchIndex] * 0.31);
          float voiceRight = (float)(voiceRightMix[patchIndex] * 0.31);
          ScoreDSPApplyVoiceEffects (s, patchIndex, &voiceLeft, &voiceRight);
          mixedLeft += voiceLeft;
          mixedRight += voiceRight;
        }
      left[f] = mixedLeft;
      right[f] = mixedRight;
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
  NSInteger _generalMIDIProgram;
  NSArray *_effectConfiguration;
  NSMutableDictionary *_internalSynthPatches;
  NSMutableDictionary *_internalSynthEffects;
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
            @"lfoDelay" : @0.0,
            @"filterCutoff" : @12000.0,
            @"filterResonance" : @0.0,
            @"filterAttack" : @0.01,
            @"filterDecay" : @0.15,
            @"filterSustain" : @0.0,
            @"filterRelease" : @0.25,
            @"filterEnvelopeAmount" : @0.0,
            @"velocityToAmplitude" : @1.0,
            @"velocityToFilter" : @0.0 };
}
+ (NSDictionary *)factoryInternalSynthPatches
{
  NSArray *specifications = @[
    @{ @"name" : @"Aurora Saw Lead", @"category" : @"Lead", @"description" : @"Bright, expressive saw lead with a velocity-opened filter.",
       @"settings" : @{ @"waveform" : @"Saw", @"attack" : @0.015, @"release" : @0.22, @"filterCutoff" : @2600, @"filterResonance" : @0.28, @"filterEnvelopeAmount" : @30, @"velocityToFilter" : @18 } },
    @{ @"name" : @"Velvet Square Lead", @"category" : @"Lead", @"description" : @"Rounded square-wave solo voice with gentle vibrato.",
       @"settings" : @{ @"waveform" : @"Square", @"attack" : @0.035, @"release" : @0.38, @"lfoDepth" : @0.12, @"lfoDelay" : @0.3, @"filterCutoff" : @4200, @"filterResonance" : @0.18 } },
    @{ @"name" : @"Singing Triangle", @"category" : @"Lead", @"description" : @"Clear lyrical lead that blooms after the note begins.",
       @"settings" : @{ @"waveform" : @"Triangle", @"attack" : @0.06, @"release" : @0.55, @"lfoDepth" : @0.18, @"lfoDelay" : @0.45, @"filterCutoff" : @3400, @"filterEnvelopeAmount" : @22 } },
    @{ @"name" : @"Copper Resonance", @"category" : @"Lead", @"description" : @"Focused resonant lead for articulated melodic lines.",
       @"settings" : @{ @"waveform" : @"Saw", @"decay" : @0.22, @"sustain" : @0.66, @"filterCutoff" : @1450, @"filterResonance" : @0.7, @"filterDecay" : @0.28, @"filterSustain" : @0.22, @"filterEnvelopeAmount" : @42, @"velocityToFilter" : @24 } },

    @{ @"name" : @"Foundation Sub", @"category" : @"Bass", @"description" : @"Clean sine sub-bass with controlled release.",
       @"settings" : @{ @"waveform" : @"Sine", @"attack" : @0.008, @"decay" : @0.12, @"sustain" : @0.9, @"release" : @0.16, @"filterCutoff" : @12000 } },
    @{ @"name" : @"Solid Square Bass", @"category" : @"Bass", @"description" : @"Firm square bass with strong velocity response.",
       @"settings" : @{ @"waveform" : @"Square", @"attack" : @0.006, @"decay" : @0.16, @"sustain" : @0.62, @"release" : @0.14, @"filterCutoff" : @1250, @"filterResonance" : @0.2, @"velocityToFilter" : @15 } },
    @{ @"name" : @"Acid Etch Bass", @"category" : @"Bass", @"description" : @"Resonant saw bass with a short, animated filter envelope.",
       @"settings" : @{ @"waveform" : @"Saw", @"attack" : @0.004, @"release" : @0.12, @"filterCutoff" : @620, @"filterResonance" : @0.82, @"filterAttack" : @0.003, @"filterDecay" : @0.2, @"filterSustain" : @0.08, @"filterEnvelopeAmount" : @54, @"velocityToFilter" : @20 } },
    @{ @"name" : @"Plucked Round Bass", @"category" : @"Bass", @"description" : @"Short triangle bass suited to contrapuntal lines.",
       @"settings" : @{ @"waveform" : @"Triangle", @"attack" : @0.003, @"decay" : @0.24, @"sustain" : @0.28, @"release" : @0.18, @"filterCutoff" : @1900, @"filterEnvelopeAmount" : @25 } },

    @{ @"name" : @"Warm Horizon Pad", @"category" : @"Pad", @"description" : @"Slow warm saw pad with a spacious tail.",
       @"settings" : @{ @"waveform" : @"Saw", @"attack" : @1.1, @"decay" : @0.8, @"sustain" : @0.72, @"release" : @2.4, @"filterCutoff" : @1800, @"filterResonance" : @0.12, @"filterAttack" : @1.5, @"filterDecay" : @1.2, @"filterSustain" : @0.45, @"filterEnvelopeAmount" : @24 },
       @"effects" : @[ @{ @"type" : @"reverb", @"roomSize" : @0.6, @"mix" : @0.32 } ] },
    @{ @"name" : @"Glass Triangle Pad", @"category" : @"Pad", @"description" : @"Airy triangle pad with slow vibrato and delay.",
       @"settings" : @{ @"waveform" : @"Triangle", @"attack" : @0.75, @"sustain" : @0.8, @"release" : @2.0, @"lfoDepth" : @0.08, @"lfoDelay" : @0.8, @"filterCutoff" : @6500 },
       @"effects" : @[ @{ @"type" : @"delay", @"time" : @0.38, @"feedback" : @0.3, @"mix" : @0.2 }, @{ @"type" : @"reverb", @"roomSize" : @0.5, @"mix" : @0.25 } ] },
    @{ @"name" : @"Slow Northern Light", @"category" : @"Pad", @"description" : @"Dark evolving square pad with a long filter rise.",
       @"settings" : @{ @"waveform" : @"Square", @"attack" : @1.6, @"release" : @3.0, @"filterCutoff" : @720, @"filterResonance" : @0.32, @"filterAttack" : @2.2, @"filterDecay" : @1.5, @"filterSustain" : @0.65, @"filterEnvelopeAmount" : @40 },
       @"effects" : @[ @{ @"type" : @"reverb", @"roomSize" : @0.7, @"mix" : @0.38 } ] },
    @{ @"name" : @"Choral Triangle", @"category" : @"Pad", @"description" : @"Soft sustained pad for chorale-like writing.",
       @"settings" : @{ @"waveform" : @"Triangle", @"attack" : @0.55, @"decay" : @0.6, @"sustain" : @0.86, @"release" : @1.8, @"lfoRate" : @4.2, @"lfoDepth" : @0.06, @"filterCutoff" : @3900 },
       @"effects" : @[ @{ @"type" : @"reverb", @"roomSize" : @0.55, @"mix" : @0.28 } ] },

    @{ @"name" : @"Crystal Bell Pluck", @"category" : @"Pluck", @"description" : @"Bright sine pluck with a delicate echo.",
       @"settings" : @{ @"waveform" : @"Sine", @"attack" : @0.002, @"decay" : @0.42, @"sustain" : @0.0, @"release" : @0.32, @"velocityToAmplitude" : @1.0 },
       @"effects" : @[ @{ @"type" : @"delay", @"time" : @0.24, @"feedback" : @0.24, @"mix" : @0.18 } ] },
    @{ @"name" : @"Wooden Triangle Pluck", @"category" : @"Pluck", @"description" : @"Dry woody attack with a fast filter decay.",
       @"settings" : @{ @"waveform" : @"Triangle", @"attack" : @0.002, @"decay" : @0.2, @"sustain" : @0.0, @"release" : @0.16, @"filterCutoff" : @1100, @"filterDecay" : @0.16, @"filterEnvelopeAmount" : @35, @"velocityToFilter" : @22 } },
    @{ @"name" : @"Neon Sequence Pluck", @"category" : @"Pluck", @"description" : @"Crisp saw pluck designed for repeating figures.",
       @"settings" : @{ @"waveform" : @"Saw", @"attack" : @0.001, @"decay" : @0.16, @"sustain" : @0.08, @"release" : @0.12, @"filterCutoff" : @1500, @"filterResonance" : @0.35, @"filterEnvelopeAmount" : @40 },
       @"effects" : @[ @{ @"type" : @"delay", @"time" : @0.18, @"feedback" : @0.2, @"mix" : @0.12 } ] },
    @{ @"name" : @"Soft Mallet", @"category" : @"Pluck", @"description" : @"Mellow sine mallet with natural velocity shading.",
       @"settings" : @{ @"waveform" : @"Sine", @"attack" : @0.006, @"decay" : @0.32, @"sustain" : @0.04, @"release" : @0.28, @"filterCutoff" : @5200, @"velocityToAmplitude" : @0.9 } },

    @{ @"name" : @"Pure Sine Keys", @"category" : @"Keys", @"description" : @"Simple responsive sine keyboard tone.",
       @"settings" : @{ @"waveform" : @"Sine", @"attack" : @0.012, @"decay" : @0.35, @"sustain" : @0.68, @"release" : @0.55 } },
    @{ @"name" : @"Electric Triangle Keys", @"category" : @"Keys", @"description" : @"Warm electric-keyboard character with tremulous delay.",
       @"settings" : @{ @"waveform" : @"Triangle", @"attack" : @0.01, @"decay" : @0.48, @"sustain" : @0.54, @"release" : @0.7, @"filterCutoff" : @4600 },
       @"effects" : @[ @{ @"type" : @"delay", @"time" : @0.22, @"feedback" : @0.18, @"mix" : @0.12 } ] },
    @{ @"name" : @"Bright Digital Keys", @"category" : @"Keys", @"description" : @"Present square keys for rhythmic accompaniment.",
       @"settings" : @{ @"waveform" : @"Square", @"attack" : @0.006, @"decay" : @0.3, @"sustain" : @0.58, @"release" : @0.38, @"filterCutoff" : @5200, @"velocityToFilter" : @14 } },
    @{ @"name" : @"Mellow Score Keys", @"category" : @"Keys", @"description" : @"Restrained triangle keys that sit behind notation playback.",
       @"settings" : @{ @"waveform" : @"Triangle", @"attack" : @0.025, @"decay" : @0.5, @"sustain" : @0.62, @"release" : @0.8, @"filterCutoff" : @2600, @"velocityToAmplitude" : @0.75 } },

    @{ @"name" : @"Rising Filter Sweep", @"category" : @"Effects", @"description" : @"Long resonant rise for transitions and held notes.",
       @"settings" : @{ @"waveform" : @"Saw", @"attack" : @0.2, @"sustain" : @0.8, @"release" : @1.2, @"filterCutoff" : @180, @"filterResonance" : @0.72, @"filterAttack" : @2.8, @"filterDecay" : @0.5, @"filterSustain" : @0.9, @"filterEnvelopeAmount" : @72 },
       @"effects" : @[ @{ @"type" : @"reverb", @"roomSize" : @0.65, @"mix" : @0.3 } ] },
    @{ @"name" : @"Pulsing Signal", @"category" : @"Effects", @"description" : @"Narrow square signal with pronounced delayed vibrato.",
       @"settings" : @{ @"waveform" : @"Square", @"attack" : @0.02, @"release" : @0.45, @"lfoRate" : @7.5, @"lfoDepth" : @0.85, @"lfoDelay" : @0.18, @"filterCutoff" : @2400, @"filterResonance" : @0.5 } },
    @{ @"name" : @"Deep Space Tone", @"category" : @"Effects", @"description" : @"Dark slow-moving tone with long echoes.",
       @"settings" : @{ @"waveform" : @"Sine", @"attack" : @0.9, @"release" : @3.5, @"lfoRate" : @0.35, @"lfoDepth" : @0.4, @"filterCutoff" : @900, @"filterResonance" : @0.42 },
       @"effects" : @[ @{ @"type" : @"delay", @"time" : @0.62, @"feedback" : @0.55, @"mix" : @0.34 }, @{ @"type" : @"reverb", @"roomSize" : @0.72, @"mix" : @0.42 } ] },
    @{ @"name" : @"Distant Chime", @"category" : @"Effects", @"description" : @"Sparse high chime with an extended ambient tail.",
       @"settings" : @{ @"waveform" : @"Triangle", @"attack" : @0.004, @"decay" : @0.7, @"sustain" : @0.0, @"release" : @1.4, @"filterCutoff" : @7800 },
       @"effects" : @[ @{ @"type" : @"delay", @"time" : @0.48, @"feedback" : @0.42, @"mix" : @0.3 }, @{ @"type" : @"reverb", @"roomSize" : @0.7, @"mix" : @0.44 } ] }
  ];
  NSMutableDictionary *library = [NSMutableDictionary dictionary];
  for (NSDictionary *specification in specifications)
    {
      NSMutableDictionary *patch = [NSMutableDictionary dictionaryWithDictionary:[self defaultInternalSynthPatch]];
      [patch addEntriesFromDictionary:[specification objectForKey:@"settings"]];
      [patch setObject:[specification objectForKey:@"name"] forKey:@"name"];
      [patch setObject:[specification objectForKey:@"category"] forKey:@"category"];
      [patch setObject:[specification objectForKey:@"description"] forKey:@"description"];
      [patch setObject:[specification objectForKey:@"effects"] ?: [NSArray array] forKey:@"effects"];
      [library setObject:patch forKey:[specification objectForKey:@"name"]];
    }
  return library;
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
      _generalMIDIProgram = -1;
      ScoreDSPInitializeEffects (_dsp, 48000.0);
      _effectConfiguration = [[NSArray alloc] init];
      _internalSynthPatches = [[NSMutableDictionary alloc] init];
      _internalSynthEffects = [[NSMutableDictionary alloc] init];
      for (NSInteger voice = 1; voice <= SCORE_DSP_PATCHES; voice++)
        {
          [_internalSynthPatches setObject:[[self class] defaultInternalSynthPatch]
                                    forKey:[NSNumber numberWithInteger:voice]];
          [_internalSynthEffects setObject:[NSArray array]
                                    forKey:[NSNumber numberWithInteger:voice]];
        }
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
  if (!_instrument)
    return;
  [self stop];
  [_instrument release];
  _instrument = nil;
  [_instrumentDescription release];
  _instrumentDescription = nil;
  _generalMIDIProgram = -1;
#endif
}
- (BOOL)useGeneralMIDIProgram:(NSInteger)program error:(NSError **)error
{
#if defined(__APPLE__)
  program = MAX ((NSInteger)0, MIN ((NSInteger)127, program));
  if (_instrument && !_instrumentDescription && _generalMIDIProgram == program)
    return YES;

  NSURL *soundBankURL = [NSURL fileURLWithPath:
    @"/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls"];
  AVAudioUnitSampler *sampler = [[[AVAudioUnitSampler alloc] init] autorelease];
  NSError *loadError = nil;
  if (![sampler loadSoundBankInstrumentAtURL:soundBankURL
                                     program:(uint8_t)program
                                     bankMSB:kAUSampler_DefaultMelodicBankMSB
                                     bankLSB:kAUSampler_DefaultBankLSB
                                       error:&loadError])
    {
      if (error)
        *error = loadError;
      return NO;
    }

  [self stop];
  [_instrument release];
  _instrument = [sampler retain];
  [_instrumentDescription release];
  _instrumentDescription = nil;
  _generalMIDIProgram = program;
  return YES;
#else
  (void)program;
  if (error)
    *error = [NSError errorWithDomain:@"ScoreMakerDSP"
                                 code:12
                             userInfo:@{ NSLocalizedDescriptionKey :
                                           @"General MIDI live audition is unavailable." }];
  return NO;
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
                          _generalMIDIProgram = -1;
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
  return [self internalSynthPatchForVoice:1];
}
- (BOOL)configureInternalSynthPatch:(NSDictionary *)patch error:(NSError **)error
{
  return [self configureInternalSynthPatch:patch forVoice:1 error:error];
}
- (NSDictionary *)internalSynthPatchForVoice:(NSInteger)voice
{
  NSInteger normalizedVoice = MAX ((NSInteger)1, MIN ((NSInteger)SCORE_DSP_PATCHES, voice));
  return [_internalSynthPatches objectForKey:[NSNumber numberWithInteger:normalizedVoice]];
}
- (BOOL)configureInternalSynthPatch:(NSDictionary *)patch
                           forVoice:(NSInteger)voice
                              error:(NSError **)error
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
  float filterCutoff = MAX (20.0f, MIN (20000.0f, ScoreDSPPatchFloat (patch, defaults, @"filterCutoff")));
  float filterResonance = MAX (0.0f, MIN (0.95f, ScoreDSPPatchFloat (patch, defaults, @"filterResonance")));
  float filterAttack = MAX (0.0f, MIN (10.0f, ScoreDSPPatchFloat (patch, defaults, @"filterAttack")));
  float filterDecay = MAX (0.0f, MIN (10.0f, ScoreDSPPatchFloat (patch, defaults, @"filterDecay")));
  float filterSustain = MAX (0.0f, MIN (1.0f, ScoreDSPPatchFloat (patch, defaults, @"filterSustain")));
  float filterRelease = MAX (0.0f, MIN (20.0f, ScoreDSPPatchFloat (patch, defaults, @"filterRelease")));
  float filterEnvelopeAmount = MAX (-96.0f, MIN (96.0f, ScoreDSPPatchFloat (patch, defaults, @"filterEnvelopeAmount")));
  float velocityToAmplitude = MAX (0.0f, MIN (1.0f, ScoreDSPPatchFloat (patch, defaults, @"velocityToAmplitude")));
  float velocityToFilter = MAX (-48.0f, MIN (48.0f, ScoreDSPPatchFloat (patch, defaults, @"velocityToFilter")));
  NSMutableDictionary *normalized = [NSMutableDictionary dictionaryWithDictionary:@{
    @"waveform" : waveform,
    @"attack" : [NSNumber numberWithFloat:attack],
    @"decay" : [NSNumber numberWithFloat:decay],
    @"sustain" : [NSNumber numberWithFloat:sustain],
    @"release" : [NSNumber numberWithFloat:release],
    @"lfoRate" : [NSNumber numberWithFloat:lfoRate],
    @"lfoDepth" : [NSNumber numberWithFloat:lfoDepth],
    @"lfoDelay" : [NSNumber numberWithFloat:lfoDelay],
    @"filterCutoff" : [NSNumber numberWithFloat:filterCutoff],
    @"filterResonance" : [NSNumber numberWithFloat:filterResonance],
    @"filterAttack" : [NSNumber numberWithFloat:filterAttack],
    @"filterDecay" : [NSNumber numberWithFloat:filterDecay],
    @"filterSustain" : [NSNumber numberWithFloat:filterSustain],
    @"filterRelease" : [NSNumber numberWithFloat:filterRelease],
    @"filterEnvelopeAmount" : [NSNumber numberWithFloat:filterEnvelopeAmount],
    @"velocityToAmplitude" : [NSNumber numberWithFloat:velocityToAmplitude],
    @"velocityToFilter" : [NSNumber numberWithFloat:velocityToFilter]
  }];
  if ([[patch objectForKey:@"name"] isKindOfClass:[NSString class]])
    [normalized setObject:[patch objectForKey:@"name"] forKey:@"name"];
  if ([[patch objectForKey:@"category"] isKindOfClass:[NSString class]])
    [normalized setObject:[patch objectForKey:@"category"] forKey:@"category"];
  if ([[patch objectForKey:@"description"] isKindOfClass:[NSString class]])
    [normalized setObject:[patch objectForKey:@"description"] forKey:@"description"];
  NSInteger normalizedVoice = MAX ((NSInteger)1, MIN ((NSInteger)SCORE_DSP_PATCHES, voice));
  [_internalSynthPatches setObject:normalized
                            forKey:[NSNumber numberWithInteger:normalizedVoice]];
  ScoreDSPStorePatch (_dsp, normalizedVoice,
                      (ScoreDSPPatch){ (int)waveformIndex, attack, decay, sustain, release,
                                       lfoRate, lfoDepth, lfoDelay, filterCutoff,
                                       filterResonance, filterAttack, filterDecay, filterSustain,
                                       filterRelease, filterEnvelopeAmount, velocityToAmplitude,
                                       velocityToFilter });
  NSArray *effects = [patch objectForKey:@"effects"];
  if (![effects isKindOfClass:[NSArray class]])
    effects = [NSArray array];
  if (![effects isEqualToArray:[self internalSynthEffectsForVoice:normalizedVoice]]
      && ![self configureInternalSynthEffects:effects forVoice:normalizedVoice error:error])
    return NO;
  return YES;
}

- (NSArray *)internalSynthEffectsForVoice:(NSInteger)voice
{
  NSInteger normalizedVoice = MAX ((NSInteger)1, MIN ((NSInteger)SCORE_DSP_PATCHES, voice));
  return [_internalSynthEffects objectForKey:[NSNumber numberWithInteger:normalizedVoice]]
         ?: [NSArray array];
}

- (BOOL)configureInternalSynthEffects:(NSArray *)effects
                              forVoice:(NSInteger)voice
                                 error:(NSError **)error
{
  NSSet *supported = [NSSet setWithObjects:@"gain", @"lowpass", @"compressor", @"delay",
                                           @"reverb", nil];
  for (NSDictionary *effect in effects)
    if (![supported containsObject:[effect objectForKey:@"type"]])
      {
        if (error)
          *error = [NSError errorWithDomain:@"ScoreMakerDSP"
                                       code:13
                                   userInfo:@{ NSLocalizedDescriptionKey : @"The patch contains an unsupported effect." }];
        return NO;
      }
  NSInteger normalizedVoice = MAX ((NSInteger)1, MIN ((NSInteger)SCORE_DSP_PATCHES, voice));
  NSUInteger index = (NSUInteger)normalizedVoice - 1;
  BOOL restart = _running;
  if (restart)
    [self stop];
  [_internalSynthEffects setObject:[[[NSArray alloc] initWithArray:effects copyItems:YES] autorelease]
                               forKey:[NSNumber numberWithInteger:normalizedVoice]];
  NSArray *storedEffects = [_internalSynthEffects objectForKey:[NSNumber numberWithInteger:normalizedVoice]];
  NSMutableDictionary *patch = [NSMutableDictionary
    dictionaryWithDictionary:[_internalSynthPatches objectForKey:[NSNumber numberWithInteger:normalizedVoice]]
                               ?: [[self class] defaultInternalSynthPatch]];
  [patch setObject:storedEffects forKey:@"effects"];
  [_internalSynthPatches setObject:patch forKey:[NSNumber numberWithInteger:normalizedVoice]];

  _dsp->voiceGain[index] = 1.0f;
  _dsp->voiceLowpassCoefficient[index] = 0.0f;
  _dsp->voiceCompressorThreshold[index] = 1.0f;
  _dsp->voiceCompressorRatio[index] = 1.0f;
  _dsp->voiceDelayFrames[index] = 0;
  _dsp->voiceDelayMix[index] = 0.0f;
  _dsp->voiceDelayFeedback[index] = 0.0f;
  _dsp->voiceReverbFrames[index] = 0;
  _dsp->voiceReverbMix[index] = 0.0f;
  _dsp->voiceReverbFeedback[index] = 0.0f;
  for (NSDictionary *effect in storedEffects)
    {
      if ([[effect objectForKey:@"bypass"] boolValue])
        continue;
      NSString *type = [effect objectForKey:@"type"];
      if ([type isEqualToString:@"gain"])
        _dsp->voiceGain[index] = powf (10.0f, [[effect objectForKey:@"decibels"] floatValue] / 20.0f);
      else if ([type isEqualToString:@"lowpass"])
        {
          float cutoff = MAX (20.0f, MIN (20000.0f, [[effect objectForKey:@"cutoff"] floatValue] ?: 12000.0f));
          _dsp->voiceLowpassCoefficient[index] = 1.0f - expf (-2.0f * (float)M_PI * cutoff / (float)_dsp->sampleRate);
        }
      else if ([type isEqualToString:@"compressor"])
        {
          _dsp->voiceCompressorThreshold[index] = powf (10.0f, [[effect objectForKey:@"threshold"] floatValue] / 20.0f);
          _dsp->voiceCompressorRatio[index] = MAX (1.0f, [[effect objectForKey:@"ratio"] floatValue]);
        }
      else if ([type isEqualToString:@"delay"])
        {
          double seconds = MAX (0.001, MIN (2.0, [[effect objectForKey:@"time"] doubleValue] ?: 0.3));
          _dsp->voiceDelayFrames[index] = MIN (_dsp->delayCapacity, MAX ((NSUInteger)1, (NSUInteger)llround (seconds * _dsp->sampleRate)));
          _dsp->voiceDelayMix[index] = MAX (0.0f, MIN (1.0f, [[effect objectForKey:@"mix"] floatValue]));
          _dsp->voiceDelayFeedback[index] = MAX (0.0f, MIN (0.95f, [[effect objectForKey:@"feedback"] floatValue]));
        }
      else if ([type isEqualToString:@"reverb"])
        {
          double room = MAX (0.05, MIN (0.75, [[effect objectForKey:@"roomSize"] doubleValue] ?: 0.35));
          _dsp->voiceReverbFrames[index] = MIN (_dsp->reverbCapacity, MAX ((NSUInteger)1, (NSUInteger)llround (room * _dsp->sampleRate)));
          _dsp->voiceReverbMix[index] = MAX (0.0f, MIN (1.0f, [[effect objectForKey:@"mix"] floatValue]));
          _dsp->voiceReverbFeedback[index] = MAX (0.0f, MIN (0.92f, 0.45f + (float)room * 0.55f));
        }
    }
  memset (_dsp->voiceDelayLeft[index], 0, _dsp->delayCapacity * sizeof (float));
  memset (_dsp->voiceDelayRight[index], 0, _dsp->delayCapacity * sizeof (float));
  memset (_dsp->voiceReverbLeft[index], 0, _dsp->reverbCapacity * sizeof (float));
  memset (_dsp->voiceReverbRight[index], 0, _dsp->reverbCapacity * sizeof (float));
  _dsp->voiceDelayIndex[index] = 0;
  _dsp->voiceReverbIndex[index] = 0;
  if (restart && ![self startWithError:error])
    return NO;
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
  [self noteOn:pitch voice:1 velocity:velocity];
}
- (void)noteOn:(NSInteger)pitch voice:(NSInteger)voice velocity:(NSUInteger)velocity
{
#if defined(__APPLE__)
  if (_instrument)
    {
      [_instrument sendMIDIEvent:0x90 data1:(UInt8)pitch data2:(UInt8)MIN (127, velocity)];
      return;
    }
#endif
  ScoreDSPPush (_dsp, (int)pitch, (int)MAX (1, MIN (SCORE_DSP_PATCHES, voice)),
                (float)MIN ((NSUInteger)127, velocity) / 127.0f, YES);
}
- (void)noteOff:(NSInteger)pitch
{
  [self noteOff:pitch voice:1];
}
- (void)noteOff:(NSInteger)pitch voice:(NSInteger)voice
{
#if defined(__APPLE__)
  if (_instrument)
    {
      [_instrument sendMIDIEvent:0x80 data1:(UInt8)pitch data2:0];
      return;
    }
#endif
  ScoreDSPPush (_dsp, (int)pitch, (int)MAX (1, MIN (SCORE_DSP_PATCHES, voice)), 0, NO);
}
- (void)allNotesOff
{
#if defined(__APPLE__)
  if (_instrument)
    {
      for (NSInteger pitch = 0; pitch < 128; pitch++)
        [self noteOff:pitch];
      return;
    }
#endif
  for (NSInteger pitch = 0; pitch < 128; pitch++)
    for (NSInteger voice = 1; voice <= SCORE_DSP_PATCHES; voice++)
      [self noteOff:pitch voice:voice];
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
        [[item objectForKey:@"frequency"] doubleValue],
        [[item objectForKey:@"track"] intValue],
        MAX (1, [[item objectForKey:@"voice"] intValue]),
        [[item objectForKey:@"velocity"] floatValue] / 127.0f,
        MAX (-1.0f, MIN (1.0f, [[item objectForKey:@"pan"] floatValue])),
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
          uint8_t channel = (uint8_t)(MAX (0, event.track) % 16);
          if (event.on && event.frequency > 0.0)
            {
              double equalFrequency = 440.0 * pow (2.0, ((double)event.pitch - 69.0) / 12.0);
              double semitones = 12.0 * log (event.frequency / equalFrequency) / log (2.0);
              int bend = (int)lrint (8192.0 + semitones * 4096.0);
              bend = MAX (0, MIN (16383, bend));
              uint8_t bendMIDI[3] = { (uint8_t)(0xe0 | channel),
                                      (uint8_t)(bend & 0x7f),
                                      (uint8_t)((bend >> 7) & 0x7f) };
              schedule ((AUEventSampleTime)event.sampleFrame, 0, 3, bendMIDI);
            }
          uint8_t midi[3] = { (uint8_t)((event.on ? 0x90 : 0x80) | channel),
                              (uint8_t)event.pitch,
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
  for (NSInteger voice = 1; voice <= SCORE_DSP_PATCHES; voice++)
    {
      NSUInteger index = (NSUInteger)voice - 1;
      ScoreDSPStorePatch (&state, voice, ScoreDSPLoadPatch (_dsp, voice));
      state.voiceGain[index] = _dsp->voiceGain[index];
      state.voiceLowpassCoefficient[index] = _dsp->voiceLowpassCoefficient[index];
      state.voiceCompressorThreshold[index] = _dsp->voiceCompressorThreshold[index];
      state.voiceCompressorRatio[index] = _dsp->voiceCompressorRatio[index];
      state.voiceDelayFrames[index] = _dsp->voiceDelayFrames[index];
      state.voiceDelayMix[index] = _dsp->voiceDelayMix[index];
      state.voiceDelayFeedback[index] = _dsp->voiceDelayFeedback[index];
      state.voiceReverbFrames[index] = _dsp->voiceReverbFrames[index];
      state.voiceReverbMix[index] = _dsp->voiceReverbMix[index];
      state.voiceReverbFeedback[index] = _dsp->voiceReverbFeedback[index];
    }
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
        [[item objectForKey:@"frequency"] doubleValue],
        [[item objectForKey:@"track"] intValue],
        MAX (1, [[item objectForKey:@"voice"] intValue]),
        [[item objectForKey:@"velocity"] floatValue] / 127.0f,
        MAX (-1.0f, MIN (1.0f, [[item objectForKey:@"pan"] floatValue])),
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
  [_internalSynthPatches release];
  [_internalSynthEffects release];
  free (_dsp->scheduledEvents);
  ScoreDSPDisposeEffects (_dsp);
  free (_dsp);
  [super dealloc];
}
@end
