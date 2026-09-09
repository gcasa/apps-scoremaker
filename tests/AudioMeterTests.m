// Audio-thread meter regression tests. Include the DSP implementation to exercise sample processing.
#import "../src/RealtimeDSP.m"
#include <assert.h>

int main (void)
{
  @autoreleasepool
    {
      ScoreDSPState state = { 0 };
      ScoreDSPInitializeEffects (&state, 48000);
      atomic_store (&state.meteredTrack, 7);
      float left[1024], right[1024];
      ScoreDSPApplyEvent (&state, (ScoreDSPEvent){ .pitch = 60, .track = 8,
        .notationVoice = 1, .velocity = 1, .pan = 1, .on = YES });
      ScoreDSPRender (&state, left, right, 1024);
      assert (atomic_load (&state.meterPeaks[0]) == 0);
      assert (atomic_load (&state.meterPeaks[1]) == 0);
      assert (fabsf (right[1023]) > 0); // Another track is audible but excluded.
      ScoreDSPApplyEvent (&state, (ScoreDSPEvent){ .pitch = 64, .track = 7,
        .notationVoice = 1, .velocity = 1, .pan = -1, .on = YES });
      ScoreDSPRender (&state, left, right, 1024);
      assert (atomic_load (&state.meterPeaks[0]) > 0.01f);
      assert (atomic_load (&state.meterPeaks[1]) == 0); // Hard-left selected part.
      float peak = atomic_exchange (&state.meterPeaks[0], 0);
      assert (peak > 0 && atomic_load (&state.meterPeaks[0]) == 0);
      ScoreDSPAccumulatePeak (&state.meterPeaks[2], 1.2f);
      ScoreDSPAccumulatePeak (&state.meterPeaks[2], 0.4f);
      assert (atomic_exchange (&state.meterPeaks[2], 0) == 1.2f); // Preserve short overloads.
      ScoreDSPDisposeEffects (&state);
      puts ("Audio meter tests passed");
    }
  return 0;
}
