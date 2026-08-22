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

/** Posted after an interactive edit changes the score model. */
extern NSString *const ScoreViewDidEditScoreNotification;
/** Posted after the selected note or loop endpoint changes. */
extern NSString *const ScoreViewSelectionDidChangeNotification;
/** Pasteboard type used when dragging a ScoreMaker palette item. */
extern NSString *const ScorePalettePasteboardType;

/** Renders, prints, selects, and directly edits a ScoreDocument. */
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
  BOOL _writtenPitch;
  NSNumber *_publicationTrack;
  ScoreNote *_draggedNote;
  BOOL _dragChanged;
}
/** Returns the displayed score document. */
- (ScoreDocument *)document;
/** Replaces the displayed score document and invalidates layout. */
- (void)setDocument:(ScoreDocument *)document;
/** Rebuilds engraving state after in-place model changes. */
- (void)reloadDocument;
/** Returns the currently selected note, or <code>nil</code>. */
- (ScoreNote *)selectedNote;
/** Returns the selected note, or every note intersecting the Shift-click range. */
- (NSArray *)selectedNotes;
/** Selects <var>note</var> and optionally reveals it in the enclosing scroll view. */
- (void)selectNote:(ScoreNote *)note scrollToVisible:(BOOL)scroll;
/** Returns whether two notes currently define an inclusive playback loop. */
- (BOOL)hasLoopSelection;
/** Returns the first tick of the selected loop. */
- (NSUInteger)loopStartTick;
/** Returns the exclusive ending tick of the selected loop. */
- (NSUInteger)loopEndTick;
/** Displays the playback cursor at <var>tick</var>. */
- (void)setPlaybackTick:(NSUInteger)tick;
/** Hides the playback cursor. */
- (void)clearPlayback;
/** Scrolls the system containing <var>tick</var> into view. */
- (void)scrollPlaybackTickToVisible:(NSUInteger)tick;
/** Returns the number of pages required by the current print layout. */
- (NSUInteger)pageCount;
/** Returns the printable content size of one score page. */
- (NSSize)printedPageContentSize;
/** Returns whether parts are displayed in separate publication layouts. */
- (BOOL)separateParts;
/** Selects combined-score or separated-part display. */
- (void)setSeparateParts:(BOOL)separate;
/** Returns whether transposing instruments are displayed at written pitch. */
- (BOOL)writtenPitch;
/** Switches between written-pitch and concert-pitch notation. */
- (void)setWrittenPitch:(BOOL)writtenPitch;
/** Returns a note's concert or written pitch according to the display mode. */
- (NSInteger)displayedPitchForNote:(ScoreNote *)note;
/** Returns the sole legacy track selected for publication, or <code>nil</code>. */
- (NSNumber *)publicationTrack;
/** Sets the sole publication track, or <code>nil</code> to show all tracks. */
- (void)setPublicationTrack:(NSNumber *)track;
/** Inserts a palette object at the requested score position and returns success. */
- (BOOL)insertPaletteItem:(NSString *)item
                  atPoint:(NSPoint)point
                    pitch:(NSInteger)pitch
            durationTicks:(NSUInteger)durationTicks
                    track:(NSInteger)track;
@end
