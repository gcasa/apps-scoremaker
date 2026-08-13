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

NSColor *ScoreVoiceColor (NSInteger voice, BOOL darkVariant);

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
}
- (void)setDocument:(ScoreDocument *)document;
- (void)setPlaybackTick:(NSUInteger)tick;
- (void)clearPlayback;
- (void)setTarget:(id)target;
- (void)setAction:(SEL)action;
- (NSInteger)inputPitch;
- (void)setInputPitch:(NSInteger)pitch;
- (void)resetInputPitch;
- (void)liveNoteOn:(NSInteger)pitch voice:(NSInteger)voice velocity:(NSUInteger)velocity;
- (void)liveNoteOff:(NSInteger)pitch;
- (void)clearLiveNotes;
- (void)setSelectedTrack:(NSInteger)track;
@end
