/*
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This file is part of ScoreMaker.
 *
 * ScoreMaker is free software: you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or (at
 * your option) any later version.
 *
 * ScoreMaker is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
 * License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with ScoreMaker.  If not, see <https://www.gnu.org/licenses/>.
 */

#import <AppKit/AppKit.h>
#import "ScoreModel.h"

/** Returns the shared display color for a notation voice. */
NSColor *ScoreVoiceColor (NSInteger voice, BOOL darkVariant);

/**
 * Displays playback activity, live velocity meters, and an interactive piano
 * keyboard for audition and note entry.
 */
@interface PlaybackMonitorView : NSView
{
  ScoreDocument *_document;
  NSUInteger _playbackTick;
  BOOL _showPlayback;
  NSInteger _inputPitch;
  id _target;
  SEL _action;
  NSMutableDictionary *_liveNotes;
  NSInteger _selectedTrack;
  NSMutableSet *_pinnedTracks;
  BOOL _rackVisible;
  BOOL _showAllParts;
  BOOL _controllerRangeVisible;
  NSInteger _controllerFirstPitch;
  NSInteger _controllerLastPitch;
  NSTimer *_metronomeAnimationTimer;
  NSTimeInterval _metronomeBeatTime;
  NSTimeInterval _metronomeBeatDuration;
  NSUInteger _metronomeBeat;
  NSUInteger _metronomeBeatsPerMeasure;
  BOOL _metronomeActive;
}
/** Sets the score whose parts and notes are monitored. */
- (void)setDocument:(ScoreDocument *)document;
/** Advances the playback display to an absolute score tick. */
- (void)setPlaybackTick:(NSUInteger)tick;
/** Hides playback activity and clears its current tick. */
- (void)clearPlayback;
/** Sets the nonretained receiver of keyboard actions. */
- (void)setTarget:(id)target;
/** Sets the selector invoked by interactive keyboard actions. */
- (void)setAction:(SEL)action;
/** Returns the current keyboard-entry MIDI pitch. */
- (NSInteger)inputPitch;
/** Sets the keyboard-entry MIDI pitch. */
- (void)setInputPitch:(NSInteger)pitch;
/** Restores the default keyboard-entry pitch. */
- (void)resetInputPitch;
/** Displays an active live note with its voice and velocity. */
- (void)liveNoteOn:(NSInteger)pitch voice:(NSInteger)voice velocity:(NSUInteger)velocity;
/** Removes the live-note display for <var>pitch</var>. */
- (void)liveNoteOff:(NSInteger)pitch;
/** Removes every live-note display. */
- (void)clearLiveNotes;
/** Sets the track emphasized by the monitor and part rack. */
- (void)setSelectedTrack:(NSInteger)track;
/** Shades the MIDI pitches physically covered by the selected input controller. */
- (void)setControllerRangeFirstPitch:(NSInteger)firstPitch
                           lastPitch:(NSInteger)lastPitch
                             visible:(BOOL)visible;
/** Starts or stops the animated metronome at the supplied tempo and meter. */
- (void)setMetronomeActive:(BOOL)active
                       bpm:(NSUInteger)bpm
           beatsPerMeasure:(NSUInteger)beatsPerMeasure;
/** Advances the animated metronome to a beat, with zero representing the downbeat. */
- (void)pulseMetronomeBeat:(NSUInteger)beat;
@end
