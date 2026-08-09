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
#import "EngravingLayout.h"

extern NSString *const ScoreViewDidEditScoreNotification;
extern NSString *const ScoreViewSelectionDidChangeNotification;
extern NSString *const ScorePalettePasteboardType;

@interface ScoreView : NSView
{
  ScoreDocument *_document;
  ScoreNote *_selectedNote;
  ScoreNote *_loopEndNote;
  NSUInteger _playbackTick;
  BOOL _showPlayback;
  ScoreEngravingLayout *_engravingLayout;
  NSDictionary *_displayedAccidentals;
  BOOL _separateParts;
  NSNumber *_publicationTrack;
}
- (ScoreDocument *)document;
- (void)setDocument:(ScoreDocument *)document;
- (void)reloadDocument;
- (ScoreNote *)selectedNote;
- (void)selectNote:(ScoreNote *)note scrollToVisible:(BOOL)scroll;
- (BOOL)hasLoopSelection;
- (NSUInteger)loopStartTick;
- (NSUInteger)loopEndTick;
- (void)setPlaybackTick:(NSUInteger)tick;
- (void)clearPlayback;
- (void)scrollPlaybackTickToVisible:(NSUInteger)tick;
- (NSSize)printedPageContentSize;
- (BOOL)separateParts;
- (void)setSeparateParts:(BOOL)separate;
- (NSNumber *)publicationTrack;
- (void)setPublicationTrack:(NSNumber *)track;
- (BOOL)insertPaletteItem:(NSString *)item
                  atPoint:(NSPoint)point
                    pitch:(NSInteger)pitch
            durationTicks:(NSUInteger)durationTicks
                    track:(NSInteger)track;
@end
